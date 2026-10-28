package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.BuildCommand.Mode;
import helder.cli.Compiler.CompileServer;
import helder.cli.Devices.Device;
import helder.pack.android.Apk;
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

	public static function out(e:Entry):String
		return Entry.clean('${e.root}/bin/android/${e.name}.apk');

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
		var key = DebugKey.load(App.androidKey(e.config, e.root, DevCommand.cache(), Sys.getEnv("HELDER_ANDROID_KEY")));
		var assets = dev ? [] : [for (a in AssetStep.assets(lib)) {name: helder.asset.AssetPath.bundled(a.key), data: File.getBytes(a.file)}];
		File.saveBytes(apk, Apk.write(File.getBytes(lib), e.target, c.dex ? Glue.dex() : null, c.views, App.android(e.name, e.config, dev), key, assets));
	}

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
