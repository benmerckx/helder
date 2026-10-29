package helder.compiler;

import haxe.io.Path;
import sys.FileSystem;

using StringTools;

// helder's compiler: hxmc's compiler (the same command line as @hxmc/cli's
// `haxe`) with helder's hooks: markup in any function (MarkupHook), and its
// frontends (plugins: helder.typescript's), each given the compiler's short
// form, the start of a build (before Haxe types it) and its generation. So
// the helder CLI runs it as it runs hxmc's compiler: one-shot builds and
// `helder dev`'s compilation server alike.
class Compiler {
	// helder's frontends, one plugin each
	static final plugins:Array<Plugin> = [new helder.typescript.Frontend()];

	static function main() {
		Sys.exit(run(Sys.args()));
	}

	public static function run(args:Array<String>):Int {
		if (args.length > 0) for (plugin in plugins) {
			var direct = try plugin.direct(args) catch (e:Dynamic) {
				Sys.stderr().writeString(Std.string(e) + "\n");
				return 2;
			}
			if (direct != null) {
				args = direct;
				break;
			}
		}
		environment();
		// hxmc's std, given last (as hxmc.HaxeMain does)
		var hxmcStd = Sys.getEnv("HXMC_STD");
		if (hxmcStd != null && hxmcStd != "" && @:privateAccess hxmc.HaxeMain.selectsHxmc(args, 0)) args = args.concat(["-cp", hxmcStd]);
		hxmc.Defines.install();
		hxmc.ModuleCache.install();
		hxmc.ir.CInterop.install();
		hxmc.TargetFlags.install();
		hxmc.StdDce.install();
		MarkupHook.install();
		var typing = compiler.Compiler.beforeTypingHook;
		compiler.Compiler.beforeTypingHook = function(com, actx) {
			if (typing != null) typing(com, actx);
			// (a compilation server's parse replaces hxmc's: around it again)
			MarkupHook.install();
			for (plugin in plugins) plugin.beforeTyping(com, actx);
		}
		var failed:Null<String> = null;
		// (a compilation server keeps what it can between builds, as hxmc's does: the frontends' too)
		for (a in ["--wait", "--server-listen", "--server-connect"]) if (args.contains(a)) hxmc.Driver.resident = true;
		compiler.Compiler.generateHook = function(com) {
			var owner = Lambda.find(plugins, p -> p.owns(com));
			if (args.contains("--no-output") && owner == null) return;
			switch com.platform {
				case CustomTarget("hxmc"):
				case _: return;
			}
			try {
				if (owner == null) hxmc.Main.generate(com, com.file) else owner.generate(com);
			} catch (e:Dynamic) {
				if (Sys.getEnv("HELDER_TS_DEBUG") == "1") Sys.stderr().writeString(haxe.CallStack.toString(haxe.CallStack.exceptionStack()) + "\n");
				if (hxmc.Driver.resident) for (m in messages(Std.string(e))) com.error(m.text, m.pos) else failed = Std.string(e);
			}
		}
		var code = haxe.Main.run(args);
		hxmc.ModuleCache.finish(failed == null ? code : 1);
		if (failed != null) {
			Sys.stderr().writeString(failed + "\n");
			return 1;
		}
		return code;
	}

	// An error's lines as the compiler's messages, at their positions
	// (`file:line: characters a-b : text`, `file:line: text`): what a
	// compilation server's client gets, Haxe's own format.
	static function messages(error:String):Array<{text:String, pos:core.Globals.Pos}> {
		var ranged = ~/^(.+?):([0-9]+): characters ([0-9]+)-([0-9]+) : (.*)$/, lined = ~/^(.+?):([0-9]+): (.*)$/;
		return [for (line in error.split("\n")) if (line != "") {
			if (ranged.match(line)) {text: ranged.matched(5), pos: position(ranged.matched(1), Std.parseInt(ranged.matched(2)), Std.parseInt(ranged.matched(3)), Std.parseInt(ranged.matched(4)))};
			else if (lined.match(line)) {text: lined.matched(3), pos: position(lined.matched(1), Std.parseInt(lined.matched(2)), -1, -1)};
			else {text: line, pos: core.Globals.nullPos};
		}];
	}

	// a position in a file, as Haxe's: byte offsets; from a line (1-based) and
	// UTF-16 columns (-1: the whole line)
	static function position(file:String, line:Int, from:Int, to:Int):core.Globals.Pos {
		var bytes = try sys.io.File.getBytes(file) catch (_:Dynamic) return core.Globals.nullPos;
		var start = 0;
		for (_ in 1...line) {
			while (start < bytes.length && bytes.get(start) != "\n".code) start++;
			start++;
		}
		var end = start;
		while (end < bytes.length && bytes.get(end) != "\n".code) end++;
		if (from < 0) return new core.Globals.Pos(FileSystem.fullPath(file), start, end);
		// (UTF-16 columns to bytes)
		function at(column:Int):Int {
			var p = start, units = 0;
			while (p < end && units < column) {
				var c = bytes.get(p);
				p += c < 0x80 ? 1 : c < 0xE0 ? 2 : c < 0xF0 ? 3 : 4;
				units += c >= 0xF0 ? 2 : 1;
			}
			return p;
		}
		return new core.Globals.Pos(FileSystem.fullPath(file), at(from), at(to));
	}

	// helder's cache: HELDER_CACHE, else the user's (as build.mjs has it)
	public static function cache():String {
		var configured = Sys.getEnv("HELDER_CACHE");
		if (configured != null && configured != "") return configured;
		var home = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".";
		return switch Sys.systemName() {
			case "Windows": Path.join([Sys.getEnv("LOCALAPPDATA") ?? home, "helder", "cache"]);
			case "Mac": Path.join([home, "Library/Caches/helder"]);
			case _: Path.join([Sys.getEnv("XDG_CACHE_HOME") ?? Path.join([home, ".cache"]), "helder"]);
		}
	}

	// helder's sources: the class path holding `marker` (a file under it)
	public static function source(marker:String):String {
		var configured = Sys.getEnv("HELDER_SRC");
		if (configured != null && configured != "") return configured;
		for (start in [Path.directory(FileSystem.fullPath(Sys.programPath())), Sys.getCwd()]) {
			var dir = FileSystem.fullPath(start);
			while (dir != null && dir != "") {
				for (candidate in [dir + "/src", dir + "/node_modules/helder/src"])
					if (FileSystem.exists(candidate + "/" + marker)) return candidate;
				var up = Path.directory(dir);
				if (up == dir || up == "") break;
				dir = up;
			}
		}
		throw "helder's sources not found (set HELDER_SRC)";
	}

	// What @hxmc/cli's launcher gives its compiler: upstream's std, hxmc's,
	// and the platform packages' runtime objects.
	static function environment() {
		var cli = locate("node_modules/@hxmc/cli");
		if (cli == null) return;
		if ((Sys.getEnv("HAXE_STD_PATH") ?? "") == "") Sys.putEnv("HAXE_STD_PATH", cli + "/haxe/upstream/std");
		if ((Sys.getEnv("HXMC_STD") ?? "") == "") Sys.putEnv("HXMC_STD", cli + "/hxmc/bootstrap/hxmc-std");
		if ((Sys.getEnv("HXMC_RT_DIR") ?? "") == "") {
			var dir = Path.directory(cli);
			var dirs = [for (name in FileSystem.readDirectory(dir)) if (~/^(linux|darwin|win32)-/.match(name)) dir + "/" + name];
			Sys.putEnv("HXMC_RT_DIR", dirs.join(Sys.systemName() == "Windows" ? ";" : ":"));
		}
	}

	// rel in the working directory or one above it, else beside this program or above
	public static function locate(rel:String):Null<String> {
		for (start in [Sys.getCwd(), Path.directory(FileSystem.fullPath(Sys.programPath()))]) {
			var dir = FileSystem.fullPath(start);
			while (dir != null && dir != "") {
				var p = Path.join([dir, rel]);
				if (FileSystem.exists(p)) return p;
				var up = Path.directory(dir);
				if (up == dir || up == "") break;
				dir = up;
			}
		}
		return null;
	}
}
