package studio;

import haxe.Json;
import helder.async.*;

import helder.syntax.Edits;
import helder.syntax.Cst.Kind;
import helder.syntax.Transaction;
import helder.syntax.Transaction.Change;
import helder.ui.*;
import helder.ui.code.CodeEditor;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;
import studio.Previews;
import studio.Project;

using StringTools;

// The studio's state and what it does (Shell draws it): a project opened,
// its screens' previews (Previews: the program in a process of its own;
// none for a project of design files alone), its design files' frames
// (Designs: interpreted here, an edit drawn again at once),
// the canvas' camera and layout, what is in focus (all screens, or the
// screen zoomed into), the node selected in it, and every edit (Docs: the
// files, one history). An edit's way to the program (commit): a live
// literal's value is patched in the running screens at once (the next
// frame shows it), then the file saved; anything else saved, then built
// and the screens reloaded with their state.
class Studio {
	public static var current(default, null):Null<Studio> = null;
	// when the program started (Main's first line): the cold start's measure
	public static var processStart = haxe.Timer.stamp();

	public final project:Null<Project>;
	public final previews:Null<Previews>;
	public final designs:Designs;
	public final docs = new Docs();
	public final camera = new Camera();
	public final layout:Layout;
	public final tools:Tools;
	public final drag:Drag;
	// the project's folder (the sidebar's tree; null: no project)
	public final tree:Null<FileTree>;
	// the file shown: in its viewer (mode "file": an image, a font...), the code view's, a design's page
	public final shown:Signal<Null<String>> = signal(null);
	public final agent:Agent;
	public var mcp(default, null):Null<Mcp> = null;
	// "design" (the canvas), "code" (the code view beside the screen), "stories" (the list)
	public final mode = signal("design");
	// the screen zoomed into (its name; null: all screens)
	public final focused:Signal<Null<String>> = signal(null);
	public final selection:Signal<Null<Selection>> = signal(null);
	// the other nodes selected with it (shift-click, a design's frame: the
	// selection the one clicked last, the inspector's)
	public final others:Signal<Array<Selection>> = signal([]);
	// the code view's file
	public final codeFile:Signal<Null<String>> = signal(null);
	// the window is compact (narrower than Theme.COMPACT: a phone, a tablet
	// upright): the screens' list a drawer (open: drawer), the inspector a
	// bottom sheet (open or peeking: sheetOpen)
	public final compact = signal(false);
	public final drawer = signal(false);
	public final sheetOpen = signal(true);
	// the sidebar's layers shown (its section's header closes it)
	public final layersOpen = signal(true);
	// the command field's list open (secondary-K: Command)
	public final commandOpen = signal(false);
	// the status line's message, the agent's last reply
	public final message = signal("");
	public final reply = signal("");
	// the stage's size (points): what fits a view; its node; bumped when it changes
	public var stageWidth(default, null) = 0.0;
	public var stageHeight(default, null) = 0.0;
	public var stageNode:Null<Node> = null;
	public final stageSize = signal(0);
	public final editor:CodeEditor;
	// events for checks (--events <file>: JSON lines; in the browser the page's, window.studioWeb.events), measurements
	#if !(hxmc.target == "wasm32-wasi")
	final events:Null<sys.io.FileOutput>;
	#end
	final startedAt:Float;
	var openedAt = 0.0;
	var shownAll = false;
	var firstFrame = false;
	public var frames(default, null) = 0;
	// (the code view's own edits, not applied to it again; its save pending)
	var applyingToEditor = false;
	var saveGeneration = 0;
	// a patch being measured: when it was sent, the frame then, the screen's version then
	var measuring:Null<{t0:Float, frame:Int, screen:Screen, version:Int, label:String}> = null;
	// selection refreshes in flight
	var refreshing = false;
	var refreshAgain = false;
	// (an edit's gesture: its history group)
	public var gesture(default, null) = 0;

	public function new(dir:Null<String>, options:{?events:String, ?mcpPort:Int, ?holdWhile:String}) {
		current = this;
		startedAt = processStart;
		var p:Null<Project> = null;
		#if (hxmc.target == "wasm32-wasi")
		// (the page's project, opened before the module started)
		p = try Project.opened() catch (e:Dynamic) {
			Sys.println('studio: the project: $e');
			null;
		}
		#else
		events = options.events == null ? null : sys.io.File.write(options.events, false);
		if (dir != null) p = try Project.open(dir) catch (e:Dynamic) {
			Sys.println('studio: $dir: $e');
			null;
		}
		#end
		project = p;
		previews = p == null || p.live().length == 0 ? null : new Previews(p);
		designs = new Designs(this);
		layout = new Layout(this);
		tools = new Tools(this);
		drag = new Drag(this);
		tree = p == null ? null : new FileTree(p);
		agent = new Agent.LocalAgent(this);
		editor = new CodeEditor("", null);
		editor.view.fontFamily = Theme.CODE;
		editor.onChange = codeChanged;
		docs.onChange = changed;
		if (previews != null) {
			previews.onFrame = framed;
			var pr = previews;
			hold(() -> pr.allShown(), "the screens' first frames", 300);
		}
		#if !(hxmc.target == "wasm32-wasi")
		if (options.holdWhile != null) {
			var f = options.holdWhile;
			hold(() -> !sys.FileSystem.exists(f), 'while $f exists', 600);
		}
		if (p != null) mcp = new Mcp(this, options.mcpPort ?? 0);
		#end
	}

	// the project opened: the compiler, the screens' program built and started, the MCP server
	public function open() {
		openedAt = haxe.Timer.stamp();
		if (project != null) Async.launch(_ -> watch());
		// (a project of design files alone: its MCP server too, no program)
		if (mcp != null) {
			var m = mcp;
			Async.launch(task -> m.serve(task));
		}
		var pr = previews;
		if (pr != null) Async.launch(task -> pr.start(task));
		#if (hxmc.target == "wasm32-wasi")
		Async.launch(_ -> studio.web.WebTools.serve(this));
		#end
	}

	// (a headless run's script waits while the studio waits on its processes: Headless.hold)
	public static function hold(done:Void->Bool, why:String, seconds = 120.0) {
		#if helder.headless
		helder.headless.Headless.run.hold(done, why, seconds);
		#end
	}

	public function log(event:String, data:Dynamic) {
		Reflect.setField(data, "event", event);
		Reflect.setField(data, "frame", frames);
		#if (hxmc.target == "wasm32-wasi")
		var line = Json.stringify(data);
		hxmc.unsafe.Arena.scoped(a -> studio.web.StudioWeb.event(a.cstring(line)));
		#else
		if (events == null) return;
		events.writeString(Json.stringify(data) + "\n");
		events.flush();
		#end
	}

	// (each frame the studio draws: the first measured, the stage's size followed)
	public function drawn() {
		var stage = stageNode;
		frames++;
		if (!firstFrame) {
			firstFrame = true;
			var ms = Math.round((haxe.Timer.stamp() - startedAt) * 1000);
			Sys.println('studio: first frame $ms ms after start');
			log("first-frame", {ms: ms});
		}
		var w = Main.window == null ? 0.0 : Main.window.ui.width;
		if (w > 0 && (w < Theme.COMPACT) != compact.peek()) {
			compact(w < Theme.COMPACT);
			if (!compact.peek()) drawer(false);
		}
		if (stage != null && (stage.width != stageWidth || stage.height != stageHeight) && stage.width > 0) {
			stageWidth = stage.width;
			stageHeight = stage.height;
			stageSize(v -> v + 1);
			fitView(false);
		}
		showVisible();
		designs.follow(openedAt > 0 ? openedAt : startedAt);
	}

	// the previews told which screens are in view (the camera's; the others
	// suspended, their last frames kept) and which one is zoomed into (drawn
	// every frame): a preview host draws only those
	function showVisible() {
		var pr = previews;
		if (pr == null || stageWidth <= 0) return;
		var names = [];
		if (mode.peek() != "stories")
			for (r in layout.screens()) {
				var x0 = camera.sx(r.x), y0 = camera.sy(r.y), x1 = camera.sx(r.x + r.w), y1 = camera.sy(r.y + r.h);
				if (x1 > 0 && y1 > 0 && x0 < stageWidth && y0 < stageHeight) names.push(r.name);
			}
		// (the zoomed screen's pixels a point: the canvas' scale on the display, in halves, from 1 to 3; kept while the camera flies)
		if (!camera.flying) {
			var px = camera.k * (Main.window == null ? 1.0 : Main.window.renderer.scale);
			focusScale = Math.max(1, Math.min(3, Math.ceil(px * 2 - 0.05) / 2));
		}
		pr.show(names, mode.peek() == "stories" ? null : focused.peek(), focused.peek() == null ? 1 : focusScale);
	}

	var focusScale = 1.0;

	// ---- the canvas: focus and views

	// all screens, or one zoomed into (on the spring)
	public function focus(name:Null<String>) {
		focused(name);
		others([]);
		if (name == null) selection(null);
		fitTo(name, true);
		refreshCode();
	}

	// a page's screens (a design file's, a story flow's) fitted, none zoomed into
	public function showPage(page:String) {
		if (mode.peek() == "stories") setMode("design");
		focused(null);
		selection(null);
		var b = layout.bounds(page), i = insets();
		var v = Camera.fit(b.x, b.y, b.w, b.h, stageWidth, stageHeight, 28, i.right, i.bottom, i.top + Theme.TITLES, i.left);
		camera.fly(v.x, v.y, v.k);
		log("page", {page: page});
	}

	// the inspector's sheet opened or closed (compact), the zoomed screen fitted above it
	public function toggleSheet() {
		sheetOpen(!sheetOpen.peek());
		fitView(true);
	}

	// (the mode just set: a signal's write lands at the end of the event, and a fit after it in the same event needs it)
	var modeNow = "design";

	public function setMode(m:String) {
		modeNow = m;
		mode(m);
		fitView(true, m);
		if (m == "code") {
			refreshCode();
			editor.view.focus();
		}
	}

	// the view for what is in focus (fly: on the spring)
	public function fitView(fly:Bool, ?m:String)
		fitTo(focused.peek(), fly, m);

	function fitTo(name:Null<String>, fly:Bool, ?m:String) {
		if (stageWidth <= 0) return;
		var code = (m ?? modeNow) == "code";
		var small = compact.peek(), i = insets(m);
		var v = if (name == null) {
			var b = layout.bounds();
			Camera.fit(b.x, b.y, b.w, b.h, stageWidth, stageHeight, 28, i.right, i.bottom, i.top + Theme.TITLES, i.left);
		} else {
			var r = layout.rect(name);
			if (r == null) return;
			if (small) Camera.fit(r.x, r.y, r.w, r.h, stageWidth, stageHeight, 14, 0, code ? 0 : (sheetOpen.peek() ? Theme.SHEET : Theme.SHEET_PEEK) + 8, 18)
			else Camera.fit(r.x, r.y, r.w, r.h, stageWidth, stageHeight, 22, i.right, i.bottom, i.top + 14, i.left);
		}
		if (fly) camera.fly(v.x, v.y, v.k) else camera.jump(v.x, v.y, v.k);
	}

	// the stage's points the cards cover (the canvas is under them): the
	// sidebar and the code at the left, the inspector at the right, the
	// toolbar above, the prompt bar below; compact, none
	public function insets(?m:String):{left:Float, right:Float, top:Float, bottom:Float} {
		if (compact.peek()) return {left: 0, right: 0, top: 0, bottom: Theme.ASK_SPACE};
		var code = (m ?? modeNow) == "code", g = Theme.GAP;
		return {
			left: Theme.SIDEBAR + g + (code ? Shell.codeWidth(this) + g : 0),
			right: code ? 0 : Theme.INSPECTOR + g,
			top: Theme.HEADER,
			bottom: code ? 0 : Theme.ASK_SPACE
		};
	}

	// every frame fitted (shift-1)
	public function fitAll() {
		if (focused.peek() != null) focus(null) else fitTo(null, true);
	}

	// the selection fitted (shift-2): the frame in focus, else every frame
	public function fitSelection()
		fitTo(focused.peek(), true);

	// whether a screen shows the layers' panel when zoomed into (a design's frame)
	public function layers(name:Null<String>):Bool {
		var s = name == null ? null : project?.screen(name);
		return s != null && s.source.match(Design(_));
	}

	// a click on the stage at (px, py): a screen zoomed into, or a node of the zoomed one selected
	// (add: shift held, a design's node added to the selection or taken from it)
	public function clickStage(px:Float, py:Float, add = false) {
		var wx = camera.wx(px), wy = camera.wy(py);
		var hit = layout.at(wx, wy);
		if (hit == null) return;
		if (focused.peek() != hit.name) {
			focus(hit.name);
			return;
		}
		pick(hit.name, wx - hit.x, wy - hit.y, add);
	}

	// the node at (x, y) of a screen (its points) selected: the program's
	// tree's boxes, the node's source (a design's frame: its own nodes')
	public function pick(name:String, x:Float, y:Float, add = false) {
		var info = project?.screen(name);
		if (info != null && info.source.match(Design(_))) {
			var hit = designs.pick(name, x, y);
			if (hit != null) selectDesign(info, hit.node, hit.at, add) else if (!add) {
				selection(null);
				others([]);
			}
			return;
		}
		var s = previews?.screen(name);
		if (s == null) return;
		var answered = false;
		var asked = previews.request(s, "Ui.getTree", {}, r -> {
			answered = true;
			var root:Dynamic = Studio.rootOf(r);
			if (root == null) return;
			var n = hitNode(root, x, y);
			if (n == null) {
				selection(null);
				return;
			}
			select(s, n);
		});
		if (asked) hold(() -> answered, "the tree");
	}

	// the deepest node holding (x, y) that the project's markup made
	function hitNode(n:Dynamic, x:Float, y:Float):Null<Dynamic> {
		if (n == null || x < n.x || y < n.y || x >= n.x + n.width || y >= n.y + n.height || n.style?.display == "none") return null;
		var kids:Array<Dynamic> = n.children ?? [];
		var i = kids.length;
		while (--i >= 0) {
			var h = hitNode(kids[i], x, y);
			if (h != null) return h;
		}
		return n.source != null && ours(n.source.file) ? n : null;
	}

	// a file of the project (not helder's own)
	public function ours(file:String):Bool {
		if (project == null || file == null) return false;
		var f = project.real(file);
		return f.startsWith(project.dir + "/") && !f.substr(project.dir.length).contains("/bin/");
	}

	function select(s:Screen, n:Dynamic) {
		var file = project.real(n.source.file);
		var f = docs.get(file);
		var start = f.doc.fromByte(Std.int(n.source.offsets[0]));
		var el = f.doc.elementAt(start);
		var sel:Selection = {
			screen: s.info.name,
			file: file,
			start: start,
			tag: el?.name ?? n.tag ?? "node",
			nodeTag: n.tag,
			id: n.id,
			x: n.x,
			y: n.y,
			width: n.width,
			height: n.height,
			opacity: n.style?.opacity ?? 1,
		};
		selection(sel);
		gesture++;
		docs.close();
		log("selected", {screen: sel.screen, file: file, start: start, tag: sel.tag, rect: [sel.x, sel.y, sel.width, sel.height]});
		refreshCode();
	}

	// a node of a design's frame selected: its element at its markup's
	// offset (add: with what is selected, or taken from it when it is)
	public function selectDesign(info:ScreenInfo, n:Null<Node>, at:Int, add = false) {
		var cur = selection.peek(), more = [];
		if (add && cur != null && cur.screen == info.name) {
			var rest = [for (o in others.peek()) if (o.start != at) o];
			if (cur.start == at || rest.length < others.peek().length) {
				// (a selected one clicked again: no longer; the last of the rest the selection)
				if (cur.start != at) rest.push(cur);
				var last = rest.pop();
				others(rest);
				selection(last);
				log("selected", {screen: info.name, others: rest.length, tag: last?.tag, start: last?.start});
				refreshCode();
				return;
			}
			more = rest.concat([cur]);
		}
		others(more);
		var el = docs.get(info.file).doc.elementAt(at);
		// (a node not drawn yet: its box when its frame is, Designs.follow)
		var b = n == null ? {x: 0.0, y: 0.0, width: 0.0, height: 0.0} : designs.box(info.name, n);
		var sel:Selection = {
			screen: info.name,
			file: info.file,
			start: at,
			tag: el?.name ?? n?.tag ?? "node",
			nodeTag: n?.tag,
			id: 0,
			x: b.x,
			y: b.y,
			width: b.width,
			height: b.height,
			opacity: n == null ? 1 : n.style.opacity,
		};
		selection(sel);
		gesture++;
		docs.close();
		log("selected", {screen: sel.screen, file: sel.file, start: at, tag: sel.tag, rect: [sel.x, sel.y, sel.width, sel.height], others: more.length});
		refreshCode();
	}

	// the selection's box again from the program's tree (after a frame: a
	// layout moved it): the nodes its source makes now (Ui.nodesAt), their boxes
	function refreshSelection() {
		var sel = selection.peek();
		var s = sel == null ? null : previews?.screen(sel.screen);
		if (sel == null || s == null) return;
		if (refreshing) {
			refreshAgain = true;
			return;
		}
		refreshing = true;
		var f = docs.get(sel.file);
		var lc = f.doc.lineCol(sel.start);
		var line = lc.line, col = f.doc.toByte(sel.start) - f.doc.toByte(f.doc.lineStart(sel.start)) + 1;
		var file = sel.file;
		var done = false;
		function finish() {
			done = true;
			refreshing = false;
			if (refreshAgain) {
				refreshAgain = false;
				refreshSelection();
			}
		}
		var ok = previews.request(s, "Ui.getTree", {}, t -> {
			var root:Dynamic = Studio.rootOf(t);
			var asked = previews.request(s, "Ui.nodesAt", {file: realToBuilt(file), line: line, col: col}, r -> {
				var nodes:Array<Dynamic> = r.result?.nodes ?? [];
				var found = nodes.length == 0 ? null : findId(root, nodes[0].id);
				var cur = selection.peek();
				if (found != null && cur != null && cur.file == file) {
					var next:Selection = Reflect.copy(cur);
					next.id = found.id;
					next.x = found.x;
					next.y = found.y;
					next.width = found.width;
					next.height = found.height;
					next.opacity = found.style?.opacity ?? 1;
					selection(next);
					log("selection", {screen: next.screen, tag: found.tag, rect: [next.x, next.y, next.width, next.height], opacity: next.opacity, text: found.text,
						color: found.style?.color, background: found.style?.background});
				}
				finish();
			});
			if (!asked) finish();
		});
		if (!ok) finish() else hold(() -> done, "the selection's node");
	}

	// (a project's file as the build knows it: a linked story file's link)
	function realToBuilt(file:String):String {
		if (project != null) for (l => r in project.links) if (r == file) return l;
		return file;
	}

	// a Ui.getTree response's first window's root (null: none)
	public static function rootOf(r:Dynamic):Null<Dynamic> {
		var uis:Array<Dynamic> = r?.result?.uis;
		return uis == null || uis.length == 0 ? null : uis[0].root;
	}

	static function findId(n:Dynamic, id:Int):Null<Dynamic> {
		if (n == null) return null;
		if (n.id == id) return n;
		for (c in (n.children : Array<Dynamic>) ?? []) {
			var f = findId(c, id);
			if (f != null) return f;
		}
		return null;
	}

	// a screen's new frame: the first ones counted, a patch's measured, the selection followed
	function framed(s:Screen) {
		var ui = Main.window?.ui;
		if (ui != null) ui.requestFrame();
		if (!shownAll && previews.allShown()) {
			shownAll = true;
			var ms = Math.round((haxe.Timer.stamp() - openedAt) * 1000);
			var host = previews.sinceHost();
			Sys.println('studio: all ${previews.screens.length} screens shown $ms ms after opening ${project.name}' + (host >= 0 ? ', $host ms after the screens\' program started' : ''));
			log("all-shown", {ms: ms, screens: previews.screens.length, hostMs: host, sharing: previews.sharing});
			fitView(false);
		}
		var m = measuring;
		if (m != null && m.screen == s && s.version > m.version) {
			measuring = null;
			var ms = Math.round((haxe.Timer.stamp() - m.t0) * 10000) / 10;
			var color = selectionColor(s);
			Sys.println('studio: ${m.label} shown in $ms ms, ${frames - m.frame} studio frame(s)' + (s.patchedMs >= 0 ? ', the program\'s own ${s.patchedMs} ms' : ''));
			log("patch-shown", {ms: ms, frames: frames - m.frame, programMs: s.patchedMs, label: m.label, color: color, version: s.version});
		}
		if (focused.peek() == s.info.name && selection.peek() != null) refreshSelection();
	}

	// the strongest colour in the selection's box of the screen's last frame (a check's: what it shows)
	function selectionColor(s:Screen):Null<String> {
		var sel = selection.peek(), img = s.image.peek();
		// (a frame of the browser's preview host is a bitmap on the GPU: its pixels not here)
		if (sel == null || img == null || sel.screen != s.info.name || !img.hasPixels) return null;
		var px = img.pixels, best = -1.0, out:Null<String> = null;
		var x0 = Std.int(Math.max(0, sel.x)), y0 = Std.int(Math.max(0, sel.y));
		var x1 = Std.int(Math.min(img.width, sel.x + sel.width)), y1 = Std.int(Math.min(img.height, sel.y + sel.height));
		for (y in y0...y1)
			for (x in x0...x1) {
				var i = (y * img.width + x) * 4;
				var r = px.get(i), g = px.get(i + 1), b = px.get(i + 2);
				var sat = Math.max(r, Math.max(g, b)) - Math.min(r, Math.min(g, b));
				if (sat > best) {
					best = sat;
					out = "#" + StringTools.hex(r, 2).toLowerCase() + StringTools.hex(g, 2).toLowerCase() + StringTools.hex(b, 2).toLowerCase();
				}
			}
		return out;
	}

	// ---- edits

	// the selected element (null: none, or its source no longer reads as one)
	public function element():Null<helder.syntax.Document.Element> {
		var sel = selection();
		docs.version();
		if (sel == null) return null;
		return docs.get(sel.file).doc.elementAt(sel.start);
	}

	// an attribute of the selected element set (Studio.attribute's form)
	public function setAttribute(name:String, raw:String, ?group:String) {
		var sel = selection.peek();
		if (sel == null) return;
		var f = docs.get(sel.file), doc = f.doc;
		var el = doc.elementAt(sel.start);
		if (el == null) return;
		var tx = try attribute(doc, el, name, raw) catch (e:Dynamic) {
			message('$name: $e');
			return;
		}
		edit(sel.file, tx, '$name $raw', "inspector", group ?? 'attr:$name:$gesture');
	}

	// an element's attribute set (raw: as a field has it; its form kept: a
	// number in braces, a string in quotes; "" removes it), against the doc's text
	public static function attribute(doc:helder.syntax.Document, el:helder.syntax.Document.Element, name:String, raw:String):Transaction {
		if (raw.trim() == "") return Edits.removeAttribute(doc, el, name);
		var a = el.attr(name);
		var v = raw.trim();
		var numeric = ~/^-?[0-9]+(\.[0-9]+)?$/.match(v);
		var braced = a != null && a.value != null && doc.text.charAt(a.value.start) == "{";
		var lit = a == null ? null : a.literal();
		return if (a != null && a.value != null && a.value.kind == Str && !numeric && !v.contains('"') && !v.contains("\\"))
			// (a string's value: its text alone, its quotes kept)
			new Transaction([new Change(a.value.start + 1, a.value.end - 1, v)], null, doc.text)
		else if (lit != null && numeric && lit.kind == Num)
			// (a number in braces: the number alone)
			new Transaction([new Change(lit.start, lit.end, v)], null, doc.text)
		else Edits.setAttribute(doc, el, name, numeric && (a == null || braced) ? ACode(v) : AString(v));
	}

	// the selected element's text (its one run of text) set
	public function setText(text:String, ?group:String) {
		var sel = selection.peek();
		if (sel == null) return;
		var f = docs.get(sel.file), doc = f.doc;
		var el = doc.elementAt(sel.start);
		if (el == null) return;
		var run = textRun(el);
		if (run == null || text.trim() == "" || text.contains("<") || text.contains("{")) return;
		edit(sel.file, new Transaction([new helder.syntax.Transaction.Change(run.start, run.end, text)], null, doc.text), 'text $text', "inspector", group ?? 'text:$gesture');
	}

	// an element's one run of text (null: none, or more than text in it)
	public static function textRun(el:helder.syntax.Document.Element):Null<{start:Int, end:Int, text:String}> {
		var kids = el.content();
		if (kids.length != 1) return null;
		var k = kids[0];
		var t = el.doc.text.substring(k.start, k.end);
		if (t.trim() == "" || t.contains("{") || t.contains("<")) return null;
		var lead = t.length - t.ltrim().length, trail = t.length - t.rtrim().length;
		return {start: k.start + lead, end: k.end - trail, text: t.trim()};
	}

	// an edit of a file by the studio (origin: inspector, agent, canvas), recorded
	public function edit(file:String, tx:Transaction, label:String, origin:String, ?group:String)
		docs.apply(file, tx, label, origin, group);

	// the next edit its own history entry (a field left, a scrub ended)
	public function endGesture() {
		gesture++;
		docs.close();
	}

	public function undo() {
		var l = docs.undo();
		message(l == null ? "nothing to undo" : 'undid $l');
		gesture++;
	}

	public function redo() {
		var l = docs.redo();
		message(l == null ? "nothing to redo" : 'redid $l');
		gesture++;
	}

	// a file's text changed (Docs): the selection moved with it, the code view
	// told, then the program: a live literal patched, else a build
	function changed(file:String, tx:Transaction, origin:String) {
		var sel = selection.peek();
		if (sel != null && sel.file == file) {
			var next:Selection = Reflect.copy(sel);
			next.start = tx.map(sel.start, 1);
			selection(next);
		}
		if (others.peek().length > 0 && others.peek()[0].file == file) others([for (o in others.peek()) {var n:Selection = Reflect.copy(o); n.start = tx.map(o.start, 1); n;}]);
		if (file.endsWith(".helder") && project != null) framesChanged(file, project.design(file, docs.get(file).text));
		if (origin != "code" && codeFile.peek() == file) {
			applyingToEditor = true;
			var changes = [for (c in tx.changes) new helder.syntax.Transaction.Change(c.start, c.end, c.text)];
			editor.model.apply(changes, null, helder.ui.code.CodeModel.EDIT, false);
			editor.view.changed();
			applyingToEditor = false;
			decorate();
		}
		log("edited", {file: file, origin: origin, changes: [for (c in tx.changes) {start: c.start, end: c.end, text: c.text}]});
		if (origin == "code") saveLater(file) else commit(file);
	}

	// a design file's frames read again (null: as they were): what was
	// focused or selected in a renamed one follows it, a frame gone is left
	function framesChanged(file:String, renamed:Null<Array<{from:String, to:String}>>) {
		if (renamed == null) return;
		var f = focused.peek(), sel = selection.peek();
		for (r in renamed) {
			if (f == r.from) focused(f = r.to);
			if (sel != null && sel.screen == r.from) {
				var next:Selection = Reflect.copy(sel);
				next.screen = r.to;
				selection(sel = next);
			}
		}
		if (renamed.length > 0) others([]);
		if (f != null && project.screen(f) == null) focus(null);
		log("frames", {file: file, frames: [for (s in project.screens) if (s.file == file) s.name], renamed: renamed});
	}

	// (natively) the design files on disk watched, a second apart: one changed
	// there (another editor's save, git) read into the studio as an edit of
	// the file's (in the history, undone like any other), one added or
	// deleted its frames shown or gone
	@:coroutine function watch() {
		#if !(hxmc.target == "wasm32-wasi")
		var stamps = new Map<String, Float>();
		function stamp(f:String):Float
			return try sys.FileSystem.stat(f).mtime.getTime() catch (_:Dynamic) -1;
		for (f in project.designFiles())
			stamps.set(f, stamp(f));
		while (true) {
			Async.delay(1);
			tree?.scan();
			var now = [for (f in Project.found(project.dir)) if (f.endsWith(".helder")) f];
			for (f in now) {
				var t = stamp(f);
				if (stamps.get(f) == t) continue;
				var known = stamps.exists(f);
				stamps.set(f, t);
				var text = try Files.read(f) catch (_:Dynamic) continue;
				if (!known) {
					framesChanged(f, project.design(f, text));
					continue;
				}
				var d = docs.get(f);
				if (d.text != text) docs.apply(f, new Transaction([difference(d.text, text)], null, d.text), "the file changed on disk", "disk");
			}
			for (f in [for (k in stamps.keys()) k])
				if (!now.contains(f)) {
					stamps.remove(f);
					framesChanged(f, project.design(f, null));
				}
		}
		#end
	}

	// (the one range where a and b differ, as a change of a: what is the same before and after it kept)
	static function difference(a:String, b:String):Change {
		var s = 0, ea = a.length, eb = b.length;
		while (s < ea && s < eb && StringTools.fastCodeAt(a, s) == StringTools.fastCodeAt(b, s))
			s++;
		while (ea > s && eb > s && StringTools.fastCodeAt(a, ea - 1) == StringTools.fastCodeAt(b, eb - 1)) {
			ea--;
			eb--;
		}
		return new Change(s, ea, b.substring(s, eb));
	}

	// the program told of a file's text: its live literals patched now (the
	// next frame shows them), then the file saved; else saved and built
	public function commit(file:String) {
		var pr = previews;
		var f = docs.get(file);
		// (a design file: its frames drawn again from the text, nothing built)
		if (file.endsWith(".helder")) {
			f.save();
			message("drawn again, nothing built");
			log("redrawn", {file: file});
			return;
		}
		if (pr == null) {
			f.save();
			return;
		}
		var why = null;
		var patches = pr.literalPatches(file, f.text, w -> why = w);
		if (patches != null && patches.length > 0 && pr.patch(patches)) {
			startMeasure('${patches.length} literal(s) patched');
			pr.write(file, f.text);
			pr.took(patches);
			message('patched ${patches.length} live literal(s), nothing built');
			log("patched", {file: file, patches: patches});
			return;
		}
		pr.write(file, f.text);
		if (patches != null && patches.length == 0) return;
		message('building: ${why ?? "not a live literal"}');
		log("building", {file: file, why: why});
		rebuild(file);
	}

	function rebuild(file:String) {
		var pr = previews;
		var done = false;
		Async.launch(task -> {
			var ok = pr.rebuild(task, [file]);
			done = true;
			message(ok ? 'rebuilt in ${pr.buildMs.peek()} ms' : "the build failed: the last good build keeps running");
			log("built", {ok: ok, ms: pr.buildMs.peek(), diagnostics: pr.diagnostics.peek().length});
			if (codeFile.peek() != null) editor.setDiagnostics(pr.diagnostics.peek(), codeFile.peek());
		});
		hold(() -> done && !pr.busy(), "a build and the screens' reload");
	}

	// (a patch's frame to come, measured)
	function startMeasure(label:String) {
		var name = focused.peek() ?? selection.peek()?.screen;
		var s = name == null ? previews.screens[0] : previews.screen(name);
		if (s == null) return;
		var v = s.version;
		measuring = {t0: haxe.Timer.stamp(), frame: frames, screen: s, version: v, label: label};
		hold(() -> s.version > v, "a patch's frame", 10);
	}

	// ---- the code view

	// the code view on the selection's file (else the focused screen's story, else the first source), its element revealed and marked
	public function refreshCode() {
		var sel = selection.peek();
		var file = sel?.file;
		if (file == null && project != null) {
			var name = focused.peek();
			var s = name == null ? null : Lambda.find(project.screens, x -> x.name == name);
			file = s?.file;
			if (file == null || file == "") file = codeFile.peek() ?? project.sources()[0];
		}
		if (file == null) return;
		load(file);
		decorate();
	}

	// a file in the code view (the command field's, the sidebar's), nothing selected
	public function openCode(file:String) {
		selection(null);
		others([]);
		focused(null);
		shown(file);
		load(file);
		setMode("code");
	}

	// a file of the tree opened in its view: a design or story file's page
	// on the canvas, code in the code view, an image or a font in its
	// viewer (FileView), anything else as text when it reads as text
	public function openFile(e:FileTree.FileEntry) {
		drawer(false);
		switch e.kind {
			case Dir:
				tree.toggle(e);
			case Design | Story:
				var frames = tree.frames(e.path);
				shown(e.path);
				if (mode.peek() != "design") setMode("design");
				if (frames.length > 0) showPage(frames[0].flow) else openCode(e.path);
			case Image | Font | Model | Audio | Other:
				selection(null);
				focused(null);
				shown(e.path);
				setMode("file");
			case Code:
				openCode(e.path);
		}
		log("opened", {file: tree.relative(e.path), kind: (e.kind : String)});
	}

	// an image dragged from the tree onto a design's frame at the stage's
	// (px, py): an <image src> of its path from the design file, its size
	// the image's (fitted into the frame's width), the frame's last child
	public function dropImage(path:String, px:Float, py:Float) {
		var hit = layout.at(camera.wx(px), camera.wy(py));
		var info = hit == null ? null : project.screen(hit.name);
		if (info == null || !info.source.match(Design(_)) || info.start == null) {
			message("an image goes on a design's frame");
			return;
		}
		var doc = docs.get(info.file).doc, frame = doc.elementAt(info.start);
		if (frame == null) return;
		var src = FileTree.relativeTo(haxe.io.Path.directory(info.file), path);
		var size = try designs.imageSize(path) catch (_:Dynamic) {w: 120.0, h: 120.0};
		var w = Math.min(size.w, Math.max(40, (info.width > 0 ? info.width : 390) - 48));
		var h = Math.round(size.h * w / Math.max(1, size.w));
		var markup = '<image src="$src" width={${Math.round(w)}} height={$h}/>';
		var tx = try helder.syntax.Edits.insertChild(doc, frame, frame.children().length, markup) catch (e:Dynamic) {
			message('the image: $e');
			return;
		}
		edit(info.file, tx, "image inserted", "canvas");
		endGesture();
		log("image-inserted", {screen: info.name, src: src});
	}

	// files dropped from the system on the window at (x, y): copied into the
	// folder of the tree's row there (a file's row: its folder), else the project's
	public function dropFiles(files:Array<String>, x:Float, y:Float) {
		if (project == null || tree == null) return;
		var dir = project.dir, ui = Main.window?.ui;
		var n = ui == null ? null : ui.root.hitTest(x, y);
		while (n != null) {
			var p = tree.rowPath(n.tag);
			if (p != null) {
				dir = Files.isDirectory(p) ? p : haxe.io.Path.directory(p);
				break;
			}
			n = n.parent;
		}
		var copied = [];
		#if !(hxmc.target == "wasm32-wasi")
		for (f in files) {
			if (sys.FileSystem.isDirectory(f)) continue;
			var to = dir + "/" + haxe.io.Path.withoutDirectory(f);
			try {
				sys.io.File.copy(f, to);
				copied.push(tree.relative(to));
			} catch (e:Dynamic) message('$f: $e');
		}
		#end
		tree.scan();
		log("dropped", {files: copied});
	}


	function load(file:String) {
		if (codeFile.peek() != file) {
			codeFile(file);
			applyingToEditor = true;
			editor.path = file;
			editor.text = docs.get(file).text;
			applyingToEditor = false;
			if (previews != null) editor.setDiagnostics(previews.diagnostics.peek(), file);
		}
	}

	// the selected element marked and revealed, the caret after its tag's name
	function decorate() {
		editor.clearDecorations();
		var sel = selection.peek();
		if (sel == null || sel.file != codeFile.peek()) return;
		var doc = docs.get(sel.file).doc;
		var el = doc.elementAt(sel.start);
		if (el == null) return;
		editor.addDecoration(el.start, el.end, Theme.c("sel-soft"), Theme.c("sel"));
		editor.revealRange(el.start, el.end);
		var name = el.open.first(helder.syntax.Cst.Kind.TagName);
		var at = name == null ? el.start + 1 : name.end;
		editor.setSelection(at, at);
	}

	function codeChanged(changes:Array<helder.syntax.Transaction.Change>) {
		if (applyingToEditor) return;
		var file = codeFile.peek();
		if (file == null) return;
		var before = docs.get(file).text;
		var tx = new Transaction(changes, null, before);
		docs.apply(file, tx, "typing", "code", 'code:$gesture');
	}

	// (typing: saved and told after a pause)
	function saveLater(file:String) {
		var g = ++saveGeneration;
		var saved = false;
		Async.launch(_ -> {
			Async.delay(0.4);
			if (g != saveGeneration) {
				saved = true;
				return;
			}
			gesture++;
			docs.close();
			commitCode(file);
			saved = true;
		});
		hold(() -> saved, "the code's save");
	}

	function commitCode(file:String) {
		var pr = previews;
		var f = docs.get(file);
		if (pr == null || file.endsWith(".helder")) {
			f.save();
			return;
		}
		pr.write(file, f.text);
		var done = false;
		Async.launch(task -> {
			var r = pr.saved(task, file);
			done = true;
			message(switch r {
				case "patched": "patched live literals, nothing built";
				case "built": 'rebuilt in ${pr.buildMs.peek()} ms';
				case "failed": "the build failed: the last good build keeps running";
				case _: r;
			});
			log(r == "patched" ? "patched" : "built", {file: file, result: r, ms: pr.buildMs.peek()});
			editor.setDiagnostics(pr.diagnostics.peek(), file);
		});
		hold(() -> done && !pr.busy(), "a save's build or patch");
	}

	// ---- the prompt bar

	// what the prompt is about: the whole app, or the screen in focus
	// (label: the prompt's placeholder; scope: its chip, the screen and the node selected)
	public function context():{label:String, scope:String, screen:Null<String>, selection:Null<Selection>} {
		var name = focused();
		var s = name == null || project == null ? null : Lambda.find(project.screens, x -> x.name == name);
		var sel = selection();
		var scope = s == null ? "Whole app" : sel != null && sel.screen == name ? '${s.label} · ${sel.tag}' : s.label;
		return {label: s == null ? "Ask about the whole app…" : 'Ask about ${s.label}…', scope: scope, screen: name, selection: sel};
	}

	public function ask(prompt:String) {
		if (prompt.trim() == "") return;
		reply("…");
		var answered = false;
		agent.ask(prompt, {screen: focused.peek(), selection: selection.peek()}, r -> {
			reply(r);
			answered = true;
			log("replied", {prompt: prompt, reply: r});
		});
		hold(() -> answered, "the agent's reply", 30);
	}

	@:coroutine public function stop() {
		if (previews != null) previews.stop();
		#if !(hxmc.target == "wasm32-wasi")
		if (events != null) events.close();
		#end
	}
}

typedef Selection = {
	screen:String,
	// the element's file and its start (an offset of the file's text now)
	file:String,
	start:Int,
	// its element's name, the node's tag
	tag:String,
	nodeTag:Null<String>,
	// the node in the screen's tree, its box (the screen's points) and opacity
	id:Int,
	x:Float,
	y:Float,
	width:Float,
	height:Float,
	opacity:Float,
}

// Where each screen is in the canvas' world: a flow a row, the rows one under another
class Layout {
	final studio:Studio;

	public function new(studio)
		this.studio = studio;

	// (a design's frame at its canvas:at in its flow's row, else after the one before)
	public function screens():Array<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}> {
		var out:Array<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}> = [];
		var p = studio.project, pr = studio.previews;
		if (p == null) return out;
		var y = 0.0;
		for (f in p.flows()) {
			var x = 0.0, tall = 0.0;
			for (i in f.screens) {
				var s = pr?.screen(i.name);
				if (s == null && !i.source.match(Design(_))) continue;
				var w = s == null ? i.width : s.width(), h = s == null ? i.height : s.height();
				var at = i.at ?? {x: x, y: 0.0};
				out.push({name: i.name, flow: f.name, x: at.x, y: y + at.y, w: w + 0.0, h: h + 0.0});
				x = Math.max(x, at.x + w + Theme.SCREEN_GAP);
				tall = Math.max(tall, at.y + h);
			}
			y += tall + Theme.FLOW_GAP;
		}
		return out;
	}

	public function rect(name:String):Null<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}>
		return Lambda.find(screens(), s -> s.name == name);

	public function at(wx:Float, wy:Float):Null<{name:String, flow:String, x:Float, y:Float, w:Float, h:Float}>
		return Lambda.find(screens(), s -> wx >= s.x && wy >= s.y && wx < s.x + s.w && wy < s.y + s.h);

	// (page: its screens' alone)
	public function bounds(?page:String):{x:Float, y:Float, w:Float, h:Float} {
		var l = [for (s in screens()) if (page == null || s.flow == page) s];
		if (l.length == 0) return {x: 0, y: 0, w: 480, h: 560};
		var x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
		for (s in l) {
			x0 = Math.min(x0, s.x);
			y0 = Math.min(y0, s.y);
			x1 = Math.max(x1, s.x + s.w);
			y1 = Math.max(y1, s.y + s.h);
		}
		return {x: x0, y: y0, w: x1 - x0, h: y1 - y0};
	}
}
