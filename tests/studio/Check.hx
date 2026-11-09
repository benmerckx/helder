import haxe.Json;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The studio lane's checks (tests/Run.hx: studio): helder studio (apps/studio)
// run headless on copies of examples/todo and examples/ts-todo by
// tests/studio/edit.json, its events (--events: JSON lines) and frames here:
// - every screen shown, a screen zoomed into, the title clicked and selected
//   (its node's box, its element in the source);
// - its colour changed in the inspector: one change, the value's span alone
//   (#3b82f6 to #ef4444), a live literal patched (no build), the program's
//   frame showing #ef4444 within 3 of the studio's frames;
// - a padding added (a build, the title 40 points taller), then undone (the
//   file as before it, built, the title as before);
// - tag="title" typed into the code view: built, the program's node tagged so;
// - the prompt bar's /tree answered by the studio's own tools;
// - the file at the end: the original with those two changes alone, every
//   edit's span applying to the text before it in order;
// - the overview, the zoomed and the selected frames against the goldens here.
// Then examples/design (design files alone, tests/studio/design.json): its
// two frames drawn by the studio itself, nothing built; the title clicked
// and selected (its box, its element); its colour changed in the inspector
// (the value's span alone, the frame drawn again with it within 3 frames),
// undone and redone (drawn so each time); the file with that change alone.
// The measurements (cold start to the first frame, the project's screens
// all shown, an inspector's change to the program's frame) printed.
class Check {
	static var failed = 0;
	static var checks = 0;
	static final here = "tests/studio";

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('studio: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		var dir = args[0], bless = args[1] == "--bless";
		var rows = [];
		for (app in ["todo", "ts-todo"]) {
			var source = app == "todo" ? "Todo.hx" : "app.tsx";
			rows.push(run(app, File.getContent('examples/$app/$source'), File.getContent('$dir/$app/$source'), events('$dir/$app.jsonl')));
			for (shot in ["overview", "zoomed", "selected"])
				image('$app-$shot.png', '$dir/$app-$shot.png', bless);
		}
		design(File.getContent("examples/design/app.helder"), File.getContent('$dir/design/app.helder'), events('$dir/design.jsonl'));
		Sys.println("studio: | | cold start to first frame | open to all screens shown | inspector change to the program's frame |");
		for (r in rows) Sys.println('studio: | ${r.app} | ${r.first} ms | ${r.shown} ms | ${r.patch} ms (${r.frames} studio frame(s)) |');
		Sys.println('studio: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		Sys.exit(failed == 0 ? 0 : 1);
	}

	static function events(path:String):Array<Dynamic>
		return [for (l in File.getContent(path).split("\n")) if (l.trim() != "") Json.parse(l)];

	static function run(app:String, original:String, final_:String, ev:Array<Dynamic>) {
		function all(name:String):Array<Dynamic>
			return ev.filter(e -> e.event == name);
		function first(name:String):Null<Dynamic>
			return all(name)[0];
		var ff:Dynamic = first("first-frame"), shown:Dynamic = first("all-shown");
		check('$app: the first frame', ff != null);
		check('$app: all 4 screens shown', shown != null && shown.screens == 4, Json.stringify(shown));
		var sel:Dynamic = first("selected");
		check('$app: the title selected (its box, its element)', sel != null && sel.tag == "text" && Json.stringify(sel.rect) == "[24,24,432,35]", Json.stringify(sel));
		var edits = all("edited");
		// (the colour: the inspector's first edit, the value's span alone)
		var color:Dynamic = edits[0];
		var at = original.indexOf('color="#3b82f6">todos') + 'color="'.length;
		check('$app: the colour\'s edit: #3b82f6\'s span alone', color != null && color.origin == "inspector" && color.changes.length == 1
			&& color.changes[0].start == at && color.changes[0].end == at + 7 && color.changes[0].text == "#ef4444", Json.stringify(color));
		var patched:Dynamic = first("patched");
		check('$app: the colour patched as a live literal (nothing built before it)', patched != null && ev.indexOf(patched) < ev.indexOf(first("building") ?? ev[ev.length - 1]),
			Json.stringify(patched));
		var p:Dynamic = first("patch-shown");
		check('$app: the program\'s frame shows #ef4444 within 3 studio frames', p != null && p.color == "#ef4444" && p.frames <= 3, Json.stringify(p));
		// (the selection's box after each build: padded, undone, typed)
		var boxes:Array<Dynamic> = all("selection");
		check('$app: the padding built: the title 75 points tall', Lambda.exists(boxes, (b:Dynamic) -> b.rect[3] == 75), Json.stringify([for (b in boxes) b.rect]));
		var padded:Dynamic = Lambda.find(edits, (e:Dynamic) -> e.origin == "inspector" && e.changes[0].text.indexOf("padding") >= 0);
		check('$app: the padding added after the colour, before the text', padded != null && padded.changes[0].start == at + 8, Json.stringify(padded));
		var undo:Dynamic = Lambda.find(edits, (e:Dynamic) -> e.origin == "undo");
		check('$app: the undo removes the padding alone', undo != null && undo.changes.length == 1 && undo.changes[0].text == ""
			&& undo.changes[0].start == at + 8 && undo.changes[0].end == at + 8 + " padding={20}".length, Json.stringify(undo));
		var afterUndo:Array<Dynamic> = boxes.filter((b:Dynamic) -> ev.indexOf(b) > ev.indexOf(undo));
		check('$app: undone: the title 35 points tall again', afterUndo.length > 0 && afterUndo[0].rect[3] == 35, Json.stringify(afterUndo.map((b:Dynamic) -> b.rect)));
		var built = all("built");
		check('$app: every build ok', built.length >= 3 && Lambda.foreach(built, (b:Dynamic) -> b.ok != false), Json.stringify(built));
		check('$app: typed tag="title": built, the node tagged title', boxes.length > 0 && boxes[boxes.length - 1].tag == "title",
			Json.stringify(boxes[boxes.length - 1]));
		var replied:Dynamic = first("replied");
		check('$app: the prompt bar\'s /tree answered by run.tree', replied != null && (replied.reply : String).startsWith("run.tree: {"), Json.stringify(replied));
		// (the edits replayed: each span on the text before it)
		var text = original;
		for (e in edits)
			for (c in (e.changes : Array<Dynamic>))
				text = text.substr(0, c.start) + c.text + text.substr(c.end);
		check('$app: the edits replayed give the file', text == final_);
		var expected = original.replace('<text font-size={28} font-weight={700} color="#3b82f6">todos',
			'<text tag="title" font-size={28} font-weight={700} color="#ef4444">todos');
		check('$app: the file: the original with the colour and the tag alone', final_ == expected);
		return {app: app, first: ff?.ms, shown: shown?.ms, patch: p?.ms, frames: p?.frames};
	}

	static function design(original:String, final_:String, ev:Array<Dynamic>) {
		function all(name:String):Array<Dynamic>
			return ev.filter(e -> e.event == name);
		var shown:Dynamic = all("designs-shown")[0];
		check('design: both frames drawn, none marked', shown != null && shown.frames == 2 && shown.errors == 0, Json.stringify(shown));
		check('design: nothing built or run', all("building").length == 0 && all("built").length == 0 && all("all-shown").length == 0);
		var sel:Dynamic = all("selected")[0];
		check('design: the title selected (its box, its element)', sel != null && sel.tag == "text" && Json.stringify(sel.rect) == "[24,56,342,35]", Json.stringify(sel));
		var edits = all("edited");
		var at = original.indexOf('color="#3b82f6">todos') + 'color="'.length;
		var color:Dynamic = edits[0];
		check('design: the colour\'s edit: #3b82f6\'s span alone', color != null && color.origin == "inspector" && color.changes.length == 1
			&& color.changes[0].start == at && color.changes[0].end == at + 7 && color.changes[0].text == "#ef4444", Json.stringify(color));
		check('design: undone and redone', edits.length == 3 && edits[1].origin == "undo" && edits[2].origin == "redo", Json.stringify(edits.map((e:Dynamic) -> e.origin)));
		// (each edit's frame drawn again with it: the title's colour then)
		var colors = [];
		for (e in edits) {
			var next:Dynamic = Lambda.find(all("selection"), (s:Dynamic) -> s.frame > e.frame);
			colors.push(next == null || next.frame - e.frame > 3 ? null : next.color);
		}
		check('design: the title drawn #ef4444, #3b82f6, #ef4444 within 3 frames of each edit', colors.join(" ") == "#ffef4444 #ff3b82f6 #ffef4444", colors.join(" "));
		check('design: the file: the original with the colour alone', final_ == original.replace('color="#3b82f6">todos', 'color="#ef4444">todos'));
		Sys.println('studio: design: 2 frames drawn ${shown?.ms} ms after opening, nothing built');
	}

	// against tests/studio/<golden> (BLESS: rewritten): at most 1% of the pixels more than 3 levels off
	static function image(golden:String, got:String, bless:Bool) {
		if (bless) {
			File.saveBytes('$here/$golden', File.getBytes(got));
			Sys.println('studio: blessed $here/$golden');
			return;
		}
		if (!FileSystem.exists('$here/$golden')) {
			check('$golden: a golden (BLESS=1 bun run test studio)', false);
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
		Sys.println('studio: $golden ' + (off == 0 && max == 0 ? "exact" : '$off pixels off, at most $max'));
	}
}
