import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;

// The sample UI (Sample.hx) drawn headless by hxmc.ui.draw and compared
// with draw.png (GfxTest's rule: a pixel matches within TOLERANCE, at most
// MAX_OFF of them may not), on the target's GPU API (make ui-draw-check;
// Linux: Mesa's llvmpipe on an EGL pbuffer):
//   UiDrawTest <golden.png> <out.png> [--bless | --dump]
// (--dump prints the laid-out tree)
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

	static function main() {
		var args = Sys.args();
		var golden = args[0], out = args[1], bless = args[2] == "--bless";
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
		Sys.exit(ok ? 0 : 1);
	}
}
