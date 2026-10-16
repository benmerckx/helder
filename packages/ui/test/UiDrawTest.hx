import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;

// The sample UI (Sample.hx) drawn headless by hxmc.ui.draw and compared
// with draw.png (GfxTest's rule: a pixel matches within TOLERANCE, at most
// MAX_OFF of them may not), on the target's GPU API (make ui-draw-check;
// Linux: Mesa's llvmpipe on an EGL pbuffer):
//   UiDrawTest <golden.png> <out.png> [--bless | --dump | --window | --smoke]
// (--dump prints the laid-out tree; --window draws it in a UiWindow, X11
// under Xvfb on Linux, and compares the frame read back before its present;
// --smoke, for the machines without DejaVu Sans (Windows, macOS: CI's
// gfx-windows and gfx-macos): no golden image, but the system font found
// is printed and the card's paragraph must have drawn text)
class UiDrawTest {
	static inline var W = 480;
	static inline var H = 320;
	static inline var TOLERANCE = 3;
	static inline var MAX_OFF = 0.003;

	static function dump(n:Node, ind:String) {
		var extra = Std.isOfType(n, TextNode) ? ' "' + (cast n : TextNode).text.substr(0, 24) + '"' : "";
		Sys.println(ind + n.tag + " " + n.absX + "," + n.absY + " " + n.width + "x" + n.height + extra);
		for (c in n.children)
			dump(c, ind + "  ");
	}

	static var smoke = false;

	static function main() {
		var args = Sys.args();
		var golden = args[0], out = args[1], bless = args[2] == "--bless";
		if (args[2] == "--smoke") smoke = true;
		if (args[2] == "--window") {
			window(golden, out);
			return;
		}
		var device = Device.create(Surface.headless(W, H));
		var ui = new Ui(new DrawText(), W, H);
		Sample.build(ui.root);
		var r = new Renderer(device);
		var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
		var pixels = Bytes.alloc(W * H * 4);
		var t0 = haxe.Timer.stamp();
		ui.update();
		var t1 = haxe.Timer.stamp();
		if (args[2] == "--dump") dump(ui.root, "");
		var enc = device.beginFrame();
		enc.beginPass(pass);
		r.begin(W, H);
		ui.paint(r);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		Sys.println('UiDrawTest: layout ${Math.round((t1 - t0) * 1000)} ms, frame ${Math.round((haxe.Timer.stamp() - t1) * 1000)} ms');
		device.dispose();
		sys.io.File.saveBytes(out, Png.encode(pixels, W, H));
		if (bless) {
			sys.io.File.saveBytes(golden, Png.encode(pixels, W, H));
			Sys.println('UiDrawTest: blessed $golden');
			Sys.exit(0);
		}
		if (smoke) {
			var face = (cast ui.text : DrawText).face(ui.root.font());
			// the card's paragraph: dark text on white
			var dark = 0;
			for (y in 110...190)
				for (x in 170...450) {
					var o = 4 * (y * W + x);
					if (pixels.get(o) + pixels.get(o + 1) + pixels.get(o + 2) < 3 * 128) dark++;
				}
			var ok = dark > 400;
			Sys.println('UiDrawTest: smoke: the font ${face.family} ${face.subfamily}, $dark dark pixels in the paragraph: ' + (ok ? "ok" : "FAIL"));
			Sys.exit(ok ? 0 : 1);
		}
		Sys.exit(compare(pixels, golden) ? 0 : 1);
	}

	static function window(golden:String, out:String) {
		var w = new UiWindow("UiDrawTest", W, H);
		Sample.build(w.root);
		var pixels = Bytes.alloc(W * H * 4);
		var frames = 0;
		w.onFrame = () -> {
			frames++;
			// (frames 2 and 3 asked for: with nothing changed the window draws no more)
			if (frames < 3) w.ui.requestFrame();
			if (frames == 2) w.capture = pixels;
		};
		// UiWindow.run's loop, counting the turns with nothing to draw: each
		// sleeps (App.wait) until an event or 50 ms; closed after half a second idle
		var idle = 0, since = 0.0;
		App.run(() -> {
			if (w.needsFrame()) {
				w.frame();
				since = haxe.Timer.stamp();
			} else {
				idle++;
				App.wait(0.05);
				if (haxe.Timer.stamp() - since > 0.5) w.close();
			}
		}, e -> w.handle(e));
		sys.io.File.saveBytes(out, Png.encode(pixels, W, H));
		var slept = frames == 3 && idle > 2 && idle < 40;
		Sys.println('UiDrawTest: window: $frames frames, then $idle turns idle, scale ${w.renderer.scale}' + (slept ? "" : " (FAIL: 3 frames and the loop asleep expected)"));
		Sys.exit(compare(pixels, golden) && slept ? 0 : 1);
	}

	static function compare(pixels:Bytes, golden:String):Bool {
		var g = Png.decode(sys.io.File.getBytes(golden));
		var off = 0, differ = 0, max = 0;
		for (p in 0...W * H) {
			var d = 0;
			for (k in 0...3) {
				var v = pixels.get(4 * p + k) - g.rgba.get(4 * p + k);
				if (v < 0) v = -v;
				if (v > d) d = v;
			}
			if (d > 0) differ++;
			if (d > TOLERANCE) off++;
			if (d > max) max = d;
		}
		var ok = g.width == W && off <= MAX_OFF * W * H;
		Sys.println('UiDrawTest: ' + (ok ? "ok" : "FAIL") + (differ == 0 ? " (exact)" : ' ($differ pixels differ, $off by more than $TOLERANCE, at most $max)'));
		return ok;
	}
}
