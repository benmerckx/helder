package helder.test;

import haxe.PosInfos;
import sys.FileSystem;
import sys.io.File;

// Text snapshots (Test.snapshot), a file per test file beside it
// (Foo.test.hx's Foo.test.snap): each one a header with its key ("describe
// > test: name") and its number of lines, then the lines. Written at the
// end of the run when one was missing, or changed with -u; the others are
// kept (an obsolete one stays until removed by hand).
class Snapshots {
	static final files = new Map<String, {entries:Map<String, String>, dirty:Bool}>();

	public static function check(name:String, value:String, pos:PosInfos) {
		Runner.check();
		var c = Runner.running();
		var key = (c == null ? "" : c.fullName() + ": ") + name;
		var path = Runner.file(pos.fileName);
		path = (StringTools.endsWith(path, ".hx") ? path.substr(0, path.length - 3) : path) + ".snap";
		var f = files.get(path);
		if (f == null) {
			if (!files.iterator().hasNext()) Runner.atEnd.push(save);
			files.set(path, f = {entries: load(path), dirty: false});
		}
		var old = f.entries.get(key);
		if (old == value) return;
		if (old != null && !Runner.update) {
			Runner.failure('snapshot "$name" differs (-u: rewrite it)\n  expected:\n${indent(old)}\n  actual:\n${indent(value)}', pos);
			return;
		}
		f.entries.set(key, value);
		f.dirty = true;
	}

	static function indent(s:String):String
		return [for (l in s.split("\n")) "    " + l].join("\n");

	static function load(path:String):Map<String, String> {
		var out = new Map();
		if (!FileSystem.exists(path)) return out;
		var lines = File.getContent(path).split("\n");
		var head = ~/^--- (.*) \((\d+) lines?\)$/;
		var i = 0;
		while (i < lines.length) {
			if (!head.match(lines[i++])) continue;
			var n = Std.parseInt(head.matched(2));
			out.set(head.matched(1), lines.slice(i, i + n).join("\n"));
			i += n;
		}
		return out;
	}

	static function save()
		for (path => f in files) {
			if (!f.dirty) continue;
			var keys = [for (k in f.entries.keys()) k];
			keys.sort(Reflect.compare);
			var out = ["// helder.test snapshots: `helder test -u` rewrites them"];
			for (k in keys) {
				var v = f.entries.get(k).split("\n");
				out.push("");
				out.push('--- $k (${v.length} line${v.length == 1 ? "" : "s"})');
				for (l in v) out.push(l);
			}
			try File.saveContent(path, out.join("\n") + "\n") catch (e:Dynamic) Sys.println('helder.test: $path not written: $e');
		}
}
