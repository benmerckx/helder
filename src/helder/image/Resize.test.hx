package helder.image;

import haxe.io.Bytes;
import helder.test.Test;

// Resize.half: the SIMD pairs (opaque) and the weighted pixels give what
// the mean of four, weighted by alpha, gives; odd sides; toFit's sizes
function tests() {
	describe("Resize", () -> {
		function image(w:Int, h:Int, alpha:Bool):Bytes {
			var b = Bytes.alloc(w * h * 4), seed = 3;
			for (i in 0...w * h * 4) {
				seed = (seed * 1103515245 + 12345) & 0x7fffffff;
				b.set(i, (i & 3) == 3 && !alpha ? 255 : (seed >> 16) & 255);
			}
			return b;
		}
		function reference(src:Bytes, w:Int, h:Int):Bytes {
			var nw = (w + 1) >> 1, nh = (h + 1) >> 1, out = Bytes.alloc(nw * nh * 4);
			for (y in 0...nh)
				for (x in 0...nw) {
					var r = 0, g = 0, b = 0, a = 0;
					for (dy in 0...2)
						for (dx in 0...2) {
							var p = 4 * (Std.int(Math.min(2 * y + dy, h - 1)) * w + Std.int(Math.min(2 * x + dx, w - 1))), pa = src.get(p + 3);
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
			return out;
		}
		for (c in [{w: 64, h: 32, alpha: false}, {w: 37, h: 29, alpha: false}, {w: 40, h: 22, alpha: true}, {w: 1, h: 1, alpha: false}, {w: 3, h: 7, alpha: true}])
			test('${c.w}x${c.h}${c.alpha ? " with alpha" : ""}: the mean of four', () -> {
				var src = image(c.w, c.h, c.alpha);
				var r = Resize.half(src, c.w, c.h);
				equals([r.width, r.height], [(c.w + 1) >> 1, (c.h + 1) >> 1]);
				// (the opaque pairs' rounding: (sum + 2) >> 2, the weighted one's to nearest: within a level)
				var want = reference(src, c.w, c.h), worst = 0;
				for (i in 0...want.length)
					worst = Std.int(Math.max(worst, Math.abs(want.get(i) - r.rgba.get(i))));
				assert(worst <= 1, 'off by $worst');
			});
		test("toFit: halved until within", () -> {
			var r = Resize.toFit(image(100, 60, false), 100, 60, 30, 30);
			equals([r.width, r.height], [25, 15]);
		});
	});
}
