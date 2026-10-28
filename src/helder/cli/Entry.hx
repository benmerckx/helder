package helder.cli;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// What `helder build`, `run` and `dev` build: the entry (their one
// positional, never a target: Options) for a target (--target).
//
//   (nothing)                the working directory, a project
//   examples/counter         a project (package.json, src/Main.hx), else a
//                            directory with one main file (or the one
//                            named as the directory: cube/Cube.hx)
//   examples/counter/Counter.hx   a file: its module is the main class, its
//                            class path the directory its package line
//                            makes it (one up per package segment)
//
// The nearest package.json at or above the entry adds its class paths
// ("haxe": {"classPath"}, this checkout's src/), its dependencies' (a
// package in node_modules with a "haxe" field: node_modules/helder), and
// the overrides: a "helder" key ({"main", "name", "defines": {k: v}}) and a
// helder.hxml beside it, given to every build. Outputs go to the project's
// bin/<target>/<name>.
class Entry {
	// "web" or an hxmc target (host resolved)
	public var target:String;
	// -d/--device: which phone, emulator or simulator (android, ios), null for none
	public var device(default, null):Null<String> = null;
	public var main(default, null):String;
	public var name(default, null):String;
	// the project's directory (bin/ is under it); the class paths, the entry's own first
	public var root(default, null):String;
	public var classPaths(default, null):Array<String> = [];
	// helder's src/ (helder.dev, the browser modules)
	public var helder(default, null):String;
	public var defines(default, null):Array<String> = [];
	public var hxml(default, null):Null<String> = null;
	// the directories watched (the class paths but helder's own when it is a package)
	public var sources(default, null):Array<String> = [];

	function new() {}

	// the entry (null: .) for a target (null: host); an error's message thrown
	public static function resolve(path:Null<String>, ?target:String, ?device:String):Entry {
		var e = new Entry();
		e.target = target ?? "host";
		e.device = device;
		if (e.target == "host") e.target = Compiler.hostTarget();
		path = clean(path ?? ".");
		if (!FileSystem.exists(path)) throw '$path: no such file or directory';
		if (FileSystem.isDirectory(path)) {
			if (FileSystem.exists('$path/package.json')) e.project(path) else e.file(mainOf(path));
		} else if (path.endsWith(".hx")) e.file(path) else throw '$path: not a .hx file or a directory';
		return e;
	}

	// (from Options: the entry and the target)
	public static function of(o:Options):Entry
		return resolve(o.entry, o.target, o.device);

// a directory's main file: the only one with a main, else the one named as the directory
	static function mainOf(dir:String):String {
		var files = [for (f in FileSystem.readDirectory(dir)) if (f.endsWith(".hx") && ~/static\s+function\s+main\s*\(/.match(File.getContent('$dir/$f'))) f];
		files.sort(Reflect.compare);
		if (files.length == 1) return '$dir/${files[0]}';
		var named = Path.withoutDirectory(FileSystem.fullPath(dir)).replace("-", "").toLowerCase();
		for (f in files) if (f.substr(0, f.length - 3).toLowerCase() == named) return '$dir/$f';
		throw files.length == 0 ? '$dir: no package.json, and no .hx file with a main' : '$dir: several main files (${files.join(", ")}): name one';
	}

	function file(path:String) {
		var dir = Path.directory(path);
		if (dir == "") dir = ".";
		var declared = ~/^\s*package\s+([\w.]*)\s*;/m;
		var pack = declared.match(File.getContent(path)) ? declared.matched(1) : "";
		var cp = dir;
		if (pack != "") for (_ in pack.split(".")) cp = parent(cp);
		var module = Path.withoutExtension(Path.withoutDirectory(path));
		main = pack == "" ? module : '$pack.$module';
		name = module;
		classPaths.push(cp);
		var pj = above(dir);
		root = pj == null ? "." : Path.directory(pj);
		if (root == "") root = ".";
		if (pj != null) configure(pj, false);
		finish();
	}

	function project(dir:String) {
		root = dir;
		configure('$dir/package.json', true);
		if (main == null) main = "Main";
		var file = classPaths[0] + "/" + main.split(".").join("/") + ".hx";
		if (!FileSystem.exists(file)) throw '$dir: no $file (a project\'s entry point, or package.json\'s "helder": {"main"})';
		finish();
	}

	// package.json's class paths, dependencies and overrides
	function configure(pj:String, own:Bool) {
		var dir = Path.directory(pj);
		if (dir == "") dir = ".";
		var json:Dynamic = try haxe.Json.parse(File.getContent(pj)) catch (e:Dynamic) throw '$pj: $e';
		var cps = paths(json.haxe?.classPath);
		if (own && cps.length == 0) cps = ["src"];
		for (c in cps) add(join(dir, c));
		for (field in ["dependencies", "devDependencies", "peerDependencies"]) {
			var deps:Dynamic = Reflect.field(json, field);
			if (deps != null) for (d in Reflect.fields(deps)) dependency(dir, d);
		}
		var h:Dynamic = json.helder;
		if (h != null) {
			if (h.main != null) main = h.main;
			if (h.name != null) name = h.name;
			if (h.defines != null) for (k in Reflect.fields(h.defines)) defines = defines.concat(["-D", '$k=${Reflect.field(h.defines, k)}']);
		}
		if (own) name ??= Path.withoutDirectory(Std.string(json.name ?? Path.withoutDirectory(FileSystem.fullPath(dir))));
		if (FileSystem.exists('$dir/helder.hxml')) hxml = '$dir/helder.hxml';
	}

	// a package in node_modules (here or above) with a "haxe" field
	function dependency(dir:String, name:String) {
		var d = FileSystem.fullPath(dir);
		while (true) {
			var pj = '$d/node_modules/$name/package.json';
			if (FileSystem.exists(pj)) {
				var json:Dynamic = try haxe.Json.parse(File.getContent(pj)) catch (_:Dynamic) null;
				if (json?.haxe != null) for (c in paths(json.haxe.classPath)) add(join(Path.directory(pj), c));
				return;
			}
			var up = Path.directory(d);
			if (up == d || up == "") return;
			d = up;
		}
	}

	function finish() {
		helder = Lambda.find(classPaths, c -> FileSystem.exists('$c/helder/dev/Hot.hx'));
		if (helder == null) {
			// (the CLI's own checkout: bin/cli/helder)
			var beside = Path.directory(Sys.programPath()) + "/../../src";
			if (!FileSystem.exists('$beside/helder/dev/Hot.hx')) throw "no helder library: add helder to package.json's dependencies";
			helder = FileSystem.fullPath(beside);
			classPaths.push(helder);
		}
		// (helder's own sources only while they are this project's: this checkout)
		var isLib = helder.contains("node_modules");
		sources = [for (c in classPaths) if (!(isLib && c == helder) && !c.contains("node_modules")) c];
		if (root != null && FileSystem.exists('$root/assets')) sources.push('$root/assets');
	}

	function add(cp:String) {
		cp = clean(cp);
		if (!classPaths.contains(cp)) classPaths.push(cp);
	}

	public function isWeb():Bool
		return target == "web" || target == "wasm32-wasi";

	// the output: <root>/bin/<dir>/<name>, its extension the target's
	public function out(dir:String):String {
		var ext = isWeb() ? ".wasm" : target.startsWith("windows-") ? ".exe" : "";
		return clean('$root/bin/$dir/$name$ext');
	}

	// the compiler's arguments for this entry (the output's and the mode's added by the caller)
	public function args():Array<String> {
		var out = [];
		for (c in classPaths) out = out.concat(["-cp", c]);
		out = out.concat(["-main", main, "-D", "hxmc.target=" + (target == "web" ? "wasm32-wasi" : target)]);
		if (target.startsWith("linux-")) out = out.concat(["-D", "hxmc.libc=glibc"]);
		// (legacy exception handling: every browser with WebGPU has it, those with WebGL2 since 2021)
		if (target == "web") out = out.concat(["-D", "hxmc.wasm-eh=legacy"]);
		out = out.concat(defines);
		if (hxml != null) out.push(hxml);
		return out;
	}

	static function paths(v:Dynamic):Array<String>
		return v == null ? [] : v is String ? [v] : [for (x in (v : Array<Dynamic>)) Std.string(x)];

	// the nearest package.json at or above dir
	static function above(dir:String):Null<String> {
		var d = dir;
		for (_ in 0...64) {
			if (FileSystem.exists('$d/package.json')) return '$d/package.json';
			var full = FileSystem.fullPath(d), up = Path.directory(full);
			if (up == full || up == "") return null;
			d = parent(d);
		}
		return null;
	}

	static function parent(dir:String):String {
		if (dir == "." || dir == "") return "..";
		if (dir == ".." || dir.endsWith("/..")) return '$dir/..';
		var p = Path.directory(dir);
		return p == "" ? "." : p;
	}

	static function join(dir:String, p:String):String
		return Path.isAbsolute(p) ? p : dir == "." ? p : '$dir/$p';

	public static function clean(p:String):String {
		p = Path.normalize(p.split("\\").join("/"));
		while (p.startsWith("./")) p = p.substr(2);
		return p == "" ? "." : p;
	}
}
