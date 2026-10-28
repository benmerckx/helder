package helder.cli;

import helder.cli.Style.Tone;
import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder test`: the project's `*.test.hx` files (under src/ and tests/ and
// its class paths, not bin/ or node_modules/), built into one program with
// helder.test's runner and run, on the host, wasm32-wasi (node) or Eval.
// Eval (interp) only for the files that opt in: `@:test.interp` on their
// `tests()` (code that runs at compile time: macros); the rest is shipped
// natively and as wasm only, and may use what Eval has not (hxmc.unsafe,
// helder.os's windows).
//
// Haxe takes no dot in a module's name, so each file is linked (Link) into
// bin/test/src under its package's directories as `Foo_test.hx`, and a
// generated main (bin/test/src/HelderTestMain.hx; interp's
// HelderTestInterp.hx, the files that opt in) calls each one's
// module-level `tests()`. The compiler's output and the program's are
// written with the real paths again (the content, so the positions, are
// the same).
class TestCommand {
	public static inline var GEN = "bin/test/src";
	// (a test file's opt-in to interp: on its tests())
	public static final INTERP = ~/^\s*@:test\.interp\b/m;

	@:coroutine public static function run(task:Node, o:Options):Int {
		var filters = o.positionals, targets = o.targets, watch = o.has("watch"), runner = [];
		for (x in o.own) switch x.key {
			case "test-name-pattern": runner = runner.concat(["-t", x.value]);
			case "update-snapshots": runner.push("-u");
			case "timeout": runner = runner.concat(["--timeout", x.value]);
			case _:
		}
		// (the runner's colours and symbols: its output is a pipe here)
		if (Term.outColor) runner.push("--color");
		if (Term.outColor && Style.unicode) runner.push("--unicode");
		Term.out(Style.header("test", [targets.join(", ")]));
		var p = new Project();
		if (!watch) return once(p, filters, targets, runner, null);
		var compiler = Compiler.start();
		var server = compiler?.port;
		if (compiler == null) Term.err(Style.status("warning", Warn, "no compilation server (each build from the module cache)"));
		// (ctrl-c, SIGTERM: the compilation server stopped too)
		task.async(_ -> {
			var sig = Signals.next([Signal.SIGINT, Signal.SIGTERM]);
			if (compiler != null) compiler.process.stop();
			Sys.exit(128 + sig);
		});
		var w = new PollWatcher(p.watched(), 0.2, 0.1, path -> {
			var n = Path.withoutDirectory(path);
			return n == "bin" || n == "node_modules" || n.startsWith(".") || n.endsWith(".snap");
		});
		while (true) {
			once(p, filters, targets, runner, server);
			Term.out("");
			Term.out(Style.status("watching", Info, Style.dim("ctrl-c to stop")));
			var changed = w.next();
			Term.out("");
			Term.out(Style.status("changed", Quiet, changed.length == 1 ? changed[0] : changed.length + " files"));
		}
		return 0;
	}

	// one run: found, linked, built and run for each target; the exit code
	@:coroutine static function once(p:Project, filters:Array<String>, targets:Array<String>, runner:Array<String>, server:Null<Int>):Int {
		var files = try p.testFiles() catch (e:haxe.Exception) {
			Term.err(Style.usage('helder test: ${e.message}'));
			return 1;
		}
		// (the filters that are part of a path pick files; the rest names)
		var paths = filters.filter(f -> Lambda.exists(files, t -> t.real.contains(norm(f))));
		var names = filters.filter(f -> !paths.contains(f));
		if (paths.length > 0) files = files.filter(t -> Lambda.exists(paths, f -> t.real.contains(norm(f))));
		for (n in names) runner = runner.concat(["-n", n]);
		if (files.length == 0) {
			Term.err(Style.usage("helder test: no *.test.hx files" + (paths.length > 0 ? " match " + paths.join(" ") : " under " + p.roots.join(", "))));
			return 1;
		}
		// (a /regex/ -t: the runner given EReg)
		var regex = false;
		for (i in 0...runner.length - 1)
			if (runner[i] == "-t" && runner[i + 1].length > 2 && runner[i + 1].startsWith("/") && runner[i + 1].endsWith("/")) regex = true;
		generate(files, regex);
		var map = new Mapper(files);
		var cp = [];
		for (c in p.classPaths(files).concat([GEN])) cp = cp.concat(["-cp", c]);
		var results = [], failed = false;
		for (t in targets) {
			// (interp: the files that opt in, else a line, not a failure)
			if (t == "interp" && !Lambda.exists(files, f -> f.interp)) {
				var none = "no test file opts in (@:test.interp on its tests())";
				Term.out("");
				Term.out(Style.status("interp", Quiet, none));
				results.push(Style.status(t, Quiet, none));
				continue;
			}
			var r = target(t, p, cp, runner, map, server);
			results.push(Style.status(t, r.ok ? Ok : Fail, r.summary));
			if (!r.ok) failed = true;
		}
		if (targets.length > 1) {
			Term.out("");
			for (r in results) Term.out(r);
		}
		return failed ? 1 : 0;
	}

	// (the assets the tests name, helder.asset's: natively built into the
	// executable, for wasm copied beside it in bin/test/assets/; built again
	// when what was built in was not what the tests use: AssetStep)
	@:coroutine static function assets(words:Array<String>, exe:String, target:String, map:Mapper, what:String, b:Output):Output {
		var roots = [for (i in 0...words.length - 1) if (words[i] == "-cp") words[i + 1]].concat(["."]);
		if (b.code != 0 || AssetStep.after(exe, target, roots, false)) return b;
		b = Output.of(Compiler.tool(), words, map, what);
		if (b.code == 0) AssetStep.after(exe, target, roots, false);
		return b;
	}

	@:coroutine static function target(t:String, p:Project, cp:Array<String>, runner:Array<String>, map:Mapper, server:Null<Int>):{ok:Bool, summary:String} {
		var connect = server == null ? [] : ["--connect", Std.string(server)];
		var t0 = haxe.Timer.stamp();
		var out:Output;
		switch t {
			case "interp":
				// (built and run by one process: Eval)
				Term.out("");
				Term.out(Style.status("running", Info, "interp" + Style.dim(Style.sep() + "built and run by the compiler (Eval)")));
				out = Output.of(Compiler.tool(), cp.concat(["--run", "HelderTestInterp"]).concat(runner), map, "building and running the tests on interp");
				return {ok: out.code == 0, summary: out.summary() + ' (${secs(haxe.Timer.stamp() - t0)} built and run)'};
			case "wasm":
				var exe = "bin/test/test.wasm";
				var words = connect.concat(cp).concat(AssetStep.define(exe)).concat(["-main", "HelderTestMain", "-D", "hxmc.target=wasm32-wasi", "--custom-target", 'hxmc=$exe']);
				var b = assets(words, exe, "wasm32-wasi", map, "building the tests for wasm", Output.of(Compiler.tool(), words, map, "building the tests for wasm"));
				var built = haxe.Timer.stamp() - t0;
				if (b.code != 0) return buildFailed(t, built);
				Term.out("");
				Term.out(Style.status("built", Ok, 'wasm in ${Style.bold(secs(built))}' + Style.dim(Style.sep() + kb(exe))));
				var t1 = haxe.Timer.stamp();
				var node = Sys.getEnv("NODE") ?? "node";
				out = Output.of(node, ["--no-warnings", "--no-turbo-fast-api-calls", "--stack-size=65500", p.helder + "/helder/test/wasi.mjs", exe].concat(runner), map);
				return {ok: out.code == 0, summary: out.summary() + ' (${secs(built)} build, ${secs(haxe.Timer.stamp() - t1)} run)'};
			case _:
				var exe = Sys.systemName() == "Windows" ? "bin/test/host.exe" : "bin/test/host";
				// (Linux: the dynamic glibc mode, as helder build's: tests of helder.os link the system's libraries)
				var mode = Sys.systemName() == "Linux" ? ["-D", "hxmc.libc=glibc"] : [];
				var words = connect.concat(cp).concat(AssetStep.define(exe)).concat(["-main", "HelderTestMain", "--custom-target", 'hxmc=$exe']).concat(mode);
				var b = assets(words, exe, Compiler.hostTarget(), map, "building the tests for host", Output.of(Compiler.tool(), words, map, "building the tests for host"));
				var built = haxe.Timer.stamp() - t0;
				if (b.code != 0) return buildFailed(t, built);
				Term.out("");
				Term.out(Style.status("built", Ok, 'host in ${Style.bold(secs(built))}' + Style.dim(Style.sep() + kb(exe))));
				var t1 = haxe.Timer.stamp();
				out = Output.of(exe, runner, map);
				return {ok: out.code == 0, summary: out.summary() + ' (${secs(built)} build, ${secs(haxe.Timer.stamp() - t1)} run)'};
		}
	}

	static function buildFailed(t:String, seconds:Float):{ok:Bool, summary:String} {
		Term.err(Style.status("failed", Fail, '$t: the build failed in ${secs(seconds)}'));
		return {ok: false, summary: "the build failed"};
	}

	// the links, stale ones removed, and the main (written only when it changed:
	// the module cache keeps it)
	static function generate(files:Array<TestFile>, regex:Bool) {
		var wanted = [for (f in files) f.linked => true];
		function clean(dir:String)
			for (n in (try FileSystem.readDirectory(dir) catch (_:Dynamic) [])) {
				var p = '$dir/$n';
				if (FileSystem.isDirectory(p)) clean(p) else if (n.endsWith("_test.hx") && !wanted.exists(p)) FileSystem.deleteFile(p);
			}
		clean(GEN);
		for (f in files) {
			mkdirs(Path.directory(f.linked));
			Link.make(f.real, f.linked);
		}
		writeMain("HelderTestMain", files, regex);
		writeMain("HelderTestInterp", files.filter(f -> f.interp), regex);
	}

	static function writeMain(name:String, files:Array<TestFile>, regex:Bool) {
		var main = ["// `helder test`'s runner: the test files linked here, in order", 'class $name {', "\tstatic function main() {"];
		for (f in files)
			main.push('\t\thelder.test.Runner.add("${lit(f.real)}", "${lit(f.linked)}", ${f.module}.tests);');
		if (regex) main.push('\t\thelder.test.Runner.regex = p -> {\n\t\t\tvar r = new EReg(p, "");\n\t\t\ts -> r.match(s);\n\t\t};');
		main = main.concat(["\t\thelder.test.Runner.run();", "\t}", "}", ""]);
		var text = main.join("\n"), path = '$GEN/$name.hx';
		if (!FileSystem.exists(path) || File.getContent(path) != text) File.saveContent(path, text);
	}

	static function norm(p:String):String {
		p = p.split("\\").join("/");
		return p.startsWith("./") ? p.substr(2) : p;
	}

	// (a path in a Haxe string literal: a Windows path's backslashes escaped)
	static function lit(s:String):String
		return s.split("\\").join("\\\\").split('"').join('\\"');

	static function secs(s:Float):String
		return Math.round(s * 100) / 100 + "s";

	static function kb(path:String):String
		return FileSystem.exists(path) ? Math.round(FileSystem.stat(path).size / 1024) + " KB" : "-";

	public static function mkdirs(dir:String)
		if (dir != "" && !FileSystem.exists(dir)) {
			mkdirs(Path.directory(dir));
			FileSystem.createDirectory(dir);
		}

	// a file, or a directory and everything under it
	public static function rmrf(path:String) {
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (n in FileSystem.readDirectory(path)) rmrf('$path/$n');
			FileSystem.deleteDirectory(path);
		} else FileSystem.deleteFile(path);
	}
}

typedef TestFile = {
	// src/helder/test/Equal.test.hx, bin/test/src/helder/test/Equal_test.hx, helder.test.Equal_test
	real:String,
	linked:String,
	module:String,
	// (it opts in to interp: @:test.interp)
	interp:Bool,
}

// The project in the working directory: its class paths (package.json's
// "haxe": {"classPath"}, else src), the roots searched for test files
// (those and src/, tests/), helder's own src/ (this checkout's, else
// node_modules/helder's, else beside the program).
class Project {
	public final classPath:Array<String>;
	public final roots:Array<String>;
	public final helder:String;

	public function new() {
		var cps = [];
		try {
			var cfg:Dynamic = haxe.Json.parse(File.getContent("package.json")).haxe;
			var c:Dynamic = cfg?.classPath;
			if (c is String) cps.push(c) else if (c is Array) cps = cps.concat(c);
		} catch (_:Dynamic) {}
		if (cps.length == 0) cps.push("src");
		classPath = [for (c in cps) clean(c)];
		roots = [];
		for (r in classPath.concat(["src", "tests"]))
			if (!roots.contains(r) && FileSystem.exists(r) && FileSystem.isDirectory(r)) roots.push(r);
		var beside = Path.directory(Sys.programPath()) + "/../../src";
		helder = [for (d in ["src", "node_modules/helder/src", beside]) if (FileSystem.exists('$d/helder/test/Test.hx')) d][0] ?? "src";
	}

	static function clean(p:String):String {
		p = p.split("\\").join("/");
		while (p.endsWith("/")) p = p.substr(0, p.length - 1);
		return p.startsWith("./") ? p.substr(2) : p;
	}

	// the directories a change in which runs the tests again
	public function watched():Array<String>
		return roots.copy();

	// the class paths of a build: the project's, helder's, each test file's root
	public function classPaths(files:Array<TestFile>):Array<String> {
		var out = classPath.copy();
		if (!out.contains(helder)) out.push(helder);
		for (f in files) {
			var r = root(f.real);
			if (r != null && !out.contains(r)) out.push(r);
		}
		return out;
	}

	// (the longest root a path is under)
	function root(path:String):Null<String> {
		var best:Null<String> = null;
		for (r in roots) if (path.startsWith(r + "/") && (best == null || r.length > best.length)) best = r;
		return best;
	}

	// every test file, sorted; an error for one whose package line is not its directory's
	public function testFiles():Array<TestFile> {
		var found = [];
		function walk(dir:String)
			for (n in (try FileSystem.readDirectory(dir) catch (_:Dynamic) [])) {
				if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
				var p = '$dir/$n';
				if (FileSystem.isDirectory(p)) walk(p) else if (n.endsWith(".test.hx") && !found.contains(p)) found.push(p);
			}
		for (r in roots) walk(r);
		found.sort(Reflect.compare);
		var out = [];
		var seen = new Map<String, String>();
		for (p in found) {
			var r = root(p);
			var dirs = Path.directory(p.substr(r.length + 1));
			var pack = dirs == "" ? "" : dirs.split("/").join(".");
			var declared = ~/^\s*package\s+([\w.]*)\s*;/m;
			var content = File.getContent(p);
			var have = declared.match(content) ? declared.matched(1) : "";
			if (have != pack)
				throw '$p: package ${have == "" ? "(none)" : have}, but its directory under $r/ makes it ${pack == "" ? "(none)" : pack}';
			var name = Path.withoutDirectory(p);
			name = name.substr(0, name.length - ".test.hx".length) + "_test";
			var module = pack == "" ? name : '$pack.$name';
			// (the same module from two roots)
			if (seen.exists(module)) throw '$p: the same module as ${seen.get(module)}';
			seen.set(module, p);
			out.push({real: p, linked: '${TestCommand.GEN}/' + (dirs == "" ? "" : dirs + "/") + name + ".hx", module: module, interp: TestCommand.INTERP.match(content)});
		}
		return out;
	}
}

// A linked file's paths written as the real one's, in the compiler's and the
// program's output (relative and absolute)
class Mapper {
	final pairs:Array<{from:String, to:String}> = [];

	public function new(files:Array<TestFile>) {
		var cwd = Sys.getCwd().split("\\").join("/");
		if (!cwd.endsWith("/")) cwd += "/";
		for (f in files) {
			pairs.push({from: cwd + f.linked, to: f.real});
			pairs.push({from: f.linked, to: f.real});
		}
	}

	public function apply(line:String):String {
		if (!line.contains("_test.hx")) return line;
		for (p in pairs) line = line.split(p.from).join(p.to);
		return line;
	}
}

// A child's output, streamed (mapped) as it comes, and its exit code
class Output {
	public var code = 0;
	public final lines:Array<String> = [];

	function new() {}

	// (spin: the spinner's text while it runs, the compiler's messages readable)
	@:coroutine public static function of(cmd:String, args:Array<String>, map:Mapper, ?spin:String):Output {
		var o = new Output();
		var p = try new Process(cmd, args) catch (e:haxe.Exception) {
			Term.err(Style.usage('helder test: $cmd: ${e.message}'));
			o.code = 127;
			return o;
		}
		p.closeStdin();
		var d = spin == null ? null : new Diagnostics();
		if (spin != null) Term.spin(spin);
		Async.scope(task -> {
			task.async(_ -> o.pipe(p.stdout, false, map, d));
			task.async(_ -> o.pipe(p.stderr, true, map, d));
			null;
		});
		o.code = p.wait();
		Term.done();
		p.close();
		return o;
	}

	@:coroutine function pipe(s:Stream.Source, err:Bool, map:Mapper, d:Null<Diagnostics>) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) {
			line = map.apply(line);
			lines.push(Style.strip(line));
			if (d != null) line = d.line(line);
			if (err) Term.err(line) else Term.out(line);
		}
	}

	// "3 pass, 1 fail", from the runner's summary
	public function summary():String {
		var out = [];
		var re = ~/^ (\d+) (pass|skip|fail)$/;
		for (l in lines) if (re.match(l)) out.push(re.matched(1) + " " + re.matched(2));
		return out.length > 0 ? out.join(", ") : 'exit code $code';
	}
}
