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
// the trace's lines, the frames written, and each output of the second run
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
			traceLines(app, '$one/$app.jsonl');
			image('$app-toggled.png', '$one/$app-toggled.png', bless);
		}
		image("glow.png", '$one/glow.png', bless);
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
