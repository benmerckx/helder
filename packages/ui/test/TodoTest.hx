import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;
import hxmc.ui.reactive.*;

// The todo example (examples/Todo.hx) driven headless through its Ui:
// typing into the field and Enter, the Add button, a checkbox, a filter,
// Remove; its state checked, then its frame against todo.png (Linux:
// llvmpipe, DejaVu Sans) (make ui-draw-check):
//   TodoTest <golden.png> <out.png> [--bless]
class TodoTest {
	static inline var W = 420;
	static inline var H = 480;
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TodoTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		var device = Device.create(Surface.headless(W, H));
		var ui = new Ui(new DrawText(), W, H);
		var app = new Todo();
		Render.render(app.view(), ui.root);
		ui.update();
		function click(tag:String) {
			var n = ui.root.find(tag);
			if (n == null) throw "TodoTest: no " + tag;
			ui.pointerDown(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			ui.pointerUp(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			Clock.finish();
			ui.update();
		}
		function type(s:String)
			for (c in new haxe.iterators.StringIteratorUnicode(s)) {
				ui.keyDown(c, 0);
				ui.textInput(String.fromCharCode(c));
			}
		click("draft");
		check("the field takes the focus", ui.focus == ui.root.find("draft"));
		type("Buy milk");
		check("typing edits the draft", app.draft.value == "Buy milk", app.draft.value);
		ui.keyDown(Key.ENTER, 0);
		ui.update();
		check("Enter adds it", app.todos.value.length == 1 && app.draft.value == "" && (cast ui.root.find("draft") : TextNode).text == "");
		type("Write the renderer");
		ui.keyDown(Key.LEFT, Key.MOD_SHIFT);
		ui.keyDown(Key.LEFT, Key.MOD_SHIFT);
		type("ER");
		check("a selection is replaced", app.draft.value == "Write the renderER", app.draft.value);
		ui.keyDown(Key.BACKSPACE, 0);
		ui.keyDown(Key.BACKSPACE, 0);
		type("er");
		click("add");
		// (the button took the focus)
		click("draft");
		type("Ship it");
		click("add");
		check("Add adds", app.todos.value.length == 3 && app.todos.value[1].title == "Write the renderer", [for (t in app.todos.value) t.title].join("|"));
		click("checkbox");
		check("a checkbox toggles its item", app.todos.value[0].done.value);
		var left:TextNode = cast ui.root.find("left");
		check("the count follows", left.text == "2 items left", left.text);
		click("filter-active");
		var list = ui.root.find("list");
		var rows = [for (c in list.children) if (c.style.display != None) c].length;
		check("a filter hides the done items", rows == 2, '$rows');
		click("filter-all");
		Sys.println('TodoTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		// the frame (the widgets' transitions finished)
		Clock.finish();
		var r = new Renderer(device);
		var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
		var pixels = Bytes.alloc(W * H * 4);
		ui.update();
		var enc = device.beginFrame();
		enc.beginPass(pass);
		r.begin(W, H);
		ui.paint(r);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		sys.io.File.saveBytes(args[1], Png.encode(pixels, W, H));
		if (args[2] == "--bless") {
			sys.io.File.saveBytes(args[0], Png.encode(pixels, W, H));
			Sys.println('TodoTest: blessed ${args[0]}');
			Sys.exit(failed == 0 ? 0 : 1);
		}
		var g = Png.decode(sys.io.File.getBytes(args[0]));
		var off = 0, max = 0;
		for (p in 0...W * H) {
			var d = 0;
			for (k in 0...3) {
				var v = pixels.get(4 * p + k) - g.rgba.get(4 * p + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			if (d > 3) off++;
			if (d > max) max = d;
		}
		var ok = g.width == W && off <= 0.003 * W * H;
		Sys.println('TodoTest: frame ' + (ok ? "ok" : "FAIL") + (off == 0 && max == 0 ? " (exact)" : ' ($off pixels off, at most $max)'));
		Sys.exit(failed == 0 && ok ? 0 : 1);
	}
}
