package helder.cli;

import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder test`: the project's `*.test.hx` files (under src/ and tests/ and
// its class paths, not bin/ or node_modules/), built into one program with
// helder.test's runner and run, on the host, Eval or wasm32-wasi (node).
//
// Haxe takes no dot in a module's name, so each file is linked (Link) into
// bin/test/src under its package's directories as `Foo_test.hx`, and a
// generated main (bin/test/src/HelderTestMain.hx) calls each one's
// module-level `tests()`. The compiler's output and the program's are
// written with the real paths again (the content, so the positions, are
// the same).
class TestCommand {
	public static inline var GEN = "bin/test/src";

	static final usage = [
		"helder test [file or name filter...] [options]",
		"",
		"  a filter that is part of a test file's path picks those files, any other",
		"  one the tests whose name (\"describe > test\") contains it",
		"",
		"  -t <text>         the tests whose name contains it (/text/: a regex)",
		"  --target <t>      host (the default), interp, wasm or all; several: host,wasm",
		"  --watch, -w       run again on every change (a compilation server's builds)",
		"  -u                rewrite the snapshots that differ",
		"  --timeout <s>     seconds an async test may take (5)",
	].join("\n");

	@:coroutine public static function run(args:Array<String>):Int {
		var filters = [], targets = ["host"], watch = false, runner = [];
		var i = 0;
		while (i < args.length) {
			var a = args[i++];
			if (["-t", "--test-name-pattern", "--target", "--timeout"].contains(a) && i == args.length) {
				Sys.println('helder test: $a takes a value\n\n$usage');
				return 2;
			}
			switch a {
				case "-t" | "--test-name-pattern": runner = runner.concat(["-t", args[i++]]);
				case "--target": targets = args[i++].split(",");
				case "--watch" | "-w": watch = true;
				case "-u" | "--update-snapshots": runner.push("-u");
				case "--timeout": runner = runner.concat(["--timeout", args[i++]]);
				case "-h" | "--help":
					Sys.println(usage);
					return 0;
				case _ if (a.startsWith("-")):
					Sys.println('helder test: unknown option $a\n\n$usage');
					return 2;
				case _: filters.push(a);
			}
		}
		if (targets.contains("all")) targets = ["host", "interp", "wasm"];
		for (t in targets) if (!["host", "interp", "wasm"].contains(t)) {
			Sys.println('helder test: no target $t (host, interp, wasm, all)');
			return 2;
		}
		var p = new Project();
		if (!watch) return once(p, filters, targets, runner, null);
		var server = Compiler.start();
		if (server == null) Sys.println("helder test: no compilation server (each build from the module cache)");
		var w = new PollWatcher(p.watched(), 0.2, 0.1, path -> {
			var n = Path.withoutDirectory(path);
			return n == "bin" || n == "node_modules" || n.startsWith(".") || n.endsWith(".snap");
		});
		while (true) {
			once(p, filters, targets, runner, server);
			Sys.println("\nwatching (ctrl-c to stop)");
			var changed = w.next();
			Sys.println('\n${changed.length == 1 ? changed[0] : changed.length + " files"} changed');
		}
		return 0;
	}

	// one run: found, linked, built and run for each target; the exit code
	@:coroutine static function once(p:Project, filters:Array<String>, targets:Array<String>, runner:Array<String>, server:Null<Int>):Int {
		var files = try p.testFiles() catch (e:haxe.Exception) {
			Sys.println('helder test: ${e.message}');
			return 1;
		}
		// (the filters that are part of a path pick files; the rest names)
		var paths = filters.filter(f -> Lambda.exists(files, t -> t.real.contains(norm(f))));
		var names = filters.filter(f -> !paths.contains(f));
		if (paths.length > 0) files = files.filter(t -> Lambda.exists(paths, f -> t.real.contains(norm(f))));
		for (n in names) runner = runner.concat(["-n", n]);
		if (files.length == 0) {
			Sys.println("helder test: no *.test.hx files" + (paths.length > 0 ? " match " + paths.join(" ") : " under " + p.roots.join(", ")));
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
			var r = target(t, p, cp, runner, map, server);
			results.push('$t: ${r.summary}');
			if (!r.ok) failed = true;
		}
		if (targets.length > 1) Sys.println("\n" + results.join("\n"));
		return failed ? 1 : 0;
	}

	@:coroutine static function target(t:String, p:Project, cp:Array<String>, runner:Array<String>, map:Mapper, server:Null<Int>):{ok:Bool, summary:String} {
		var connect = server == null ? [] : ["--connect", Std.string(server)];
		var t0 = haxe.Timer.stamp();
		var out:Output;
		switch t {
			case "interp":
				// (built and run by one process: Eval)
				Sys.println('\n[interp]');
				out = Output.of(Compiler.tool(), cp.concat(["--run", "HelderTestMain"]).concat(runner), map);
				return {ok: out.code == 0, summary: out.summary() + ' (${secs(haxe.Timer.stamp() - t0)} built and run)'};
			case "wasm":
				var exe = "bin/test/test.wasm";
				var b = Output.of(Compiler.tool(), connect.concat(cp).concat(["-main", "HelderTestMain", "-D", "hxmc.target=wasm32-wasi", "--custom-target", 'hxmc=$exe']), map);
				var built = haxe.Timer.stamp() - t0;
				if (b.code != 0) {
					Sys.println('\n[$t] the build failed');
					return {ok: false, summary: "the build failed"};
				}
				Sys.println('\n[wasm] built in ${secs(built)} (${kb(exe)})');
				var t1 = haxe.Timer.stamp();
				var node = Sys.getEnv("NODE") ?? "node";
				out = Output.of(node, ["--no-warnings", "--stack-size=65500", p.helder + "/helder/test/wasi.mjs", exe].concat(runner), map);
				return {ok: out.code == 0, summary: out.summary() + ' (${secs(built)} build, ${secs(haxe.Timer.stamp() - t1)} run)'};
			case _:
				var exe = Sys.systemName() == "Windows" ? "bin/test/host.exe" : "bin/test/host";
				var b = Output.of(Compiler.tool(), connect.concat(cp).concat(["-main", "HelderTestMain", "--custom-target", 'hxmc=$exe']), map);
				var built = haxe.Timer.stamp() - t0;
				if (b.code != 0) {
					Sys.println('\n[$t] the build failed');
					return {ok: false, summary: "the build failed"};
				}
				Sys.println('\n[host] built in ${secs(built)} (${kb(exe)})');
				var t1 = haxe.Timer.stamp();
				out = Output.of(exe, runner, map);
				return {ok: out.code == 0, summary: out.summary() + ' (${secs(built)} build, ${secs(haxe.Timer.stamp() - t1)} run)'};
		}
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
		var main = ["// `helder test`'s runner: the test files linked here, in order", "class HelderTestMain {", "\tstatic function main() {"];
		for (f in files)
			main.push('\t\thelder.test.Runner.add("${f.real}", "${f.linked}", ${f.module}.tests);');
		if (regex) main.push('\t\thelder.test.Runner.regex = p -> {\n\t\t\tvar r = new EReg(p, "");\n\t\t\ts -> r.match(s);\n\t\t};');
		main = main.concat(["\t\thelder.test.Runner.run();", "\t}", "}", ""]);
		var text = main.join("\n"), path = '$GEN/HelderTestMain.hx';
		if (!FileSystem.exists(path) || File.getContent(path) != text) File.saveContent(path, text);
	}

	static function norm(p:String):String {
		p = p.split("\\").join("/");
		return p.startsWith("./") ? p.substr(2) : p;
	}

	static function secs(s:Float):String
		return Math.round(s * 100) / 100 + "s";

	static function kb(path:String):String
		return FileSystem.exists(path) ? Math.round(FileSystem.stat(path).size / 1024) + " KB" : "-";

	public static function mkdirs(dir:String)
		if (dir != "" && !FileSystem.exists(dir)) {
			mkdirs(Path.directory(dir));
			FileSystem.createDirectory(dir);
		}
}

typedef TestFile = {
	// src/helder/test/Equal.test.hx, bin/test/src/helder/test/Equal_test.hx, helder.test.Equal_test
	real:String,
	linked:String,
	module:String,
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
			var have = declared.match(File.getContent(p)) ? declared.matched(1) : "";
			if (have != pack)
				throw '$p: package ${have == "" ? "(none)" : have}, but its directory under $r/ makes it ${pack == "" ? "(none)" : pack}';
			var name = Path.withoutDirectory(p);
			name = name.substr(0, name.length - ".test.hx".length) + "_test";
			var module = pack == "" ? name : '$pack.$name';
			// (the same module from two roots)
			if (seen.exists(module)) throw '$p: the same module as ${seen.get(module)}';
			seen.set(module, p);
			out.push({real: p, linked: '${TestCommand.GEN}/' + (dirs == "" ? "" : dirs + "/") + name + ".hx", module: module});
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

	@:coroutine public static function of(cmd:String, args:Array<String>, map:Mapper):Output {
		var o = new Output();
		var p = try new Process(cmd, args) catch (e:haxe.Exception) {
			Sys.println('helder test: $cmd: ${e.message}');
			o.code = 127;
			return o;
		}
		p.closeStdin();
		Async.scope(task -> {
			task.async(_ -> o.pipe(p.stdout, false, map));
			task.async(_ -> o.pipe(p.stderr, true, map));
			null;
		});
		o.code = p.wait();
		p.close();
		return o;
	}

	@:coroutine function pipe(s:Stream.Source, err:Bool, map:Mapper) {
		var r = new Reader(s), line;
		while ((line = r.readLine()) != null) {
			line = map.apply(line);
			lines.push(line);
			if (err) Sys.stderr().writeString(line + "\n") else Sys.println(line);
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
