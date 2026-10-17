import haxe.io.Bytes;
import hxmc.gfx.*;
import hxmc.os.*;
import hxmc.ui.*;
import hxmc.ui.draw.*;

// Colour emoji drawn by hxmc.ui.draw headless (Noto Color Emoji's bitmaps:
// a heart with VS16, a thumbs up with a skin tone, a flag; make
// ui-draw-check) against emoji.png, Chromium drawing the same at the same
// place (emoji-ref.mjs): a pixel matches within TOLERANCE, at most MAX_OFF
// of them may not. Where the system has another colour emoji font instead
// (Apple Color Emoji's sbix bitmaps on macOS, Segoe UI Emoji's COLR layers
// on Windows: CI), the same text must come out in colour (no golden
// image). Without any it says so and passes.
//   EmojiTest <emoji.png> <out.png>
class EmojiTest {
	static inline var W = 200;
	static inline var H = 64;
	static inline var TOLERANCE = 48;
	static inline var MAX_OFF = 0.02;

	static function main() {
		var args = Sys.args();
		var text = new DrawText();
		var family = "";
		for (f in ["Noto Color Emoji", "Apple Color Emoji", "Segoe UI Emoji"]) {
			var face = text.fonts.match(f);
			if (family == "" && face != null && face.family == f && face.hasColor) family = f;
		}
		if (family == "") {
			Sys.println("EmojiTest: no colour emoji font, skipped");
			return;
		}
		var device = Device.create(Surface.headless(W, H));
		var r = new Renderer(device);
		var p = text.layout("❤️\u{1F44D}\u{1F3FD}\u{1F1E7}\u{1F1EA}", new Font(family, 32, 400, false, 1.25), Math.NaN);
		var pixels = Bytes.alloc(W * H * 4);
		var enc = device.beginFrame();
		var pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
		enc.beginPass(pass);
		r.begin(W, H);
		// (the first line's top at 10: its baseline at 41)
		r.text(p, 10, 10, W, Left, Color.BLACK);
		r.end(enc);
		enc.endPass();
		device.readPixels(pixels);
		device.endFrame();
		device.dispose();
		sys.io.File.saveBytes(args[1], Png.encode(pixels, W, H));
		var golden = family == "Noto Color Emoji";
		var want = golden ? PngDecoder.decode(sys.io.File.getBytes(args[0])) : {width: W, height: H, rgba: pixels};
		var off = 0, most = 0, colored = 0;
		for (i in 0...W * H) {
			var d = 0;
			for (c in 0...3) {
				var v = Std.int(Math.abs(pixels.get(4 * i + c) - want.rgba.get(4 * i + c)));
				if (v > d) d = v;
			}
			if (d > TOLERANCE) off++;
			if (d > most) most = d;
			// (a colour: channels apart)
			var r0 = pixels.get(4 * i), g0 = pixels.get(4 * i + 1), b0 = pixels.get(4 * i + 2);
			if (Math.max(r0, Math.max(g0, b0)) - Math.min(r0, Math.min(g0, b0)) > 80) colored++;
		}
		var ok = off <= MAX_OFF * W * H && colored > 300;
		Sys.println('EmojiTest: $family: ${ok ? "ok" : "FAILED"} (' + (golden ? '$off pixels off by more than $TOLERANCE, at most $most; ' : "") + '$colored coloured)');
		Sys.exit(ok ? 0 : 1);
	}
}
