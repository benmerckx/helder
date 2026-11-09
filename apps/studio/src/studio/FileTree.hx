package studio;

import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

using StringTools;

// The project's folder as it is on disk (bin/, node_modules/ and dot
// directories left out), read again as files change (Studio's watch: a
// second apart natively; the page's writes in the browser): the sidebar's
// tree. A design file's rows go on to its frames, a story file's to its
// stories (Project's screens of that file). Directories and the files that
// have frames are open until closed; the others closed until opened.
class FileTree {
	final project:Project;
	// every file and directory, by path (sorted: directories first, then by name)
	public final entries:Signal<Array<FileEntry>> = signal([]);
	// the rows closed or opened by hand (path: open)
	public final toggled:Signal<Map<String, Bool>> = signal(new Map<String, Bool>());
	var listed = "";

	public function new(project:Project) {
		this.project = project;
		scan();
	}

	// the folder read again; true when what is in it changed
	public function scan():Bool {
		var out:Array<FileEntry> = [];
		function go(dir:String, depth:Int) {
			var names = Files.list(dir).filter(n -> !n.startsWith(".") && !(depth == 0 && n == "bin") && n != "node_modules");
			var dirs = [], files = [];
			for (n in names)
				(Files.isDirectory('$dir/$n') ? dirs : files).push(n);
			dirs.sort(order);
			files.sort(order);
			for (n in dirs) {
				out.push({path: '$dir/$n', name: n, depth: depth, kind: Dir});
				go('$dir/$n', depth + 1);
			}
			for (n in files)
				out.push({path: '$dir/$n', name: n, depth: depth, kind: kindOf(n)});
		}
		go(project.dir, 0);
		var key = [for (e in out) e.path].join("\n");
		if (key == listed) return false;
		listed = key;
		entries(out);
		return true;
	}

	static function order(a:String, b:String):Int {
		var x = a.toLowerCase(), y = b.toLowerCase();
		return x < y ? -1 : x > y ? 1 : 0;
	}

	// what a file is, by its name: the view it opens in
	public static function kindOf(name:String):FileKind {
		var n = name.toLowerCase(), ext = n.lastIndexOf(".") < 0 ? "" : n.substr(n.lastIndexOf(".") + 1);
		if (ext == "helder") return Design;
		if (~/\.story\.(hx|tsx|ts)$/.match(n)) return Story;
		return switch ext {
			case "png" | "jpg" | "jpeg" | "gif" | "webp" | "svg" | "bmp": Image;
			case "ttf" | "otf": Font;
			case "gltf" | "glb": Model;
			case "wav" | "ogg" | "mp3" | "flac": Audio;
			case "hx" | "ts" | "tsx" | "js" | "mjs" | "json" | "md" | "txt" | "css" | "html" | "xml" | "yml" | "yaml" | "toml" | "glsl" | "wgsl" | "hxml": Code;
			case _: Other;
		}
	}

	// the frames a file shows: a design file's, a story file's stories
	public function frames(path:String):Array<Project.ScreenInfo> {
		project.version();
		return [for (s in project.screens) if (s.file == path) s];
	}

	// whether a row shows what is under it
	public function open(e:FileEntry):Bool {
		var t = toggled().get(e.path);
		if (t != null) return t;
		return switch e.kind {
			case Dir: holdsFrames(e.path);
			case Design | Story: true;
			case _: false;
		}
	}

	public function toggle(e:FileEntry)
		toggled(m -> {
			var c = m.copy();
			c.set(e.path, !open(e));
			c;
		});

	function holdsFrames(dir:String):Bool {
		for (e in entries.peek())
			if ((e.kind == Design || e.kind == Story) && e.path.startsWith(dir + "/")) return true;
		return false;
	}

	// the rows shown: each entry under open directories, a file's frames under it when open
	public function rows():Array<TreeRow> {
		var out:Array<TreeRow> = [], closed:Null<String> = null;
		for (e in entries()) {
			if (closed != null && e.path.startsWith(closed + "/")) continue;
			closed = null;
			var frames = e.kind == Design || e.kind == Story ? frames(e.path) : [];
			out.push({key: e.path, entry: e, screen: null, depth: e.depth, hasChildren: e.kind == Dir || frames.length > 0});
			if (!open(e)) {
				if (e.kind == Dir) closed = e.path;
				continue;
			}
			for (s in frames)
				out.push({key: "screen:" + s.name, entry: e, screen: s, depth: e.depth + 1, hasChildren: false});
		}
		return out;
	}

	// (a row's tag, Shell's: file-<slug>) its path, for what is dropped on it
	public final tags = new Map<String, String>();

	public function rowPath(tag:Null<String>):Null<String>
		return tag == null ? null : tags.get(tag);

	public function tag(path:String):String {
		var t = "file-" + ~/[^A-Za-z0-9_-]+/g.replace(relative(path), "-").toLowerCase();
		tags.set(t, path);
		return t;
	}

	// target's path from dir, '/'-separated (../ where it is above)
	public static function relativeTo(dir:String, target:String):String {
		var a = dir.split("/").filter(x -> x != ""), b = target.split("/").filter(x -> x != "");
		var i = 0;
		while (i < a.length && i < b.length && a[i] == b[i])
			i++;
		return [for (_ in i...a.length) ".."].concat(b.slice(i)).join("/");
	}

	// a path relative to the project's folder
	public function relative(path:String):String
		return path.startsWith(project.dir + "/") ? path.substr(project.dir.length + 1) : path;
}

enum abstract FileKind(String) to String {
	var Dir = "dir";
	var Design = "design";
	var Story = "story";
	var Code = "code";
	var Image = "image";
	var Font = "font";
	var Model = "model";
	var Audio = "audio";
	var Other = "other";
}

@:structInit class FileEntry {
	public final path:String;
	public final name:String;
	public final depth:Int;
	public final kind:FileKind;
}

// (a row of the tree: an entry, or one of a file's frames)
@:structInit class TreeRow {
	public final key:String;
	public final entry:FileEntry;
	public final screen:Null<Project.ScreenInfo>;
	public final depth:Int;
	public final hasChildren:Bool;
}
