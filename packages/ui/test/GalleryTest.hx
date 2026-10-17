import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;
import hxmc.view.*;

// The widget gallery (examples/Gallery.hx) driven headless through its Ui:
// buttons, the select, menu and dialog (popups: clicked, keys), the
// checkbox and switch (clicked and with the keyboard), radio
// buttons, the slider (dragged, clicked, arrow keys, Home and End), tabs,
// the tree opened and the table sorted in their split view,
// the field, the images' sizes; PNG files decoded natively (png/*.png,
// as UiTest on Eval); its state checked, then its frame against gallery.png (Linux:
// llvmpipe, DejaVu Sans) (make ui-draw-check):
// With --dark, in Theme.DARK, against gallery-dark.png.
//   GalleryTest <golden.png> <out.png> [--dark] [--bless]
class GalleryTest {
	static inline var W = 560;
	static inline var H = 1160;
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
		if (args.indexOf("--dark") >= 0) hxmc.ui.widgets.Theme.current.value = hxmc.ui.widgets.Theme.DARK;
		var device = Device.create(Surface.headless(W, H));
		var ui = new Ui(new DrawText(), W, H);
		var app = new Gallery();
		Render.render(app.view(), ui.root);
		ui.update();
		function find(tag:String):Node {
			var n = ui.root.find(tag) ?? ui.overlay.find(tag);
			if (n == null) throw "GalleryTest: no " + tag;
			return n;
		}
		function click(tag:String) {
			var n = find(tag);
			ui.pointerDown(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			ui.pointerUp(n.absX + n.width / 2, n.absY + n.height / 2, 1);
			Clock.finish();
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
		// popups: the select's list, the menu, the dialog it opens
		click("fruit");
		check("the select opens", ui.overlay.find("fruit-list") != null && ui.focus == find("fruit-Apple"));
		key(Key.DOWN);
		key(Key.ENTER);
		check("an option chosen with the keys", app.fruit.value == "Pear" && ui.overlay.children.length == 0 && ui.focus == find("fruit"), app.fruit.value);
		click("file");
		click("file-1");
		check("a menu item clicked", app.chosen.value == "Open" && shown("chosen") == "Open", app.chosen.value);
		ui.setFocus(find("file"));
		key(Key.DOWN);
		key(Key.UP);
		key(Key.DOWN);
		key(Key.DOWN);
		key(Key.ENTER);
		check("the dialog, opened from the menu, its field focused", app.dialog.value && ui.focus == find("rename"), '${ui.focus}');
		click("done");
		check("the dialog closed by its button", !app.dialog.value && ui.overlay.children.length == 0);
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
		// the split view: the tree's first folder opened, a file chosen; the table sorted by size
		click("files-toggle");
		check("a tree's folder opened", app.open.value.length == 1 && app.open.value[0].name == "examples");
		ui.setFocus(find("files"));
		key(Key.DOWN);
		key(Key.DOWN);
		check("a tree's file chosen with the keys", app.file.value != null && app.file.value.name == "Gallery.hx", app.file.value == null ? "none" : app.file.value.name);
		click("sizes-head-1");
		click("sizes-head-1");
		ui.setFocus(find("sizes-body"));
		key(Key.HOME);
		check("the table sorted by size, the other way", app.row.value != null && app.row.value.name == "Ui.hx", app.row.value == null ? "none" : app.row.value.name);
		check("the split's panes", find("panes-first").width == 200 && find("panes-divider").absX == find("panes").absX + 200);
		click("name");
		for (c in new haxe.iterators.StringIteratorUnicode("Ada")) {
			ui.keyDown(c, 0);
			ui.textInput(String.fromCharCode(c));
		}
		ui.update();
		check("the field", app.name.value == "Ada" && shown("greeting") == "Hello, Ada!", shown("greeting"));
		click("notes");
		for (c in new haxe.iterators.StringIteratorUnicode("One")) {
			ui.keyDown(c, 0);
			ui.textInput(String.fromCharCode(c));
		}
		key(Key.ENTER);
		for (c in new haxe.iterators.StringIteratorUnicode("Two, on a line long enough to wrap in the area")) {
			ui.keyDown(c, 0);
			ui.textInput(String.fromCharCode(c));
		}
		ui.update();
		check("the area", StringTools.startsWith(app.notes.value, "One\nTwo") && shown("lines") == "2 lines", shown("lines"));
		// Tab from the area: no further focusable node, back to the first (the
		// Plain button), its focus ring shown
		key(Key.TAB);
		check("Tab wraps to the first button", ui.focus == find("plain") && ui.focusVisible);
		var natural = find("natural");
		check("an image's natural size", natural.width == 120 && natural.height == 60, '${natural.width}x${natural.height}');
		// the PNG cases, decoded by the native build
		var dir = "packages/ui/test/png";
		if (sys.FileSystem.exists(dir)) {
			var n = 0, bad = [];
			for (f in sys.FileSystem.readDirectory(dir))
				if (StringTools.endsWith(f, ".png")) {
					n++;
					var img = Image.decode(sys.io.File.getBytes(dir + "/" + f));
					if (img.pixels.compare(sys.io.File.getBytes(dir + "/" + f.substr(0, f.length - 4) + ".rgba")) != 0) bad.push(f);
				}
			check("PNG files decoded", n >= 20 && bad.length == 0, bad.join(" "));
		}
		// (the frame with the select's list open over the toggles)
		click("fruit");
		Sys.println('GalleryTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
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
		if (args.indexOf("--bless") >= 0) {
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
