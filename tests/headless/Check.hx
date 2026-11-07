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
// the viewer's file dialog and context menu answered by its script, the
// trace's lines, the frames written, and each output of the second run
// byte for byte the first's.
//   Check <dir> [--bless]
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
