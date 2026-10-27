package helder.image;

import haxe.io.Bytes;
import haxe.ds.Vector;

// A VP8 key frame (lossy WebP) decoded to RGBA8 as libwebp decodes it
// (RFC 6386; libwebp's integer arithmetic throughout): the frame header
// (segments, loop filter, quantizers, the coefficients' probabilities) and
// the first partition's modes by the boolean decoder, the macroblocks'
// coefficients from the token partitions (contexts, dequantized), each
// predicted (16x16, chroma 8x8 or 4x4 subblocks; out of the frame 127
// above and 129 to the left, as libwebp's work buffer has them) and its
// residue added (the Walsh-Hadamard transform of the DCs, the inverse
// DCT); then the loop filter (simple or normal) over the frame, and the
// colours by libwebp's fancy upsampler and fixed-point YUV to RGB.
class Vp8Decoder {
	static final ZIGZAG = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15];
	static final BANDS = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0];
	static final CAT3 = [173, 148, 140];
	static final CAT4 = [176, 155, 140, 135];
	static final CAT5 = [180, 157, 141, 134, 130];
	static final CAT6 = [254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129];
	// the subblock modes' tree (RFC 6386's order: DC, TM, VE, HE, LD, RD, VR, VL, HD, HU)
	static final BMODE_TREE = [0, 2, -1, 4, -2, 6, 8, 12, -3, 10, -5, -6, -4, 14, -7, 16, -8, -9];
	static inline var DC = 0;
	static inline var TM = 1;
	static inline var VE = 2;
	static inline var HE = 3;
	static inline var LD = 4;
	static inline var RD = 5;
	static inline var VR = 6;
	static inline var VL = 7;
	static inline var HD = 8;
	static inline var HU = 9;
	static inline var BPS = 32;

	public static function decode(data:Bytes, at:Int, size:Int):{width:Int, height:Int, rgba:Bytes}
		return new Vp8Decoder(data, at, size).run();

	final data:Bytes;
	final at:Int;
	final size:Int;
	var width = 0;
	var height = 0;
	var mbw = 0;
	var mbh = 0;
	// the planes, whole macroblocks (unfiltered while decoding)
	var Y:Bytes;
	var U:Bytes;
	var V:Bytes;
	var ys = 0;
	var uvs = 0;
	// header
	var useSegment = false;
	var updateMap = false;
	var absoluteDelta = false;
	final quantizer = [0, 0, 0, 0];
	final filterStrength = [0, 0, 0, 0];
	final segmentProbs = [255, 255, 255];
	var simple = false;
	var level = 0;
	var sharpness = 0;
	var useLfDelta = false;
	final refLfDelta = [0, 0, 0, 0];
	final modeLfDelta = [0, 0, 0, 0];
	var filterType = 0;
	final probs = new Vector<Int>(4 * 8 * 3 * 11);
	var useSkip = false;
	var skipProb = 0;
	// per segment: y1 dc, y1 ac, y2 dc, y2 ac, uv dc, uv ac
	final dq = [for (i in 0...24) 0];

	function new(data:Bytes, at:Int, size:Int) {
		this.data = data;
		this.at = at;
		this.size = size;
	}

	function run():{width:Int, height:Int, rgba:Bytes} {
		if (size < 10) throw "WebpDecoder: a VP8 frame too short";
		var bits = data.get(at) | (data.get(at + 1) << 8) | (data.get(at + 2) << 16);
		if (bits & 1 != 0) throw "WebpDecoder: not a key frame";
		var first = bits >> 5;
		if (data.get(at + 3) != 0x9D || data.get(at + 4) != 0x01 || data.get(at + 5) != 0x2A) throw "WebpDecoder: no VP8 start code";
		width = (data.get(at + 6) | (data.get(at + 7) << 8)) & 0x3FFF;
		height = (data.get(at + 8) | (data.get(at + 9) << 8)) & 0x3FFF;
		if (width == 0 || height == 0) throw "WebpDecoder: an empty frame";
		mbw = (width + 15) >> 4;
		mbh = (height + 15) >> 4;
		ys = mbw * 16;
		uvs = mbw * 8;
		Y = Bytes.alloc(ys * mbh * 16);
		U = Bytes.alloc(uvs * mbh * 8);
		V = Bytes.alloc(uvs * mbh * 8);
		var p = at + 10;
		var br = new BoolDecoder(data, p, p + first);
		header(br);
		// the token partitions
		var count = 1 << br.literal(2);
		var sizes = p + first, start = sizes + 3 * (count - 1), end = at + size;
		var parts:Array<BoolDecoder> = [];
		for (i in 0...count) {
			var len = i < count - 1 ? data.get(sizes + 3 * i) | (data.get(sizes + 3 * i + 1) << 8) | (data.get(sizes + 3 * i + 2) << 16) : end - start;
			var e = start + len > end ? end : start + len;
			parts.push(new BoolDecoder(data, start, e));
			start = e;
		}
		quant(br);
		br.bit(128); // (refresh_entropy_probs)
		for (i in 0...probs.length)
			probs[i] = br.bit(Vp8Tables.COEFF_UPDATE[i]) == 1 ? br.literal(8) : Vp8Tables.COEFF_DEFAULT[i];
		useSkip = br.bit(128) == 1;
		if (useSkip) skipProb = br.literal(8);
		macroblocks(br, parts);
		if (filterType > 0) filter();
		return rgb();
	}

	function header(br:BoolDecoder) {
		br.bit(128); // (colour space)
		br.bit(128); // (clamping type)
		useSegment = br.bit(128) == 1;
		if (useSegment) {
			updateMap = br.bit(128) == 1;
			if (br.bit(128) == 1) {
				absoluteDelta = br.bit(128) == 1;
				for (s in 0...4)
					quantizer[s] = br.bit(128) == 1 ? br.signed(7) : 0;
				for (s in 0...4)
					filterStrength[s] = br.bit(128) == 1 ? br.signed(6) : 0;
			}
			if (updateMap)
				for (s in 0...3)
					segmentProbs[s] = br.bit(128) == 1 ? br.literal(8) : 255;
		}
		simple = br.bit(128) == 1;
		level = br.literal(6);
		sharpness = br.literal(3);
		useLfDelta = br.bit(128) == 1;
		if (useLfDelta && br.bit(128) == 1) {
			for (i in 0...4)
				if (br.bit(128) == 1) refLfDelta[i] = br.signed(6);
			for (i in 0...4)
				if (br.bit(128) == 1) modeLfDelta[i] = br.signed(6);
		}
		filterType = level == 0 ? 0 : simple ? 1 : 2;
	}

	function quant(br:BoolDecoder) {
		var base = br.literal(7);
		inline function delta():Int
			return br.bit(128) == 1 ? br.signed(4) : 0;
		var y1dc = delta(), y2dc = delta(), y2ac = delta(), uvdc = delta(), uvac = delta();
		inline function clip(v:Int, m:Int):Int
			return v < 0 ? 0 : v > m ? m : v;
		for (s in 0...4) {
			var q = base;
			if (useSegment) {
				q = quantizer[s];
				if (!absoluteDelta) q += base;
			}
			var o = 6 * s;
			dq[o] = Vp8Tables.DC_Q[clip(q + y1dc, 127)];
			dq[o + 1] = Vp8Tables.AC_Q[clip(q, 127)];
			dq[o + 2] = Vp8Tables.DC_Q[clip(q + y2dc, 127)] * 2;
			var ac2 = (Vp8Tables.AC_Q[clip(q + y2ac, 127)] * 101581) >> 16;
			dq[o + 3] = ac2 < 8 ? 8 : ac2;
			dq[o + 4] = Vp8Tables.DC_Q[clip(q + uvdc, 117)];
			dq[o + 5] = Vp8Tables.AC_Q[clip(q + uvac, 127)];
		}
	}

	// --- macroblocks ---

	// per macroblock: its segment, whether it is 4x4 predicted, its filter's inner edges
	var segments:Vector<Int>;
	var i4x4:Vector<Bool>;
	var inner:Vector<Bool>;

	function macroblocks(br:BoolDecoder, parts:Array<BoolDecoder>) {
		segments = new Vector(mbw * mbh);
		i4x4 = new Vector(mbw * mbh);
		inner = new Vector(mbw * mbh);
		// the modes' contexts: each column's bottom subblock modes, the row's right ones
		var intraT = [for (i in 0...4 * mbw) DC];
		var intraL = [DC, DC, DC, DC];
		// the coefficients' non-zero contexts: Y (4), U (2), V (2), Y2 per column; and the left's
		var topNz = [for (i in 0...9 * mbw) 0];
		var leftNz = [for (i in 0...9) 0];
		var coeffs = new Vector<Int>(384);
		var modes = [for (i in 0...16) 0];
		var ws = Bytes.alloc(BPS * 17), wu = Bytes.alloc(BPS * 9), wv = Bytes.alloc(BPS * 9);
		for (my in 0...mbh) {
			for (i in 0...4)
				intraL[i] = DC;
			for (i in 0...9)
				leftNz[i] = 0;
			var tokens = parts[my & (parts.length - 1)];
			for (mx in 0...mbw) {
				var mb = my * mbw + mx;
				// modes (the first partition)
				var segment = updateMap ? (br.bit(segmentProbs[0]) == 0 ? br.bit(segmentProbs[1]) : 2 + br.bit(segmentProbs[2])) : 0;
				var skip = useSkip ? br.bit(skipProb) == 1 : false;
				var is4 = br.bit(145) == 0;
				var ymode = DC;
				if (!is4) {
					ymode = br.bit(156) == 1 ? (br.bit(128) == 1 ? TM : HE) : (br.bit(163) == 1 ? VE : DC);
					for (i in 0...4) {
						intraT[4 * mx + i] = ymode;
						intraL[i] = ymode;
					}
				} else {
					for (y in 0...4) {
						var left = intraL[y];
						for (x in 0...4) {
							var above = intraT[4 * mx + x];
							var o = (above * 10 + left) * 9;
							var i = 0;
							do
								i = BMODE_TREE[i + br.bit(Vp8Tables.BMODE[o + (i >> 1)])]
							while (i > 0);
							left = -i;
							intraT[4 * mx + x] = left;
							modes[4 * y + x] = left;
						}
						intraL[y] = left;
					}
				}
				var uvmode = br.bit(142) == 0 ? DC : br.bit(114) == 0 ? VE : br.bit(183) == 1 ? TM : HE;
				segments[mb] = segment;
				i4x4[mb] = is4;
				// coefficients (the row's token partition)
				for (i in 0...384)
					coeffs[i] = 0;
				var nonZero = false;
				if (!skip) nonZero = residuals(tokens, segment, is4, mx, topNz, leftNz, coeffs) else {
					for (i in 0...8) {
						topNz[9 * mx + i] = 0;
						leftNz[i] = 0;
					}
					if (!is4) {
						topNz[9 * mx + 8] = 0;
						leftNz[8] = 0;
					}
				}
				inner[mb] = is4 || nonZero;
				reconstruct(mx, my, is4, ymode, modes, uvmode, coeffs, ws, wu, wv);
			}
		}
	}

	// a macroblock's coefficients, dequantized (coeffs: 16 Y blocks, 4 U, 4 V,
	// each 16 in raster order); whether any is non-zero
	function residuals(br:BoolDecoder, segment:Int, is4:Bool, mx:Int, topNz:Array<Int>, leftNz:Array<Int>, coeffs:Vector<Int>):Bool {
		var q = 6 * segment, t = 9 * mx;
		var any = false;
		var first = 0, type = 3;
		var block = new Vector<Int>(16);
		if (!is4) {
			for (i in 0...16)
				block[i] = 0;
			var ctx = topNz[t + 8] + leftNz[8];
			var nz = tokens(br, 1, ctx, dq[q + 2], dq[q + 3], 0, block, 0);
			topNz[t + 8] = leftNz[8] = nz > 0 ? 1 : 0;
			wht(block, coeffs);
			first = 1;
			type = 0;
		}
		for (y in 0...4)
			for (x in 0...4) {
				var o = 16 * (4 * y + x);
				var ctx = topNz[t + x] + leftNz[y];
				var nz = tokens(br, type, ctx, dq[q], dq[q + 1], first, coeffs, o);
				var flag = nz > first ? 1 : 0;
				topNz[t + x] = flag;
				leftNz[y] = flag;
				// (a coefficient past the first, or a DC: the Y2's included)
				if (nz > first || coeffs[o] != 0) any = true;
			}
		for (ch in 0...2)
			for (y in 0...2)
				for (x in 0...2) {
					var o = 256 + 64 * ch + 16 * (2 * y + x);
					var ctx = topNz[t + 4 + 2 * ch + x] + leftNz[4 + 2 * ch + y];
					var nz = tokens(br, 2, ctx, dq[q + 4], dq[q + 5], 0, coeffs, o);
					var flag = nz > 0 ? 1 : 0;
					topNz[t + 4 + 2 * ch + x] = flag;
					leftNz[4 + 2 * ch + y] = flag;
					if (nz > 0) any = true;
				}
		return any;
	}

	// one block's tokens from n on, dequantized into out at o (raster order);
	// the position after its last (0: none)
	function tokens(br:BoolDecoder, type:Int, ctx:Int, dc:Int, ac:Int, n:Int, out:Vector<Int>, o:Int):Int {
		inline function prob(n:Int, c:Int, k:Int):Int
			return probs[((type * 8 + BANDS[n]) * 3 + c) * 11 + k];
		var c = ctx;
		while (n < 16) {
			if (br.bit(prob(n, c, 0)) == 0) return n;
			while (br.bit(prob(n, c, 1)) == 0) {
				n++;
				c = 0;
				if (n == 16) return 16;
			}
			var v:Int;
			if (br.bit(prob(n, c, 2)) == 0) {
				v = 1;
				c = 1;
			} else {
				if (br.bit(prob(n, c, 3)) == 0) {
					if (br.bit(prob(n, c, 4)) == 0) v = 2 else v = 3 + br.bit(prob(n, c, 5));
				} else if (br.bit(prob(n, c, 6)) == 0) {
					if (br.bit(prob(n, c, 7)) == 0) v = 5 + br.bit(159) else {
						v = 7 + 2 * br.bit(165);
						v += br.bit(145);
					}
				} else {
					var b1 = br.bit(prob(n, c, 8));
					var b0 = br.bit(prob(n, c, 9 + b1));
					var cat = 2 * b1 + b0;
					var tab = cat == 0 ? CAT3 : cat == 1 ? CAT4 : cat == 2 ? CAT5 : CAT6;
					v = 0;
					for (p in tab)
						v += v + br.bit(p);
					v += 3 + (8 << cat);
				}
				c = 2;
			}
			var sign = br.bit(128);
			out[o + ZIGZAG[n]] = (sign == 1 ? -v : v) * (n > 0 ? ac : dc);
			n++;
		}
		return 16;
	}

	// the inverse Walsh-Hadamard transform of the Y2 block: each Y block's DC
	static function wht(input:Vector<Int>, coeffs:Vector<Int>) {
		var tmp = new Vector<Int>(16);
		for (i in 0...4) {
			var a0 = input[i] + input[12 + i], a1 = input[4 + i] + input[8 + i];
			var a2 = input[4 + i] - input[8 + i], a3 = input[i] - input[12 + i];
			tmp[i] = a0 + a1;
			tmp[8 + i] = a0 - a1;
			tmp[4 + i] = a3 + a2;
			tmp[12 + i] = a3 - a2;
		}
		for (i in 0...4) {
			var dc = tmp[i * 4] + 3;
			var a0 = dc + tmp[3 + i * 4], a1 = tmp[1 + i * 4] + tmp[2 + i * 4];
			var a2 = tmp[1 + i * 4] - tmp[2 + i * 4], a3 = dc - tmp[3 + i * 4];
			var o = 64 * i;
			coeffs[o] = (a0 + a1) >> 3;
			coeffs[o + 16] = (a3 + a2) >> 3;
			coeffs[o + 32] = (a0 - a1) >> 3;
			coeffs[o + 48] = (a3 - a2) >> 3;
		}
	}

	// --- prediction and reconstruction (libwebp's work buffer: BPS wide,
	// a row above and a column to the left of each block) ---

	function reconstruct(mx:Int, my:Int, is4:Bool, ymode:Int, modes:Array<Int>, uvmode:Int, coeffs:Vector<Int>, ws:Bytes, wu:Bytes, wv:Bytes) {
		var x0 = mx * 16, y0 = my * 16;
		// Y: the row above (and four to its right), the column to the left
		inline function w(x:Int, y:Int):Int
			return (y + 1) * BPS + 4 + x;
		for (x in -1...20) {
			var v = if (my == 0) 127 else if (x == -1) (mx == 0 ? 129 : Y.get((y0 - 1) * ys + x0 - 1)) else if (x < 16) Y.get((y0 - 1) * ys + x0 + x) else if (mx
				== mbw - 1) Y.get((y0 - 1) * ys + x0 + 15) else Y.get((y0 - 1) * ys + x0 + x);
			ws.set(w(x, -1), v);
		}
		for (y in 0...16)
			ws.set(w(-1, y), mx == 0 ? 129 : Y.get((y0 + y) * ys + x0 - 1));
		if (is4) {
			// (the top right replicated beside the subblocks below it)
			for (k in 0...4) {
				var v = ws.get(w(16 + k, -1));
				ws.set(w(16 + k, 3), v);
				ws.set(w(16 + k, 7), v);
				ws.set(w(16 + k, 11), v);
			}
			for (n in 0...16) {
				var bx = 4 * (n & 3), by = 4 * (n >> 2);
				predict4(ws, w(bx, by), modes[n]);
				idct(coeffs, 16 * n, ws, w(bx, by));
			}
		} else {
			predict(ws, w(0, 0), 16, ymode, mx, my);
			for (n in 0...16)
				idct(coeffs, 16 * n, ws, w(4 * (n & 3), 4 * (n >> 2)));
		}
		for (y in 0...16)
			Y.blit((y0 + y) * ys + x0, ws, w(0, y), 16);
		// U, V
		var cx0 = mx * 8, cy0 = my * 8;
		for (plane in 0...2) {
			var P = plane == 0 ? U : V, wb = plane == 0 ? wu : wv;
			for (x in -1...8) {
				var v = if (my == 0) 127 else if (x == -1) (mx == 0 ? 129 : P.get((cy0 - 1) * uvs + cx0 - 1)) else P.get((cy0 - 1) * uvs + cx0 + x);
				wb.set(w(x, -1), v);
			}
			for (y in 0...8)
				wb.set(w(-1, y), mx == 0 ? 129 : P.get((cy0 + y) * uvs + cx0 - 1));
			predict(wb, w(0, 0), 8, uvmode, mx, my);
			for (n in 0...4)
				idct(coeffs, 256 + 64 * plane + 16 * n, wb, w(4 * (n & 1), 4 * (n >> 1)));
			for (y in 0...8)
				P.blit((cy0 + y) * uvs + cx0, wb, w(0, y), 8);
		}
	}

	static inline function clip8(v:Int):Int
		return v < 0 ? 0 : v > 255 ? 255 : v;

	// a 16x16 (luma) or 8x8 (chroma) block's prediction at d (size n), by
	// mode; DC with no row above or column to the left as libwebp: the other
	// edge's mean, or 128
	static function predict(b:Bytes, d:Int, n:Int, mode:Int, mx:Int, my:Int) {
		switch mode {
			case DC:
				var shift = n == 16 ? 4 : 3, v = 0;
				if (mx > 0 && my > 0) {
					for (i in 0...n)
						v += b.get(d - BPS + i) + b.get(d - 1 + i * BPS);
					v = (v + n) >> (shift + 1);
				} else if (my > 0) {
					for (i in 0...n)
						v += b.get(d - BPS + i);
					v = (v + (n >> 1)) >> shift;
				} else if (mx > 0) {
					for (i in 0...n)
						v += b.get(d - 1 + i * BPS);
					v = (v + (n >> 1)) >> shift;
				} else v = 128;
				for (y in 0...n)
					for (x in 0...n)
						b.set(d + y * BPS + x, v);
			case TM:
				var tl = b.get(d - BPS - 1);
				for (y in 0...n) {
					var l = b.get(d - 1 + y * BPS);
					for (x in 0...n)
						b.set(d + y * BPS + x, clip8(b.get(d - BPS + x) + l - tl));
				}
			case VE:
				for (y in 0...n)
					b.blit(d + y * BPS, b, d - BPS, n);
			case _:
				for (y in 0...n) {
					var l = b.get(d - 1 + y * BPS);
					for (x in 0...n)
						b.set(d + y * BPS + x, l);
				}
		}
	}

	static inline function avg3(a:Int, b:Int, c:Int):Int
		return (a + 2 * b + c + 2) >> 2;

	static inline function avg2(a:Int, b:Int):Int
		return (a + b + 1) >> 1;

	// a 4x4 subblock's prediction at d, by mode (libwebp's)
	static function predict4(b:Bytes, d:Int, mode:Int) {
		inline function top(i:Int):Int
			return b.get(d - BPS + i);
		inline function left(i:Int):Int
			return b.get(d - 1 + i * BPS);
		inline function put(x:Int, y:Int, v:Int)
			b.set(d + y * BPS + x, v);
		var tl = b.get(d - BPS - 1);
		switch mode {
			case DC:
				var v = 4;
				for (i in 0...4)
					v += top(i) + left(i);
				v >>= 3;
				for (y in 0...4)
					for (x in 0...4)
						put(x, y, v);
			case TM:
				for (y in 0...4)
					for (x in 0...4)
						put(x, y, clip8(top(x) + left(y) - tl));
			case VE:
				var v = [avg3(tl, top(0), top(1)), avg3(top(0), top(1), top(2)), avg3(top(1), top(2), top(3)), avg3(top(2), top(3), top(4))];
				for (y in 0...4)
					for (x in 0...4)
						put(x, y, v[x]);
			case HE:
				var A = tl, B = left(0), C = left(1), D = left(2), E = left(3);
				var v = [avg3(A, B, C), avg3(B, C, D), avg3(C, D, E), avg3(D, E, E)];
				for (y in 0...4)
					for (x in 0...4)
						put(x, y, v[y]);
			case RD:
				var I = left(0), J = left(1), K = left(2), L = left(3), X = tl, A = top(0), B = top(1), C = top(2), D = top(3);
				put(0, 3, avg3(J, K, L));
				var v = avg3(I, J, K);
				put(1, 3, v);
				put(0, 2, v);
				v = avg3(X, I, J);
				put(2, 3, v);
				put(1, 2, v);
				put(0, 1, v);
				v = avg3(A, X, I);
				put(3, 3, v);
				put(2, 2, v);
				put(1, 1, v);
				put(0, 0, v);
				v = avg3(B, A, X);
				put(3, 2, v);
				put(2, 1, v);
				put(1, 0, v);
				v = avg3(C, B, A);
				put(3, 1, v);
				put(2, 0, v);
				put(3, 0, avg3(D, C, B));
			case LD:
				var A = top(0), B = top(1), C = top(2), D = top(3), E = top(4), F = top(5), G = top(6), H = top(7);
				put(0, 0, avg3(A, B, C));
				var v = avg3(B, C, D);
				put(1, 0, v);
				put(0, 1, v);
				v = avg3(C, D, E);
				put(2, 0, v);
				put(1, 1, v);
				put(0, 2, v);
				v = avg3(D, E, F);
				put(3, 0, v);
				put(2, 1, v);
				put(1, 2, v);
				put(0, 3, v);
				v = avg3(E, F, G);
				put(3, 1, v);
				put(2, 2, v);
				put(1, 3, v);
				v = avg3(F, G, H);
				put(3, 2, v);
				put(2, 3, v);
				put(3, 3, avg3(G, H, H));
			case VR:
				var I = left(0), J = left(1), K = left(2), X = tl, A = top(0), B = top(1), C = top(2), D = top(3);
				var v = avg2(X, A);
				put(0, 0, v);
				put(1, 2, v);
				v = avg2(A, B);
				put(1, 0, v);
				put(2, 2, v);
				v = avg2(B, C);
				put(2, 0, v);
				put(3, 2, v);
				put(3, 0, avg2(C, D));
				put(0, 3, avg3(K, J, I));
				put(0, 2, avg3(J, I, X));
				v = avg3(I, X, A);
				put(0, 1, v);
				put(1, 3, v);
				v = avg3(X, A, B);
				put(1, 1, v);
				put(2, 3, v);
				v = avg3(A, B, C);
				put(2, 1, v);
				put(3, 3, v);
				put(3, 1, avg3(B, C, D));
			case VL:
				var A = top(0), B = top(1), C = top(2), D = top(3), E = top(4), F = top(5), G = top(6), H = top(7);
				put(0, 0, avg2(A, B));
				var v = avg2(B, C);
				put(1, 0, v);
				put(0, 2, v);
				v = avg2(C, D);
				put(2, 0, v);
				put(1, 2, v);
				v = avg2(D, E);
				put(3, 0, v);
				put(2, 2, v);
				put(0, 1, avg3(A, B, C));
				v = avg3(B, C, D);
				put(1, 1, v);
				put(0, 3, v);
				v = avg3(C, D, E);
				put(2, 1, v);
				put(1, 3, v);
				v = avg3(D, E, F);
				put(3, 1, v);
				put(2, 3, v);
				put(3, 2, avg3(E, F, G));
				put(3, 3, avg3(F, G, H));
			case HD:
				var I = left(0), J = left(1), K = left(2), L = left(3), X = tl, A = top(0), B = top(1), C = top(2);
				var v = avg2(I, X);
				put(0, 0, v);
				put(2, 1, v);
				v = avg2(J, I);
				put(0, 1, v);
				put(2, 2, v);
				v = avg2(K, J);
				put(0, 2, v);
				put(2, 3, v);
				put(0, 3, avg2(L, K));
				put(3, 0, avg3(A, B, C));
				put(2, 0, avg3(X, A, B));
				v = avg3(I, X, A);
				put(1, 0, v);
				put(3, 1, v);
				v = avg3(J, I, X);
				put(1, 1, v);
				put(3, 2, v);
				v = avg3(K, J, I);
				put(1, 2, v);
				put(3, 3, v);
				put(1, 3, avg3(L, K, J));
			case _:
				var I = left(0), J = left(1), K = left(2), L = left(3);
				put(0, 0, avg2(I, J));
				var v = avg2(J, K);
				put(2, 0, v);
				put(0, 1, v);
				v = avg2(K, L);
				put(2, 1, v);
				put(0, 2, v);
				put(1, 0, avg3(I, J, K));
				v = avg3(J, K, L);
				put(3, 0, v);
				put(1, 1, v);
				v = avg3(K, L, L);
				put(3, 1, v);
				put(1, 2, v);
				put(3, 2, L);
				put(2, 2, L);
				put(0, 3, L);
				put(1, 3, L);
				put(2, 3, L);
				put(3, 3, L);
		}
	}

	// the inverse DCT of a block's coefficients (at c) added to the 4x4 pixels at d
	static function idct(c:Vector<Int>, o:Int, b:Bytes, d:Int) {
		inline function mul1(a:Int):Int
			return ((a * 20091) >> 16) + a;
		inline function mul2(a:Int):Int
			return (a * 35468) >> 16;
		var tmp = new Vector<Int>(16);
		for (i in 0...4) {
			var a = c[o + i] + c[o + 8 + i], bb = c[o + i] - c[o + 8 + i];
			var cc = mul2(c[o + 4 + i]) - mul1(c[o + 12 + i]), dd = mul1(c[o + 4 + i]) + mul2(c[o + 12 + i]);
			tmp[4 * i] = a + dd;
			tmp[4 * i + 1] = bb + cc;
			tmp[4 * i + 2] = bb - cc;
			tmp[4 * i + 3] = a - dd;
		}
		for (i in 0...4) {
			var dc = tmp[i] + 4;
			var a = dc + tmp[8 + i], bb = dc - tmp[8 + i];
			var cc = mul2(tmp[4 + i]) - mul1(tmp[12 + i]), dd = mul1(tmp[4 + i]) + mul2(tmp[12 + i]);
			var r = d + i * BPS;
			b.set(r, clip8(b.get(r) + ((a + dd) >> 3)));
			b.set(r + 1, clip8(b.get(r + 1) + ((bb + cc) >> 3)));
			b.set(r + 2, clip8(b.get(r + 2) + ((bb - cc) >> 3)));
			b.set(r + 3, clip8(b.get(r + 3) + ((a - dd) >> 3)));
		}
	}

	// --- the loop filter, macroblock by macroblock in raster order ---

	function filter() {
		// per segment and 4x4: level's limit, interior limit, high edge variance threshold
		var limits = [for (i in 0...8) 0], ilevels = [for (i in 0...8) 0], hevs = [for (i in 0...8) 0];
		for (s in 0...4) {
			var base = level;
			if (useSegment) {
				base = filterStrength[s];
				if (!absoluteDelta) base += level;
			}
			for (k in 0...2) {
				var l = base;
				if (useLfDelta) {
					l += refLfDelta[0];
					if (k == 1) l += modeLfDelta[0];
				}
				l = l < 0 ? 0 : l > 63 ? 63 : l;
				if (l > 0) {
					var il = l;
					if (sharpness > 0) {
						il >>= sharpness > 4 ? 2 : 1;
						if (il > 9 - sharpness) il = 9 - sharpness;
					}
					if (il < 1) il = 1;
					ilevels[2 * s + k] = il;
					limits[2 * s + k] = 2 * l + il;
					hevs[2 * s + k] = l >= 40 ? 2 : l >= 15 ? 1 : 0;
				}
			}
		}
		for (my in 0...mbh)
			for (mx in 0...mbw) {
				var mb = my * mbw + mx, k = 2 * segments[mb] + (i4x4[mb] ? 1 : 0);
				var limit = limits[k];
				if (limit == 0) continue;
				var il = ilevels[k], hev = hevs[k], inside = inner[mb];
				var y = (my * 16) * ys + mx * 16, u = (my * 8) * uvs + mx * 8;
				if (filterType == 1) {
					if (mx > 0) simpleEdge(Y, y, 1, ys, 16, limit + 4);
					if (inside)
						for (e in 1...4)
							simpleEdge(Y, y + 4 * e, 1, ys, 16, limit);
					if (my > 0) simpleEdge(Y, y, ys, 1, 16, limit + 4);
					if (inside)
						for (e in 1...4)
							simpleEdge(Y, y + 4 * e * ys, ys, 1, 16, limit);
				} else {
					if (mx > 0) {
						edge(Y, y, 1, ys, 16, limit + 4, il, hev, true);
						edge(U, u, 1, uvs, 8, limit + 4, il, hev, true);
						edge(V, u, 1, uvs, 8, limit + 4, il, hev, true);
					}
					if (inside) {
						for (e in 1...4)
							edge(Y, y + 4 * e, 1, ys, 16, limit, il, hev, false);
						edge(U, u + 4, 1, uvs, 8, limit, il, hev, false);
						edge(V, u + 4, 1, uvs, 8, limit, il, hev, false);
					}
					if (my > 0) {
						edge(Y, y, ys, 1, 16, limit + 4, il, hev, true);
						edge(U, u, uvs, 1, 8, limit + 4, il, hev, true);
						edge(V, u, uvs, 1, 8, limit + 4, il, hev, true);
					}
					if (inside) {
						for (e in 1...4)
							edge(Y, y + 4 * e * ys, ys, 1, 16, limit, il, hev, false);
						edge(U, u + 4 * uvs, uvs, 1, 8, limit, il, hev, false);
						edge(V, u + 4 * uvs, uvs, 1, 8, limit, il, hev, false);
					}
				}
			}
	}

	static inline function sclip1(v:Int):Int
		return v < -128 ? -128 : v > 127 ? 127 : v;

	static inline function sclip2(v:Int):Int
		return v < -16 ? -16 : v > 15 ? 15 : v;

	static inline function iabs(v:Int):Int
		return v < 0 ? -v : v;

	// the simple filter across an edge: size lines (step across it, next along it)
	static function simpleEdge(b:Bytes, p:Int, step:Int, next:Int, size:Int, thresh:Int) {
		var t2 = 2 * thresh + 1;
		for (i in 0...size) {
			var q = p + i * next;
			var p1 = b.get(q - 2 * step), p0 = b.get(q - step), q0 = b.get(q), q1 = b.get(q + step);
			if (4 * iabs(p0 - q0) + iabs(p1 - q1) <= t2) filter2(b, q, step);
		}
	}

	static inline function filter2(b:Bytes, q:Int, step:Int) {
		var p1 = b.get(q - 2 * step), p0 = b.get(q - step), q0 = b.get(q), q1 = b.get(q + step);
		var a = 3 * (q0 - p0) + sclip1(p1 - q1);
		var a1 = sclip2((a + 4) >> 3), a2 = sclip2((a + 3) >> 3);
		b.set(q - step, clip8(p0 + a2));
		b.set(q, clip8(q0 - a1));
	}

	// the normal filter across an edge: a macroblock edge (6 pixels changed) or an inner one (4)
	static function edge(b:Bytes, p:Int, step:Int, next:Int, size:Int, thresh:Int, ithresh:Int, hevThresh:Int, mbEdge:Bool) {
		var t2 = 2 * thresh + 1;
		for (i in 0...size) {
			var q = p + i * next;
			var p3 = b.get(q - 4 * step), p2 = b.get(q - 3 * step), p1 = b.get(q - 2 * step), p0 = b.get(q - step);
			var q0 = b.get(q), q1 = b.get(q + step), q2 = b.get(q + 2 * step), q3 = b.get(q + 3 * step);
			if (4 * iabs(p0 - q0) + iabs(p1 - q1) > t2) continue;
			if (iabs(p3 - p2) > ithresh || iabs(p2 - p1) > ithresh || iabs(p1 - p0) > ithresh || iabs(q3 - q2) > ithresh || iabs(q2 - q1) > ithresh
				|| iabs(q1 - q0) > ithresh) continue;
			if (iabs(p1 - p0) > hevThresh || iabs(q1 - q0) > hevThresh) filter2(b, q, step) else if (mbEdge) {
				var a = sclip1(3 * (q0 - p0) + sclip1(p1 - q1));
				var a1 = (27 * a + 63) >> 7, a2 = (18 * a + 63) >> 7, a3 = (9 * a + 63) >> 7;
				b.set(q - 3 * step, clip8(p2 + a3));
				b.set(q - 2 * step, clip8(p1 + a2));
				b.set(q - step, clip8(p0 + a1));
				b.set(q, clip8(q0 - a1));
				b.set(q + step, clip8(q1 - a2));
				b.set(q + 2 * step, clip8(q2 - a3));
			} else {
				var a = 3 * (q0 - p0);
				var a1 = sclip2((a + 4) >> 3), a2 = sclip2((a + 3) >> 3), a3 = (a1 + 1) >> 1;
				b.set(q - 2 * step, clip8(p1 + a3));
				b.set(q - step, clip8(p0 + a2));
				b.set(q, clip8(q0 - a1));
				b.set(q + step, clip8(q1 - a3));
			}
		}
	}

	// --- colours: libwebp's fancy upsampler (chroma interpolated 9:3:3:1) and YUV to RGB ---

	function rgb():{width:Int, height:Int, rgba:Bytes} {
		var out = Bytes.alloc(width * height * 4);
		inline function mulHi(v:Int, c:Int):Int
			return (v * c) >> 8;
		inline function clip(v:Int):Int
			return (v & ~16383) == 0 ? v >> 6 : v < 0 ? 0 : 255;
		inline function put(row:Int, x:Int, yv:Int, u:Int, v:Int) {
			var o = (row * width + x) * 4;
			out.set(o, clip(mulHi(yv, 19077) + mulHi(v, 26149) - 14234));
			out.set(o + 1, clip(mulHi(yv, 19077) - mulHi(u, 6419) - mulHi(v, 13320) + 8708));
			out.set(o + 2, clip(mulHi(yv, 19077) + mulHi(u, 33050) - 17685));
			out.set(o + 3, 255);
		}
		// one or two rows: top (and bottom) from chroma rows tu (above) and cu
		function pair(top:Int, bottom:Int, tu:Int, cu:Int) {
			var last = (width - 1) >> 1;
			inline function uAt(r:Int, x:Int):Int
				return U.get(r * uvs + x);
			inline function vAt(r:Int, x:Int):Int
				return V.get(r * uvs + x);
			var tlu = uAt(tu, 0), tlv = vAt(tu, 0), lu = uAt(cu, 0), lv = vAt(cu, 0);
			put(top, 0, Y.get(top * ys), (3 * tlu + lu + 2) >> 2, (3 * tlv + lv + 2) >> 2);
			if (bottom >= 0) put(bottom, 0, Y.get(bottom * ys), (3 * lu + tlu + 2) >> 2, (3 * lv + tlv + 2) >> 2);
			for (x in 1...last + 1) {
				var tu1 = uAt(tu, x), tv1 = vAt(tu, x), u1 = uAt(cu, x), v1 = vAt(cu, x);
				var au = tlu + tu1 + lu + u1 + 8, av = tlv + tv1 + lv + v1 + 8;
				var d12u = (au + 2 * (tu1 + lu)) >> 3, d12v = (av + 2 * (tv1 + lv)) >> 3;
				var d03u = (au + 2 * (tlu + u1)) >> 3, d03v = (av + 2 * (tlv + v1)) >> 3;
				put(top, 2 * x - 1, Y.get(top * ys + 2 * x - 1), (d12u + tlu) >> 1, (d12v + tlv) >> 1);
				put(top, 2 * x, Y.get(top * ys + 2 * x), (d03u + tu1) >> 1, (d03v + tv1) >> 1);
				if (bottom >= 0) {
					put(bottom, 2 * x - 1, Y.get(bottom * ys + 2 * x - 1), (d03u + lu) >> 1, (d03v + lv) >> 1);
					put(bottom, 2 * x, Y.get(bottom * ys + 2 * x), (d12u + u1) >> 1, (d12v + v1) >> 1);
				}
				tlu = tu1;
				tlv = tv1;
				lu = u1;
				lv = v1;
			}
			if (width & 1 == 0) {
				put(top, width - 1, Y.get(top * ys + width - 1), (3 * tlu + lu + 2) >> 2, (3 * tlv + lv + 2) >> 2);
				if (bottom >= 0) put(bottom, width - 1, Y.get(bottom * ys + width - 1), (3 * lu + tlu + 2) >> 2, (3 * lv + tlv + 2) >> 2);
			}
		}
		pair(0, -1, 0, 0);
		var y = 1;
		while (y + 1 < height) {
			pair(y, y + 1, (y - 1) >> 1, (y + 1) >> 1);
			y += 2;
		}
		if (height & 1 == 0) pair(height - 1, -1, (height - 1) >> 1, (height - 1) >> 1);
		return {width: width, height: height, rgba: out};
	}
}

// the boolean entropy decoder (RFC 6386, section 7)
private class BoolDecoder {
	final data:Bytes;
	var p:Int;
	final end:Int;
	var value = 0;
	var range = 255;
	var count = 0;

	public function new(data:Bytes, start:Int, end:Int) {
		this.data = data;
		this.end = end;
		p = start;
		value = (next() << 8) | next();
	}

	inline function next():Int
		return p < end ? data.get(p++) : 0;

	public function bit(prob:Int):Int {
		var split = 1 + (((range - 1) * prob) >> 8);
		var big = split << 8, b:Int;
		if (value >= big) {
			b = 1;
			range -= split;
			value -= big;
		} else {
			b = 0;
			range = split;
		}
		while (range < 128) {
			value <<= 1;
			range <<= 1;
			if (++count == 8) {
				count = 0;
				value |= next();
			}
		}
		return b;
	}

	public function literal(n:Int):Int {
		var v = 0;
		for (i in 0...n)
			v = (v << 1) | bit(128);
		return v;
	}

	public function signed(n:Int):Int {
		var v = literal(n);
		return bit(128) == 1 ? -v : v;
	}
}
