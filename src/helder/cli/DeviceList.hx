package helder.cli;

using StringTools;

// helder devices' lists, read from adb's and simctl's output, and its table
// (pure: Devices runs the tools)
class DeviceList {
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
