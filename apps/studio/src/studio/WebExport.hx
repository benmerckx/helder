package studio;

#if !(hxmc.target == "wasm32-wasi")
import haxe.Json;
import helder.async.*;
import helder.compiler.service.Service;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// A project for the studio in the browser (`helder studio <project> --
// --export-web <dir>`; apps/studio/web/build.mjs bundles the examples with
// it): its files, and its preview module, the screens' program built for
// the web (Project.words(web): helder.story.Screens there is
// helder.story.web.Preview, the preview host the page runs in a worker),
// a dev build with its live literals' tables. Written to <dir>:
//
//   preview.wasm    the program (none for a project of design files alone)
//   project.json    {name, label, summary (its sources' `// title:` and
//                   `// summary:`, as the examples' headers), files: {path: text}, imports: [package],
//                   root: the project's directory where it was built,
//                   links: {built path: path}, tables: [{file, content, entries}],
//                   screens}
//
// Paths in it are the project's own, from its directory ("Todo.hx"); the
// page puts the files in OPFS and gives the studio the links and tables
// with its own directory in front (/projects/<name>/...).
class WebExport {
	public static function run(dir:String, out:String):Int {
		var p = Project.open(dir);
		helder.cli.TestCommand.mkdirs(out);
		var wasm = FileSystem.fullPath(out) + "/preview.wasm";
		var literals = '${p.out}/web-literals';
		removeTree(literals);
		var r = p.entry == null ? null : Async.run(task -> {
			if (p.typescript) helder.cli.Compiler.typescript(p.entry.helder);
			var s = Service.start(task, {tool: helder.cli.Compiler.tool(), env: Process.environment(), std: helder.cli.Compiler.hxmcStd()}, m -> Sys.println('studio: $m'));
			if (s == null) return null;
			s.literals(literals);
			var words = p.words('${p.out}/web-preview', true);
			words[words.length - 1] = 'hxmc=$wasm';
			var r = s.build(words, p.dir, null);
			s.stop();
			r;
		});
		if (p.entry != null && (r == null || !r.ok)) {
			if (r != null) Sys.println(r.messages);
			Sys.println('studio: ${p.name}: the web preview did not build');
			return 1;
		}
		var rel = (f:String) -> f.startsWith(p.dir + "/") ? f.substr(p.dir.length + 1) : f;
		var files:haxe.DynamicAccess<String> = {};
		for (f in p.sources())
			files.set(rel(f), File.getContent(f));
		var links:haxe.DynamicAccess<String> = {};
		for (l => real in p.links)
			links.set(l, rel(real));
		var tables = [];
		if (FileSystem.exists(literals))
			for (f in FileSystem.readDirectory(literals)) {
				if (!f.endsWith(".json")) continue;
				var t:Dynamic = Json.parse(File.getContent('$literals/$f'));
				var file:String = t.file, real = p.real(file);
				if (!FileSystem.exists(real) || haxe.crypto.Md5.encode(File.getContent(real)) != f.substr(0, f.length - 5)) continue;
				tables.push({file: file, content: File.getContent(real), entries: t.entries});
			}
		var manifest = {
			name: p.name,
			label: header(p, "title") ?? p.name,
			summary: header(p, "summary"),
			root: p.dir,
			files: files,
			imports: r == null ? [] : helder.cli.Page.packages(BuildInfo.helderSrc(), wasm),
			links: links,
			tables: tables,
			screens: p.screens.length,
		};
		File.saveContent('$out/project.json', Json.stringify(manifest));
		Sys.println('studio: ${p.name}: ${p.screens.length} screens for the web in ${r?.ms ?? 0} ms, ${tables.length} sources\' live literals, $out');
		return 0;
	}

	static function header(p:Project, key:String):Null<String> {
		var r = new EReg('^// *$key: *(.*)$', "m");
		for (f in p.sources())
			if (r.match(File.getContent(f))) return r.matched(1);
		return null;
	}

	static function removeTree(d:String) {
		if (!FileSystem.exists(d)) return;
		for (f in FileSystem.readDirectory(d))
			if (FileSystem.isDirectory('$d/$f')) removeTree('$d/$f') else FileSystem.deleteFile('$d/$f');
		FileSystem.deleteDirectory(d);
	}
}
#end
