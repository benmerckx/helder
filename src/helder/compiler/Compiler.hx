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
		args = install(args);
		var code = haxe.Main.run(args);
		hxmc.ModuleCache.finish(failed == null ? code : 1);
		if (failed != null) {
			Sys.stderr().writeString(failed + "\n");
			return 1;
		}
		return code;
	}

	// a one-shot build's failure (a compilation server's are its messages)
	static var failed:Null<String> = null;

	// this build's --no-output (a compilation server's request's, not its own command line's)
	static var noOutput = false;

	// helder's hooks and frontends installed and the environment set (hxmc's
	// std, the runtime objects); args with hxmc's std given last. run's, and
	// helder.compiler.web.WebMain's (the compiler resident in a worker)
	public static function install(args:Array<String>):Array<String> {
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
			Phases.begin(com);
			noOutput = actx.noOutput;
			dev(com);
			nullSafety(actx);
			if (typing != null) typing(com, actx);
			// (a compilation server's parse replaces hxmc's: around it again)
			MarkupHook.install();
			for (plugin in plugins) plugin.beforeTyping(com, actx);
		}
		// (a compilation server keeps what it can between builds, as hxmc's does: the frontends' too)
		for (a in ["--wait", "--server-listen", "--server-connect"]) if (args.contains(a)) hxmc.Driver.resident = true;
		compiler.Compiler.generateHook = function(com) {
			var owner = Lambda.find(plugins, p -> p.owns(com));
			Phases.mark("to generation");
			if (noOutput && owner == null) {
				Phases.end();
				return;
			}
			switch com.platform {
				case CustomTarget("hxmc"):
				case _: return;
			}
			try {
				if (owner == null) hxmc.Main.generate(com, com.file, (com, prog) -> {
					Phases.mark("lowering");
					if (hxmc.Main.beforeCodegen != null) hxmc.Main.beforeCodegen(com, prog);
				}) else owner.generate(com);
				Phases.mark("codegen and link");
				Phases.end();
			} catch (e:Dynamic) {
				Phases.end();
				if (Sys.getEnv("HELDER_TS_DEBUG") == "1") Sys.stderr().writeString(haxe.CallStack.toString(haxe.CallStack.exceptionStack()) + "\n");
				if (hxmc.Driver.resident) for (m in messages(Std.string(e))) com.error(m.text, m.pos) else failed = Std.string(e);
			}
		}
		return args;
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
		for (start in [beside(), Sys.getCwd()]) if (start != null) {
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
	// a dev build reports where it failed: an uncaught exception's frames
	// with their files and lines natively (hxmc's table of them, in every
	// program), and in the browser the functions' names (a name section: the
	// JavaScript stack names each frame; hxmc has no lines there yet)
	static function dev(com:context.Common.CommonContext) {
		if (!core.Define.rawDefined(com.defines, "hxmc.dev")) return;
		core.Define.rawDefine(com.defines, "hxmc.stacks");
		if (core.Define.rawDefinedValueSafe(com.defines, "hxmc.target") == "wasm32-wasi") core.Define.rawDefine(com.defines, "hxmc.symbols");
	}

	// Haxe's null safety for helder's packages that keep it (NullSafety's,
	// by package; HELDER_NULL_SAFETY="<package>=<mode>,..." adds others, a
	// measure's): an init macro of every build this compiler makes
	static function nullSafety(actx:compiler.ParsedArg.ArgContext) {
		var env = Sys.getEnv("HELDER_NULL_SAFETY") ?? "";
		var all = [for (p in NullSafety.packages.keys()) p => NullSafety.packages.get(p)];
		for (kv in env.split(",")) {
			var i = kv.indexOf("=");
			if (i > 0) all.set(kv.substr(0, i), kv.substr(i + 1));
		}
		for (p => mode in all)
			actx.configMacros.unshift('nullSafety("$p", $mode)');
	}

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
		for (start in [Sys.getCwd(), beside()]) if (start != null) {
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

	// this program's directory (null where it has none: a worker's module)
	static function beside():Null<String>
		return try Path.directory(FileSystem.fullPath(Sys.programPath())) catch (_:Dynamic) null;
}
