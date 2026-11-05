package helder.image;

import haxe.io.Bytes;
import hxmc.simd.*;

// RGBA8 images made smaller on the CPU: half (each pixel the mean of four,
// straight alpha weighted by it), two output pixels at once where all four
// sources of both are opaque (hxmc.simd: sums of 16-bit lanes), the rest
// one by one; toFit halves until the image is within w x h.
class Resize {
	public static function half(src:Bytes, w:Int, h:Int, ?mem:ImageMemory):{width:Int, height:Int, rgba:Bytes} {
		var nw = (w + 1) >> 1, nh = (h + 1) >> 1, out = (mem ?? ImageMemory.gc).bytes(nw * nh * 4);
		var two = U16x8.splat(2), opaque = I32x4.splat(-1);
		for (y in 0...nh) {
			GcPoint.poll();
			var y0 = 2 * y, y1 = Std.int(Math.min(2 * y + 1, h - 1)), x = 0;
			// (pairs of output pixels while four source pixels a row remain)
			while (2 * x + 4 <= w) {
				var a = U8x16.load(src, 4 * (y0 * w + 2 * x)), b = U8x16.load(src, 4 * (y1 * w + 2 * x));
				if (((a.asI32x4() | I32x4.splat(0xFFFFFF)) & (b.asI32x4() | I32x4.splat(0xFFFFFF))).eq(opaque).all()) {
					var s0 = U16x8.extendLow(a) + U16x8.extendLow(b), s1 = U16x8.extendHigh(a) + U16x8.extendHigh(b);
					// (lanes 0-3 and 4-7: a pixel each; the pairs side by side summed)
					var sum = s0.shuffle(s1, 0, 1, 2, 3, 8, 9, 10, 11) + s0.shuffle(s1, 4, 5, 6, 7, 12, 13, 14, 15);
					U8x16.narrow(((sum + two) >>> 2).asI16x8(), I16x8.zero()).store64(out, 4 * (y * nw + x));
				} else {
					one(src, w, h, out, nw, x, y);
					one(src, w, h, out, nw, x + 1, y);
				}
				x += 2;
			}
			while (x < nw) {
				one(src, w, h, out, nw, x, y);
				x++;
			}
		}
		return {width: nw, height: nh, rgba: out};
	}

	// halved until within w x h (the image itself when it is)
	public static function toFit(src:Bytes, width:Int, height:Int, w:Int, h:Int, ?mem:ImageMemory):{width:Int, height:Int, rgba:Bytes} {
		var r = {width: width, height: height, rgba: src};
		while (r.width > w || r.height > h)
			r = half(r.rgba, r.width, r.height, mem);
		return r;
	}

	// (one output pixel: the alpha-weighted mean of its four sources)
	static inline function one(src:Bytes, w:Int, h:Int, out:Bytes, nw:Int, x:Int, y:Int) {
		var r = 0, g = 0, b = 0, a = 0;
		for (dy in 0...2)
			for (dx in 0...2) {
				var sx = Std.int(Math.min(2 * x + dx, w - 1)), sy = Std.int(Math.min(2 * y + dy, h - 1)), p = 4 * (sy * w + sx);
				var pa = src.get(p + 3);
				r += src.get(p) * pa;
				g += src.get(p + 1) * pa;
				b += src.get(p + 2) * pa;
				a += pa;
			}
		var o = 4 * (y * nw + x);
		if (a > 0) {
			out.set(o, Std.int(r / a + 0.5));
			out.set(o + 1, Std.int(g / a + 0.5));
			out.set(o + 2, Std.int(b / a + 0.5));
		}
		out.set(o + 3, (a + 2) >> 2);
	}
}
