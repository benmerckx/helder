package hxmc.ui;

import haxe.io.Bytes;

// WebP files decoded to RGBA8 (Image.decode), as libwebp (Chromium's)
// decodes them: the RIFF container's chunks (VP8L, VP8, and VP8X's with
// ALPH), lossless images (VP8L: the predictor, colour, subtract-green and
// colour-indexing transforms, prefix codes by meta codes over the image,
// the colour cache, backward references), lossy ones (VP8, Vp8Decoder) with
// their alpha (ALPH: raw or lossless, filtered). The first frame of an
// animation.
class WebpDecoder {
	public static function decode(webp:Bytes):{width:Int, height:Int, rgba:Bytes} {
		if (webp.length < 16 || webp.getString(0, 4) != "RIFF" || webp.getString(8, 4) != "WEBP") throw "WebpDecoder: not a WebP file";
		var p = 12, end = webp.length;
		var alpha:Null<{at:Int, length:Int}> = null;
		var width = 0, height = 0;
		while (p + 8 <= end) {
			var tag = webp.getString(p, 4), size = u32le(webp, p + 4), at = p + 8;
			switch tag {
				case "VP8L":
					return new Lossless(webp, at, size).image();
				case "VP8 ":
					var d = Vp8Decoder.decode(webp, at, size);
					if (alpha != null) Alpha.apply(webp, alpha.at, alpha.length, d.width, d.height, d.rgba);
					return d;
				case "VP8X":
					width = 1 + (webp.get(at + 4) | (webp.get(at + 5) << 8) | (webp.get(at + 6) << 16));
					height = 1 + (webp.get(at + 7) | (webp.get(at + 8) << 8) | (webp.get(at + 9) << 16));
				case "ALPH":
					alpha = {at: at, length: size};
				case "ANMF":
					// (an animation: its first frame, on its canvas)
					return frame(webp, at, size, width, height);
				case _:
			}
			p = at + size + (size & 1);
		}
		throw "WebpDecoder: no image data";
	}

	// an animation's frame: its image placed on the canvas (transparent elsewhere)
	static function frame(webp:Bytes, at:Int, size:Int, width:Int, height:Int):{width:Int, height:Int, rgba:Bytes} {
		var fx = 2 * (webp.get(at) | (webp.get(at + 1) << 8) | (webp.get(at + 2) << 16));
		var fy = 2 * (webp.get(at + 3) | (webp.get(at + 4) << 8) | (webp.get(at + 5) << 16));
		var inner = Bytes.alloc(12 + size - 16);
		inner.blit(0, Bytes.ofString("RIFF"), 0, 4);
		inner.blit(8, Bytes.ofString("WEBP"), 0, 4);
		inner.blit(12, webp, at + 16, size - 16);
		var d = decode(inner);
		var out = Bytes.alloc(width * height * 4);
		out.fill(0, out.length, 0);
		for (y in 0...d.height) {
			if (fy + y >= height) break;
			var n = Std.int(Math.min(d.width, width - fx));
			if (n > 0) out.blit(((fy + y) * width + fx) * 4, d.rgba, y * d.width * 4, n * 4);
		}
		return {width: width, height: height, rgba: out};
	}

	static inline function u32le(b:Bytes, p:Int):Int
		return b.get(p) | (b.get(p + 1) << 8) | (b.get(p + 2) << 16) | (b.get(p + 3) << 24);
}

// a VP8L bitstream: its header, transforms and entropy-coded image (or,
// for ALPH, the image alone at a given size)
@:allow(hxmc.ui.Alpha)
private class Lossless {
	static final ORDER = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];
	// the distance codes' (dx, dy) for the first 120
	static final OFFSETS = [
		0, 1, 1, 0, 1, 1, -1, 1, 0, 2, 2, 0, 1, 2, -1, 2, 2, 1, -2, 1, 2, 2, -2, 2, 0, 3, 3, 0, 1, 3, -1, 3, 3, 1, -3, 1, 2, 3, -2, 3, 3, 2, -3, 2, 0, 4, 4,
		0, 1, 4, -1, 4, 4, 1, -4, 1, 3, 3, -3, 3, 2, 4, -2, 4, 4, 2, -4, 2, 0, 5, 3, 4, -3, 4, 4, 3, -4, 3, 5, 0, 1, 5, -1, 5, 5, 1, -5, 1, 2, 5, -2, 5,
		5, 2, -5, 2, 4, 4, -4, 4, 3, 5, -3, 5, 5, 3, -5, 3, 0, 6, 6, 0, 1, 6, -1, 6, 6, 1, -6, 1, 2, 6, -2, 6, 6, 2, -6, 2, 4, 5, -4, 5, 5, 4, -5, 4,
		3, 6, -3, 6, 6, 3, -6, 3, 0, 7, 7, 0, 1, 7, -1, 7, 5, 5, -5, 5, 7, 1, -7, 1, 4, 6, -4, 6, 6, 4, -6, 4, 2, 7, -2, 7, 7, 2, -7, 2, 3, 7, -3, 7, 7,
		3, -7, 3, 5, 6, -5, 6, 6, 5, -6, 5, 8, 0, 4, 7, -4, 7, 7, 4, -7, 4, 8, 1, 8, 2, 6, 6, -6, 6, 8, 3, 5, 7, -5, 7, 7, 5, -7, 5, 8, 4, 6, 7, -6, 7,
		7, 6, -7, 6, 8, 5, 7, 7, -7, 7, 8, 6, 8, 7
	];

	final data:Bytes;
	final end:Int;
	var bit:Int;
	var width = 0;
	var height = 0;
	var hasAlpha = false;

	public function new(data:Bytes, at:Int, size:Int) {
		this.data = data;
		this.end = at + size;
		bit = at * 8;
	}

	public function image():{width:Int, height:Int, rgba:Bytes} {
		if (bits(8) != 0x2F) throw "WebpDecoder: not a lossless image";
		width = bits(14) + 1;
		height = bits(14) + 1;
		hasAlpha = bits(1) == 1;
		if (bits(3) != 0) throw "WebpDecoder: an unknown lossless version";
		var argb = stream(width, height);
		var out = Bytes.alloc(width * height * 4);
		for (i in 0...width * height) {
			var c = argb[i];
			out.set(4 * i, (c >> 16) & 255);
			out.set(4 * i + 1, (c >> 8) & 255);
			out.set(4 * i + 2, c & 255);
			out.set(4 * i + 3, (c >>> 24) & 255);
		}
		return {width: width, height: height, rgba: out};
	}

	// the image's transforms and pixels, the transforms undone (last read first)
	function stream(w:Int, h:Int):Array<Int> {
		var transforms:Array<{kind:Int, bits:Int, data:Array<Int>, xsize:Int}> = [];
		var xsize = w;
		while (bits(1) == 1) {
			var kind = bits(2);
			switch kind {
				case 0 | 1:
					var b = bits(3) + 2;
					transforms.push({kind: kind, bits: b, data: entropyImage(divUp(xsize, b), divUp(h, b), false), xsize: xsize});
				case 2:
					transforms.push({kind: 2, bits: 0, data: null, xsize: xsize});
				case _:
					var n = bits(8) + 1;
					var table = entropyImage(n, 1, false);
					for (i in 1...n)
						table[i] = add(table[i], table[i - 1]);
					var b = n <= 2 ? 3 : n <= 4 ? 2 : n <= 16 ? 1 : 0;
					transforms.push({kind: 3, bits: b, data: table, xsize: xsize});
					xsize = divUpBits(xsize, b);
			}
		}
		var px = entropyImage(xsize, h, true);
		var i = transforms.length;
		while (--i >= 0) {
			var t = transforms[i];
			switch t.kind {
				case 0: predict(px, t.xsize, h, t.bits, t.data);
				case 1: colors(px, t.xsize, h, t.bits, t.data);
				case 2:
					for (k in 0...px.length) {
						var c = px[k], g = (c >> 8) & 255;
						px[k] = (c & 0xFF00FF00) | ((((c >> 16) & 255) + g) & 255) << 16 | (((c & 255) + g) & 255);
					}
				case _: px = unindex(px, t.xsize, h, t.bits, t.data);
			}
		}
		return px;
	}

	static inline function divUp(n:Int, b:Int):Int
		return (n + (1 << b) - 1) >> b;

	static inline function divUpBits(n:Int, b:Int):Int
		return (n + (1 << b) - 1) >> b;

	// per channel, modulo 256
	static inline function add(a:Int, b:Int):Int
		return (((a >>> 24) + (b >>> 24)) & 255) << 24 | ((((a >> 16) & 255) + ((b >> 16) & 255)) & 255) << 16 | ((((a >> 8) & 255) + ((b >> 8) & 255)) & 255) << 8 | (((a & 255) + (b & 255)) & 255);

	// an entropy-coded image: its colour cache, meta prefix codes (the main
	// image only), its prefix code groups, then its pixels
	function entropyImage(w:Int, h:Int, main:Bool):Array<Int> {
		var cacheBits = bits(1) == 1 ? bits(4) : 0;
		if (cacheBits > 11) throw "WebpDecoder: a colour cache too large";
		var metaBits = 0, meta:Null<Array<Int>> = null, groups = 1;
		if (main && bits(1) == 1) {
			metaBits = bits(3) + 2;
			meta = entropyImage(divUp(w, metaBits), divUp(h, metaBits), false);
			for (k in 0...meta.length) {
				var g = (meta[k] >> 8) & 0xFFFF;
				meta[k] = g;
				if (g + 1 > groups) groups = g + 1;
			}
		}
		var cacheSize = cacheBits > 0 ? 1 << cacheBits : 0;
		var codes = [for (g in 0...groups) [code(256 + 24 + cacheSize), code(256), code(256), code(256), code(40)]];
		var cache = cacheSize > 0 ? [for (i in 0...cacheSize) 0] : null;
		var px = [for (i in 0...w * h) 0];
		var metaW = divUp(w, metaBits);
		var i = 0, n = w * h;
		inline function remember(c:Int)
			if (cache != null) cache[(0x1E35A7BD * c) >>> (32 - cacheBits)] = c;
		while (i < n) {
			var group = meta == null ? codes[0] : codes[meta[((Std.int(i / w)) >> metaBits) * metaW + ((i % w) >> metaBits)]];
			var s = read(group[0]);
			if (s < 256) {
				var r = read(group[1]), b = read(group[2]), a = read(group[3]);
				var c = (a << 24) | (r << 16) | (s << 8) | b;
				px[i++] = c;
				remember(c);
			} else if (s < 280) {
				var length = prefixed(s - 256);
				var d = prefixed(read(group[4]));
				var dist = if (d > 120) d - 120 else {
					var k = d - 1;
					var v = OFFSETS[2 * k] + OFFSETS[2 * k + 1] * w;
					v < 1 ? 1 : v;
				}
				if (dist > i) throw "WebpDecoder: a reference before the image";
				for (k in 0...length) {
					if (i >= n) break;
					var c = px[i - dist];
					px[i++] = c;
					remember(c);
				}
			} else {
				if (cache == null) throw "WebpDecoder: no colour cache";
				px[i++] = cache[s - 280];
			}
		}
		return px;
	}

	// a length's or distance's value from its prefix symbol (and its extra bits)
	inline function prefixed(p:Int):Int {
		if (p < 4) return p + 1;
		var extra = (p - 2) >> 1;
		return ((2 + (p & 1)) << extra) + bits(extra) + 1;
	}

	// --- prefix codes ---

	// a prefix code over n symbols (simple: one or two symbols; normal: code lengths coded)
	function code(n:Int):Code {
		var lengths = [for (i in 0...n) 0];
		if (bits(1) == 1) {
			var two = bits(1) == 1;
			var s0 = bits(bits(1) == 1 ? 8 : 1);
			lengths[s0] = 1;
			if (two) lengths[bits(8)] = 1;
		} else {
			var cl = [for (i in 0...19) 0];
			var count = 4 + bits(4);
			for (i in 0...count)
				cl[ORDER[i]] = bits(3);
			var clCode = new Code(cl);
			var max = n;
			if (bits(1) == 1) {
				var nb = 2 + 2 * bits(3);
				max = 2 + bits(nb);
			}
			var prev = 8, s = 0;
			while (s < n) {
				if (max-- == 0) break;
				var l = read(clCode);
				if (l < 16) {
					lengths[s++] = l;
					if (l != 0) prev = l;
				} else {
					var repeat = l == 16 ? 3 + bits(2) : l == 17 ? 3 + bits(3) : 11 + bits(7);
					var v = l == 16 ? prev : 0;
					for (k in 0...repeat)
						if (s < n) lengths[s++] = v;
				}
			}
		}
		return new Code(lengths);
	}

	// a symbol: the code's bits one at a time, first the most significant (canonical codes, as deflate's)
	function read(c:Code):Int {
		if (c.single >= 0) return c.single;
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(1);
			var count = c.counts[len];
			if (code - count < first) return c.symbols[index + (code - first)];
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		throw "WebpDecoder: a bad prefix code";
	}

	// n bits, least significant first
	inline function bits(n:Int):Int {
		var v = 0;
		for (i in 0...n) {
			var p = bit >> 3;
			if (p >= end) throw "WebpDecoder: the data ends early";
			v |= ((data.get(p) >> (bit & 7)) & 1) << i;
			bit++;
		}
		return v;
	}

	// --- the transforms undone ---

	static function predict(px:Array<Int>, w:Int, h:Int, b:Int, modes:Array<Int>) {
		var bw = divUp(w, b);
		for (y in 0...h)
			for (x in 0...w) {
				var i = y * w + x;
				var pred = if (y == 0) x == 0 ? 0xFF000000 : px[i - 1] else if (x == 0) px[i - w] else {
					var L = px[i - 1], T = px[i - w], TL = px[i - w - 1], TR = px[i - w + 1];
					switch (modes[(y >> b) * bw + (x >> b)] >> 8) & 15 {
						case 0: 0xFF000000;
						case 1: L;
						case 2: T;
						case 3: TR;
						case 4: TL;
						case 5: avg(avg(L, TR), T);
						case 6: avg(L, TL);
						case 7: avg(L, T);
						case 8: avg(TL, T);
						case 9: avg(T, TR);
						case 10: avg(avg(L, TL), avg(T, TR));
						case 11: select(L, T, TL);
						case 12: clampFull(L, T, TL);
						case 13: clampHalf(avg(L, T), TL);
						case _: 0xFF000000;
					}
				}
				px[i] = add(px[i], pred);
			}
	}

	static inline function avg(a:Int, b:Int):Int
		return (((a >>> 24) + (b >>> 24)) >> 1) << 24 | ((((a >> 16) & 255) + ((b >> 16) & 255)) >> 1) << 16 | ((((a >> 8) & 255) + ((b >> 8) & 255)) >> 1) << 8 | (((a & 255) + (b & 255)) >> 1);

	static function select(L:Int, T:Int, TL:Int):Int {
		var pL = 0, pT = 0;
		for (s in [24, 16, 8, 0]) {
			var l = (L >>> s) & 255, t = (T >>> s) & 255, tl = (TL >>> s) & 255;
			var p = l + t - tl;
			pL += abs(p - l);
			pT += abs(p - t);
		}
		return pL < pT ? L : T;
	}

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;

	static inline function clamp(v:Int):Int
		return v < 0 ? 0 : v > 255 ? 255 : v;

	static function clampFull(a:Int, b:Int, c:Int):Int {
		var out = 0;
		for (s in [24, 16, 8, 0])
			out |= clamp(((a >>> s) & 255) + ((b >>> s) & 255) - ((c >>> s) & 255)) << s;
		return out;
	}

	static function clampHalf(a:Int, b:Int):Int {
		var out = 0;
		for (s in [24, 16, 8, 0]) {
			var x = (a >>> s) & 255, y = (b >>> s) & 255;
			// (C's division: toward zero)
			out |= clamp(x + Std.int((x - y) / 2)) << s;
		}
		return out;
	}

	static function colors(px:Array<Int>, w:Int, h:Int, b:Int, data:Array<Int>) {
		var bw = divUp(w, b);
		inline function delta(t:Int, c:Int):Int
			return (sbyte(t) * sbyte(c)) >> 5;
		for (y in 0...h)
			for (x in 0...w) {
				var i = y * w + x, m = data[(y >> b) * bw + (x >> b)];
				var g2r = m & 255, g2b = (m >> 8) & 255, r2b = (m >> 16) & 255;
				var c = px[i], g = (c >> 8) & 255;
				var r = (((c >> 16) & 255) + delta(g2r, g)) & 255;
				var bl = ((c & 255) + delta(g2b, g) + delta(r2b, r)) & 255;
				px[i] = (c & 0xFF00FF00) | (r << 16) | bl;
			}
	}

	static inline function sbyte(v:Int):Int
		return v >= 128 ? v - 256 : v;

	static function unindex(px:Array<Int>, xsize:Int, h:Int, b:Int, table:Array<Int>):Array<Int> {
		var w = xsize, packed = divUpBits(w, b), per = 8 >> b, mask = (1 << per) - 1;
		var out = [for (i in 0...w * h) 0];
		for (y in 0...h)
			for (x in 0...w) {
				var v = (px[y * packed + (x >> b)] >> 8) & 255;
				var index = b == 0 ? v : (v >> ((x & ((1 << b) - 1)) * per)) & mask;
				out[y * w + x] = index < table.length ? table[index] : 0;
			}
		return out;
	}
}

// a canonical prefix code from its symbols' code lengths (one symbol: no bits)
private class Code {
	public final counts = [for (i in 0...16) 0];
	public final symbols:Array<Int> = [];
	public var single = -1;

	public function new(lengths:Array<Int>) {
		var used = 0, last = 0;
		for (s in 0...lengths.length)
			if (lengths[s] > 0) {
				counts[lengths[s]]++;
				used++;
				last = s;
			}
		if (used == 1) {
			single = last;
			return;
		}
		if (used == 0) {
			single = 0;
			return;
		}
		for (len in 1...16)
			for (s in 0...lengths.length)
				if (lengths[s] == len) symbols.push(s);
	}
}

// ALPH: an image's alpha, raw or as a lossless image's green, filtered
// (horizontally, vertically or by gradient) before coding
private class Alpha {
	public static function apply(data:Bytes, at:Int, length:Int, w:Int, h:Int, rgba:Bytes) {
		var header = data.get(at), method = header & 3, filter = (header >> 2) & 3;
		var a = Bytes.alloc(w * h);
		if (method == 0) a.blit(0, data, at + 1, w * h) else {
			var l = new Lossless(data, at + 1, length - 1);
			l.width = w;
			l.height = h;
			var px = l.stream(w, h);
			for (i in 0...w * h)
				a.set(i, (px[i] >> 8) & 255);
		}
		// (the filters undone: each value plus its prediction, modulo 256)
		for (y in 0...h)
			for (x in 0...w) {
				var i = y * w + x;
				var pred = switch filter {
					case 1: x > 0 ? a.get(i - 1) : y > 0 ? a.get(i - w) : 0;
					case 2: y > 0 ? a.get(i - w) : x > 0 ? a.get(i - 1) : 0;
					case 3:
						if (y == 0) x > 0 ? a.get(i - 1) : 0 else if (x == 0) a.get(i - w) else {
							var g = a.get(i - 1) + a.get(i - w) - a.get(i - w - 1);
							g < 0 ? 0 : g > 255 ? 255 : g;
						}
					case _: 0;
				}
				a.set(i, (a.get(i) + pred) & 255);
			}
		for (i in 0...w * h)
			rgba.set(4 * i + 3, a.get(i));
	}
}
