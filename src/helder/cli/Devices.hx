package helder.cli;

import helder.async.*;
import helder.cli.BuildCommand.Lines;
import sys.FileSystem;

using StringTools;

// `helder devices`: where a program can run, what can be found today: this
// machine (host), a browser (web, through helder dev's server), Android's
// devices and emulators (`adb devices -l`, adb on the PATH) and iOS's
// simulators (`xcrun simctl list devices available`, on macOS). A table:
// id, name, kind, target. The device tooling proper (booting an emulator,
// installing, a device's own dev host) comes with the packaging's port from
// hxmc; until then --target android and ios are refused (Options.NOT_YET).
class Devices {
	@:coroutine public static function run(o:Options):Int {
		var rows = [
			{id: "host", name: 'this machine (${Sys.systemName()})', kind: "host", target: Compiler.hostTarget()},
			{id: "web", name: "a browser, through helder dev's server", kind: "browser", target: "web"},
		];
		var notes = [];
		var adb = which("adb");
		if (adb == null) notes.push("adb not found: no Android devices or emulators (Android's platform-tools on the PATH)");
		else {
			var r = output(adb, ["devices", "-l"]);
			if (r.code == 0) rows = rows.concat(adbDevices(r.text)) else notes.push('adb devices -l: exit code ${r.code}');
		}
		if (Sys.systemName() == "Mac") {
			var xcrun = which("xcrun");
			if (xcrun == null) notes.push("xcrun not found: no iOS simulators (Xcode's command line tools)");
			else {
				var r = output(xcrun, ["simctl", "list", "devices", "available"]);
				if (r.code == 0) rows = rows.concat(simulators(r.text)) else notes.push('xcrun simctl: exit code ${r.code}');
			}
		} else notes.push("iOS simulators: on macOS only (xcrun simctl)");
		var table = table(rows).split("\n");
		Term.out(Style.bold(table[0]));
		for (l in table.slice(1)) Term.out(l);
		if (notes.length > 0) {
			Term.out("");
			for (n in notes) Term.out(Style.dim(n));
		}
		Term.out("");
		Term.out(Style.dim('helder dev, run, build: --target <target>; -d <id> for android and ios (${Options.NOT_YET})'));
		return 0;
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

	@:coroutine static function output(cmd:String, args:Array<String>):{code:Int, text:String} {
		var p = try new Process(cmd, args) catch (e:haxe.Exception) return {code: -1, text: ""};
		p.closeStdin();
		var lines = [], errors = [];
		Async.scope(task -> {
			task.async(_ -> Lines.collect(p.stdout, lines));
			task.async(_ -> Lines.collect(p.stderr, errors));
			null;
		});
		var code = p.wait();
		p.close();
		return {code: code, text: lines.join("\n")};
	}

	// (the lists, read from adb's and simctl's output, and the table: pure)
	// `adb devices -l`'s lines: an id, a state, then key:value pairs
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
			if (w[1] != "device") name += ' (${w[1]})';
			out.push({id: w[0], name: name, kind: w[0].startsWith("emulator-") ? "emulator" : "device", target: "android"});
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
}

typedef Device = {id:String, name:String, kind:String, target:String};

