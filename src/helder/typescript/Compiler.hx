package helder.typescript;

import haxe.io.Path;
import sys.FileSystem;
import helder.typescript.check.Project;
import helder.typescript.lower.Frontend;
import helder.typescript.ir.Verifier;
import helder.typescript.ir.TextIR;

using StringTools;

// hxmc's compiler with a TypeScript frontend: the same command line as
// @hxmc/cli's `haxe`, and a build given `-D helder.typescript=<entry.ts>`
// also checks that program with tsgo and lowers it straight into the
// program's IR, after the Haxe side (helder.typescript.js, the JavaScript
// runtime, and whatever it uses) is lowered and before code generation. So
// the helder CLI runs it as it runs hxmc's compiler: one-shot builds and
// `helder dev`'s compilation server alike.
//
// For a quick build: `helder-ts <entry.ts> [-o out] [--target t]
// [--dump-ir file] [--roundtrip-ir] [--coverage]`.
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
		var failed:Null<String> = null;
		compiler.Compiler.generateHook = function(com) {
			if (args.contains("--no-output") && !core.Define.rawDefined(com.defines, DEFINE)) return;
			switch com.platform {
				case CustomTarget("hxmc"):
				case _: return;
			}
			try {
				var entry = core.Define.rawDefinedValueSafe(com.defines, DEFINE, "");
				if (entry == "") @:privateAccess hxmc.Main.generate(com, com.file) else generate(com, entry);
			} catch (e:Dynamic) {
				if (Sys.getEnv("HELDER_TS_DEBUG") == "1") Sys.stderr().writeString(haxe.CallStack.toString(haxe.CallStack.exceptionStack()) + "\n");
				if (hxmc.Driver.resident) com.error(Std.string(e), core.Globals.nullPos) else failed = Std.string(e);
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

	// As hxmc's Main.generate, with the TypeScript program lowered into the IR.
	static function generate(com:context.Common.CommonContext, entry:String) {
		var o = hxmc.Options.read(com), abi = hxmc.Abi.get(o.target);
		abi.setLibc(o.libc);
		hxmc.ir.Lower.targetOs = abi.osCode();
		hxmc.ir.Lower.targetArm = abi.arm ? 1 : 0;
		hxmc.ir.Lower.targetCode = hxmc.MirBuild.targetCode(abi);
		hxmc.ir.Lower.targetPlatform = abi.platformCode();
		hxmc.ir.Lower.resources = com.resources.fold((name, data, acc:Array<{name:String, data:haxe.io.Bytes}>) -> [{name: name, data: data}].concat(acc), []);
		hxmc.ir.Lower.bounds = o.bounds;
		hxmc.ir.Lower.nullChecks = o.nullChecks;
		hxmc.ir.Lower.spanChecks = o.spanChecks;
		hxmc.ir.Lower.lines = (o.debugLines || o.stacks) && !abi.wasm;
		hxmc.ir.Reach.stacksAlways = o.stacksAlways;
		hxmc.ir.RuntimeSymbols.check(com, abi.wasm ? hxmc.ir.RuntimeSymbols.WASM32 : hxmc.ir.RuntimeSymbols.NATIVE, abi.name);
		phase("type (haxe)");
		var project = Project.check(entry, Path.join([source(), "helder/typescript/globals.d.ts"]));
		phase("check (tsgo)");
		var p = hxmc.ir.Lower.program(context.Common.getEntryPoint(com).cls, com.types, com.basic);
		phase("lower runtime");
		var frontend = new Frontend(project, p);
		frontend.lower();
		Verifier.check(p);
		phase("lower program");
		var dump = core.Define.rawDefinedValueSafe(com.defines, DEFINE + ".dump-ir", "");
		if (core.Define.rawDefined(com.defines, DEFINE + ".roundtrip-ir")) {
			var text = TextIR.dump(p);
			TextIR.parse(p, text);
			Verifier.check(p);
			if (TextIR.dump(p) != text) throw "TSHXIR004: text round trip changed IR";
		}
		if (dump != "") sys.io.File.saveContent(dump, TextIR.dump(p));
		if (core.Define.rawDefined(com.defines, DEFINE + ".coverage")) {
			Sys.println(haxe.Json.stringify(frontend.coverage()));
			return;
		}
		hxmc.Driver.run(p, com.file, o);
		phase("generate");
	}

	// `helder-ts <entry> ...` as the compiler's own command line
	static function direct(args:Array<String>):Array<String> {
		var entry = args.shift(), out = "bin/" + Path.withoutExtension(Path.withoutDirectory(entry)), target:Null<String> = null;
		var defines = ["-D", DEFINE + "=" + FileSystem.fullPath(entry)];
		while (args.length > 0) switch args.shift() {
			case "-o": out = args.shift();
			case "--target": target = args.shift();
			case "--dump-ir": defines = defines.concat(["-D", DEFINE + ".dump-ir=" + args.shift()]);
			case "--roundtrip-ir": defines = defines.concat(["-D", DEFINE + ".roundtrip-ir"]);
			case "--coverage": defines = defines.concat(["-D", DEFINE + ".coverage"]);
			case a: throw 'helder-ts: unexpected argument $a (helder-ts <entry.ts> [-o out] [--target t] [--dump-ir file] [--roundtrip-ir] [--coverage])';
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
		throw "helder-ts: helder's sources not found (set HELDER_SRC)";
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
			var dirs = [for (name in FileSystem.readDirectory(dir)) if (name != "cli") dir + "/" + name];
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
