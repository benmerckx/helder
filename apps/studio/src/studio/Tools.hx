package studio;

import haxe.Json;
import helder.async.*;
import helder.syntax.Transaction;
import studio.Previews;

using StringTools;

// The studio's tools for agents (the MCP server's, Mcp; the prompt bar's,
// LocalAgent): the project read and patched (each patch an edit of the
// studio's, in its history: undone like any other, a live literal's
// patched in the screens, anything else built), the program checked,
// a screen's frame and tree read.
//
//   project.read   {path?}                    a file's text (its current edits too), else the files and screens
//   project.patch  {path, edits: [{old, new}]} or {path, text}   then {result: patched | built | failed | unchanged, diagnostics}
//   build.check    {}                         the program typed (tsgo's check too), nothing written: diagnostics
//   run.snap       {screen?, path?}           a screen's last frame as a PNG (an image, and the file written; a design's frame drawn offscreen)
//   run.tree       {screen?}                  a screen's node tree: tags, boxes, texts, styles, sources (a design's: its interpreted nodes)
class Tools {
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	public static final list:Array<Dynamic> = [
		{
			name: "project.read",
			description: "Read a file of the project open in helder studio (with the studio's unsaved state), or without a path list its source files and screens (stories by flow).",
			inputSchema: {type: "object", properties: {path: {type: "string", description: "a path relative to the project's directory, or absolute"}}}
		},
		{
			name: "project.patch",
			description: "Edit a file of the project: each edit's old text (once in the file) replaced by its new text, or the whole text given. The edit goes through the studio's history (undoable); live literals' values are patched in the running screens at once, anything else rebuilds. Answers what happened and the build's diagnostics.",
			inputSchema: {
				type: "object",
				properties: {
					path: {type: "string"},
					edits: {
						type: "array",
						items: {type: "object", properties: {old: {type: "string"}, "new": {type: "string"}}, required: ["old", "new"]}
					},
					text: {type: "string", description: "the file's whole new text (instead of edits)"}
				},
				required: ["path"]
			}
		},
		{
			name: "build.check",
			description: "Type the project's program (TypeScript's tsgo check too) without building it: its diagnostics.",
			inputSchema: {type: "object", properties: {}}
		},
		{
			name: "run.snap",
			description: "A screen's last frame as the running program drew it (a PNG); a design file's frame drawn by the studio from its markup as it is now. Without a screen, the one in focus, else the first.",
			inputSchema: {type: "object", properties: {screen: {type: "string", description: "a screen's (story's) name, Flow/Screen"}, path: {type: "string"}}}
		},
		{
			name: "run.tree",
			description: "A screen's node tree from the running program (a design file's frame: its nodes as interpreted from its markup, and what could not be): each node's tag, box, text, a few styles and where its markup is (file:line).",
			inputSchema: {type: "object", properties: {screen: {type: "string"}}}
		},
	];

	// a tool called: its content (MCP's: [{type: text, text} | {type: image, data, mimeType}]) and whether it failed
	@:coroutine public function call(name:String, args:Dynamic):{content:Array<Dynamic>, isError:Bool} {
		if (args == null) args = {};
		return try switch name {
			case "project.read": text(read(args.path));
			case "project.patch": text(Json.stringify(patch(args), "  "));
			case "build.check":
				var pr = studio.previews;
				if (pr == null) throw "no project open";
				var r = pr.check();
				text(Json.stringify({ok: r.ok, ms: r.ms, diagnostics: r.diagnostics}, "  "));
			case "run.snap": snap(args);
			case "run.tree": text(Json.stringify(tree(args.screen), "  "));
			case _: throw 'no tool $name';
		} catch (e:Dynamic) {content: [{type: "text", text: Std.string(e)}], isError: true};
	}

	static function text(s:String):{content:Array<Dynamic>, isError:Bool}
		return {content: [{type: "text", text: s}], isError: false};

	function path(p:Null<String>):String {
		var pr = studio.project;
		if (pr == null) throw "no project open";
		if (p == null || p == "") throw "a path is needed";
		var full = haxe.io.Path.isAbsolute(p) ? p : pr.dir + "/" + p;
		full = haxe.io.Path.normalize(full);
		if (!full.startsWith(pr.dir + "/")) throw '$p is not in the project ($pr.dir)';
		return full;
	}

	function read(p:Null<String>):String {
		var pr = studio.project;
		if (pr == null) throw "no project open";
		if (p == null || p == "") {
			var files = [for (f in pr.sources()) f.substr(pr.dir.length + 1)];
			var flows = [for (f in pr.flows()) {flow: f.name, screens: [for (s in f.screens) {name: s.name, width: s.width, height: s.height, file: s.file.substr(pr.dir.length + 1)}]}];
			return Json.stringify({project: pr.name, dir: pr.dir, typescript: pr.typescript, files: files, flows: flows}, "  ");
		}
		var f = path(p);
		if (!Files.exists(f)) throw '$p: no such file';
		return studio.docs.get(f).text;
	}

	@:coroutine function patch(args:Dynamic):Dynamic {
		var f = path(args.path);
		var doc = studio.docs.get(f);
		var base = doc.text, changes = [];
		if (args.text != null) changes.push(new helder.syntax.Transaction.Change(0, base.length, args.text));
		else {
			var edits:Array<Dynamic> = args.edits ?? [];
			if (edits.length == 0) throw "no edits (edits: [{old, new}], or text)";
			for (e in edits) {
				var old:String = e.old, at = base.indexOf(old);
				if (old == "" || at < 0) throw 'not in ${args.path}: ${old.substr(0, 60)}';
				if (base.indexOf(old, at + 1) >= 0) throw 'more than once in ${args.path}: ${old.substr(0, 60)} (give more of it)';
				changes.push(new helder.syntax.Transaction.Change(at, at + old.length, Reflect.field(e, "new")));
			}
		}
		var pr = studio.previews;
		var before = pr == null ? 0 : pr.buildMs.peek();
		studio.edit(f, new Transaction(changes, null, base), "agent's patch", "agent");
		// (its way to the program: a patch at once, a build waited for)
		var t0 = haxe.Timer.stamp();
		Async.delay(0.02);
		while (pr != null && pr.busy() && haxe.Timer.stamp() - t0 < 120) Async.delay(0.02);
		var diags = pr == null ? [] : [for (d in pr.diagnostics.peek()) d];
		return {
			result: pr == null ? "saved" : pr.failed ? "failed" : studio.message.peek().startsWith("patched") ? "patched" : "built",
			message: studio.message.peek(),
			diagnostics: diags
		};
	}

	function screenOf(name:Null<String>):Screen {
		var pr = studio.previews;
		if (pr == null) throw "no project open";
		var n = name ?? studio.focused.peek();
		var s = n == null ? pr.screens[0] : pr.screen(n);
		if (s == null) throw 'no screen $n (${[for (x in pr.screens) x.info.name].join(", ")})';
		return s;
	}

	// the design frame named (else in focus; else the first screen, without
	// a program): drawn by the studio itself; null: the program's screen
	function designOf(name:Null<String>):Null<Project.ScreenInfo> {
		var p = studio.project;
		if (p == null) throw "no project open";
		var n = name ?? studio.focused.peek();
		var s = n == null ? (studio.previews == null ? p.screens[0] : null) : p.screen(n);
		if (n != null && s == null) throw 'no screen $n (${[for (x in p.screens) x.name].join(", ")})';
		return s != null && s.source.match(Design(_)) ? s : null;
	}

	@:coroutine function snap(args:Dynamic):{content:Array<Dynamic>, isError:Bool} {
		var d = designOf(args.screen);
		if (d != null) {
			var img = studio.designs.pixels(d.name);
			var png = helder.image.PngEncoder.encode(img.pixels, img.width, img.height, true);
			var out = written(png, args.path, Shell.slug(d.name));
			return {
				content: [
					{type: "image", data: haxe.crypto.Base64.encode(png), mimeType: "image/png"},
					{type: "text", text: '${d.name}: ${img.width}x${img.height}, interpreted from ${rel(d.file)}, written to $out'}
				],
				isError: false
			};
		}
		var s = screenOf(args.screen);
		var img = s.image.peek();
		if (img == null) throw '${s.info.name} has no frame yet';
		#if (hxmc.target == "wasm32-wasi")
		// (a frame of the preview host's is the browser's, its pixels on the GPU)
		if (!img.hasPixels) throw '${s.info.name}: its frame is on the GPU (the web\'s previews): no PNG of it here';
		var out = "(not written)";
		var png = helder.image.PngEncoder.encode(img.pixels, img.width, img.height, true);
		#else
		// (a texture the host shares: read back there)
		img = studio.previews.pixels(s);
		if (img == null) throw '${s.info.name}: its frame could not be read';
		var png = helder.image.PngEncoder.encode(img.pixels, img.width, img.height, true);
		var out = written(png, args.path, s.slug);
		#end
		return {
			content: [
				{type: "image", data: haxe.crypto.Base64.encode(png), mimeType: "image/png"},
				{type: "text", text: '${s.info.name}: ${img.width}x${img.height}, frame ${s.version}, written to $out'}
			],
			isError: false
		};
	}

	// (a snap's PNG written: path, else the project's snaps/<slug>.png)
	function written(png:haxe.io.Bytes, path:Null<String>, slug:String):String {
		#if (hxmc.target == "wasm32-wasi")
		return "(not written)";
		#else
		var out = path ?? '${studio.project.out}/snaps/$slug.png';
		helder.cli.TestCommand.mkdirs(haxe.io.Path.directory(out));
		sys.io.File.saveBytes(out, png);
		return out;
		#end
	}

	function rel(f:String):String
		return f.startsWith(studio.project.dir + "/") ? f.substr(studio.project.dir.length + 1) : f;

	// a design frame's tree: its nodes as interpreted now, offscreen at its size
	function designTree(d:Project.ScreenInfo):Dynamic {
		var o = studio.designs.offscreen(d.name);
		var doc = studio.docs.get(d.file).doc;
		function node(n:helder.ui.Node, root:helder.ui.Node):Dynamic {
			var o2:Dynamic = {tag: n.tag, rect: [r(n.absX - root.absX), r(n.absY - root.absY), r(n.width), r(n.height)]};
			if (Std.isOfType(n, helder.ui.TextNode)) o2.text = (cast n : helder.ui.TextNode).text;
			if ((n.style.background : Int) != 0) o2.background = hex(n.style.background);
			if (n.style.color != null) o2.color = hex(n.style.color);
			if (n.style.opacity != 1) o2.opacity = n.style.opacity;
			var at = o.made.sources.get(n);
			if (at != null) o2.source = rel(d.file) + ":" + doc.lineCol(at).line;
			if (n.children.length > 0) o2.children = [for (c in n.children) node(c, root)];
			return o2;
		}
		var root = o.made.nodes[0];
		var errors = [for (e in o.made.errors) {message: e.message, source: e.at < 0 ? null : rel(d.file) + ":" + doc.lineCol(e.at).line}];
		return {screen: d.name, interpreted: true, root: root == null ? null : node(root, root), errors: errors};
	}

	static function hex(c:Int):String
		return "#" + StringTools.hex(c, 8).toLowerCase();

	@:coroutine function tree(name:Null<String>):Dynamic {
		var d = designOf(name);
		if (d != null) return designTree(d);
		var s = screenOf(name);
		var answer:Dynamic = null;
		if (!studio.previews.request(s, "Ui.getTree", {}, r -> answer = r)) throw '${s.info.name} is not running';
		var t0 = haxe.Timer.stamp();
		while (answer == null && haxe.Timer.stamp() - t0 < 5) Async.delay(0.005);
		if (answer == null) throw '${s.info.name} did not answer';
		var root:Dynamic = Studio.rootOf(answer);
		return {screen: s.info.name, root: simplify(root)};
	}

	// (a node as an agent reads it: its source a file:line of the project)
	function simplify(n:Dynamic):Dynamic {
		if (n == null) return null;
		var o:Dynamic = {tag: n.tag, rect: [r(n.x), r(n.y), r(n.width), r(n.height)]};
		if (n.text != null) o.text = n.text;
		var st:Dynamic = n.style;
		if (st != null) {
			if (st.background != null && st.background != "#00000000") o.background = st.background;
			if (st.color != null) o.color = st.color;
			if (st.opacity != null && st.opacity != 1) o.opacity = st.opacity;
		}
		if (n.source != null) {
			var f = studio.project.real(n.source.file);
			o.source = (f.startsWith(studio.project.dir + "/") ? f.substr(studio.project.dir.length + 1) : f) + ":" + n.source.line;
		}
		var kids:Array<Dynamic> = n.children ?? [];
		if (kids.length > 0) o.children = [for (c in kids) simplify(c)];
		return o;
	}

	static function r(v:Float):Float
		return Math.round(v * 10) / 10;
}
