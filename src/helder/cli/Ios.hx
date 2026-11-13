package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.BuildCommand.Mode;
import helder.cli.Compiler.CompileServer;
import helder.cli.Devices.Device;
import helder.pack.apple.CodeSign;
import helder.pack.apple.Identity;
import helder.pack.ios.AssetCatalog;
import helder.pack.ios.Bundle;
import helder.pack.ios.Plist;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `--target ios` and `ios-sim`: an app bundle around hxmc's Mach-O
// executable (ios-arm64, an iPhone's: for build only, an .ipa, signed for
// the App Store and TestFlight when a signing identity and a provisioning
// profile are given (signing: helder.pack.apple.CodeSign, after the link),
// else ad hoc, which no device runs; ios-sim-arm64, the simulator's: an
// .app, which run and dev install). The
// bundle's Info.plist and _CodeSignature/CodeResources (helder.pack.ios,
// from package.json's "helder" key: App) are written first, then hxmc links
// the executable into <name>.app and signs it ad hoc binding them
// (-D hxmc.codesign-id, -info-plist, -resources, -entitlements; -D
// hxmc.ios-min-version the plist's MinimumOSVersion), as `codesign -s -`
// signs a bundle: enough for the simulator. An .ipa zips the bundle under
// Payload/. Outputs: bin/ios/<name>.ipa (and its .app beside it),
// bin/ios-sim/<name>.app. On a simulator (xcrun simctl): booted when it is
// not, installed, launched with its output here (--console).
class Ios {
	// --target's hxmc target: ios: an iPhone's for build, else the simulator's
	public static function target(t:String, command:String):String
		return switch t {
			case "ios": command == "build" ? "ios-arm64" : "ios-sim-arm64";
			case "ios-sim": "ios-sim-arm64";
			case t: t;
		}

	public static function out(e:Entry):String
		return e.target == "ios-arm64" ? Entry.clean('${e.root}/bin/ios/${e.name}.ipa') : Entry.clean('${e.root}/bin/ios-sim/${e.name}.app');

	// the bundle an output is or is beside (an .ipa's)
	public static function app(out:String):String
		return out.endsWith(".app") ? out : Path.withoutExtension(out) + ".app";

	// the executable in an app bundle
	public static function executable(app:String):String
		return app + "/" + Path.withoutExtension(Path.withoutDirectory(app));

	// the bundle's id (Info.plist's, the signature's)
	public static function id(e:Entry):String
		return App.ios(e.name, e.config).id;

	// the bundle's files, then the executable linked into it (and the .ipa;
	// signed for distribution when a signing identity is given: signing)
	@:coroutine public static function build(e:Entry, out:String, mode:Mode, ?server:CompileServer, ?extra:Array<String>):{ok:Bool, ms:Int, messages:String} {
		if (!out.endsWith(".app") && !out.endsWith(".ipa")) throw '$out: an iOS app is a .app or an .ipa';
		var app = app(out), name = Path.withoutExtension(Path.withoutDirectory(app));
		var o = App.ios(e.name, e.config);
		Manifest.warn(e);
		var device = e.target == "ios-arm64";
		Runtime.ensure(e.target);
		// (the identity and profile checked before the build: its mistakes first)
		var sign = device ? signing(o, e.root) : null;
		if (sign != null && sign.profile == null) {
			var key = try Publish.ascKey() catch (err:String)
				throw 'no provisioning profile given (HELDER_IOS_PROFILE): it is fetched from App Store Connect, which takes an API key: $err';
			sign.profile = Publish.profile(o.id, sign.identity.leaf.der, key);
		}
		var appEntitlements:Null<Map<String, PValue>> = null;
		var art = artwork(e.config, e.root, o.minVersion);
		var keys = art.keys;
		if (device) for (k => v in dtKeys(o)) keys.set(k, v);
		if (o.nonExemptEncryption != null) keys.set("ITSAppUsesNonExemptEncryption", PBool(o.nonExemptEncryption));
		var info = Bundle.infoPlist(name, o.id, o.label, o.version, o.versionName, o.minVersion, !device, o.orientation, o.fullscreen, keys);
		TestCommand.mkdirs(Path.directory(app) == "" ? "." : Path.directory(app));
		var full = FileSystem.fullPath(Path.directory(app) == "" ? "." : Path.directory(app)) + "/" + Path.withoutDirectory(app);
		var words = ["-D", 'hxmc.ios-min-version=${o.minVersion}', "-D", 'hxmc.codesign-id=${o.id}', "-D", 'hxmc.codesign-info-plist=$full/Info.plist', "-D",
			'hxmc.codesign-resources=$full/_CodeSignature/CodeResources'].concat(App.defines(e.config));
		if (o.entitlements != null) {
			var ent = Path.isAbsolute(o.entitlements) || e.root == "." ? o.entitlements : '${e.root}/${o.entitlements}';
			if (!FileSystem.exists(ent)) throw '$ent: no such file (package.json\'s "helder": {"ios": {"entitlements"}})';
			words = words.concat(["-D", 'hxmc.codesign-entitlements=${FileSystem.fullPath(ent)}']);
			appEntitlements = switch (try Plist.parse(File.getContent(ent)) catch (err:Dynamic) throw '$ent: not a property list ($err)') {
				case PDict(d): d;
				case _: throw '$ent: not a dictionary of entitlements';
			}
		}
		var entitlements = sign == null ? null : CodeSign.entitlements(sign.profile, o.id, appEntitlements);
		if (sign != null)
			for (w in CodeSign.checkProfile(sign.profile, sign.identity, "iOS", Date.now()))
				Term.err(Style.status("warning", Warn, w));
		var exe = executable(app);
		// (before each link: the bundle afresh, what an older build left in it
		// is not signed; its Info.plist, the program's assets (a release's: the
		// last build's, AssetStep, as assets/<key>; a dev build reads them from
		// this machine's disk), the icon's catalog, PrivacyInfo.xcprivacy, the
		// profile, and CodeResources with their hashes, which the signature binds)
		var resources = null, assets:Array<{path:String, data:haxe.io.Bytes}> = [], files = new Map<String, haxe.io.Bytes>();
		function put(path:String, data:haxe.io.Bytes) {
			File.saveBytes('$app/$path', data);
			files.set(path, data);
			assets = assets.filter(a -> a.path != path);
			assets.push({path: path, data: data});
		}
		function prepare():Array<String> {
			if (FileSystem.exists(app)) TestCommand.rmrf(app);
			TestCommand.mkdirs('$app/_CodeSignature');
			File.saveBytes('$app/Info.plist', info);
			var copied = mode == Release ? AssetStep.intoApp(exe, app, e.classPaths.concat([e.root])) : {keys: [], files: new Map()};
			files = ["Info.plist" => info];
			assets = [];
			for (f in art.files)
				put(f.path, f.data);
			for (k => b in copied.files) {
				files.set(k, b);
				assets.push({path: k, data: b});
			}
			if (device) put(PRIVACY, privacyInfo(o.privacy, null));
			if (sign != null) put("embedded.mobileprovision", sign.profile.der);
			resources = Bundle.codeResources(files);
			File.saveBytes('$app/_CodeSignature/CodeResources', resources);
			return copied.keys;
		}
		return BuildCommand.build(e, exe, mode, server, words.concat(extra ?? []), () -> {
			if (sign != null) {
				// (the APIs the program uses declared; then signed for distribution)
				var bin = File.getBytes(exe);
				var privacy = privacyInfo(o.privacy, bin);
				if (privacy.compare(files.get(PRIVACY)) != 0) {
					put(PRIVACY, privacy);
					resources = Bundle.codeResources(files);
					File.saveBytes('$app/_CodeSignature/CodeResources', resources);
				}
				File.saveBytes(exe, CodeSign.sign(bin, {
					identifier: o.id,
					identity: sign.identity,
					team: sign.profile.team,
					infoPlist: info,
					resources: resources,
					entitlements: entitlements,
					sdk: MachO.version(sdkValues(o).version)
				}));
			}
			if (out.endsWith(".ipa")) File.saveBytes(out, Bundle.ipa(name, File.getBytes(exe), info, resources, assets));
			out;
		}, prepare);
	}

	// --- distribution

	public static inline var PRIVACY = "PrivacyInfo.xcprivacy";

	// Xcode's values the App Store's validation reads (Info.plist's DT*
	// keys, LC_BUILD_VERSION's SDK): Xcode 26.0's, iOS 26.0's SDK, on macOS
	// 26.0; the manifest's "sdk" (Manifest.SDK's names) over them
	public static final SDK:Map<String, String> = ["version" => "26.0", "build" => "23A339", "xcode" => "2600", "xcodeBuild" => "17A324", "machine" => "25A354"];

	public static function sdkValues(o:App.IosOptions):{version:String, build:String, xcode:String, xcodeBuild:String, machine:String} {
		inline function v(k:String):String {
			var given:Dynamic = o.sdk == null ? null : Reflect.field(o.sdk, k);
			return given != null ? Std.string(given) : SDK.get(k);
		}
		return {version: v("version"), build: v("build"), xcode: v("xcode"), xcodeBuild: v("xcodeBuild"), machine: v("machine")};
	}

	// a device's Info.plist keys of the toolchain, as Xcode writes them
	public static function dtKeys(o:App.IosOptions):Map<String, PValue> {
		var s = sdkValues(o);
		return [
			"BuildMachineOSBuild" => PString(s.machine), "DTCompiler" => PString("com.apple.compilers.llvm.clang.1_0"), "DTPlatformBuild" => PString(s.build),
			"DTPlatformName" => PString("iphoneos"), "DTPlatformVersion" => PString(s.version), "DTSDKBuild" => PString(s.build),
			"DTSDKName" => PString("iphoneos" + s.version), "DTXcode" => PString(s.xcode), "DTXcodeBuild" => PString(s.xcodeBuild)
		];
	}

	// the required-reason APIs (Apple's list) a program's imports show, and
	// the reason declared for each: the one an app of its own uses them for
	static final REASONS = [
		{category: "NSPrivacyAccessedAPICategoryFileTimestamp", reason: "C617.1", symbols: ["_stat", "_fstat", "_lstat", "_fstatat", "_getattrlist", "_fgetattrlist", "_getattrlistbulk"]},
		{category: "NSPrivacyAccessedAPICategorySystemBootTime", reason: "35F9.1", symbols: ["_mach_absolute_time"]},
		{category: "NSPrivacyAccessedAPICategoryDiskSpace", reason: "E174.1", symbols: ["_statfs", "_fstatfs", "_statvfs", "_fstatvfs"]},
		{category: "NSPrivacyAccessedAPICategoryUserDefaults", reason: "CA92.1", symbols: ["_OBJC_CLASS_$_NSUserDefaults"]}
	];

	// PrivacyInfo.xcprivacy: no tracking, no data collected, the APIs'
	// reasons: the manifest's ("privacy": {category: [reason]}), and for the
	// required-reason APIs the executable imports (exe; null: none known
	// yet) that the manifest does not name, REASONS'
	public static function privacyInfo(declared:Null<Dynamic<Array<String>>>, exe:Null<haxe.io.Bytes>):haxe.io.Bytes {
		var reasons = new Map<String, Array<String>>();
		if (declared != null) for (k in Reflect.fields(declared)) reasons.set(k, Reflect.field(declared, k));
		if (exe != null) {
			var wanted = new Map<String, Int>();
			for (i => r in REASONS) for (s in r.symbols) wanted.set(s, i);
			var at = 0, n = exe.length;
			while (at < n) {
				var end = at;
				while (end < n && exe.get(end) != 0)
					end++;
				if (end - at > 1 && end - at < 64 && exe.get(at) == "_".code) {
					var r = wanted.get(exe.getString(at, end - at));
					if (r != null && !reasons.exists(REASONS[r].category)) reasons.set(REASONS[r].category, [REASONS[r].reason]);
				}
				at = end + 1;
			}
		}
		var categories = [for (k in reasons.keys()) k];
		categories.sort(Reflect.compare);
		return Plist.xml(PDict([
			"NSPrivacyTracking" => PBool(false),
			"NSPrivacyTrackingDomains" => PArray([]),
			"NSPrivacyCollectedDataTypes" => PArray([]),
			"NSPrivacyAccessedAPITypes" => PArray([
				for (c in categories)
					PDict(["NSPrivacyAccessedAPIType" => PString(c), "NSPrivacyAccessedAPITypeReasons" => PArray([for (r in reasons.get(c)) PString(r)])])
			])
		]));
	}

	// the distribution signature's identity and provisioning profile:
	// HELDER_IOS_IDENTITY (the certificate, its chain and the key in one
	// PEM), or HELDER_IOS_CERTIFICATE (the certificate and its chain) and
	// HELDER_IOS_KEY (the private key), and optionally HELDER_IOS_PROFILE
	// (the .mobileprovision; else build fetches the bundle id's active App
	// Store profile from App Store Connect: Publish.profile), each a file's
	// path or its contents (PEM's text; the profile's base64), else the
	// manifest's "signing" (paths from the project's directory); null: none
	// given (an .ipa signed ad hoc, for no device). A key without its certificate: an error
	public static function signing(o:App.IosOptions, root:String, ?env:String->Null<String>):Null<{identity:Identity, profile:Null<Profile>}> {
		env = env ?? Sys.getEnv;
		// (HELDER_IOS_IDENTITY: the certificate, its chain and the key in one PEM)
		var bundle = env("HELDER_IOS_IDENTITY");
		if (bundle != null && bundle.trim() != "") {
			var both = bundle, outer = env;
			env = n -> n == "HELDER_IOS_CERTIFICATE" || n == "HELDER_IOS_KEY" ? both : outer(n);
		}
		var names = [
			{env: "HELDER_IOS_CERTIFICATE", key: "certificate"},
			{env: "HELDER_IOS_KEY", key: "key"},
			{env: "HELDER_IOS_PROFILE", key: "profile"}
		];
		var given = [];
		for (n in names) {
			var v = env(n.env);
			if (v != null && v.trim() != "") given.push({name: n.env, value: v, file: false});
			else {
				var m:Dynamic = o.signing == null ? null : Reflect.field(o.signing, n.key);
				given.push(m == null ? null : {name: '"helder": {"ios": {"signing": {"${n.key}"}}}', value: Path.isAbsolute(m) || root == "." ? m : '$root/$m', file: true});
			}
		}
		if (!Lambda.exists(given, g -> g != null)) return null;
		var missing = [for (i => g in given) if (g == null && i < 2) '${names[i].env} (or "helder": {"ios": {"signing": {"${names[i].key}"}}})'];
		if (missing.length > 0) throw 'signing for the App Store takes a certificate and its key (HELDER_IOS_IDENTITY: both in one PEM): ${missing.join(", ")} not given';
		function bytes(g:{name:String, value:String, file:Bool}, text:Bool):haxe.io.Bytes {
			if (text && !g.file && g.value.indexOf("-----BEGIN") >= 0) return haxe.io.Bytes.ofString(g.value);
			if (FileSystem.exists(g.value) && !FileSystem.isDirectory(g.value)) return File.getBytes(g.value);
			if (!text && !g.file) {
				var b64 = ~/\s+/g.replace(g.value, "");
				var d = try haxe.crypto.Base64.decode(b64) catch (_:Dynamic) null;
				if (d != null && d.length > 0 && d.get(0) == 0x30) return d;
			}
			throw '${g.name}: ${g.value.length > 200 ? g.value.substr(0, 40) + "..." : g.value}: no such file' + (g.file ? "" : text ? " (nor PEM text)" : " (nor the profile in base64)");
		}
		function named(g:{name:String, value:String, file:Bool}, f:Void->Dynamic):Dynamic
			return try f() catch (err:String) throw err.startsWith("HELDER_IOS_") || err.startsWith('"helder"') ? err : '${g.name}: $err';
		var who = bundle != null && bundle.trim() != "" ? "HELDER_IOS_IDENTITY" : '${given[0].name}, ${given[1].name}';
		var identity:Identity = named({name: who, value: "", file: false}, () -> Identity.fromPem(bytes(given[0], true).toString(), bytes(given[1], true).toString()));
		// (no profile given: App Store Connect's, fetched by build: Publish.profile)
		var profile:Null<Profile> = given[2] == null ? null : named(given[2], () -> Profile.parse(bytes(given[2], false)));
		return {identity: identity, profile: profile};
	}

	// the manifest's icons and splash as the bundle's files and Info.plist's
	// keys, without Xcode: the app icon's asset catalog (Assets.car:
	// helder.pack.ios.AssetCatalog, the renditions App Store validation
	// asks for, opaque: Icons.iosPixels) named in CFBundleIcons (and
	// ~ipad's), with the loose PNGs actool writes beside it; the launch
	// screen (UILaunchScreen's UIImageName, an image shown at its size in the
	// middle of the screen): the splash image, else the icon, at 160 points
	// on a square of the splash's background as large as the largest
	// screen (an iPhone's at @3x, an iPad's at @2x), so that the colour
	// fills it (UIColorName would need an asset catalog's colour). None for
	// package.json's "helder" key's app
	public static function artwork(cfg:Dynamic, root:String, min = "15.0", ?read:String->haxe.io.Bytes):{files:Array<{path:String, data:haxe.io.Bytes}>, keys:Map<String, helder.pack.ios.Plist.PValue>} {
		var m:Manifest.AppConfig = cfg, files = [], keys = new Map<String, helder.pack.ios.Plist.PValue>();
		if (m == null || m.icons == null && m.splash == null) return {files: files, keys: keys};
		var icons = new Icons(m, root, read);
		if (icons.has("any") || icons.has("maskable")) {
			files.push({path: "Assets.car", data: AssetCatalog.appIcon(icons.iosPixels, min)});
			for (f in AssetCatalog.LOOSE) files.push({path: f.file, data: icons.ios(f.px)});
			for (k => v in AssetCatalog.plistKeys()) keys.set(k, v);
		}
		var s = m.splash;
		if (s != null && (s.background != null || s.image != null)) {
			var phone = icons.launch(LAUNCH_POINTS * 3, 160 * 3, s.image, s.background), pad = icons.launch(LAUNCH_POINTS_PAD * 2, 160 * 2, s.image, s.background);
			if (phone != null) {
				files.push({path: "LaunchImage@3x~iphone.png", data: phone});
				files.push({path: "LaunchImage@2x~ipad.png", data: pad});
				keys.set("UILaunchScreen", PDict(["UIImageName" => PString("LaunchImage"), "UIImageRespectsSafeAreaInsets" => PBool(false)]));
			}
		}
		return {files: files, keys: keys};
	}

	// (the largest screens' longer side in points: iPhone Pro Max, iPad Pro 13")
	static inline var LAUNCH_POINTS = 960;
	static inline var LAUNCH_POINTS_PAD = 1376;

	// --- a simulator's tools

	// -d's simulator, or the one booted; an error's message thrown
	@:coroutine public static function device(given:Null<String>):Device {
		if (Devices.xcrun() == null)
			throw Sys.systemName() == "Mac" ? "xcrun not found (Xcode's command line tools)" : "the iOS simulator: on macOS only (xcrun simctl)";
		return Devices.pick(Devices.ios().rows, "ios", given);
	}

	@:coroutine public static function simctl(args:Array<String>):{code:Int, text:String, errors:String}
		return Devices.output(Devices.xcrun(), ["simctl"].concat(args));

	static function check(what:String, r:{code:Int, text:String, errors:String}) {
		if (r.code != 0) throw '$what: exit code ${r.code}\n' + (r.text + "\n" + r.errors).trim();
	}

	// booted, when it is not (and until it has finished booting)
	@:coroutine public static function boot(d:Device) {
		if (d.kind.indexOf("booted") >= 0) return;
		check('xcrun simctl boot ${d.id}', simctl(["boot", d.id]));
		check('xcrun simctl bootstatus ${d.id}', simctl(["bootstatus", d.id, "-b"]));
	}

	@:coroutine public static function install(udid:String, app:String)
		check('xcrun simctl install $app', simctl(["install", udid, app]));

	// launched (a running one ended first), its output on the process's
	// (--console: simctl stays until the app ends); env: the app's
	// environment (SIMCTL_CHILD_ for each)
	public static function launch(udid:String, id:String, ?env:Map<String, String>):Process {
		var all = Process.environment();
		if (env != null) for (k => v in env) all.set('SIMCTL_CHILD_$k', v);
		return new Process(Devices.xcrun(), ["simctl", "launch", "--console", "--terminate-running-process", udid, id], {env: all});
	}
}
