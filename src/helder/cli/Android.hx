package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.BuildCommand.Mode;
import helder.cli.Compiler.CompileServer;
import helder.cli.Devices.Device;
import helder.pack.android.Apk;
import helder.pack.android.Apk.ApkOptions;
import helder.pack.android.Apk.Signer;
import helder.pack.android.Arsc;
import helder.pack.android.Axml;
import helder.pack.android.Axml.Element as XmlElement;
import helder.pack.android.DebugKey;
import helder.pack.android.Glue;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `--target android`: the program built by hxmc as Android's shared library
// (android-arm64, a phone's; android-x86_64, an emulator's: the device's
// own ABI for run and dev), named libmain.so (its soname), then packaged by
// helder.pack.android into an APK: the manifest of package.json's "helder"
// key (App), classes.dex when the program needs it (Classes, a macro of the
// build, tells), signed with the user's debug key (DebugKey:
// HELDER_ANDROID_KEY, else "helder": {"android": {"key"}}, else
// <helder's cache>/android/debug-key, made on first use). Outputs:
// bin/android/<name>.apk, the library and the macro's answer beside it in
// bin/android/<name>.lib/. On a device (adb -s <id>): installed (install
// -r), started (am start, the launcher's activity), its output logcat's
// (tag hxmc); helder dev's reverse port (adb reverse) for the dev server.
// The program's assets (helder.asset: the files its code names and keeps,
// the build's manifest) go in the APK's assets/, stored.
class Android {
	// --target's hxmc target: android-arm64 or android-x86_64 as given; for
	// android the device's ABI when one is known, else a phone's
	public static function target(t:String, abi:Null<String>):String
		return t == "android" ? (abi ?? "android-arm64") : t;

	public static function out(e:Entry, bundle = false):String
		return Entry.clean('${e.root}/bin/android/${e.name}.${bundle ? "aab" : "apk"}');

	// the library built for an APK, beside it
	public static function library(apk:String):String
		return Path.withoutExtension(apk) + ".lib/" + Apk.LIBRARY;

	static function classesFile(apk:String):String
		return Path.withoutExtension(apk) + ".lib/classes.json";

	// the library, then the APK (dev: helder dev's host, which asks for
	// INTERNET; packed false: the library alone, a build helder dev sends)
	@:coroutine public static function build(e:Entry, apk:String, mode:Mode, ?server:CompileServer, ?extra:Array<String>, dev = false,
			packed = true):{ok:Bool, ms:Int, messages:String} {
		var lib = library(apk), classes = classesFile(apk);
		TestCommand.mkdirs(Path.directory(lib));
		try FileSystem.deleteFile(classes) catch (_:Dynamic) {};
		// (a Haxe string in the macro call: forward slashes)
		var words = ["--macro", 'helder.pack.android.Classes.write("${FileSystem.fullPath(Path.directory(lib)).split("\\").join("/")}/classes.json")'].concat(App.defines(e.config));
		return BuildCommand.build(e, lib, mode, server, words.concat(extra ?? []), packed ? () -> {
			pack(e, lib, apk, dev);
			apk;
		} : null);
	}

	// the APK of a built library (its assets in assets/, but a dev build's:
	// helder dev serves those)
	public static function pack(e:Entry, lib:String, apk:String, dev = false) {
		var c = classes(apk);
		var release = dev ? null : releaseSigner(e.config, e.root);
		var key = release ?? Apk.debugSigner(debugKey(e));
		var assets = dev ? [] : [for (a in AssetStep.assets(lib)) {name: helder.asset.AssetPath.bundled(a.key), data: File.getBytes(a.file)}];
		var o = options(e, c.views, dev, release == null);
		File.saveBytes(apk, Apk.write(File.getBytes(lib), e.target, c.dex ? Glue.dex() : null, c.views, o, key, assets));
	}

	// the debug key (HELDER_ANDROID_KEY: the key's text, or its file's path)
	static function debugKey(e:Entry):{d:haxe.io.Bytes, cert:haxe.io.Bytes} {
		var env = Sys.getEnv("HELDER_ANDROID_KEY");
		return env != null && DebugKey.isText(env) ? DebugKey.fromEnv(env) : DebugKey.load(App.androidKey(e.config, e.root, DevCommand.cache(), env));
	}

	// the release key: HELDER_ANDROID_UPLOAD_IDENTITY (one PEM of both), or HELDER_ANDROID_SIGNING_CERTIFICATE and
	// HELDER_ANDROID_SIGNING_KEY (PEM: each a file's path or its text), else
	// the manifest's "android": {"signing": {"certificate", "key"}} (paths
	// from the project); null: none (the debug key). One without the other: an error
	public static function releaseSigner(cfg:Dynamic, root:String, ?env:String->Null<String>):Null<Signer> {
		env = env ?? Sys.getEnv;
		var m:Dynamic = cfg?.android?.signing;
		function given(name:String, key:String):Null<{name:String, value:String, file:Bool}> {
			var v = env(name);
			if (v != null && v.trim() != "") return {name: name, value: v, file: v.indexOf("-----BEGIN") < 0};
			var f:Dynamic = m == null ? null : Reflect.field(m, key);
			return f == null ? null : {name: '"helder": {"android": {"signing": {"$key"}}}', value: Path.isAbsolute(f) || root == "." ? f : '$root/$f', file: true};
		}
		var cert = given("HELDER_ANDROID_SIGNING_CERTIFICATE", "certificate"), key = given("HELDER_ANDROID_SIGNING_KEY", "key");
		// (HELDER_ANDROID_UPLOAD_IDENTITY: the certificate and the key in one PEM, over the two)
		var both = env("HELDER_ANDROID_UPLOAD_IDENTITY");
		if (both != null && both.trim() != "") {
			var g = {name: "HELDER_ANDROID_UPLOAD_IDENTITY", value: both, file: both.indexOf("-----BEGIN") < 0};
			cert = g;
			key = g;
		}
		if (cert == null && key == null) return null;
		if (cert == null || key == null)
			throw 'release signing takes a certificate and its key: ${cert == null ? "HELDER_ANDROID_SIGNING_CERTIFICATE (or \"helder\": {\"android\": {\"signing\": {\"certificate\"}}})" : "HELDER_ANDROID_SIGNING_KEY (or \"helder\": {\"android\": {\"signing\": {\"key\"}}})"} not given';
		function text(g:{name:String, value:String, file:Bool}):String {
			if (!g.file) return g.value;
			if (!FileSystem.exists(g.value)) throw '${g.name}: ${g.value}: no such file (nor PEM text)';
			return File.getContent(g.value);
		}
		var id = try helder.pack.apple.Identity.fromPem(text(cert), text(key)) catch (err:String) throw (cert == key ? cert.name : '${cert.name}, ${key.name}') + ': $err';
		return Apk.releaseSigner(id);
	}

	// the manifest's options with its resources (debuggable: a debug key's build)
	static function options(e:Entry, views:Bool, dev:Bool, debuggable:Bool):ApkOptions {
		var o = App.android(e.name, e.config, dev);
		Manifest.warn(e);
		var r = resources(e.config, e.root, o.id, views);
		return r == null ? {
			id: o.id,
			label: o.label,
			versionCode: o.versionCode,
			versionName: o.versionName,
			minSdk: o.minSdk,
			targetSdk: o.targetSdk,
			permissions: o.permissions,
			orientation: o.orientation,
			debuggable: debuggable
		} : {
			id: o.id,
			label: o.label,
			versionCode: o.versionCode,
			versionName: o.versionName,
			minSdk: o.minSdk,
			targetSdk: o.targetSdk,
			permissions: o.permissions,
			orientation: o.orientation,
			resources: r.files,
			icon: r.icon,
			theme: r.theme,
			debuggable: debuggable
		};
	}

	// an App Bundle for Google Play: the program built for both ABIs
	// (android-arm64, android-x86_64; their libraries beside it, in
	// <name>.<abi>.lib/), its resources and manifest in aapt2's protobuf
	// formats, signed by the release key (required: Play's upload key)
	@:coroutine public static function bundle(e:Entry, out:String):{ok:Bool, ms:Int, messages:String} {
		if (!out.endsWith(".aab")) throw '$out: an App Bundle is an .aab';
		var key = releaseSigner(e.config, e.root);
		if (key == null)
			throw "an App Bundle is signed by the upload key: HELDER_ANDROID_SIGNING_CERTIFICATE and HELDER_ANDROID_SIGNING_KEY (or \"helder\": {\"android\": {\"signing\"}}) not given";
		var libs = [], last = null, ms = 0;
		for (t in ["android-arm64", "android-x86_64"]) {
			e.target = t;
			Runtime.ensure(t);
			var base = Path.withoutExtension(out) + "." + Apk.abiDir(t);
			var r = build(e, base + ".apk", Release, null, null, false, false);
			ms += r.ms;
			if (!r.ok) return r;
			libs.push({target: t, so: File.getBytes(library(base + ".apk")), lib: library(base + ".apk"), classes: classes(base + ".apk")});
			last = r;
		}
		var c = libs[0].classes;
		var assets = [for (a in AssetStep.assets(libs[0].lib)) {name: helder.asset.AssetPath.bundled(a.key), data: File.getBytes(a.file)}];
		var o = options(e, c.views, false, false);
		var r = resources(e.config, e.root, o.id, c.views);
		File.saveBytes(out, helder.pack.android.Aab.write([for (l in libs) {target: l.target, so: l.so}], c.dex ? Glue.dex() : null, Apk.manifestOf(o, c.dex, c.views),
			r == null ? null : {table: r.table, files: r.files, xml: r.xml}, assets, key));
		Term.out(helder.cli.Style.status("bundled", helder.cli.Style.Tone.Ok, helder.cli.Style.path(out) + helder.cli.Style.dim(helder.cli.Style.sep() + Math.round(FileSystem.stat(out).size / 1024) + " KB")));
		return {ok: true, ms: ms, messages: last.messages};
	}

	// the manifest's icon and splash as Android's resources (null: neither,
	// package.json's "helder" key's app): the adaptive icon (Icons: its
	// foreground at xxxhdpi, background_color behind it, the monochrome
	// layer of a monochrome icon), the splash's theme (Android 12's
	// SplashScreen: windowSplashScreenBackground, and the image as its
	// windowSplashScreenAnimatedIcon, else the launcher's icon; the window's
	// background the same colour before it, and on Android 10 and 11),
	// their dark variants in the night configuration; theme_color the
	// system bars' (statusBarColor, navigationBarColor); the activity's theme
	// the framework's it was (views: DayNight) as their parent
	public static function resources(cfg:Dynamic, root:String, pkg:String, views:Bool, ?read:String->haxe.io.Bytes):Null<{
		files:Array<{name:String, data:haxe.io.Bytes}>,
		icon:Null<Int>,
		theme:Null<Int>,
		table:Arsc,
		xml:Map<String, XmlElement>
	}> {
		var m:Manifest.AppConfig = cfg;
		if (m == null || m.icons == null && m.splash == null && m.theme == null) return null;
		var icons = new Icons(m, root, read), t = new Arsc(pkg), files = [];
		var icon:Null<Int> = null, theme:Null<Int> = null, xml = new Map<String, XmlElement>();
		var density:Config = {density: Arsc.XXXHDPI};
		function file(type:String, name:String, path:String, data:haxe.io.Bytes, ?config:Config):Int {
			files.push({name: path, data: data});
			return t.add(type, name, FilePath(path), config);
		}
		var fg = icons.androidForeground();
		if (fg != null) {
			var bg = t.add("color", "ic_launcher_background", Argb(icons.background()));
			var layers = [
				Axml.el("background", [{android: true, name: "drawable", type: Axml.REFERENCE, value: bg}]),
				Axml.el("foreground", [
					{android: true, name: "drawable", type: Axml.REFERENCE, value: file("mipmap", "ic_launcher_foreground", "res/mipmap-xxxhdpi-v4/ic_launcher_foreground.png", fg, density)}
				])
			];
			var mono = icons.androidMonochrome();
			if (mono != null) layers.push(Axml.el("monochrome", [
				{android: true, name: "drawable", type: Axml.REFERENCE, value: file("mipmap", "ic_launcher_monochrome", "res/mipmap-xxxhdpi-v4/ic_launcher_monochrome.png", mono, density)}
			]));
			// (an adaptive icon in every configuration: minSdk is 29, adaptive icons are 26's)
			var adaptive = Axml.el("adaptive-icon", [], layers);
			xml.set("res/mipmap-anydpi-v26/ic_launcher.xml", adaptive);
			icon = file("mipmap", "ic_launcher", "res/mipmap-anydpi-v26/ic_launcher.xml", Axml.encode(adaptive));
		}
		var s = m.splash, items:Array<{attr:Int, value:Value}> = [];
		if (s?.background != null) {
			var c = t.add("color", "splash_background", Argb(s.background));
			if (s.darkBackground != null) t.add("color", "splash_background", Argb(s.darkBackground), {night: true});
			items.push({attr: WINDOW_BACKGROUND, value: Ref(c)});
			items.push({attr: SPLASH_BACKGROUND, value: Ref(c)});
		}
		if (s?.image != null) {
			var id = file("mipmap", "splash_icon", "res/mipmap-xxxhdpi-v4/splash_icon.png", icons.androidSplash(s.image), density);
			if (s.darkImage != null) file("mipmap", "splash_icon", "res/mipmap-night-xxxhdpi-v8/splash_icon.png", icons.androidSplash(s.darkImage), {density: Arsc.XXXHDPI, night: true});
			items.push({attr: SPLASH_ICON, value: Ref(id)});
		}
		// (theme_color: the system bars', the window's statusBarColor and navigationBarColor;
		// Android 15's edge to edge, at targetSdk 35, draws them behind the app instead)
		if (m.theme != null) {
			var c = t.add("color", "theme_color", Argb(m.theme));
			items.push({attr: STATUS_BAR_COLOR, value: Ref(c)});
			items.push({attr: NAVIGATION_BAR_COLOR, value: Ref(c)});
		}
		if (items.length > 0) theme = t.add("style", "Theme.Helder", Style(views ? Apk.THEME_VIEWS : Apk.THEME, items));
		if (icon == null && theme == null) return null;
		files.unshift({name: "resources.arsc", data: t.encode()});
		return {files: files, icon: icon, theme: theme, table: t, xml: xml};
	}

	// the framework's attributes (public.xml): windowBackground, windowSplashScreenBackground, windowSplashScreenAnimatedIcon,
	static inline var WINDOW_BACKGROUND = 0x01010054;
	static inline var SPLASH_BACKGROUND = 0x0101062c;
	static inline var SPLASH_ICON = 0x0101062d;
	// statusBarColor, navigationBarColor
	static inline var STATUS_BAR_COLOR = 0x01010451;
	static inline var NAVIGATION_BAR_COLOR = 0x01010452;

	// what the build's Classes wrote: classes.dex, org.hxmc.Activity
	static function classes(apk:String):{dex:Bool, views:Bool} {
		var f = classesFile(apk);
		if (!FileSystem.exists(f)) throw '$f: not written (helder.pack.android.Classes did not run)';
		var j:Dynamic = haxe.Json.parse(File.getContent(f));
		return {dex: j.dex == true, views: j.views == true};
	}

	// the activity an APK starts: org.hxmc.Activity with views, else NativeActivity
	public static function activity(apk:String):String
		return classes(apk).views ? Glue.ACTIVITY : "android.app.NativeActivity";

	// --- a device's tools

	// -d's device, or the one there is; an error's message thrown
	@:coroutine public static function device(given:Null<String>):Device {
		if (Devices.adb() == null) throw "adb not found (Android's platform-tools on the PATH, or ADB)";
		return Devices.pick(Devices.android().rows, "android", given);
	}

	@:coroutine public static function adb(serial:String, args:Array<String>):{code:Int, text:String, errors:String}
		return Devices.output(Devices.adb(), ["-s", serial].concat(args));

	// the device's ABI as an hxmc target (getprop ro.product.cpu.abi)
	@:coroutine public static function abi(serial:String):String {
		var r = adb(serial, ["shell", "getprop", "ro.product.cpu.abi"]);
		return switch r.text.trim() {
			case "arm64-v8a": "android-arm64";
			case "x86_64": "android-x86_64";
			case "" if (r.code != 0): throw 'adb -s $serial shell getprop: exit code ${r.code} ${r.errors.trim()}';
			case a: throw '$serial is $a: helder builds for arm64-v8a and x86_64';
		}
	}

	// a tool's failure as one message (null: it did not fail)
	static function failed(what:String, r:{code:Int, text:String, errors:String}):Null<String>
		return r.code == 0 && r.text.indexOf("Failure") < 0 && r.text.indexOf("Error:") < 0 ? null : '$what: exit code ${r.code}\n' + (r.text + "\n" + r.errors).trim();

	// installed over the app there (its data kept, the same debug key)
	@:coroutine public static function install(serial:String, apk:String) {
		var f = failed('adb install $apk', adb(serial, ["install", "-r", apk]));
		if (f != null) throw f;
	}

	// started as the launcher starts it (stopped first: a fresh process)
	@:coroutine public static function start(serial:String, id:String, activity:String) {
		adb(serial, ["shell", "am", "force-stop", id]);
		var f = failed('adb shell am start $id', adb(serial, ["shell", "am", "start", "-W", "-n", '$id/$activity', "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER"]));
		if (f != null) throw f;
	}

	// the device's 127.0.0.1:port reaching this machine's (helder dev's server)
	@:coroutine public static function reverse(serial:String, port:Int) {
		var f = failed('adb reverse tcp:$port', adb(serial, ["reverse", 'tcp:$port', 'tcp:$port']));
		if (f != null) throw f;
	}

	// the app's process id there, "" when it runs not
	@:coroutine public static function pid(serial:String, id:String):String
		return adb(serial, ["shell", "pidof", id]).text.trim();

	// what the app prints (logcat's tag hxmc, from now on): a process whose lines are those
	@:coroutine public static function logcat(serial:String):Null<Process> {
		adb(serial, ["logcat", "-c"]);
		return try new Process(Devices.adb(), ["-s", serial, "logcat", "-v", "raw", "-s", "hxmc:V"]) catch (_:haxe.Exception) null;
	}
}
