package studio;

import haxe.io.Path;
#if !(hxmc.target == "wasm32-wasi")
import helder.cli.Entry;
import sys.FileSystem;
#end
import helder.syntax.Document;
import helder.syntax.Scanner.Lang;

using StringTools;

// A project opened in the studio: its entry (helder.cli.Entry: what
// `helder dev` would build), its screens, and the program the studio builds
// of them.
//
// Screens (README.md, "Screens"): a project's screens are its stories,
// story({name: "Flow/Screen", width, height, render}) in its *.story.hx
// (Haxe) and *.story.tsx / *.story.ts (TypeScript) files, found under the
// project's directory; a screen's flow is its name's part before the last
// "/" (none: "Screens"), its size the story's (a phone's, 390x844, without).
// A project without stories has one screen: its own main's window, the flow
// "App". The stories are read from their text (helder.syntax), not built:
// the canvas lays them out before anything compiled.
//
// The program: a dev build (-D hxmc.dev: live literals, the devtools'
// agent, node <-> source mapping) for a headless run (-D helder.headless:
// offscreen, its frames to a file), its main the screens' host
// (helder.story.Screens over the stories: bin/studio/<name>/gen/StudioScreens.hx
// with the story files linked beside it as test files are, Foo_story.hx;
// TypeScript: bin/studio/<name>/screens.tsx importing them).
//
// In the browser (apps/studio/web) a project is the page's: its files a
// copy kept in OPFS (Files), its program a preview module for the web
// (helder.story.web.Preview over its stories) the page has, built where it
// came from (an example's, bundled with the page) or by the compiler's
// worker; links maps the build's paths (its sources' paths where it was
// built, which its live literals' ids and its nodes' sources name) to the
// project's.
class Project {
	// the project's directory (full path), its name
	public final dir:String;
	public final name:String;
	#if !(hxmc.target == "wasm32-wasi")
	public final entry:Entry;
	#end
	public final typescript:Bool;
	public final screens:Array<ScreenInfo> = [];
	// where the studio's files for it go: <root>/bin/studio/<name>
	public final out:String;
	// the story files' links (Haxe): linked path to real path
	public final links = new Map<String, String>();

	#if (hxmc.target == "wasm32-wasi")
	// the preview's live literals' tables ({file: its built path, content, entries})
	public final tables:Array<Dynamic>;

	// (the page's project: studio.web.StudioWeb.project's)
	function new(info:Dynamic) {
		tables = info.tables ?? [];
		dir = info.dir;
		name = info.name;
		out = '$dir/bin/studio/$name';
		var l:haxe.DynamicAccess<String> = info.links ?? {};
		for (k => v in l)
			links.set(k, v);
		findScreens();
		typescript = Lambda.exists(screens, s -> StringTools.endsWith(s.file, ".tsx") || StringTools.endsWith(s.file, ".ts"));
	}

	// the page's project (null: none opened)
	public static function opened():Null<Project> {
		var h = studio.web.StudioWeb.project();
		return h == 0 ? null : new Project(haxe.Json.parse(studio.web.StudioWeb.WebText.take(h)));
	}
	#else
	function new(dir:String) {
		this.dir = FileSystem.fullPath(dir).split("\\").join("/");
		entry = Entry.resolve(this.dir);
		typescript = entry.typescript != null;
		name = entry.name;
		out = FileSystem.fullPath(entry.root).split("\\").join("/") + '/bin/studio/$name';
		findScreens();
	}

	// the project in dir (a thrown message: not one)
	public static function open(dir:String):Project
		return new Project(dir);
	#end

	// the stories of the story files under the project's directory, in path order, each in the order written
	function findScreens() {
		var files = [];
		walk(dir, files);
		files.sort(Reflect.compare);
		for (f in files) {
			var text = Files.read(f);
			var doc = Document.parse(text, Lang.of(f));
			for (c in doc.calls("story")) {
				var o = c.object(0);
				if (o == null) continue;
				var n = o.field("name");
				var lit = n == null ? null : n.literal();
				if (lit == null) continue;
				var name = unquote(lit.text(doc.text));
				var cut = name.lastIndexOf("/");
				screens.push({
					name: name,
					flow: cut < 0 ? "Screens" : name.substr(0, cut),
					label: cut < 0 ? name : name.substr(cut + 1),
					width: num(o, "width", doc) ?? 390,
					height: num(o, "height", doc) ?? 844,
					file: f,
					binding: c.name,
					story: true
				});
			}
		}
		if (screens.length == 0) screens.push({
			name: name,
			flow: "App",
			label: name,
			width: 0,
			height: 0,
			file: #if (hxmc.target == "wasm32-wasi") "" #else entry.typescript ?? "" #end,
			binding: null,
			story: false
		});
	}

	static function walk(d:String, into:Array<String>) {
		for (n in Files.list(d)) {
			if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
			var p = '$d/$n';
			if (Files.isDirectory(p)) walk(p, into) else if (n.endsWith(".story.hx") || n.endsWith(".story.tsx") || n.endsWith(".story.ts")) into.push(p);
		}
	}

	static function num(o:ObjectLit, key:String, doc:Document):Null<Int> {
		var f = o.field(key);
		var l = f == null ? null : f.literal();
		return l == null ? null : Std.parseInt(l.text(doc.text));
	}

	static function unquote(s:String):String
		return s.length >= 2 && (s.charAt(0) == '"' || s.charAt(0) == "'") ? s.substring(1, s.length - 1) : s;

	// the flows in order, each its screens
	public function flows():Array<{name:String, screens:Array<ScreenInfo>}> {
		var out:Array<{name:String, screens:Array<ScreenInfo>}> = [];
		for (s in screens) {
			var f = Lambda.find(out, x -> x.name == s.flow);
			if (f == null) out.push(f = {name: s.flow, screens: []});
			f.screens.push(s);
		}
		return out;
	}

	#if !(hxmc.target == "wasm32-wasi")
	// the compiler's words for the screens' program into exe (its host's files written)
	// (web: the program for the browser, helder.story.Screens there the
	// preview host of a worker, helder.story.web.Preview: WebExport's)
	public function words(exe:String, web = false):Array<String> {
		var was = entry.target;
		if (web) entry.target = "web";
		var w = entry.args();
		entry.target = was;
		var host = screens[0].story;
		if (host && typescript) {
			var main = writeTypescriptHost();
			w = [for (x in w) x.startsWith("helder.typescript=") ? 'helder.typescript=$main' : x];
		} else if (host) {
			var gen = writeHaxeHost();
			var k = w.indexOf("-main");
			w[k + 1] = "StudioScreens";
			w = ["-cp", gen].concat(w);
		}
		return w.concat(["-D", "hxmc.dev", "-D", "disable-hxb-cache"])
			.concat(web ? [] : ["-D", "helder.headless"])
			.concat(["-D", 'helder.name=$name', "--custom-target", 'hxmc=$exe']);
	}

	// (Haxe) the story files linked as modules (Foo.story.hx: Foo_story) and a main over their stories
	function writeHaxeHost():String {
		var gen = '$out/gen';
		var modules = [];
		for (f in storyFiles()) {
			var cp = Lambda.find(entry.classPaths.map(c -> FileSystem.fullPath(c).split("\\").join("/")), c -> f.startsWith(c + "/"));
			if (cp == null) throw '$f: not under the project\'s class paths (${entry.classPaths.join(", ")})';
			var rel = f.substr(cp.length + 1), dirs = Path.directory(rel);
			var module = Path.withoutDirectory(rel);
			module = module.substr(0, module.length - ".story.hx".length) + "_story";
			var linked = '$gen/' + (dirs == "" ? "" : dirs + "/") + module + ".hx";
			helder.cli.TestCommand.mkdirs(Path.directory(linked));
			helder.cli.Link.make(f, linked);
			links.set(linked, f);
			modules.push(dirs == "" ? module : dirs.split("/").join(".") + "." + module);
		}
		var all = [for (m in modules) 'helder.story.Stories.of("$m")'].join(".concat(") + [for (_ in 1...modules.length) ")"].join("");
		save('$gen/StudioScreens.hx', '// helder studio\'s screens: the project\'s stories (generated)\nclass StudioScreens {\n\tstatic function main()\n\t\thelder.story.Screens.run($all);\n}\n');
		return gen;
	}

	// (TypeScript) a main importing the stories (each bound to an exported name)
	function writeTypescriptHost():String {
		helder.cli.TestCommand.mkdirs(out);
		var lines = ['// helder studio\'s screens: the project\'s stories (generated)', 'import { screens } from "helder/story";'];
		var names = [];
		var byFile = new Map<String, Array<String>>();
		var order = [];
		for (s in screens) {
			if (s.binding == null) throw '${s.file}: the story "${s.name}" is not bound to an exported name (export const x = story({...}))';
			if (!byFile.exists(s.file)) {
				byFile.set(s.file, []);
				order.push(s.file);
			}
			byFile.get(s.file).push(s.binding);
		}
		var k = 0;
		for (f in order) {
			var as = [for (b in byFile.get(f)) '$b as s${k++}'];
			var rel = helder.cli.Link.relative(f, out);
			if (!rel.startsWith(".")) rel = "./" + rel;
			lines.push('import { ${as.join(", ")} } from "${~/\.tsx?$/.replace(rel, "")}";');
		}
		for (i in 0...k) names.push('s$i');
		lines.push('screens([${names.join(", ")}]);');
		var main = '$out/screens.tsx';
		save(main, lines.join("\n") + "\n");
		return main;
	}

	#end

	function storyFiles():Array<String> {
		var out = [];
		for (s in screens) if (!out.contains(s.file)) out.push(s.file);
		return out;
	}

	// a source's path as the project's (a linked story file's: its real one)
	public function real(file:String):String
		return links.get(file) ?? file;

	// the project's source files (the code view's list): .hx, .ts, .tsx under its directory
	public function sources():Array<String> {
		var out = [];
		function go(d:String)
			for (n in Files.list(d)) {
				if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
				var p = '$d/$n';
				if (Files.isDirectory(p)) go(p) else if ((n.endsWith(".hx") || n.endsWith(".tsx") || n.endsWith(".ts")) && !n.endsWith(".d.ts")) out.push(p);
			}
		go(dir);
		out.sort(Reflect.compare);
		return out;
	}

	static function save(path:String, text:String)
		if (!Files.exists(path) || Files.read(path) != text) Files.save(path, text);
}

typedef ScreenInfo = {
	// the story's name (Flow/Screen), its flow and its own part
	name:String,
	flow:String,
	label:String,
	// points (0: the program's own window's)
	width:Int,
	height:Int,
	// the story's file, the name it is bound to (TypeScript's import)
	file:String,
	binding:Null<String>,
	// a story (false: the program's own main)
	story:Bool,
}
