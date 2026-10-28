package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.BuildCommand.Mode;
import helder.cli.Compiler.CompileServer;
import helder.cli.Devices.Device;
import helder.pack.ios.Bundle;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `--target ios` and `ios-sim`: an app bundle around hxmc's Mach-O
// executable (ios-arm64, an iPhone's: for build only, an .ipa, since a
// device needs a signing identity and a profile, not written yet;
// ios-sim-arm64, the simulator's: an .app, which run and dev install). The
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

	// the bundle's files, then the executable linked into it (and the .ipa)
	@:coroutine public static function build(e:Entry, out:String, mode:Mode, ?server:CompileServer, ?extra:Array<String>):{ok:Bool, ms:Int, messages:String} {
		if (!out.endsWith(".app") && !out.endsWith(".ipa")) throw '$out: an iOS app is a .app or an .ipa';
		var app = app(out), name = Path.withoutExtension(Path.withoutDirectory(app));
		var o = App.ios(e.name, e.config);
		var info = Bundle.infoPlist(name, o.id, o.label, o.version, o.versionName, o.minVersion, e.target == "ios-sim-arm64");
		var resources = Bundle.codeResources(["Info.plist" => info]);
		// (the bundle afresh: what an older build left in it is not signed)
		if (FileSystem.exists(app)) TestCommand.rmrf(app);
		TestCommand.mkdirs('$app/_CodeSignature');
		File.saveBytes('$app/Info.plist', info);
		File.saveBytes('$app/_CodeSignature/CodeResources', resources);
		var full = FileSystem.fullPath(app);
		var words = ["-D", 'hxmc.ios-min-version=${o.minVersion}', "-D", 'hxmc.codesign-id=${o.id}', "-D", 'hxmc.codesign-info-plist=$full/Info.plist', "-D",
			'hxmc.codesign-resources=$full/_CodeSignature/CodeResources'];
		if (o.entitlements != null) {
			var ent = Path.isAbsolute(o.entitlements) || e.root == "." ? o.entitlements : '${e.root}/${o.entitlements}';
			if (!FileSystem.exists(ent)) throw '$ent: no such file (package.json\'s "helder": {"ios": {"entitlements"}})';
			words = words.concat(["-D", 'hxmc.codesign-entitlements=${FileSystem.fullPath(ent)}']);
		}
		var exe = executable(app);
		return BuildCommand.build(e, exe, mode, server, words.concat(extra ?? []), () -> {
			if (out.endsWith(".ipa")) File.saveBytes(out, Bundle.ipa(name, File.getBytes(exe), info, resources));
			out;
		});
	}

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
