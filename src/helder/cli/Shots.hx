package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.TestCommand.Mapper;
import helder.cli.TestCommand.Output;
import helder.cli.TestCommand.Project;
import helder.cli.TestCommand.TestFile;
import helder.syntax.Document;
import helder.syntax.Scanner.Lang;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// An app's screenshots from its stories, the one source of them: the
// stories with store: true (helder.story) rendered by a program of the
// project's story files around helder.story.StoreShots, built for this
// machine (not a release: a release has no stories), run, its shots.json
// read. helder publish --screenshots asks it for the stores' sizes with
// their captions (store), helder publish --run for helder.run's frames
// (web: one size, no caption band).
//
// The story files are the entry's project's: under its directory (the
// helder.json's, a TypeScript program's, a project's, the main file's
// class path), Foo.story.hx for a Haxe program, foo.story.ts(x) for a
// TypeScript one; none there, the working directory's as helder test finds
// them (its src/, tests/ and class paths). Each Haxe one linked as a module
// of its own (Foo_story) beside a generated main (bin/shots/gen); a
// TypeScript program's main imports each story it exports
// (bin/shots/shots.tsx: shots([...]) of helder/story).
class Shots {
	// the stores' screenshots in dir (StoreShots.store): shots.json's list
	@:coroutine public static function store(e:Entry, dir:String, landscape:Bool):Array<Dynamic> {
		var found = find(e, true);
		if (found.files.length == 0) throw "store screenshots: no story files (*.story.hx, *.story.tsx: helder.story; one with store: true)";
		return render(e, found, [dir, landscape ? "landscape" : "portrait"], "store screenshots");
	}

	// helder.run's: at most max of the stories with store: true at width x
	// height pixels (scale: pixels a point), no caption band, in dir
	// (shot-<n>.png); an empty list when there are none (nothing built)
	@:coroutine public static function web(e:Entry, dir:String, width:Int, height:Int, scale:Float, max:Int):Array<Dynamic> {
		var found = find(e, false);
		if (found.stores == 0) return [];
		return render(e, found, [dir, "web", '${width}x$height', Std.string(scale), Std.string(max)], "helder.run's screenshots");
	}

	// the entry's story files (stores: how many stories with store: true
	// they have, read from their text); none and others: the working
	// directory's as helder test finds them (a Haxe program's)
	public static function find(e:Entry, others:Bool):{files:Array<String>, stores:Int, own:Bool} {
		var dir = home(e), ts = e.typescript != null;
		var files = [];
		walk(dir, ts, files);
		files.sort(Reflect.compare);
		var own = true;
		if (files.length == 0 && !ts && others) {
			own = false;
			files = [for (f in new Project().testFiles()) if (f.story == true) f.real];
		}
		var stores = 0;
		for (f in files)
			for (s in stories(f))
				if (s.store) stores++;
		return {files: files, stores: stores, own: own};
	}

	// the directory the entry's stories are under
	static function home(e:Entry):String {
		if (FileSystem.exists('${e.root}/${HelderJson.FILE}')) return e.root;
		if (e.typescript != null) {
			var d = Path.directory(e.typescript.split("\\").join("/"));
			return Path.withoutDirectory(d) == "src" && FileSystem.exists(Path.directory(d) + "/package.json") ? Path.directory(d) : d;
		}
		var cp = e.classPaths[0] ?? ".";
		// (a project's own class path, src/: the project, its tests/ too)
		var pj:Dynamic = try haxe.Json.parse(File.getContent('${e.root}/package.json')) catch (_:Dynamic) null;
		if (pj != null) {
			var c:Dynamic = pj.haxe?.classPath;
			var own:Array<String> = c == null ? ["src"] : c is String ? [c] : [for (x in (c : Array<Dynamic>)) Std.string(x)];
			for (o in own)
				if (Entry.clean(e.root == "." ? o : '${e.root}/$o') == cp) return e.root;
		}
		return cp;
	}

	static function walk(dir:String, ts:Bool, into:Array<String>)
		for (n in (try FileSystem.readDirectory(dir) catch (_:Dynamic) [])) {
			if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
			var p = dir == "." ? n : '$dir/$n';
			if (FileSystem.isDirectory(p)) walk(p, ts, into);
			else if (ts ? n.endsWith(".story.tsx") || n.endsWith(".story.ts") : n.endsWith(".story.hx")) into.push(p);
		}

	// a story file's stories, read from its text (helder.syntax): each one's
	// name, the name it is bound to, whether it is a store screenshot
	public static function stories(file:String):Array<{name:String, binding:Null<String>, store:Bool}> {
		var doc = Document.parse(File.getContent(file), Lang.of(file));
		var out = [];
		for (c in doc.calls("story")) {
			var o = c.object(0);
			if (o == null) continue;
			var n = o.field("name"), st = o.field("store");
			var lit = n?.literal(), flag = st?.literal();
			out.push({
				name: lit == null ? "" : lit.text(doc.text),
				binding: c.name,
				store: flag != null && flag.text(doc.text) == "true"
			});
		}
		return out;
	}

	// the program built (bin/shots under the entry's root) and run with args; its shots.json's list
	@:coroutine static function render(e:Entry, found:{files:Array<String>, stores:Int, own:Bool}, args:Array<String>, what:String):Array<Dynamic> {
		var dir = args[0];
		var out = Entry.clean('${e.root}/bin/shots');
		var gen = '$out/gen';
		TestCommand.mkdirs(gen);
		var words = e.args(), linked:Array<TestFile> = [];
		if (e.typescript != null) {
			Compiler.typescript(e.helder);
			var main = FileSystem.fullPath(out).split("\\").join("/") + "/shots.tsx";
			save(main, typescriptMain(found.files, Path.directory(main)));
			words = [for (w in words) w.startsWith("helder.typescript=") ? 'helder.typescript=$main' : w];
			for (f in found.files) linked.push({real: f, linked: f, module: "", interp: false, ts: true});
		} else {
			var modules = [], cps = [gen];
			for (f in found.files) {
				var l = link(f, gen);
				linked.push({real: f, linked: l.linked, module: l.module, interp: false, story: true});
				modules.push(l.module);
				if (!cps.contains(l.classPath) && !e.classPaths.contains(l.classPath)) cps.push(l.classPath);
			}
			var lines = ["// helder publish's screenshots: the project's stories, then StoreShots (generated)", "class HelderShots {", "\tstatic function main() {"];
			for (m in modules)
				lines.push('\t\tfor (s in helder.story.Stories.of("$m")) helder.story.Stories.add(s);');
			lines = lines.concat(["\t\thelder.story.StoreShots.main();", "\t}", "}", ""]);
			save('$gen/HelderShots.hx', lines.join("\n"));
			var k = words.indexOf("-main");
			words[k + 1] = "HelderShots";
			var pre = [];
			for (c in cps) pre = pre.concat(["-cp", c]);
			words = pre.concat(words);
		}
		var exe = '$out/shots' + (Sys.systemName() == "Windows" ? ".exe" : "");
		var map = new Mapper(linked);
		// (a program for this machine: its runtime objects hxmc's own, not
		// HXMC_RT_DIR's, which names a phone's for the other builds)
		var rt = Sys.getEnv("HXMC_RT_DIR");
		if (rt != null) Sys.putEnv("HXMC_RT_DIR", "");
		var b = Output.of(Compiler.tool(), words.concat(["--custom-target", 'hxmc=$exe']), map, 'building $what');
		if (rt != null) Sys.putEnv("HXMC_RT_DIR", rt);
		if (b.code != 0) throw '$what: the build failed';
		TestCommand.mkdirs(dir);
		if (FileSystem.exists('$dir/shots.json')) FileSystem.deleteFile('$dir/shots.json');
		if (Sys.systemName() == "Linux" && (Sys.getEnv("LIBGL_ALWAYS_SOFTWARE") ?? "") == "") Sys.putEnv("LIBGL_ALWAYS_SOFTWARE", "1");
		var r = Output.of(exe, args, map, 'rendering $what');
		if (r.code != 0 || !FileSystem.exists('$dir/shots.json')) throw '$what: rendering failed (a GPU, or Mesa\'s llvmpipe, and fonts)';
		return haxe.Json.parse(File.getContent('$dir/shots.json'));
	}

	// a Haxe story file linked under gen as its module (Foo.story.hx: Foo_story, in its package's directory)
	static function link(f:String, gen:String):{linked:String, module:String, classPath:String} {
		var declared = ~/^\s*package\s+([\w.]*)\s*;/m;
		var pack = declared.match(File.getContent(f)) ? declared.matched(1) : "";
		var dirs = pack == "" ? [] : pack.split(".");
		var cp = Path.directory(f);
		if (cp == "") cp = ".";
		for (_ in dirs) cp = Path.directory(cp) == "" ? "." : Path.directory(cp);
		var name = Path.withoutDirectory(f);
		name = name.substr(0, name.length - ".story.hx".length) + "_story";
		var linked = '$gen/' + (dirs.length == 0 ? "" : dirs.join("/") + "/") + name + ".hx";
		TestCommand.mkdirs(Path.directory(linked));
		Link.make(f, linked);
		return {linked: linked, module: dirs.concat([name]).join("."), classPath: Entry.clean(cp)};
	}

	// (TypeScript) a main importing each exported story of the files, in their order, then shots([...])
	static function typescriptMain(files:Array<String>, at:String):String {
		var lines = ["// helder publish's screenshots: the project's stories (generated)", 'import { shots } from "helder/story";'];
		var k = 0, names = [];
		for (f in files) {
			var bound = [for (s in stories(f)) if (s.binding != null) s.binding];
			if (bound.length == 0) continue;
			var rel = Link.relative(FileSystem.fullPath(f).split("\\").join("/"), at);
			if (!rel.startsWith(".")) rel = "./" + rel;
			var as = [];
			for (b in bound) {
				as.push('$b as s$k');
				names.push('s${k++}');
			}
			lines.push('import { ${as.join(", ")} } from "${~/\.tsx?$/.replace(rel, "")}";');
		}
		lines.push('shots([${names.join(", ")}]);');
		return lines.join("\n") + "\n";
	}

	static function save(path:String, text:String)
		if (!FileSystem.exists(path) || File.getContent(path) != text) File.saveContent(path, text);
}
