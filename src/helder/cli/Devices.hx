package helder.cli;

import helder.async.*;
import helder.cli.BuildCommand.Lines;
import sys.FileSystem;

using StringTools;

// `helder devices`: where a program can run: this machine (host), a
// browser (web, through helder dev's server), Android's devices and
// emulators (`adb devices -l`: ADB names adb, else the PATH's, else
// $ANDROID_HOME/platform-tools') and iOS's simulators (`xcrun simctl list
// devices available`, on macOS; XCRUN names another xcrun). A table: id,
// name, kind, target. `pick` is -d's default for helder dev and run with
// --target android or ios (Android, Ios): the one device there is, else an
// error naming them.
class Devices {
	@:coroutine public static function run(o:Options):Int {
		var rows = [
			{id: "host", name: 'this machine (${Sys.systemName()})', kind: "host", target: Compiler.hostTarget()},
			{id: "web", name: "a browser, through helder dev's server", kind: "browser", target: "web"},
		];
		var notes = [];
		for (r in [android(), ios()]) {
			rows = rows.concat(r.rows);
			if (r.note != null) notes.push(r.note);
		}
		var table = table(rows).split("\n");
		Term.out(Style.bold(table[0]));
		for (l in table.slice(1)) Term.out(l);
		if (notes.length > 0) {
			Term.out("");
			for (n in notes) Term.out(Style.dim(n));
		}
		Term.out("");
		Term.out(Style.dim("helder dev, run, build: --target <target>; -d <id> for android and ios (by default the one device there is)"));
		return 0;
	}

	// adb: ADB, else the PATH's, else the SDK's (ANDROID_HOME, ANDROID_SDK_ROOT); null if none
	public static function adb():Null<String> {
		var env = Sys.getEnv("ADB");
		if (env != null && env != "") return env;
		var p = which("adb");
		if (p != null) return p;
		for (v in ["ANDROID_HOME", "ANDROID_SDK_ROOT"]) {
			var sdk = Sys.getEnv(v);
			if (sdk == null || sdk == "") continue;
			for (n in ["adb", "adb.exe"]) if (FileSystem.exists('$sdk/platform-tools/$n')) return '$sdk/platform-tools/$n';
		}
		return null;
	}

	// xcrun: XCRUN, else the PATH's on macOS; null if none
	public static function xcrun():Null<String> {
		var env = Sys.getEnv("XCRUN");
		if (env != null && env != "") return env;
		return Sys.systemName() == "Mac" ? which("xcrun") : null;
	}

	// Android's devices and emulators, or a note why there are none
	@:coroutine public static function android():{rows:Array<Device>, note:Null<String>} {
		var adb = adb();
		if (adb == null) return {rows: [], note: "adb not found: no Android devices or emulators (Android's platform-tools on the PATH, or ADB)"};
		var r = output(adb, ["devices", "-l"]);
		return r.code == 0 ? {rows: adbDevices(r.text), note: null} : {rows: [], note: 'adb devices -l: exit code ${r.code}'};
	}

	// iOS's simulators, or a note why there are none
	@:coroutine public static function ios():{rows:Array<Device>, note:Null<String>} {
		var xcrun = xcrun();
		if (xcrun == null)
			return {
				rows: [],
				note: Sys.systemName() == "Mac" ? "xcrun not found: no iOS simulators (Xcode's command line tools)" : "iOS simulators: on macOS only (xcrun simctl)"
			};
		var r = output(xcrun, ["simctl", "list", "devices", "available"]);
		return r.code == 0 ? {rows: simulators(r.text), note: null} : {rows: [], note: 'xcrun simctl: exit code ${r.code}'};
	}

	// a program on the PATH, null if none
	public static function which(name:String):Null<String> {
		var win = Sys.systemName() == "Windows";
		for (d in (Sys.getEnv("PATH") ?? "").split(win ? ";" : ":")) {
			if (d == "") continue;
			for (n in (win ? ['$name.exe', '$name.bat', name] : [name])) {
				var p = '$d/$n';
				if (FileSystem.exists(p) && !FileSystem.isDirectory(p)) return p;
			}
		}
		return null;
	}

	// a tool's exit code, its output and its errors (-1: it did not start)
	@:coroutine public static function output(cmd:String, args:Array<String>):{code:Int, text:String, errors:String} {
		var p = try new Process(cmd, args) catch (e:haxe.Exception) return {code: -1, text: "", errors: '$cmd: ${e.message}'};
		p.closeStdin();
		var lines = [], errors = [];
		Async.scope(task -> {
			task.async(_ -> Lines.collect(p.stdout, lines));
			task.async(_ -> Lines.collect(p.stderr, errors));
			null;
		});
		var code = p.wait();
		p.close();
		return {code: code, text: lines.join("\n"), errors: errors.join("\n")};
	}

	// (the lists, read from adb's and simctl's output, the table and -d's default: pure)

	// `adb devices -l`'s lines: an id, a state, then key:value pairs (a
	// device not ready, unauthorized or offline: its state after the kind)
	public static function adbDevices(text:String):Array<Device> {
		var out = [];
		for (l in text.split("\n")) {
			var w = [for (x in ~/\s+/g.split(l.trim())) if (x != "") x];
			if (w.length < 2 || w[0].startsWith("*") || l.startsWith("List of devices")) continue;
			var props = new Map<String, String>();
			for (x in w.slice(2)) {
				var i = x.indexOf(":");
				if (i > 0) props.set(x.substr(0, i), x.substr(i + 1));
			}
			var name = (props.get("model") ?? props.get("device") ?? w[0]).replace("_", " ");
			var kind = (w[0].startsWith("emulator-") ? "emulator" : "device") + (w[1] == "device" ? "" : ', ${w[1]}');
			out.push({id: w[0], name: name, kind: kind, target: "android"});
		}
		return out;
	}

	// `xcrun simctl list devices available`: iOS's sections' simulators
	public static function simulators(text:String):Array<Device> {
		var out = [], os:Null<String> = null;
		var section = ~/^-- (.+) --$/, sim = ~/^\s+(.+) \(([0-9A-Fa-f-]{36})\) \(([^)]+)\)\s*$/;
		for (l in text.split("\n")) {
			if (section.match(l.trim())) os = section.matched(1);
			else if (os != null && os.startsWith("iOS") && sim.match(l))
				out.push({
					id: sim.matched(2),
					name: '${sim.matched(1)} ($os)',
					kind: sim.matched(3) == "Booted" ? "simulator, booted" : "simulator",
					target: "ios"
				});
		}
		return out;
	}

	public static function table(rows:Array<Device>):String {
		var all = [{id: "id", name: "name", kind: "kind", target: "target"}].concat(rows);
		var w = [0, 0, 0];
		for (r in all) {
			w[0] = Std.int(Math.max(w[0], r.id.length));
			w[1] = Std.int(Math.max(w[1], r.name.length));
			w[2] = Std.int(Math.max(w[2], r.kind.length));
		}
		return [for (r in all) (r.id.rpad(" ", w[0] + 2) + r.name.rpad(" ", w[1] + 2) + r.kind.rpad(" ", w[2] + 2) + r.target).trim()].join("\n");
	}

	// -d's default for a platform (android, ios): the device named (its id;
	// a simulator also by its name), else the one there is (Android's ready,
	// not unauthorized or offline; iOS's booted); an error's message thrown
	// for none, or several
	public static function pick(rows:Array<Device>, platform:String, given:Null<String>):Device {
		var android = platform == "android";
		var mine = [for (r in rows) if (r.target == platform) r];
		if (given != null) {
			var d = Lambda.find(mine, r -> r.id == given);
			if (d == null && !android) d = Lambda.find(mine, r -> r.name == given || r.name.startsWith(given + " ("));
			if (d == null) throw 'no ${android ? "Android device" : "iOS simulator"} $given (helder devices lists them)';
			if (android && d.kind.indexOf(", ") > 0) throw '$given is ${d.kind.substr(d.kind.indexOf(", ") + 2)} (adb devices -l)';
			return d;
		}
		var ready = [for (r in mine) if (android ? r.kind.indexOf(", ") < 0 : r.kind.indexOf("booted") >= 0) r];
		if (ready.length == 1) return ready[0];
		if (ready.length == 0) {
			if (!android) throw "no booted iOS simulator: boot one (open -a Simulator), or name one with -d (helder devices lists them)";
			throw "no Android device or emulator ready"
				+ (mine.length > 0 ? ' (${[for (r in mine) '${r.id}: ${r.kind}'].join(", ")})' : ": connect a phone or start an emulator (adb devices)");
		}
		throw 'several ${android ? "Android devices" : "booted iOS simulators"}: pick one with -d (${[for (r in ready) '${r.id}: ${r.name}'].join(", ")})';
	}
}

typedef Device = {id:String, name:String, kind:String, target:String};
