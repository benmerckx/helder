package helder.typescript;

import haxe.io.Path;
import sys.FileSystem;
import helder.typescript.check.Project;
import helder.typescript.lower.Frontend;
import helder.typescript.ir.Verifier;
import helder.typescript.ir.TextIR;
import helder.typescript.glue.Glue;

using StringTools;

// hxmc's compiler with a TypeScript frontend: the same command line as
// @hxmc/cli's `haxe`, and a build given `-D helder.typescript=<entry.ts>`
// also checks that program with tsgo and lowers it straight into the
// program's IR, after the Haxe side (helder.typescript.js, the JavaScript
// runtime, and whatever it uses) is lowered and before code generation. So
// the helder CLI runs it as it runs hxmc's compiler: one-shot builds and
// `helder dev`'s compilation server alike.
//
// For a quick build, the compiler's short form: `<compiler> <entry.ts> [-o out] [--target t]
// [-D name[=value]] [--cp dir] [--dump-ir file] [--roundtrip-ir] [--coverage]`.
class Compiler {
	public static inline var DEFINE = "helder.typescript";

	static function main() {
		Sys.exit(run(Sys.args()));
	}

	public static function run(args:Array<String>):Int {
		if (args.length > 0 && ~/\.(m|c)?[jt]sx?$/.match(args[0])) {
			try args = direct(args) catch (e:Dynamic) {
				Sys.stderr().writeString(Std.string(e) + "\n");
				return 2;
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
		// (before Haxe types the program: the TypeScript program checked, its glue written)
		var typing = compiler.Compiler.beforeTypingHook;
		compiler.Compiler.beforeTypingHook = function(com, actx) {
			if (typing != null) typing(com, actx);
			prepared = null;
			var entry = core.Define.rawDefinedValueSafe(com.defines, DEFINE, "");
			if (entry != "" && com.platform.match(CustomTarget("hxmc"))) prepared = prepare(com, actx, entry);
		}
		var failed:Null<String> = null;
		// (a compilation server keeps what it can between builds, as hxmc's does: tsgo too)
		for (a in ["--wait", "--server-listen", "--server-connect"]) if (args.contains(a)) hxmc.Driver.resident = true;
		compiler.Compiler.generateHook = function(com) {
			if (args.contains("--no-output") && !core.Define.rawDefined(com.defines, DEFINE)) return;
			switch com.platform {
				case CustomTarget("hxmc"):
				case _: return;
			}
			try {
				var entry = core.Define.rawDefinedValueSafe(com.defines, DEFINE, "");
				if (entry == "") hxmc.Main.generate(com, com.file) else generate(com, entry);
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

	// what the build's start made of the TypeScript program: it checked, its
	// glue (or the error the check or the glue gave, reported where the build
	// would have lowered it)
	static var prepared:Null<{project:Null<Project>, glue:Null<Glue>, error:Null<String>}> = null;

	// The program checked (tsgo) and its glue written (helder.typescript.glue):
	// a Haxe module the build types with the rest, its class the build's main
	// (the runtime's seed and the glue reached from it). After a failed check,
	// a module with no glue, so the build reaches the error's report.
	static function prepare(com:context.Common.CommonContext, actx:compiler.ParsedArg.ArgContext, entry:String) {
		phase("start");
		var project:Null<Project> = null, glue:Null<Glue> = null, error:Null<String> = null;
		try {
			project = Project.check(entry, Path.join([source(), "helder/typescript/globals.d.ts"]));
			phase("check (tsgo)");
			glue = new Glue(project);
		} catch (e:Dynamic) {
			if (Sys.getEnv("HELDER_TS_DEBUG") == "1") Sys.stderr().writeString(haxe.CallStack.toString(haxe.CallStack.exceptionStack()) + "\n");
			error = Std.string(e);
		}
		var dir = Path.join([cache(), "glue", haxe.crypto.Md5.encode(FileSystem.fullPath(entry))]);
		var file = Path.join([dir, Glue.PACK, Glue.CLASS + ".hx"]);
		var text = glue != null ? glue.source(Project.relative(FileSystem.fullPath(entry))) : 'package ${Glue.PACK};\n\nclass ${Glue.CLASS} {\n\tstatic function main()\n\t\thelder.typescript.js.Seed.main();\n}\n';
		// (rewritten only when it changed: a compilation server keeps the module typed)
		if (!FileSystem.exists(file) || sys.io.File.getContent(file) != text) {
			FileSystem.createDirectory(Path.directory(file));
			sys.io.File.saveContent(file, text);
		}
		com.classPaths.add(new core.ClassPath.DirectoryClassPath(Path.addTrailingSlash(dir), User));
		var main = new core.Globals.GlobalTypePath([Glue.PACK], Glue.CLASS);
		com.main.mainPath = main;
		actx.classes.push(main);
		return {project: project, glue: glue, error: error};
	}

	// helder's cache: HELDER_CACHE, else the user's (as build.mjs has it)
	static function cache():String {
		var configured = Sys.getEnv("HELDER_CACHE");
		if (configured != null && configured != "") return configured;
		var home = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".";
		return switch Sys.systemName() {
			case "Windows": Path.join([Sys.getEnv("LOCALAPPDATA") ?? home, "helder", "cache"]);
			case "Mac": Path.join([home, "Library/Caches/helder"]);
			case _: Path.join([Sys.getEnv("XDG_CACHE_HOME") ?? Path.join([home, ".cache"]), "helder"]);
		}
	}

	// hxmc's generation (hxmc.Main.generate) with the TypeScript program
	// lowered into the IR it is about to compile (its beforeCodegen seam).
	static function generate(com:context.Common.CommonContext, entry:String) {
		phase("type (haxe)");
		var ready = prepared;
		prepared = null;
		// (helder dev's watcher: the program's files, beside the modules
		// helder.cli.Deps wrote; a failed check's too, so a fix is seen)
		var deps = core.Define.rawDefinedValueSafe(com.defines, DEFINE + ".deps", "");
		if (deps != "") {
			var listed = sys.FileSystem.exists(deps) ? sys.io.File.getContent(deps) : "";
			sys.io.File.saveContent(deps, listed + [for (f in Project.read) f + "\n"].join(""));
		}
		if (ready == null) throw "TSHX004: the TypeScript program was not prepared";
		if (ready.error != null) throw ready.error;
		hxmc.Main.generate(com, com.file, (com, p) -> {
			phase("lower runtime");
			var frontend = new Frontend(ready.project, p, ready.glue);
			frontend.lower();
			Verifier.check(p);
			phase("lower program");
			if (core.Define.rawDefined(com.defines, DEFINE + ".roundtrip_ir")) {
				var text = TextIR.dump(p);
				TextIR.parse(p, text);
				Verifier.check(p);
				if (TextIR.dump(p) != text) throw "TSHXIR004: text round trip changed IR";
			}
			var dump = core.Define.rawDefinedValueSafe(com.defines, DEFINE + ".dump_ir", "");
			if (dump != "") sys.io.File.saveContent(dump, TextIR.dump(p));
			if (core.Define.rawDefined(com.defines, DEFINE + ".coverage")) {
				Sys.println(haxe.Json.stringify(frontend.coverage()));
				Sys.exit(0);
			}
		});
		phase("generate");
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

	// `<compiler> <entry> ...`: the compiler's short form for a TypeScript program
	static function direct(args:Array<String>):Array<String> {
		var entry = args.shift(), out = "bin/" + Path.withoutExtension(Path.withoutDirectory(entry)), target:Null<String> = null;
		var defines = ["-D", DEFINE + "=" + FileSystem.fullPath(entry)];
		while (args.length > 0) switch args.shift() {
			case "-o": out = args.shift();
			case "--target": target = args.shift();
			case "--dump-ir": defines = defines.concat(["-D", DEFINE + ".dump_ir=" + args.shift()]);
			case "--roundtrip-ir": defines = defines.concat(["-D", DEFINE + ".roundtrip_ir"]);
			case "--coverage": defines = defines.concat(["-D", DEFINE + ".coverage"]);
			case "-D": defines = defines.concat(["-D", args.shift()]);
			case "--cp": defines = defines.concat(["-cp", args.shift()]);
			case a: throw 'unexpected argument $a (<compiler> <entry.ts> [-o out] [--target t] [-D name[=value]] [--cp dir] [--dump-ir file] [--roundtrip-ir] [--coverage])';
		}
		if (!FileSystem.exists(entry)) throw '$entry: TSHX002: input file not found';
		var result = ["-cp", source(), "-main", "helder.typescript.js.Seed", "--custom-target", "hxmc=" + out].concat(defines);
		if (target != null) result = result.concat(["-D", "hxmc.target=" + target]);
		return result;
	}

	// helder's sources (the class path holding helder.typescript)
	static function source():String {
		var configured = Sys.getEnv("HELDER_SRC");
		if (configured != null && configured != "") return configured;
		for (start in [Path.directory(FileSystem.fullPath(Sys.programPath())), Sys.getCwd()]) {
			var dir = FileSystem.fullPath(start);
			while (dir != null && dir != "") {
				for (candidate in [dir + "/src", dir + "/node_modules/helder/src"])
					if (FileSystem.exists(candidate + "/helder/typescript/js/Seed.hx")) return candidate;
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

	static var started = haxe.Timer.stamp();
	static final timings = Sys.getEnv("HELDER_TS_TIMES") == "1";

	// (HELDER_TS_TIMES=1: where a build's time goes)
	static function phase(name:String) {
		if (!timings) return;
		var now = haxe.Timer.stamp();
		Sys.stderr().writeString(name + ": " + Math.round((now - started) * 1000) + "ms\n");
		started = now;
	}
}
