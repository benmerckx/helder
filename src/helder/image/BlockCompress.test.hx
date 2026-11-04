package helder.image;

import haxe.io.Bytes;
import helder.test.Test;

// BlockCompress's blocks read back (its decode, the subset it writes):
// BC1, BC3 and ASTC 4x4 of a gradient with noise and edges within a few
// levels of the image (PSNR), a flat block exact, alpha kept by BC3 and
// ASTC's RGBA blocks, the mip chain's sizes, blocks past an edge. The GPU's
// own decoders read them in the 3d lane ("compressed": tests/3d/Scenes.hx).
function tests() {
	describe("BlockCompress", () -> {
		// a w x h image: gradients, a hard edge, a little noise; alpha a ramp when asked
		function image(w:Int, h:Int, alpha:Bool):Bytes {
			var b = Bytes.alloc(w * h * 4), seed = 7;
			for (y in 0...h)
				for (x in 0...w) {
					seed = (seed * 1103515245 + 12345) & 0x7fffffff;
					var n = (seed >> 16) % 9 - 4, p = 4 * (y * w + x);
					b.set(p, Std.int(Math.max(0, Math.min(255, x * 255 / w + n))));
					b.set(p + 1, Std.int(Math.max(0, Math.min(255, (x > w / 2 ? 200 : 40) + n))));
					b.set(p + 2, Std.int(y * 255 / h));
					b.set(p + 3, alpha ? Std.int(x * 255 / w) : 255);
				}
			return b;
		}
		function psnr(a:Bytes, b:Bytes, channels:Int):Float {
			var se = 0.0, n = 0;
			for (k in 0...Std.int(a.length / 4))
				for (c in 0...channels) {
					var d = a.get(k * 4 + c) - b.get(k * 4 + c);
					se += d * d;
					n++;
				}
			return se == 0 ? 99 : 10 * Math.log(255 * 255 / (se / n)) / Math.log(10);
		}
		for (f in ["bc1", "bc3", "astc"])
			test('$f: a round trip within a few levels', () -> {
				var alpha = f != "bc1", src = image(64, 32, alpha);
				var blocks = BlockCompress.encode(src, 64, 32, f);
				equals(blocks.length, 16 * 8 * BlockCompress.blockBytes(f));
				var back = BlockCompress.decode(blocks, 64, 32, f);
				var q = psnr(src, back, alpha ? 4 : 3);
				assert(q > 30, '$f: PSNR $q dB');
			});
		test("a flat colour exact (ASTC), within 565's step (BC1)", () -> {
			var src = Bytes.alloc(16 * 4);
			for (k in 0...16) {
				src.set(k * 4, 200);
				src.set(k * 4 + 1, 100);
				src.set(k * 4 + 2, 30);
				src.set(k * 4 + 3, 255);
			}
			var a = BlockCompress.decode(BlockCompress.encode(src, 4, 4, "astc"), 4, 4, "astc");
			equals(a.toHex(), src.toHex());
			var b = BlockCompress.decode(BlockCompress.encode(src, 4, 4, "bc1"), 4, 4, "bc1");
			assert(Math.abs(b.get(0) - 200) <= 4 && Math.abs(b.get(1) - 100) <= 2 && Math.abs(b.get(2) - 30) <= 4, "565's step");
		});
		test("ASTC: the block modes and colour endpoint modes it writes", () -> {
			var rgb = BlockCompress.encode(image(4, 4, false), 4, 4, "astc"), rgba = BlockCompress.encode(image(4, 4, true), 4, 4, "astc");
			// (11 bits of block mode, 2 of partitions, 4 of CEM)
			equals(rgb.getUInt16(0) & 0x7ff, 83);
			equals((rgb.getInt32(0) >> 13) & 15, 8);
			equals(rgba.getUInt16(0) & 0x7ff, 66);
			equals((rgba.getInt32(0) >> 13) & 15, 12);
		});
		test("the mip chain: every level down to 1x1, blocks past the edges", () -> {
			var levels = BlockCompress.mips(image(16, 8, false), 16, 8, "bc1");
			equals(levels.length, 5);
			equals([for (l in levels) l.length].join(","), "64,16,8,8,8");
			var odd = BlockCompress.encode(image(6, 5, false), 6, 5, "astc");
			equals(odd.length, 4 * 16);
			equals(BlockCompress.decode(odd, 6, 5, "astc").length, 6 * 5 * 4);
		});
		test("hasAlpha", () -> {
			assert(!BlockCompress.hasAlpha(image(4, 4, false)));
			assert(BlockCompress.hasAlpha(image(4, 4, true)));
		});
	});
}
