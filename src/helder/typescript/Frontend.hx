package helder.typescript;

import haxe.io.Path;
import sys.FileSystem;
import helder.compiler.Compiler;
import helder.typescript.check.Project;
import helder.typescript.ir.Verifier;
import helder.typescript.ir.TextIR;
import helder.typescript.lower.Api;
import helder.typescript.lower.Frontend as Lowering;
import core.TType.ModuleType;

using StringTools;

// The TypeScript frontend of helder's compiler (helder.compiler.Compiler's
// plugin): a build given `-D helder.typescript=<entry.ts>` also checks that
// program with tsgo and lowers it straight into the program's IR, after the
// Haxe side (helder.typescript.js, the JavaScript runtime, and whatever it
// uses) is lowered and before code generation.
//
// Its short form: `<compiler> <entry.ts> [-o out] [--target t]
// [-D name[=value]] [--cp dir] [--dump-ir file] [--roundtrip-ir] [--coverage]`.
class Frontend implements helder.compiler.Plugin {
	public static inline var DEFINE = "helder.typescript";

	public function new() {}

	// what the build's start made of the TypeScript program: it checked, the
	// API its declaration files declare (or the error the check gave, reported
	// where the build would have lowered it)
	var prepared:Null<{project:Null<Project>, api:Null<Api>, error:Null<String>}> = null;

	public function beforeTyping(com:context.Common.CommonContext, actx:compiler.ParsedArg.ArgContext) {
		prepared = null;
		var entry = core.Define.rawDefinedValueSafe(com.defines, DEFINE, "");
		if (entry != "" && com.platform.match(CustomTarget("hxmc"))) prepared = prepare(com, actx, entry);
	}

	public function owns(com:context.Common.CommonContext):Bool
		return core.Define.rawDefined(com.defines, DEFINE);

	public function generate(com:context.Common.CommonContext) {
		var entry = core.Define.rawDefinedValueSafe(com.defines, DEFINE, "");
		if (entry == "") hxmc.Main.generate(com, com.file) else lower(com, entry);
	}

	// The program checked (tsgo), and the declaration classes of the modules
	// its declaration files declare (helder's API: lower.Api) added to the
	// build: typed, each makes its part of the manifest the lowering reads
	// (helder.typescript.api.Manifest). The build's main is the runtime's
	// seed, as the short form's.
	function prepare(com:context.Common.CommonContext, actx:compiler.ParsedArg.ArgContext, entry:String) {
		phase("start");
		var project:Null<Project> = null, api:Null<Api> = null, error:Null<String> = null;
		try {
			project = Project.check(entry, Path.join([source(), "helder/typescript/globals.d.ts"]), p -> api = new Api(p));
			phase("check (tsgo)");
		} catch (e:Dynamic) {
			if (Sys.getEnv("HELDER_TS_DEBUG") == "1") Sys.stderr().writeString(haxe.CallStack.toString(haxe.CallStack.exceptionStack()) + "\n");
			error = Std.string(e);
		}
		if (api != null) for (m in api.modules) {
			var parts = m.split(".");
			actx.classes.push(new core.Globals.GlobalTypePath(parts.slice(0, parts.length - 1), parts[parts.length - 1]));
		}
		return {project: project, api: api, error: error};
	}

	// hxmc's generation (hxmc.Main.generate) with the TypeScript program
	// lowered into the IR it is about to compile (its beforeCodegen seam).
	function lower(com:context.Common.CommonContext, entry:String) {
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
		// (the manifest the build's typing made: each module's on its declaration class)
		if (ready.api != null) {
			var parts = [];
			for (t in com.types) switch t {
				case TClassDecl(c):
					var json = hxmc.ir.Lower.metaString(Manifest.META, c.clMeta);
					if (json != null) parts.push({ident: hxmc.ir.Lower.nativeName(c), json: json});
				case _:
			}
			if (parts.length > 0) ready.api.manifest = new Manifest(parts);
		}
		var dev = core.Define.rawDefined(com.defines, "hxmc.dev");
		hxmc.Main.generate(com, com.file, (com, p) -> {
			phase("lower runtime");
			var frontend = new Lowering(ready.project, p, ready.api, dev);
			frontend.lower();
			// (the manifest's keeps: their __init__s named what the lowering may call, they run no more)
			if (ready.api != null && ready.api.manifest != null) {
				var keeps = [for (k in ready.api.manifest.keep) k + "__init" => true];
				for (f in p.funcs) if (keeps.exists(f.name)) {
					p.inits.remove(f);
					p.roots.remove(f);
				}
			}
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

	// `<compiler> <entry> ...`: the compiler's short form for a TypeScript program
	public function direct(args:Array<String>):Null<Array<String>> {
		if (!~/\.(m|c)?[jt]sx?$/.match(args[0])) return null;
		args = args.copy();
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
	static function source():String
		return Compiler.source("helder/typescript/js/Seed.hx");

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
