import haxe.io.Bytes;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The headless-run lane's checks (bun run test headless-run; tests/Run.hx
// ran `helder run --headless` twice into <dir>/1 and <dir>/2 first): the
// todo examples' trees (Haxe's and TypeScript's, the same script: items
// added by Enter and by the Add button, one toggled by its role and
// label, a filter), their frames and the glow scene's against the goldens
// here (Linux: llvmpipe, DejaVu Sans; within a tolerance),
// the viewer's file dialog and context menu answered by its script, a
// VirtualList of a million rows (examples/million and ts-million: scrolled,
// jumped, the keyboard, the selection, rows put in above the view), the
// trace's lines, the frames written, examples/motion's traces checked for
// continuity (motion: no jump past what a spring allows, the edges that
// stay put still, reduced motion's snaps) and its frame strips against
// their goldens, and each output of the second run byte for byte the
// first's.
//   Check <dir> [--bless]
typedef Frame = {t:Float, nodes:Map<Int, Array<Float>>, opacity:Map<Int, Float>, tags:Map<Int, String>, paths:Map<Int, String>};

class Check {
	static var failed = 0;
	static var checks = 0;
	static final here = "tests/headless";

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('headless-run: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		var dir = args[0], bless = args[1] == "--bless";
		var one = '$dir/1', two = '$dir/2';
		for (app in ["todo", "ts-todo"]) {
			var toggled = tree('$one/$app-toggled.json'), end = tree('$one/$app-end.json');
			todoToggled(app, toggled);
			todoEnd(app, end);
			sources(app, app == "todo" ? "examples/todo/Todo.hx" : "examples/ts-todo/app.tsx", end);
			traceLines(app, '$one/$app.jsonl');
			image('$app-toggled.png', '$one/$app-toggled.png', bless);
			literals(app, '$one/$app-literal-before.png', '$one/$app-literal-after.png', tree('$one/$app-literal.json'));
		}
		image("glow.png", '$one/glow.png', bless);
		for (app in ["million", "ts-million"])
			million(app, one, bless);
		motion(one, bless);
		codeEditor(dir, one, bless);
		viewer(tree('$one/viewer-menu.json'), tree('$one/viewer-end.json'));
		var frames = [for (f in FileSystem.readDirectory('$one/frames')) f];
		frames.sort(Reflect.compare);
		check("--frames 6 --every 2: frames 0, 2 and 4", frames.join(",") == "frame_0000.png,frame_0002.png,frame_0004.png", frames.join(","));
		// (the same script, the same bytes)
		var same = 0;
		for (f in files(one)) {
			var a = File.getBytes('$one/$f'), b = FileSystem.exists('$two/$f') ? File.getBytes('$two/$f') : null;
			check('$f byte for byte the same in both runs', b != null && a.compare(b) == 0);
			same++;
		}
		check("both runs' outputs compared", same >= 12, '$same');
		Sys.println('headless-run: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	// examples/million and ts-million (a VirtualList of a million messages,
	// tests/headless/million.json): few rows made, each its place among a
	// million to assistive technology; the wheel down and back, End to the
	// last row (focused, its end at the view's), Top and the keyboard (the
	// selection following the focus), the selection kept through its row's
	// recycling, three rows put in above the view (no row moved); the last
	// frame against the golden
	static function million(app:String, one:String, bless:Bool) {
		function options(nodes:Array<Dynamic>):Array<Dynamic>
			return [for (n in nodes) if (n.role == "option") n];
		function idOf(o:Dynamic):Int {
			var r = ~/#([0-9,]+)/;
			return o.label != null && r.match(o.label) ? Std.parseInt(r.matched(1).split(",").join("")) : -1;
		}
		function status(nodes:Array<Dynamic>):String
			return byTag(nodes, "status-text")?.text ?? "";
		// (the list's view: its top and bottom, in points)
		var start = tree('$one/$app-start.json');
		var box = [for (n in start) if (n.role == "listbox") n][0];
		var top:Float = box.rect[1], bottom:Float = box.rect[1] + box.rect[3];
		var o = options(start);
		check('$app: a listbox named Messages', box.label == "Messages");
		check('$app: few rows of a million made', o.length > 5 && o.length < 30, '${o.length}');
		check('$app: the first row first of a million', o[0].posinset == 1 && o[0].setsize == 1000000 && o[0].rect[1] == top, '${o[0].posinset}/${o[0].setsize}');
		check('$app: the rows in order', [for (k in 1...o.length) o[k].posinset == o[k - 1].posinset + 1 && o[k].rect[1] == o[k - 1].rect[1] + o[k - 1].rect[3]].indexOf(false) < 0);
		check('$app: rows of their own heights', [for (x in o) x.rect[3]].filter(h -> h != o[1].rect[3]).length > 2);
		var down = options(tree('$one/$app-down.json'));
		check('$app: the wheel down: rows further made', down[0].posinset > 20 && down.length < 30, '${down[0].posinset}');
		var up = options(tree('$one/$app-up.json'));
		check('$app: the wheel back up: the first row at the top again', up[0].posinset == 1 && up[0].rect[1] == top);
		var end = tree('$one/$app-end.json'), eo = options(end), last = eo[eo.length - 1];
		check('$app: End: the last row made and focused, its end at the view\'s', last.posinset == 1000000 && last.focus == true
			&& last.rect[1] + last.rect[3] == bottom && idOf(last) == 999999, '${last.posinset} ${last.rect[1] + last.rect[3]} $bottom');
		check('$app: End: few rows made', eo.length < 30, '${eo.length}');
		var keys = tree('$one/$app-keys.json'), ko = options(keys);
		var f = [for (x in ko) if (x.focus == true) x][0];
		check('$app: Top, Down five times, Page Down, Up: the focus on a row, selected, in view', f != null && f.selected == true && f.posinset > 6
			&& f.rect[1] >= top && f.rect[1] + f.rect[3] <= bottom && [for (x in ko) if (x.selected == true) x].length == 1);
		var chosen = f == null ? -2 : idOf(f);
		check('$app: the status shows the row selected', status(keys).indexOf('#$chosen selected') >= 0, status(keys));
		var keptTree = tree('$one/$app-kept.json'), kept = options(keptTree);
		var again = [for (x in kept) if (idOf(x) == chosen) x][0];
		var shaded = [for (n in keptTree) if (n.fill == "#dbeafe") n];
		check('$app: the selection kept through End and back', again != null && again.selected == true && shaded.length == 1
			&& shaded[0].rect[1] == again.rect[1] && [for (x in kept) if (x.selected == true) x].length == 1);
		var before = options(tree('$one/$app-before.json')), after = tree('$one/$app-inserted.json'), ao = options(after);
		var moved = 0, same = 0;
		for (b in before) {
			var a = [for (x in ao) if (idOf(x) == idOf(b) && idOf(b) >= 0) x][0];
			if (a == null) continue;
			same++;
			if (a.rect[1] != b.rect[1] || a.rect[3] != b.rect[3]) moved++;
		}
		check('$app: rows put in above the view: none of those in it moved', same >= 8 && moved == 0, '$same compared, $moved moved');
		check('$app: three rows put in', ao[0].setsize == 1000003 && status(after).indexOf("1,000,003 rows") == 0, status(after));
		check('$app: the rows put in above the first in view', [for (x in ao) if (x.rect[1] + x.rect[3] <= top && idOf(x) >= 1000000) x].length == 3);
		image("million.png", '$one/$app-last.png', bless && app == "million");
	}

	// examples/code-editor on a 2,000-line TSX file (tests/headless/code-editor.json):
	// a word double-clicked and typed over, a line typed at the top, go to
	// line, three cursors by secondary-D and a word typed at each, undone and
	// redone, find and replace all, a drag's selection; its text (the
	// editor's value in the tree) and status bar at each mark, its last
	// frame against the golden
	static function codeEditor(dir:String, one:String, bless:Bool) {
		var file = File.getContent('$dir/code.tsx');
		var lines = file.split("\n").length;
		check("code-editor: its file has 2,000 lines", lines >= 2000, '$lines');
		inline function count(s:String, w:String):Int
			return s.split(w).length - 1;
		function view(nodes:Array<Dynamic>):Dynamic
			return byTag(nodes, "code-view");
		function status(nodes:Array<Dynamic>):String
			return byTag(nodes, "status")?.text ?? "";
		var multi = tree('$one/code-multi.json');
		check("code-editor: three selections by secondary-D", status(multi).indexOf("(3 selections)") >= 0, status(multi));
		var v = view(multi);
		check("code-editor: a text area with the text as its value", v != null && v.role == "textbox" && v.value != null && v.focus == true);
		var mv:String = v.value;
		check("code-editor: the word double-clicked typed over", mv.indexOf("import { state, memo, For, Show, Read }") >= 0);
		check("code-editor: a line typed at the top", StringTools.startsWith(mv, "// edited headless\n"));
		var shows = count(file.toLowerCase(), "show"), todos = count(file, "todos");
		var undone:String = view(tree('$one/code-undone.json')).value;
		check("code-editor: the word typed at three cursors undone", count(undone, "entries") == 0 && count(undone, "todos") == todos, '${count(undone, "entries")}, ${count(undone, "todos")} of $todos');
		var find = tree('$one/code-find.json');
		check("code-editor: the find panel open", byTag(find, "code-find") != null);
		var c = byTag(find, "find-count")?.text ?? "";
		check("code-editor: find's count", StringTools.endsWith(c, ' of $shows'), c);
		var end = tree('$one/code-end.json');
		var ev:String = view(end).value;
		check("code-editor: redone: the word at three cursors", count(ev, "entries") == 3 && count(ev, "todos") == todos - 3, '${count(ev, "entries")}');
		check("code-editor: every match replaced", count(ev.toLowerCase(), "show") == 0 && count(ev, "display") == shows, '${count(ev, "display")} of $shows');
		check("code-editor: typed at the end", StringTools.endsWith(ev, "// end"));
		check("code-editor: the panel closed, the text focused", byTag(end, "code-find") == null && view(end).focus == true);
		check("code-editor: the drag's selection in the status bar", status(end) == "Ln 5, Col 16 (161 selected)", status(end));
		image("code-editor.png", '$one/code-end.png', bless);
	}

	static function files(d:String, prefix = ""):Array<String> {
		var out = [];
		for (f in FileSystem.readDirectory(d))
			if (FileSystem.isDirectory('$d/$f')) out = out.concat(files('$d/$f', '$prefix$f/')) else out.push('$prefix$f');
		out.sort(Reflect.compare);
		return out;
	}

	static function tree(path:String):Array<Dynamic> {
		var t:Dynamic = haxe.Json.parse(File.getContent(path));
		return t.nodes;
	}

	static function texts(nodes:Array<Dynamic>):Array<String>
		return [for (n in nodes) if (n.text != null && n.text != "") n.text];

	static function byTag(nodes:Array<Dynamic>, tag:String):Null<Dynamic> {
		for (n in nodes)
			if (n.tag == tag) return n;
		return null;
	}

	// three items, Buy milk's box checked by its role and label
	static function todoToggled(app:String, nodes:Array<Dynamic>) {
		var t = texts(nodes);
		for (s in ["Buy milk", "Write the docs", "Ship it", "2 items left"])
			check('$app at mark:toggled: $s shown', t.contains(s), t.join("|"));
		var boxes = [for (n in nodes) if (n.role == "checkbox") n];
		check('$app at mark:toggled: three checkboxes', boxes.length == 3, '${boxes.length}');
		if (boxes.length == 3) {
			check('$app: Buy milk checked', boxes[0].label == "Buy milk" && boxes[0].checked == true, haxe.Json.stringify(boxes[0]));
			check('$app: the others not', boxes[1].checked == false && boxes[2].checked == false);
		}
		var draft = byTag(nodes, "draft");
		check('$app: the field emptied by Enter', draft != null && draft.value == "" && draft.role == "textbox");
	}

	// the active filter: the done item hidden, the filter's button the chosen one
	static function todoEnd(app:String, nodes:Array<Dynamic>) {
		var t = texts(nodes);
		check('$app at the end: Buy milk filtered out', !t.contains("Buy milk"), t.join("|"));
		for (s in ["Write the docs", "Ship it", "2 items left"])
			check('$app at the end: $s shown', t.contains(s), t.join("|"));
		var active = byTag(nodes, "filter-active"), all = byTag(nodes, "filter-all");
		check('$app: the chosen filter filled, the others white', active != null && all != null && active.fill != "#ffffff" && all.fill == "#ffffff",
			'${active?.fill} ${all?.fill}');
		check('$app: the pressed filter focused', active != null && active.focus == true && active.press == false);
		var list = byTag(nodes, "list");
		check('$app: the list where it is laid out', list != null && list.rect[0] == 24 && list.rect[2] == 432, haxe.Json.stringify(list?.rect));
		for (n in nodes)
			if (n.moving == true) check('$app: nothing moving at the end', false, n.path);
	}

	// the source map (helder.view.Source): an element's tag where it is
	// written, a component's call and its function's definition, the
	// innermost component mounting a node (Checkbox's rows, Button's)
	static function sources(app:String, file:String, nodes:Array<Dynamic>) {
		var lines = File.getContent(file).split("\n");
		function lineOf(text:String):Int {
			for (i in 0...lines.length)
				if (lines[i].indexOf(text) >= 0) return i + 1;
			return -1;
		}
		function at(s:Dynamic, line:Int):Bool
			return s != null && (s.file : String).endsWith("/" + file) && s.line == line && s.end.line >= s.line && s.offsets[1] > s.offsets[0];
		var draft = byTag(nodes, "draft");
		check('$app: the field\'s source, its tag\'s line', draft != null && at(draft.source, lineOf('tag="draft"')), haxe.Json.stringify(draft?.source));
		var col = lines[lineOf('tag="draft"') - 1].indexOf("<field") + 1;
		check('$app: the field\'s source, its tag\'s column', draft != null && draft.source.col == col, '${draft?.source?.col}, not $col');
		var add = byTag(nodes, "add");
		var c:Dynamic = add?.component;
		check('$app: Add made by Button, called where its tag is, defined where its function is', c != null && c.name == "Button" && at(c.call, lineOf('<Button tag="add"'))
			&& at(c.definition, lineOf("function Button")), haxe.Json.stringify(c));
		var boxes = [for (n in nodes) if (n.role == "checkbox") n];
		check('$app: each checkbox in a Checkbox of its row', boxes.length == 2
			&& Lambda.foreach(boxes, b -> b.component?.name == "Checkbox" && at(b.component.definition, lineOf("function Checkbox"))), haxe.Json.stringify(boxes[0]?.component));
	}

	// the viewer: a file opened through the file dialog (the script's
	// answer), its context menu open at the mark, an item picked from it
	static function viewer(menu:Array<Dynamic>, end:Array<Dynamic>) {
		var items = [for (n in menu) if (n.tag == "menu-item") n.label];
		check("viewer: the context menu open, its items", items.length == 5 && items.contains("Fit") && items.contains("Actual Size"), items.join("|"));
		var photo = byTag(menu, "photo");
		check("viewer: the file dialog's answer opened", photo != null && photo.label != null && (photo.label : String).startsWith("alpha.png"), photo?.label);
		check("viewer: the menu closed by the item picked", byTag(end, "menu") == null);
		var t = texts(end);
		check("viewer: the status at actual size", Lambda.exists(t, s -> s.startsWith("100% · 13×11 · PNG")), t.join("|"));
	}

	// a JSON line a frame, the tagged nodes; the count's text moving when it changed
	static function traceLines(app:String, path:String) {
		var lines = File.getContent(path).trim().split("\n");
		check('$app trace: a line a frame through the end mark (2.2 s at 60)', lines.length == 133, '${lines.length}');
		var moved = false, ok = true;
		for (l in lines) {
			var o:Dynamic = try haxe.Json.parse(l) catch (e:Dynamic) null;
			if (o == null) {
				ok = false;
				continue;
			}
			for (n in (o.nodes : Array<Dynamic>)) {
				if (n.tag == "view" || n.tag == "text") ok = false;
				if (n.tag == "left" && n.moving == true) moved = true;
			}
		}
		check('$app trace: JSON lines of tagged nodes', ok);
		check('$app trace: the count\'s text moving as it changed', moved);
	}

	// live literals (a dev build, tests/headless/literals.json): the title's
	// colour patched from #3b82f6 to #ef4444 and its text from todos to
	// dones; the frame before the patch blue, the frame of the patch red
	static function literals(app:String, before:String, after:String, nodes:Array<Dynamic>) {
		function count(path:String, rgb:Int):Int {
			var img = helder.image.PngDecoder.decode(File.getBytes(path)), n = 0;
			for (p in 0...img.width * img.height) {
				var d = 0;
				for (k in 0...3) {
					var v = img.rgba.get(4 * p + k) - ((rgb >> (16 - 8 * k)) & 0xFF);
					if (v < 0) v = -v;
					if (v > d) d = v;
				}
				if (d <= 8) n++;
			}
			return n;
		}
		var blue0 = count(before, 0x3b82f6), red0 = count(before, 0xef4444), blue1 = count(after, 0x3b82f6), red1 = count(after, 0xef4444);
		check('$app literal: the frame before the patch, its title blue', blue0 > 50 && red0 == 0, 'blue $blue0, red $red0');
		check('$app literal: the frame of the patch, its title red', red1 > 50 && blue1 == 0, 'blue $blue1, red $red1');
		var t = texts(nodes);
		check('$app literal: the title\'s text patched (dones)', t.contains("dones") && !t.contains("todos"), t.join(", "));
	}

	// against tests/headless/<golden> (BLESS: rewritten): at most 1% of the pixels more than 3 levels
	// off (text's edges differ a little between Mesa's releases: 25.2's against CI's)
	// examples/motion scripted (tests/headless/motion.json): its trace (every
	// tagged node's rect and opacity a frame) checked for continuity until
	// the script turns reduced motion on (3.8 s): each edge's steps within a
	// spring's (a quarter of the way it travels a frame, at most: the
	// palette's quickest, 0.2 s, moves a fifth), the rows' left and right
	// edges never moving (they only move down and up), the list's box still,
	// the rows above the one removed still while it leaves, the matched tile
	// flying from where the small one was; from 3.8 s, reduced motion: every
	// move of a box done in one frame (the fades over a few); the same with
	// --reduced-motion from the start; frame strips of the rows, the zoom
	// and the theme against their goldens
	static function motion(one:String, bless:Bool) {
		motionTrace("motion", traceOf('$one/motion.jsonl'));
		// (examples/motion/main.tsx: the same from TypeScript)
		motionTrace("motion-ts", traceOf('$one/motion-ts.jsonl'));
		var reduced = traceOf('$one/motion-reduced.jsonl');
		check("motion --reduced-motion: every move one frame", snapsOnly(reduced, 0) == "", snapsOnly(reduced, 0));
		// (its opacities fade over a few frames: the rows added)
		var fades = 0;
		for (i in 1...reduced.length)
			for (id => r in reduced[i].nodes) {
				var o = reduced[i].opacity.get(id);
				if (o > 0 && o < 1 && reduced[i].tags.get(id).startsWith("row-")) fades++;
			}
		check("motion --reduced-motion: the rows still fade", fades >= 6 && fades < 60, '$fades');
		for (strip in ["rows", "zoom", "theme"]) {
			var shots = [for (k in 0...6) '$one/motion-$strip-$k.png'];
			// (beside the runs' outputs, which are compared run by run)
			var out = '$one/../motion-$strip.png';
			File.saveBytes(out, stripOf(shots));
			image('motion-$strip.png', out, bless);
		}
	}

	static function motionTrace(name:String, frames:Array<Frame>) {
		check('$name trace: a line a frame through its end (5 s at 60)', frames.length == 301, '${frames.length}');
		var jumps = [], stationary = [], ids = new Map<Int, Bool>();
		for (f in frames)
			for (id in f.nodes.keys())
				ids.set(id, true);
		for (id in ids.keys()) {
			// (each edge's runs of change, before reduced motion)
			for (k in 0...4) {
				var run:Array<Float> = [];
				function close() {
					if (run.length > 2) {
						var end = run[run.length - 1], most = 0.0;
						for (v in run)
							most = Math.max(most, Math.abs(v - end));
						for (j in 1...run.length)
							if (Math.abs(run[j] - run[j - 1]) > 0.25 * most + 1.5 && jumps.length < 8)
								jumps.push('${frames[0].tags.get(id) ?? Std.string(id)} edge $k: ${run[j - 1]} to ${run[j]} (of $most)');
					}
					run = [];
				}
				for (i in 1...frames.length) {
					var a = frames[i - 1], b = frames[i];
					if (b.t >= 3.8) break;
					var ra = a.nodes.get(id), rb = b.nodes.get(id);
					if (ra == null || rb == null) {
						close();
						continue;
					}
					var va = ra[k], vb = rb[k];
					if (va != vb) {
						if (run.length == 0) run.push(va);
						run.push(vb);
					} else close();
				}
				close();
			}
		}
		check('$name trace: no jump past what a spring allows', jumps.length == 0, jumps.join("; "));
		// (the rows only move down and up; the list's box never moves)
		for (f in frames) {
			if (f.t >= 3.8) break;
			for (id => r in f.nodes) {
				var tag = f.tags.get(id);
				if (tag == "list" && (r[0] != 20 || r[1] != 68 || r[2] != 280 || r[3] != 500)) stationary.push('list at ${f.t}: $r');
				if (tag.startsWith("row-") && (r[0] != 32 || r[2] != 268)) stationary.push('$tag\'s sides at ${f.t}: $r');
			}
		}
		// (row 2 removed at 1 s: row 1, above it, still until the shuffle at 1.12 s)
		var row1 = [for (f in frames) if (f.t >= 1.0 && f.t < 1.12) for (id => r in f.nodes) if (f.tags.get(id) == "row-1") r[1] + "," + r[3]];
		if (row1.length > 0 && row1.filter(x -> x != row1[0]).length > 0) stationary.push('row-1 while row 2 leaves: ${row1.join(" ")}');
		check('$name trace: stationary edges never move', stationary.length == 0, stationary.slice(0, 6).join("; "));
		// (the tile zoomed into: its first frame where the small one was seen, then on its way)
		var small:Null<Array<Float>> = null, first:Null<Array<Float>> = null;
		for (f in frames) {
			if (f.t < 1.5 || f.t > 2.2) continue;
			for (id => r in f.nodes)
				if (f.tags.get(id) == "tile-2") {
					if (f.paths.get(id).indexOf("/zoom/") < 0) {
						if (f.t < 1.6) small = r;
					} else if (first == null) first = r;
				}
		}
		check('$name trace: the matched tile flies from where the small one was', small != null && first != null
			&& Math.abs(first[0] - small[0]) < 8 && Math.abs(first[2] - small[2]) < 8 && Math.abs(first[3] - small[3]) < 8, '$small then $first');
		// (reduced motion: a box's move done in one frame)
		check('$name trace: reduced motion snaps travel and size', snapsOnly(frames, 3.85) == "", snapsOnly(frames, 3.85));
	}

	// (the first changes of a box past from that take more than one frame, as "tag: n frames")
	static function snapsOnly(frames:Array<Frame>, from:Float):String {
		var slow = [];
		var ids = new Map<Int, Bool>();
		for (f in frames)
			for (id in f.nodes.keys())
				ids.set(id, true);
		for (id in ids.keys()) {
			var streak = 0;
			for (i in 1...frames.length) {
				if (frames[i].t < from) continue;
				var a = frames[i - 1].nodes.get(id), b = frames[i].nodes.get(id);
				var moved = a != null && b != null && (a[0] != b[0] || a[1] != b[1] || a[2] != b[2] || a[3] != b[3]);
				streak = moved ? streak + 1 : 0;
				if (streak == 2 && slow.length < 6) slow.push('${frames[i].tags.get(id)} at ${frames[i].t}: ${a} to ${b}');
			}
		}
		return slow.join("; ");
	}

	// (a trace's frames: each node's edges (left, top, right, bottom), opacity, tag and path by its id)
	static function traceOf(path:String):Array<Frame> {
		var out:Array<Frame> = [];
		for (l in File.getContent(path).trim().split("\n")) {
			var o:Dynamic = haxe.Json.parse(l);
			var f:Frame = {t: o.t, nodes: new Map(), opacity: new Map(), tags: new Map(), paths: new Map()};
			for (n in (o.nodes : Array<Dynamic>)) {
				var r:Array<Float> = n.rect;
				f.nodes.set(n.id, [r[0], r[1], r[0] + r[2], r[1] + r[3]]);
				f.opacity.set(n.id, n.opacity);
				f.tags.set(n.id, n.tag);
				f.paths.set(n.id, n.path);
			}
			out.push(f);
		}
		// (a node's tag in the first frame's map, whichever frame it is in)
		for (f in out)
			for (id => t in f.tags)
				out[0].tags.set(id, t);
		return out;
	}

	// (frames side by side at half their size: a strip)
	static function stripOf(paths:Array<String>):Bytes {
		var imgs = [for (p in paths) helder.image.PngDecoder.decode(File.getBytes(p))];
		var w = Std.int(imgs[0].width / 2), h = Std.int(imgs[0].height / 2), gap = 4;
		var W = imgs.length * w + (imgs.length - 1) * gap;
		var px = Bytes.alloc(W * h * 4);
		px.fill(0, px.length, 255);
		for (k in 0...imgs.length) {
			var img = imgs[k];
			for (y in 0...h)
				for (x in 0...w)
					for (c in 0...4) {
						var s = 0;
						for (dy in 0...2)
							for (dx in 0...2)
								s += img.rgba.get(4 * ((2 * y + dy) * img.width + 2 * x + dx) + c);
						px.set(4 * (y * W + k * (w + gap) + x) + c, (s + 2) >> 2);
					}
		}
		return helder.image.PngEncoder.encode(px, W, h, true);
	}

	static function image(golden:String, got:String, bless:Bool) {
		if (bless) {
			File.saveBytes('$here/$golden', File.getBytes(got));
			Sys.println('headless-run: blessed $here/$golden');
			return;
		}
		if (!FileSystem.exists('$here/$golden')) {
			check('$golden: a golden (BLESS=1 bun run test headless-run)', false);
			return;
		}
		var a = helder.image.PngDecoder.decode(File.getBytes(got)), b = helder.image.PngDecoder.decode(File.getBytes('$here/$golden'));
		if (a.width != b.width || a.height != b.height) {
			check('$got: the golden\'s size', false, '${a.width}x${a.height}, not ${b.width}x${b.height}');
			return;
		}
		var off = 0, max = 0, n = a.width * a.height;
		for (p in 0...n) {
			var d = 0;
			for (k in 0...3) {
				var v = a.rgba.get(4 * p + k) - b.rgba.get(4 * p + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			if (d > 3) off++;
			if (d > max) max = d;
		}
		check('$got against $here/$golden', off <= 0.01 * n, '$off pixels off, at most $max');
		Sys.println('headless-run: $golden ' + (off == 0 && max == 0 ? "exact" : '$off pixels off, at most $max'));
	}
}
