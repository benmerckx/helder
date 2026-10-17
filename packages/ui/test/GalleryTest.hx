import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;
import hxmc.ui.reactive.*;

// The widget gallery (examples/Gallery.hx) driven headless through its Ui:
// buttons, the checkbox and switch (clicked and with the keyboard), radio
// buttons, the slider (dragged, clicked, arrow keys, Home and End), tabs,
// the field; its state checked, then its frame against gallery.png (Linux:
// llvmpipe, DejaVu Sans) (make ui-draw-check):
//   GalleryTest <golden.png> <out.png> [--bless]
class GalleryTest {
	static inline var W = 560;
	static inline var H = 720;
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('GalleryTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var args = Sys.args();
		var device = Device.create(Surface.headless(W, H));
		var ui = new Ui(new DrawText(), W, H);
		var app = new Gallery();
		Render.render(app.view(), ui.root);
		ui.update();
		function find(tag:String):Node {
			var n = ui.root.find(tag);
			if (n == null) throw "GalleryTest: no " + tag;
			return n;
		}
		function click(tag:String) {
			var n = find(tag);
			ui.pointerDown(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			ui.pointerUp(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			ui.update();
		}
		function key(k:Int) {
			ui.keyDown(k, 0);
			ui.keyUp(k, 0);
			ui.update();
		}
		function shown(tag:String):String
			return (cast find(tag) : TextNode).text;
		click("plain");
		click("primary");
		check("buttons", app.clicks.value == 11 && shown("clicks") == "clicked 11", shown("clicks"));
		click("check");
		click("switch");
		check("a checkbox and a switch, clicked", !app.checked.value && app.on.value && shown("toggles") == "unchecked, on", shown("toggles"));
		key(Key.SPACE);
		check("the switch with the keyboard", !app.on.value);
		click("size-Large");
		check("a radio button", app.size.value == "Large" && shown("size-shown") == "size: Large", shown("size-shown"));
		// the slider: 200 wide, the knob 16 (its centre travels from 8 to 192)
		var s = find("volume");
		var y = s.absY + s.height / 2;
		ui.pointerDown(s.absX + 8, y, 1);
		check("a press at the start", app.volume.value == 0, '${app.volume.value}');
		ui.pointerMove(s.absX + 8 + 184 * 0.75, y);
		check("a drag", Math.abs(app.volume.value - 0.75) < 1e-9, '${app.volume.value}');
		ui.pointerMove(s.absX + 400, y);
		check("a drag past the end", app.volume.value == 1, '${app.volume.value}');
		ui.pointerMove(s.absX + 8 + 184 * 0.5, y);
		ui.pointerUp(s.absX + 8 + 184 * 0.5, y, 1);
		ui.update();
		check("released at the middle", Math.abs(app.volume.value - 0.5) < 1e-9 && shown("volume-shown") == "50%", shown("volume-shown"));
		check("the slider took the focus", ui.focus == s);
		key(Key.RIGHT);
		key(Key.RIGHT);
		check("arrow keys step", Math.abs(app.volume.value - 0.6) < 1e-9, '${app.volume.value}');
		key(Key.HOME);
		check("Home", app.volume.value == 0);
		key(Key.END);
		check("End", app.volume.value == 1);
		key(Key.LEFT);
		key(Key.LEFT);
		key(Key.LEFT);
		ui.update();
		click("tab-1");
		var content:Null<TextNode> = Std.downcast(find("tab-content").children[0], TextNode);
		check("a tab", app.tab.value == 1 && content != null && StringTools.startsWith(content.text, "Details"), content == null ? "no text" : content.text);
		click("name");
		for (c in new haxe.iterators.StringIteratorUnicode("Ada")) {
			ui.keyDown(c, 0);
			ui.textInput(String.fromCharCode(c));
		}
		ui.update();
		check("the field", app.name.value == "Ada" && shown("greeting") == "Hello, Ada!", shown("greeting"));
		// Tab from the field: no further focusable node, back to the first (the
		// Plain button), its focus ring shown
		key(Key.TAB);
		check("Tab wraps to the first button", ui.focus == find("plain") && ui.focusVisible);
		Sys.println('GalleryTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		// the frame
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
			Sys.println('GalleryTest: blessed ${args[0]}');
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
		Sys.println('GalleryTest: frame ' + (ok ? "ok" : "FAIL") + (off == 0 && max == 0 ? " (exact)" : ' ($off pixels off, at most $max)'));
		Sys.exit(failed == 0 && ok ? 0 : 1);
	}
}
