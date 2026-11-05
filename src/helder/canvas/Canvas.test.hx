package helder.canvas;

import haxe.io.Bytes;
import helder.canvas.Gradient;
import helder.canvas.Stroke;
import helder.test.Test;

// helder.canvas's core (the test lane, natively and as wasm32-wasi): exact
// coverage, both fill rules, clips and layers, strokes' widths, joins, caps
// and dashes, blend modes' values, gradients' ends, images, the encoders'
// round trips, Path's Canvas 2D rules, and drawing without allocating. Its
// pixels against Chromium's are the canvas lane's (tests/canvas).
function tests() {
	describe("Canvas", () -> {
		test("coverage is each pixel's area: half a pixel, a quarter, whole", () -> {
			var c = new Canvas(8, 8);
			c.fillRect(1, 1, 2.5, 1.5, Paint.solid(0xFF000000));
			equals(alpha(c, 1, 1), 255);
			equals(alpha(c, 3, 1), 128);
			equals(alpha(c, 1, 2), 128);
			equals(alpha(c, 3, 2), 64);
			equals(alpha(c, 4, 1), 0);
			equals(alpha(c, 0, 0), 0);
		});
		test("non-zero and even-odd: a square inside one wound the same way", () -> {
			var p = new Path();
			p.rect(0, 0, 10, 10);
			p.rect(3, 3, 4, 4);
			var a = new Canvas(10, 10), b = new Canvas(10, 10);
			a.fill(p, Paint.solid(0xFF000000));
			b.fill(p, Paint.solid(0xFF000000), true);
			equals(alpha(a, 5, 5), 255);
			equals(alpha(b, 5, 5), 0);
			equals(alpha(b, 1, 1), 255);
		});
		test("a negative roundRect winds the other way: the two cancel", () -> {
			var p = new Path();
			p.roundRect(0, 0, 10, 10, 0);
			p.roundRect(10, 0, -10, 10, 0);
			var c = new Canvas(10, 10);
			c.fill(p, Paint.solid(0xFF000000));
			equals(alpha(c, 5, 5), 0);
		});
		test("clips intersect, restore takes them back", () -> {
			var c = new Canvas(10, 10);
			c.save();
			c.clipRect(0, 0, 6, 10);
			c.clipRect(4, 0, 6, 10);
			c.fillRect(0, 0, 10, 10, Paint.solid(0xFF000000));
			c.restore();
			equals(alpha(c, 3, 5), 0);
			equals(alpha(c, 5, 5), 255);
			equals(alpha(c, 7, 5), 0);
			c.fillRect(0, 0, 10, 1, Paint.solid(0xFF000000));
			equals(alpha(c, 8, 0), 255);
		});
		test("a layer composites once, at its alpha", () -> {
			var c = new Canvas(4, 4);
			c.saveLayer(0.5);
			c.fillRect(0, 0, 4, 4, Paint.solid(0xFFFF0000));
			c.fillRect(0, 0, 4, 4, Paint.solid(0xFFFF0000));
			c.restore();
			equals(alpha(c, 1, 1), 128);
		});
		test("blend modes: multiply, screen, difference, copy outside the shape", () -> {
			inline function over(blend:Blend.Blender, src:Int):Int {
				var c = new Canvas(2, 2);
				c.fillRect(0, 0, 2, 2, Paint.solid(0xFF808080));
				var p = Paint.solid(src);
				p.blend = blend;
				c.fillRect(0, 0, 1, 2, p);
				return red(c, 0, 0) << 8 | red(c, 1, 0);
			}
			equals(over(Blend.multiply, 0xFF808080), (64 << 8) | 128);
			equals(over(Blend.screen, 0xFF808080), (192 << 8) | 128);
			equals(over(Blend.difference, 0xFFFF0000), (127 << 8) | 128);
			// (copy: unbounded, the pixels it does not cover cleared)
			var c = new Canvas(2, 2);
			c.fillRect(0, 0, 2, 2, Paint.solid(0xFF808080));
			var p = Paint.solid(0xFFFF0000);
			p.blend = Blend.copy;
			c.fillRect(0, 0, 1, 2, p);
			equals(alpha(c, 1, 0), 0);
			equals(red(c, 0, 0), 255);
		});
		test("a linear gradient's ends and middle", () -> {
			var c = new Canvas(100, 1);
			c.fillRect(0, 0, 100, 1, Paint.shaded(new LinearGradient(0, 0, 100, 0).addStop(0, 0xFF000000).addStop(1, 0xFFFFFFFF)));
			equals(red(c, 0, 0), 1);
			equals(red(c, 50, 0), 129);
			equals(red(c, 99, 0), 254);
		});
		test("a stroke's width, butt and square caps", () -> {
			var p = new Path();
			p.moveTo(2, 5);
			p.lineTo(8, 5);
			var c = new Canvas(10, 10), s = new Stroke(2);
			c.stroke(p, s, Paint.solid(0xFF000000));
			equals(alpha(c, 5, 4), 255);
			equals(alpha(c, 5, 3), 0);
			equals(alpha(c, 1, 5), 0);
			s.cap = Cap.square;
			c.stroke(p, s, Paint.solid(0xFF000000));
			equals(alpha(c, 1, 5), 255);
		});
		test("dashes: on and off along a line", () -> {
			var p = new Path();
			p.moveTo(0, 1);
			p.lineTo(12, 1);
			var c = new Canvas(12, 2), s = new Stroke(2);
			s.dash = new Dash([2, 2]);
			c.stroke(p, s, Paint.solid(0xFF000000));
			equals([for (x in 0...12) alpha(c, x, 0) > 128 ? 1 : 0].join(""), "110011001100");
		});
		test("arcs: clockwise, anticlockwise, a whole turn", () -> {
			var p = new Path();
			p.arc(5, 5, 4, 0, Math.PI);
			var c = new Canvas(10, 10);
			c.fill(p, Paint.solid(0xFF000000));
			equals(alpha(c, 5, 7), 255);
			equals(alpha(c, 5, 2), 0);
			p.clear();
			p.arc(5, 5, 4, 0, Math.PI, true);
			c.clear();
			c.fill(p, Paint.solid(0xFF000000));
			equals(alpha(c, 5, 2), 255);
			equals(alpha(c, 5, 7), 0);
			equals(p.verbCount, 3);
		});
		test("an image drawn scaled, nearest and bilinear", () -> {
			var img = Bitmap.fromStraight(2, 1, Bytes.ofHex("000000ffffffffff"));
			var c = new Canvas(4, 1);
			c.drawImage(img, 0, 0, 2, 1, 0, 0, 4, 1, new Paint(), false);
			equals([for (x in 0...4) red(c, x, 0)].join(","), "0,0,255,255");
			c.drawImage(img, 0, 0, 2, 1, 0, 0, 4, 1, new Paint(), true);
			equals([for (x in 0...4) red(c, x, 0)].join(","), "0,64,191,255");
		});
		test("PNG and JPEG round trips", () -> {
			var c = new Canvas(32, 16);
			c.fillRect(0, 0, 32, 16, Paint.shaded(new LinearGradient(0, 0, 32, 0).addStop(0, 0xFF2040C0).addStop(1, 0xFFE0A020)));
			var png = helder.image.PngDecoder.decode(c.toPng());
			equals(png.rgba.toHex(), c.bitmap.straight().toHex());
			var jpg = helder.image.JpegDecoder.decode(c.toJpeg(95));
			var err = 0;
			for (i in 0...32 * 16 * 4)
				err = Std.int(Math.max(err, Math.abs(jpg.rgba.get(i) - png.rgba.get(i))));
			assert(err <= 12, 'JPEG: off by $err');
		});
		test("isPointInPath's winding, on the edge inside", () -> {
			var p = new Path();
			p.rect(0, 0, 10, 10);
			p.rect(2, 2, 6, 6);
			assert(p.contains(5, 5));
			assert(!p.contains(5, 5, true));
			assert(p.contains(10, 5));
			assert(!p.contains(11, 5));
		});
		test("trapezoids tile a self-intersecting star by either rule, as the rasterizer covers it", () -> {
			var p = new Path();
			for (i in 0...5) {
				var a = -Math.PI / 2 + i * 4 * Math.PI / 5;
				if (i == 0) p.moveTo(45 + 42 * Math.cos(a), 60 + 42 * Math.sin(a)) else p.lineTo(45 + 42 * Math.cos(a), 60 + 42 * Math.sin(a));
			}
			p.close();
			for (evenOdd in [false, true]) {
				var t = new Trapezoids(), c = new Canvas(100, 120);
				p.flatten(t, Matrix.IDENTITY, 0.1);
				t.build(evenOdd);
				c.fill(p, Paint.solid(0xFF000000), evenOdd);
				var covered = 0.0;
				for (i in 0...100 * 120)
					covered += c.bitmap.pixels.get(i * 4 + 3) / 255;
				approx(t.area(), covered, 2.0);
			}
		});
		test("drawing allocates nothing", () -> {
			var c = new Canvas(64, 64), p = new Path(), s = new Stroke(3), paint = Paint.solid(0xFF336699);
			var g = new LinearGradient(0, 0, 64, 0).addStop(0, 0xFF000000).addStop(1, 0xFFFFFFFF), gp = Paint.shaded(g);
			s.join = Join.round;
			s.dash = new Dash([5, 3]);
			inline function frame(k:Int) {
				p.clear();
				p.moveTo(4, 4);
				p.cubicTo(60, 4, 4, 60, 60, 60);
				p.arc(32, 32, 10 + k % 5, 0, 5);
				c.save();
				c.translate(1, 1);
				c.clipRect(2, 2, 60, 60);
				c.fill(p, gp);
				c.stroke(p, s, paint);
				c.saveLayer(0.5);
				c.fillRect(8, 8, 20, 20, paint);
				c.restore();
				c.restore();
			}
			// (the buffers grown to the largest frame first)
			for (k in 0...5)
				frame(k);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 0...200)
				frame(k);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
		});
	});
}

private function alpha(c:Canvas, x:Int, y:Int):Int
	return c.bitmap.pixels.get((y * c.width + x) * 4 + 3);

private function red(c:Canvas, x:Int, y:Int):Int
	return c.bitmap.pixels.get((y * c.width + x) * 4);
