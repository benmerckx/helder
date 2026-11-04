package helder.image;

import haxe.io.Bytes;

// GPU block compression of RGBA8 images, for the asset step (helder.scene's
// Pack: --textures bc or astc): an image's mip chain (2x2 boxes, as
// helder.scene's Images.mipmapped) and each level in 4x4 blocks of
//
// - BC1 (8 bytes a block, 4 bits a texel: desktops, the web where WebGPU
//   has texture-compression-bc or WebGL2 WEBGL_compressed_texture_s3tc):
//   two RGB565 colours and 2-bit indices, opaque;
// - BC3 (16 bytes: BC1's colours after an alpha block of two 8-bit alphas
//   and 3-bit indices), for images with alpha;
// - ASTC 4x4 (16 bytes, 8 bits a texel: phones' GPUs, Apple's, WebGPU's
//   texture-compression-astc): one partition of LDR endpoints at 8 bits,
//   RGB direct (CEM 8) with 3-bit weights, or RGBA direct (CEM 12) with
//   2-bit weights; endpoints ordered so the decoder never blue-contracts.
//
// Each block's endpoints are its colours' principal axis' extremes (a few
// power iterations of their covariance), its indices the nearest of the
// palette. A fast encoder of fair quality, not astcenc's or bc7enc's search.
// decode reads them back (tests: the error of a round trip).
class BlockCompress {
	// the levels of a width x height RGBA8 image (rows top to bottom), down to
	// 1x1, each as blocks of format "bc1", "bc3" or "astc"
	public static function mips(rgba:Bytes, width:Int, height:Int, format:String):Array<Bytes> {
		var out = [];
		var w = width, h = height, src = rgba;
		while (true) {
			out.push(encode(src, w, h, format));
			if (w == 1 && h == 1) break;
			var nw = w > 1 ? w >> 1 : 1, nh = h > 1 ? h >> 1 : 1;
			var dst = Bytes.alloc(nw * nh * 4);
			for (y in 0...nh)
				for (x in 0...nw) {
					var x0 = w > 1 ? 2 * x : 0, y0 = h > 1 ? 2 * y : 0, x1 = w > 1 ? x0 + 1 : x0, y1 = h > 1 ? y0 + 1 : y0;
					for (c in 0...4) {
						var sum = src.get(4 * (y0 * w + x0) + c) + src.get(4 * (y0 * w + x1) + c) + src.get(4 * (y1 * w + x0) + c) + src.get(4 * (y1 * w + x1) + c);
						dst.set(4 * (y * nw + x) + c, (sum + 2) >> 2);
					}
				}
			w = nw;
			h = nh;
			src = dst;
		}
		return out;
	}

	// whether an image has a texel not opaque
	public static function hasAlpha(rgba:Bytes):Bool {
		var i = 3;
		while (i < rgba.length) {
			if (rgba.get(i) != 255) return true;
			i += 4;
		}
		return false;
	}

	// the bytes of a block of the format
	public static inline function blockBytes(format:String):Int
		return format == "bc1" ? 8 : 16;

	// one level's blocks (ceil(w / 4) x ceil(h / 4), rows of them top to
	// bottom; texels past the edge repeat its last)
	public static function encode(rgba:Bytes, width:Int, height:Int, format:String):Bytes {
		var bw = (width + 3) >> 2, bh = (height + 3) >> 2, size = blockBytes(format);
		var out = Bytes.alloc(bw * bh * size);
		var block = new haxe.ds.Vector<Int>(64);
		var e = new Encoder();
		for (by in 0...bh)
			for (bx in 0...bw) {
				for (k in 0...16) {
					var x = bx * 4 + (k & 3), y = by * 4 + (k >> 2);
					if (x >= width) x = width - 1;
					if (y >= height) y = height - 1;
					var p = 4 * (y * width + x);
					for (c in 0...4)
						block[k * 4 + c] = rgba.get(p + c);
				}
				var at = (by * bw + bx) * size;
				switch format {
					case "bc1": e.bc1(block, out, at);
					case "bc3":
						e.bc3Alpha(block, out, at);
						e.bc1(block, out, at + 8);
					case "astc": e.astc(block, out, at);
					case f: throw 'BlockCompress: no format $f';
				}
			}
		return out;
	}

	// a level's blocks back to RGBA8 (width x height)
	public static function decode(blocks:Bytes, width:Int, height:Int, format:String):Bytes {
		var bw = (width + 3) >> 2, bh = (height + 3) >> 2, size = blockBytes(format);
		var out = Bytes.alloc(width * height * 4);
		var px = new haxe.ds.Vector<Int>(64);
		for (by in 0...bh)
			for (bx in 0...bw) {
				var at = (by * bw + bx) * size;
				switch format {
					case "bc1": Decoder.bc1(blocks, at, px, false);
					case "bc3":
						Decoder.bc1(blocks, at + 8, px, true);
						Decoder.bc3Alpha(blocks, at, px);
					case _: Decoder.astc(blocks, at, px);
				}
				for (k in 0...16) {
					var x = bx * 4 + (k & 3), y = by * 4 + (k >> 2);
					if (x >= width || y >= height) continue;
					for (c in 0...4)
						out.set(4 * (y * width + x) + c, px[k * 4 + c]);
				}
			}
		return out;
	}
}

// (an encoder's scratch: a block's endpoints along its principal axis)
private class Encoder {
	// the endpoints found (0..255 each, rgba), and the projection's extremes
	final lo = [0.0, 0.0, 0.0, 0.0];
	final hi = [0.0, 0.0, 0.0, 0.0];
	final index = new haxe.ds.Vector<Int>(16);

	public function new() {}

	// lo and hi: the block's colours' extremes along their principal axis
	// (channels: 3, rgb; 4, rgba)
	function axis(b:haxe.ds.Vector<Int>, channels:Int) {
		var mean = [0.0, 0.0, 0.0, 0.0];
		for (k in 0...16)
			for (c in 0...channels)
				mean[c] += b[k * 4 + c] / 16;
		var cov = [for (_ in 0...16) 0.0];
		for (k in 0...16)
			for (i in 0...channels)
				for (j in 0...channels)
					cov[i * 4 + j] += (b[k * 4 + i] - mean[i]) * (b[k * 4 + j] - mean[j]);
		// (power iteration from the diagonal's largest: the principal axis)
		var v = [1.0, 1.0, 1.0, channels == 4 ? 1.0 : 0.0];
		for (_ in 0...6) {
			var n = [0.0, 0.0, 0.0, 0.0], len = 0.0;
			for (i in 0...channels) {
				for (j in 0...channels)
					n[i] += cov[i * 4 + j] * v[j];
				len += n[i] * n[i];
			}
			if (len < 1e-9) break;
			len = Math.sqrt(len);
			for (i in 0...channels)
				v[i] = n[i] / len;
		}
		var tmin = 1e9, tmax = -1e9;
		for (k in 0...16) {
			var t = 0.0;
			for (c in 0...channels)
				t += (b[k * 4 + c] - mean[c]) * v[c];
			if (t < tmin) tmin = t;
			if (t > tmax) tmax = t;
		}
		var vl = 0.0;
		for (c in 0...channels)
			vl += v[c] * v[c];
		if (vl < 1e-9) tmin = tmax = 0;
		for (c in 0...4) {
			var m = c < channels ? mean[c] : 255;
			var d = c < channels ? v[c] : 0;
			lo[c] = clamp(m + d * tmin);
			hi[c] = clamp(m + d * tmax);
		}
	}

	static inline function clamp(x:Float):Float
		return x < 0 ? 0 : x > 255 ? 255 : x;

	// the nearest of n palette colours (pal: n * 4, rgba; channels compared)
	function nearest(b:haxe.ds.Vector<Int>, pal:Array<Int>, n:Int, channels:Int) {
		for (k in 0...16) {
			var best = 0, bd = 1 << 30;
			for (i in 0...n) {
				var d = 0;
				for (c in 0...channels) {
					var x = b[k * 4 + c] - pal[i * 4 + c];
					d += x * x;
				}
				if (d < bd) {
					bd = d;
					best = i;
				}
			}
			index[k] = best;
		}
	}

	static inline function to565(r:Float, g:Float, b:Float):Int
		return (Math.round(r * 31 / 255) << 11) | (Math.round(g * 63 / 255) << 5) | Math.round(b * 31 / 255);

	public function bc1(b:haxe.ds.Vector<Int>, out:Bytes, at:Int) {
		axis(b, 3);
		var c0 = to565(hi[0], hi[1], hi[2]), c1 = to565(lo[0], lo[1], lo[2]);
		if (c0 < c1) {
			var t = c0;
			c0 = c1;
			c1 = t;
		}
		out.setUInt16(at, c0);
		out.setUInt16(at + 2, c1);
		var bits = 0;
		if (c0 != c1) {
			var p0 = Decoder.rgb565(c0), p1 = Decoder.rgb565(c1);
			// (index 0: c0, 1: c1, 2: two thirds c0, 3: two thirds c1)
			var pal = [p0[0], p0[1], p0[2], 0, p1[0], p1[1], p1[2], 0, Std.int((2 * p0[0] + p1[0]) / 3), Std.int((2 * p0[1] + p1[1]) / 3),
				Std.int((2 * p0[2] + p1[2]) / 3), 0, Std.int((p0[0] + 2 * p1[0]) / 3), Std.int((p0[1] + 2 * p1[1]) / 3), Std.int((p0[2] + 2 * p1[2]) / 3), 0];
			nearest(b, pal, 4, 3);
			for (k in 0...16)
				bits |= index[k] << (2 * k);
		}
		out.setInt32(at + 4, bits);
	}

	public function bc3Alpha(b:haxe.ds.Vector<Int>, out:Bytes, at:Int) {
		var a0 = 0, a1 = 255;
		for (k in 0...16) {
			var a = b[k * 4 + 3];
			if (a > a0) a0 = a;
			if (a < a1) a1 = a;
		}
		out.set(at, a0);
		out.set(at + 1, a1);
		var bits = haxe.Int64.ofInt(0);
		if (a0 != a1) {
			// (8 alphas: a0, a1, then six between)
			var pal = [a0, a1];
			for (i in 1...7)
				pal.push(Std.int(((7 - i) * a0 + i * a1) / 7));
			for (k in 0...16) {
				var a = b[k * 4 + 3], best = 0, bd = 999;
				for (i in 0...8) {
					var d = a > pal[i] ? a - pal[i] : pal[i] - a;
					if (d < bd) {
						bd = d;
						best = i;
					}
				}
				bits = haxe.Int64.or(bits, haxe.Int64.shl(haxe.Int64.ofInt(best), 3 * k));
			}
		}
		for (i in 0...6)
			out.set(at + 2 + i, haxe.Int64.toInt(haxe.Int64.and(haxe.Int64.shr(bits, 8 * i), haxe.Int64.ofInt(255))));
	}

	public function astc(b:haxe.ds.Vector<Int>, out:Bytes, at:Int) {
		var alpha = false;
		for (k in 0...16)
			if (b[k * 4 + 3] != 255) alpha = true;
		var channels = alpha ? 4 : 3;
		axis(b, channels);
		var e0 = [for (c in 0...4) Math.round(lo[c])], e1 = [for (c in 0...4) Math.round(hi[c])];
		// (the decoder swaps and blue-contracts when the second's sum is the smaller: keep it the larger)
		if (e1[0] + e1[1] + e1[2] < e0[0] + e0[1] + e0[2]) {
			var t = e0;
			e0 = e1;
			e1 = t;
		}
		var levels = alpha ? 4 : 8;
		var weights = alpha ? Decoder.W2 : Decoder.W3;
		var pal = [];
		for (i in 0...levels)
			for (c in 0...4)
				pal.push((e0[c] * (64 - weights[i]) + e1[c] * weights[i] + 32) >> 6);
		nearest(b, pal, levels, channels);
		for (i in 0...16)
			out.set(at + i, 0);
		var bit = 0;
		function put(v:Int, n:Int) {
			for (j in 0...n) {
				if ((v >> j) & 1 == 1) out.set(at + ((bit + j) >> 3), out.get(at + ((bit + j) >> 3)) | (1 << ((bit + j) & 7)));
			}
			bit += n;
		}
		// (block mode: a 4x4 weight grid, one plane; QUANT_8 (R 7) or QUANT_4 (R 4))
		put(alpha ? 66 : 83, 11);
		put(0, 2); // one partition
		put(alpha ? 12 : 8, 4); // CEM: RGBA direct, RGB direct
		for (c in 0...channels) {
			put(e0[c], 8);
			put(e1[c], 8);
		}
		// (the weights from the block's top bit down)
		var wbits = alpha ? 2 : 3, k = 0;
		for (i in 0...16)
			for (j in 0...wbits) {
				if ((index[i] >> j) & 1 == 1) {
					var p = 127 - k;
					out.set(at + (p >> 3), out.get(at + (p >> 3)) | (1 << (p & 7)));
				}
				k++;
			}
	}
}

// (the blocks read back, the subset the encoder writes for ASTC)
private class Decoder {
	// the weights' values (of 64) by index: 3 bits, 2 bits
	public static final W3 = [0, 9, 18, 27, 37, 46, 55, 64];
	public static final W2 = [0, 21, 43, 64];

	public static function rgb565(c:Int):Array<Int>
		return [Math.round(((c >> 11) & 31) * 255 / 31), Math.round(((c >> 5) & 63) * 255 / 63), Math.round((c & 31) * 255 / 31)];

	public static function bc1(b:Bytes, at:Int, px:haxe.ds.Vector<Int>, four:Bool) {
		var c0 = b.getUInt16(at), c1 = b.getUInt16(at + 2), bits = b.getInt32(at + 4);
		var p0 = rgb565(c0), p1 = rgb565(c1);
		for (k in 0...16) {
			var i = (bits >>> (2 * k)) & 3;
			for (c in 0...3)
				px[k * 4 + c] = switch i {
					case 0: p0[c];
					case 1: p1[c];
					case 2: four || c0 > c1 ? Std.int((2 * p0[c] + p1[c]) / 3) : (p0[c] + p1[c]) >> 1;
					case _: four || c0 > c1 ? Std.int((p0[c] + 2 * p1[c]) / 3) : 0;
				}
			px[k * 4 + 3] = !four && c0 <= c1 && i == 3 ? 0 : 255;
		}
	}

	public static function bc3Alpha(b:Bytes, at:Int, px:haxe.ds.Vector<Int>) {
		var a0 = b.get(at), a1 = b.get(at + 1);
		for (k in 0...16) {
			var bitAt = 16 + 3 * k, i = 0;
			for (j in 0...3)
				i |= ((b.get(at + ((bitAt + j) >> 3)) >> ((bitAt + j) & 7)) & 1) << j;
			px[k * 4 + 3] = i == 0 ? a0 : i == 1 ? a1 : a0 > a1 ? Std.int(((8 - i) * a0 + (i - 1) * a1) / 7) : i == 6 ? 0 : i == 7 ? 255 : Std.int(((6 - i) * a0
				+ (i - 1) * a1) / 5);
		}
	}

	static function bits(b:Bytes, at:Int, from:Int, n:Int):Int {
		var v = 0;
		for (j in 0...n)
			v |= ((b.get(at + ((from + j) >> 3)) >> ((from + j) & 7)) & 1) << j;
		return v;
	}

	public static function astc(b:Bytes, at:Int, px:haxe.ds.Vector<Int>) {
		var mode = bits(b, at, 0, 11), cem = bits(b, at, 13, 4);
		var alpha = cem == 12, channels = alpha ? 4 : 3;
		if ((mode != 66 && mode != 83) || (cem != 8 && cem != 12)) throw "BlockCompress: an ASTC block of another kind";
		var e0 = [0, 0, 0, 255], e1 = [0, 0, 0, 255];
		for (c in 0...channels) {
			e0[c] = bits(b, at, 17 + 16 * c, 8);
			e1[c] = bits(b, at, 25 + 16 * c, 8);
		}
		var wbits = mode == 66 ? 2 : 3, table = mode == 66 ? W2 : W3;
		for (k in 0...16) {
			var i = 0;
			for (j in 0...wbits) {
				var p = 127 - (k * wbits + j);
				i |= ((b.get(at + (p >> 3)) >> (p & 7)) & 1) << j;
			}
			var w = table[i];
			for (c in 0...4)
				px[k * 4 + c] = (e0[c] * (64 - w) + e1[c] * w + 32) >> 6;
		}
	}
}
