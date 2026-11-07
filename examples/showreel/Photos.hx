import haxe.io.Bytes;
import helder.canvas.*;
import helder.canvas.Gradient;
import helder.image.Image;

// The zoom scene's "photographs", painted with helder.canvas when the reel
// starts (no image files): a sky's gradient, a sun's glow, ridges of hills
// one behind another, fading into the haze, their outlines a sum of sines.
class Photos {
	public static final PLACES = [
		{title: "Dawn over the ridge", meta: "f/8 · 1/250 s · ISO 100", sky: [0xff1d2b53, 0xffef8a78, 0xffffd5a0], hills: 0xff2a1b3d, sun: 0xffffe2b0, sunY: 0.62},
		{title: "Glacier light", meta: "f/11 · 1/500 s · ISO 64", sky: [0xff0c2d48, 0xff5fa8d3, 0xffcae9ff], hills: 0xff0b2235, sun: 0xffffffff, sunY: 0.30},
		{title: "Desert, late", meta: "f/5.6 · 1/1000 s · ISO 100", sky: [0xff3b1c32, 0xffd9734e, 0xfff6c177], hills: 0xff4a1f22, sun: 0xffffe08a, sunY: 0.52},
		{title: "Fjord at blue hour", meta: "f/2.8 · 1/30 s · ISO 800", sky: [0xff080d26, 0xff283c86, 0xff7a6fd0], hills: 0xff070a1c, sun: 0xffcfd8ff, sunY: 0.40},
		{title: "Meadow, first frost", meta: "f/4 · 1/320 s · ISO 200", sky: [0xff14453d, 0xff5fb49c, 0xffd7f2d0], hills: 0xff0d2a25, sun: 0xfffffbe0, sunY: 0.35},
		{title: "Aurora, minus twenty", meta: "f/1.8 · 8 s · ISO 3200", sky: [0xff020611, 0xff0f3a4a, 0xff2bd99f], hills: 0xff01040a, sun: 0xff9effd8, sunY: 0.18}
	];

	public static var images(get, never):Array<Image>;
	static var made:Null<Array<Image>> = null;

	static function get_images():Array<Image> {
		if (made == null) made = [for (i in 0...PLACES.length) paint(i, 640, 400)];
		return made;
	}

	static function lerpColor(a:Int, b:Int, k:Float):Int {
		inline function ch(c:Int, s:Int):Int
			return (c >> s) & 0xff;
		var r = Std.int(ch(a, 16) + (ch(b, 16) - ch(a, 16)) * k), g = Std.int(ch(a, 8) + (ch(b, 8) - ch(a, 8)) * k),
			bl = Std.int(ch(a, 0) + (ch(b, 0) - ch(a, 0)) * k);
		return 0xff000000 | (r << 16) | (g << 8) | bl;
	}

	public static function paint(i:Int, w:Int, h:Int):Image {
		var p = PLACES[i], c = new Canvas(w, h);
		var sky = new LinearGradient(0, 0, 0, h * 0.8);
		sky.addStop(0, p.sky[0]).addStop(0.6, p.sky[1]).addStop(1, p.sky[2]);
		c.fillRect(0, 0, w, h, Paint.shaded(sky));
		// (the sun, and its glow)
		var sx = w * (0.3 + 0.4 * Reel.rand(i * 13)), sy = h * p.sunY;
		var glow = new RadialGradient(sx, sy, 0, sx, sy, w * 0.45);
		glow.addStop(0, (p.sun & 0xffffff) | 0x88000000).addStop(1, p.sun & 0xffffff);
		c.fillRect(0, 0, w, h, Paint.shaded(glow));
		var disc = new Path();
		disc.arc(sx, sy, w * 0.035, 0, Math.PI * 2);
		c.fill(disc, Paint.solid(p.sun));
		// (an aurora's curtains)
		if (i == 5) for (k in 0...3) {
			var band = new Path(), y0 = h * (0.18 + k * 0.08);
			band.moveTo(0, y0);
			var x = 0.0;
			while (x <= w) {
				band.lineTo(x, y0 + Math.sin(x * 0.012 + k * 2) * 26 + Math.sin(x * 0.031 + k) * 9);
				x += 8;
			}
			band.lineTo(w, y0 + 120);
			band.lineTo(0, y0 + 120);
			band.close();
			var g = new LinearGradient(0, y0 - 30, 0, y0 + 120);
			g.addStop(0, 0x0032ffb0).addStop(0.25, 0x6632ffb0).addStop(1, 0x0032ffb0);
			c.fill(band, Paint.shaded(g));
		}
		// (the ridges, far to near: the far ones in the haze of the sky)
		for (r in 0...5) {
			var k = r / 4, ridge = new Path(), base = h * (0.48 + 0.11 * r);
			var col = lerpColor(p.sky[2], p.hills, 0.35 + 0.65 * k);
			ridge.moveTo(0, h);
			var x = 0.0, seed = i * 31 + r * 7;
			while (x <= w + 8) {
				var y = base - (40 + 30 * (1 - k)) * (0.5 + 0.5 * Math.sin(x * (0.006 + 0.002 * r) + seed))
					- 18 * Math.sin(x * (0.017 + 0.003 * r) + seed * 1.7) - 6 * Math.sin(x * 0.07 + seed * 0.3);
				ridge.lineTo(x, y);
				x += 6;
			}
			ridge.lineTo(w, h);
			ridge.close();
			c.fill(ridge, Paint.solid(col));
		}
		var px = Bytes.alloc(w * h * 4);
		c.readPixels(px, 0, 0, w, h);
		return new Image(w, h, px);
	}
}
