package helder.cli;

import sys.FileSystem;
import sys.io.File;

using StringTools;

// Where a dev build's time went (HELDER_DEV_PHASES=1, the edit-loop lane):
// the compiler's phases (helder.compiler.Phases, -D helder.phases: typing,
// lowering, codegen and link, a frontend's own) and hxmc's own split of
// its generation (HXMC_STATS=1 given to the compilation server: prepare,
// codegen, data, link, the modules cached and compiled), read from the
// server's output. Runtime.built carries them (`phases`).
class BuildPhases {
	public static final on = Sys.getEnv("HELDER_DEV_PHASES") == "1";

	// hxmc's lines since the last build
	static var stats:Array<String> = [];

	// the compilation server's environment: its stats on
	public static function environment(env:Map<String, String>)
		if (on) env.set("HXMC_STATS", "1");

	// a line of the compilation server's output
	public static function line(l:String)
		if (on && l.startsWith("hxmc: ")) stats.push(l.substr(6));

	// the build's define: the file its phases are written to
	public static function define(out:String):Array<String>
		return on ? ["-D", 'helder.phases=${file(out)}'] : [];

	static function file(out:String):String
		return FileSystem.fullPath(haxe.io.Path.directory(out) == "" ? "." : haxe.io.Path.directory(out)).split("\\").join("/") + "/"
			+ haxe.io.Path.withoutDirectory(out) + ".phases.json";

	// the last build's phases (null: off, or none written), hxmc's split of
	// its generation in `hxmc`
	public static function take(out:String):Null<Dynamic> {
		if (!on) return null;
		var f = file(out);
		var r:Dynamic = try haxe.Json.parse(File.getContent(f)) catch (_:Dynamic) null;
		try FileSystem.deleteFile(f) catch (_:Dynamic) {};
		var h:Dynamic = {};
		var num = (s:String) -> Std.parseFloat(s);
		for (l in stats) {
			var m = ~/^prepare ([0-9]+) ms, codegen ([0-9]+) ms/;
			if (m.match(l)) {
				h.prepare = num(m.matched(1));
				h.codegen = num(m.matched(2));
			}
			m = ~/^data ([0-9]+) ms, runtime read ([0-9]+) ms, link ([0-9]+) ms/;
			if (m.match(l)) {
				h.data = num(m.matched(1));
				h.runtime = num(m.matched(2));
				h.link = num(m.matched(3));
			}
			m = ~/^data ([0-9]+) ms, link ([0-9]+) ms/;
			if (m.match(l)) {
				h.data = num(m.matched(1));
				h.link = num(m.matched(2));
			}
			m = ~/^modules ([0-9]+): ([0-9]+) cached, ([0-9]+) compiled/;
			if (m.match(l)) {
				h.modules = num(m.matched(1));
				h.cached = num(m.matched(2));
				h.compiled = num(m.matched(3));
			}
			m = ~/^lowering ([0-9]+) ms/;
			if (m.match(l)) h.lowering = num(m.matched(1));
			m = ~/^bodies ([0-9]+) reused \(([0-9]+) by key\), ([0-9]+) lowered/;
			if (m.match(l)) {
				h.bodiesReused = num(m.matched(1));
				h.bodiesLowered = num(m.matched(3));
			}
			m = ~/^([0-9]+) functions$/;
			if (m.match(l)) h.functions = num(m.matched(1));
		}
		stats = [];
		if (r == null) r = {phases: []};
		r.hxmc = h;
		return r;
	}
}
