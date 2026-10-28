package helder.image;

// PNG decoding, helder's one implementation: every colour type and bit
// depth, tRNS, Adam7 interlacing, to RGBA8 (rows top to bottom, straight
// alpha; 16-bit samples their high byte), over memory as Raw gives it.
// Every function is @:hxmc.unsafe: on hxmc it touches no GC object (the
// compiler checks it), so the same code decodes a Bytes for PngDecoder on
// the calling thread and an off-heap buffer for ImageJobs in a GC-free
// job's safe region; elsewhere (Eval) it runs on Bytes.
//
// The caller reads the header (info), gives a buffer of bufferLength
// bytes and decodes into it (decode: the IDAT data; decodeStream: a zlib
// stream of any size with the header's format, an APNG frame's): the data
// inflated (as hxmc's std's InflateImpl: a 32-bit bit buffer, codes up to
// 10 bits by table, longer ones from their canonical counts), the rows
// unfiltered in place and packed, then widened to RGBA8 in place (from the
// end when a pixel has 32 bits or fewer, from the start when more); an
// interlaced image's passes are inflated after the pixels and put in
// place. The pixels are the buffer's first width * height * 4 bytes. Its
// state is in memory it allocates and frees: decodes on several threads
// are independent. Errors are results < 0, PngDecoder's messages (message).
class PngCore {
	public static inline var ERR_SIGNATURE = -1;
	public static inline var ERR_TRUNCATED = -2; // (DETAIL: the chunk's name)
	public static inline var ERR_METHOD = -3;
	public static inline var ERR_FORMAT = -4; // (a colour type at a bit depth)
	public static inline var ERR_EMPTY = -5;
	public static inline var ERR_NO_IHDR = -6;
	public static inline var ERR_NO_PLTE = -7;
	public static inline var ERR_INTERLACE = -8; // (DETAIL: the method)
	public static inline var ERR_SHORT = -9;
	public static inline var ERR_FILTER = -10; // (DETAIL: the filter)
	public static inline var ERR_PALETTE = -11;
	public static inline var ERR_DATA = -12;
	public static inline var ERR_MEMORY = -13;
	public static inline var ERR_LARGE = -14;

	// the header's (info's 4-byte slots)
	public static inline var WIDTH = 0;
	public static inline var HEIGHT = 4;
	public static inline var DEPTH = 8;
	public static inline var TYPE = 12;
	public static inline var INTERLACE = 16;
	static inline var IDAT = 20;
	static inline var PLTE_AT = 24;
	static inline var PLTE_LEN = 28;
	static inline var TRNS_AT = 32;
	static inline var TRNS_LEN = 36;
	public static inline var DETAIL = 40;
	public static inline var INFO = 44;

	// what an error says (PngDecoder's)
	public static function message(code:Int, info:Raw):String {
		var d = info.i32(DETAIL);
		return "PngDecoder: " + switch code {
			case ERR_SIGNATURE: "not a PNG file";
			case ERR_TRUNCATED: "a truncated " + String.fromCharCode(d & 0xFF) + String.fromCharCode((d >> 8) & 0xFF) + String.fromCharCode((d >> 16) & 0xFF)
				+ String.fromCharCode(d >>> 24) + " chunk";
			case ERR_METHOD: "an unknown compression or filter method";
			case ERR_FORMAT: 'colour type ${info.i32(TYPE)} at bit depth ${info.i32(DEPTH)}';
			case ERR_EMPTY: "an empty image";
			case ERR_NO_IHDR: "no IHDR chunk";
			case ERR_NO_PLTE: "a palette image without PLTE";
			case ERR_INTERLACE: "interlace method " + d;
			case ERR_SHORT: "the image data ends early";
			case ERR_FILTER: "filter " + d;
			case ERR_PALETTE: "a colour outside the palette";
			case ERR_MEMORY: "out of memory";
			case ERR_LARGE: "an image too large";
			case _: "the image data does not decode";
		}
	}

	// png's n bytes' header into info (INFO bytes): 0, else an error
	@:hxmc.unsafe public static function info(png:Raw, n:Int, info:Raw):Int {
		info.fill(0, INFO);
		info.set32(TYPE, -1);
		if (n < 8 || png.i32(0) != 0x474E5089 || png.i32(4) != 0x0A1A0A0D) return ERR_SIGNATURE;
		var p = 8, idat = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = png.i32(p + 4);
			if (len < 0 || p + 12 + len > n) {
				info.set32(DETAIL, name);
				return ERR_TRUNCATED;
			}
			if (name == 0x52444849) { // IHDR
				if (len < 13) return ERR_SHORT;
				info.set32(WIDTH, u32(png, p + 8));
				info.set32(HEIGHT, u32(png, p + 12));
				info.set32(DEPTH, png.u8(p + 16));
				info.set32(TYPE, png.u8(p + 17));
				if (png.u8(p + 18) != 0 || png.u8(p + 19) != 0) return ERR_METHOD;
				info.set32(INTERLACE, png.u8(p + 20));
				var d = info.i32(DEPTH);
				var ok = switch info.i32(TYPE) {
					case 0: d == 1 || d == 2 || d == 4 || d == 8 || d == 16;
					case 3: d == 1 || d == 2 || d == 4 || d == 8;
					case 2 | 4 | 6: d == 8 || d == 16;
					case _: false;
				}
				if (!ok) return ERR_FORMAT;
				if (info.i32(WIDTH) <= 0 || info.i32(HEIGHT) <= 0) return ERR_EMPTY;
			} else if (name == 0x45544C50) { // PLTE
				info.set32(PLTE_AT, p + 8);
				info.set32(PLTE_LEN, len);
			} else if (name == 0x534E5274) { // tRNS
				info.set32(TRNS_AT, p + 8);
				info.set32(TRNS_LEN, len);
			} else if (name == 0x54414449) // IDAT
				idat += len;
			else if (name == 0x444E4549) // IEND
				break;
			p += 12 + len;
		}
		info.set32(IDAT, idat);
		var w = info.i32(WIDTH), h = info.i32(HEIGHT), t = info.i32(TYPE);
		if (t < 0) return ERR_NO_IHDR;
		if (t == 3 && info.i32(PLTE_LEN) == 0) return ERR_NO_PLTE;
		if (info.i32(INTERLACE) > 1) {
			info.set32(DETAIL, info.i32(INTERLACE));
			return ERR_INTERLACE;
		}
		// (the rows and the pixels within an Int: 2 GB)
		if (w > 1 << 24 || h > 1 << 24 || (h : Float) * (stride(info, w) + 2) * 2 + (w : Float) * h * 4 > 2147483000.0) return ERR_LARGE;
		return 0;
	}

	// the buffer decode needs for w x h pixels of the header's format (the
	// image, or an APNG frame): the rows with their filter bytes, or the
	// pixels if more; interlaced: the pixels, then the passes' rows
	@:hxmc.unsafe public static function bufferLength(info:Raw, w:Int, h:Int):Int {
		var rows = rawLength(info, w, h), px = w * h * 4;
		return info.i32(INTERLACE) == 1 ? px + rows : rows > px ? rows : px;
	}

	// (the inflated data's length: each pass's rows, a filter byte each)
	@:hxmc.unsafe static function rawLength(info:Raw, w:Int, h:Int):Int {
		if (info.i32(INTERLACE) != 1) return h * (stride(info, w) + 1);
		var n = 0;
		for (k in 0...7) {
			var pw = passWidth(k, w), ph = passHeight(k, h);
			if (pw > 0 && ph > 0) n += ph * (stride(info, pw) + 1);
		}
		return n;
	}

	// (Adam7's passes: where each starts, its steps)
	static inline function passX(k:Int):Int
		return k == 1 ? 4 : k == 3 ? 2 : k == 5 ? 1 : 0;

	static inline function passY(k:Int):Int
		return k == 2 ? 4 : k == 4 ? 2 : k == 6 ? 1 : 0;

	static inline function passDx(k:Int):Int
		return k <= 1 ? 8 : k <= 3 ? 4 : k <= 5 ? 2 : 1;

	static inline function passDy(k:Int):Int
		return k == 0 ? 8 : k <= 2 ? 8 : k <= 4 ? 4 : 2;

	static inline function passWidth(k:Int, w:Int):Int
		return Std.int((w - passX(k) + passDx(k) - 1) / passDx(k));

	static inline function passHeight(k:Int, h:Int):Int
		return Std.int((h - passY(k) + passDy(k) - 1) / passDy(k));

	// (a row's bytes, without its filter byte)
	@:hxmc.unsafe static inline function stride(info:Raw, w:Int):Int
		return (w * pixelBits(info) + 7) >> 3;

	// (a pixel's bits)
	@:hxmc.unsafe static inline function pixelBits(info:Raw):Int {
		var t = info.i32(TYPE);
		return info.i32(DEPTH) * (t == 2 ? 3 : t == 4 ? 2 : t == 6 ? 4 : 1);
	}

	// png's n bytes (info read) decoded into buf (bufferLength(info, width,
	// height) bytes): 0, the RGBA8 pixels at its start; else an error
	@:hxmc.unsafe public static function decode(png:Raw, n:Int, info:Raw, buf:Raw):Int {
		var idatLen = info.i32(IDAT);
		var idat = Raw.malloc(idatLen + 8);
		if (idat.isNull()) return ERR_MEMORY;
		var p = 8, at = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = png.i32(p + 4);
			if (name == 0x54414449) {
				idat.add(at).move(png.add(p + 8), len);
				at += len;
			} else if (name == 0x444E4549)
				break;
			p += 12 + len;
		}
		var e = decodeStream(png, info, idat, idatLen, info.i32(WIDTH), info.i32(HEIGHT), buf);
		idat.free();
		return e;
	}

	// a zlib stream of n bytes at src, w x h pixels of the header's format,
	// decoded into buf (bufferLength(info, w, h) bytes): 0, else an error
	@:hxmc.unsafe public static function decodeStream(png:Raw, info:Raw, src:Raw, n:Int, w:Int, h:Int, buf:Raw):Int {
		var scratch = Raw.malloc(SCRATCH);
		if (scratch.isNull()) return ERR_MEMORY;
		var interlaced = info.i32(INTERLACE) == 1, rawLen = rawLength(info, w, h);
		var raw = interlaced ? buf.add(w * h * 4) : buf;
		var r = inflate(scratch, src, n, raw, rawLen);
		scratch.free();
		if (r < 0) return r;
		if (r < rawLen) return ERR_SHORT;
		var b = pixelBits(info), bpp = b < 8 ? 1 : b >> 3;
		if (!interlaced) {
			var e = unfilter(info, raw, stride(info, w), h, bpp);
			if (e != 0) return e;
			return widen(png, info, buf, w, h);
		}
		var at = 0;
		for (k in 0...7) {
			var pw = passWidth(k, w), ph = passHeight(k, h);
			if (pw <= 0 || ph <= 0) continue;
			var s = stride(info, pw), rows = raw.add(at);
			var e = unfilter(info, rows, s, ph, bpp);
			if (e != 0) return e;
			for (j in 0...ph)
				for (i in 0...pw) {
					var e = pixel(png, info, rows.add(j * s), i, buf, 4 * ((passY(k) + j * passDy(k)) * w + passX(k) + i * passDx(k)));
					if (e != 0) return e;
				}
			at += ph * (s + 1);
		}
		return 0;
	}

	// the rows unfiltered in place and packed: row j's bytes from
	// j * (stride + 1) + 1 to j * stride (always before them), the row above
	// in place already; bpp the bytes a filter looks back
	@:hxmc.unsafe static function unfilter(info:Raw, b:Raw, stride:Int, h:Int, bpp:Int):Int {
		var lead = bpp < stride ? bpp : stride;
		for (j in 0...h) {
			var f = b.u8(j * (stride + 1)), r = j * (stride + 1) + 1, d = j * stride, u = d - stride;
			switch f {
				case 0:
					b.add(d).move(b.add(r), stride);
				case 1:
					b.add(d).move(b.add(r), lead);
					for (x in lead...stride)
						b.set8(d + x, b.u8(r + x) + b.u8(d + x - bpp));
				case 2:
					if (j == 0) b.add(d).move(b.add(r), stride) else
						for (x in 0...stride)
							b.set8(d + x, b.u8(r + x) + b.u8(u + x));
				case 3:
					for (x in 0...lead)
						b.set8(d + x, b.u8(r + x) + (j == 0 ? 0 : b.u8(u + x) >> 1));
					for (x in lead...stride)
						b.set8(d + x, b.u8(r + x) + ((b.u8(d + x - bpp) + (j == 0 ? 0 : b.u8(u + x))) >> 1));
				case 4:
					if (j == 0) {
						// (Paeth with nothing above: the byte to the left)
						b.add(d).move(b.add(r), lead);
						for (x in lead...stride)
							b.set8(d + x, b.u8(r + x) + b.u8(d + x - bpp));
					} else {
						for (x in 0...lead)
							b.set8(d + x, b.u8(r + x) + b.u8(u + x));
						for (x in lead...stride) {
							var a = b.u8(d + x - bpp), c = b.u8(u + x - bpp), bb = b.u8(u + x);
							var pa = abs(bb - c), pb = abs(a - c), pc = abs(a + bb - c - c);
							b.set8(d + x, b.u8(r + x) + (pa <= pb && pa <= pc ? a : pb <= pc ? bb : c));
						}
					}
				case _:
					info.set32(DETAIL, f);
					return ERR_FILTER;
			}
		}
		return 0;
	}

	// the packed rows of w x h pixels widened to RGBA8 in place: from the
	// end when a pixel has 32 bits or fewer (each one's RGBA at or after its
	// own bytes), from the start when more (at or before)
	@:hxmc.unsafe static function widen(png:Raw, info:Raw, b:Raw, w:Int, h:Int):Int {
		if (info.i32(TYPE) == 6 && info.i32(DEPTH) == 8) return 0;
		var s = stride(info, w), back = pixelBits(info) <= 32;
		for (qy in 0...h)
			for (qx in 0...w) {
				var y = back ? h - 1 - qy : qy, x = back ? w - 1 - qx : qx;
				var e = pixel(png, info, b.add(y * s), x, b, 4 * (y * w + x));
				if (e != 0) return e;
			}
		return 0;
	}

	// pixel x of a packed row as RGBA8 at out's o (its samples read before
	// any is written: the same memory, widened in place): 0, else an error
	@:hxmc.unsafe static inline function pixel(png:Raw, info:Raw, row:Raw, x:Int, out:Raw, o:Int):Int {
		var depth = info.i32(DEPTH), type = info.i32(TYPE);
		var r = 0, g = 0, bl = 0, a = 255, e = 0;
		switch type {
			case 0:
				var v = stored(row, x, 0, 1, depth);
				r = g = bl = scaled(v, depth);
				if (info.i32(TRNS_LEN) >= 2 && v == u16(png, info.i32(TRNS_AT))) a = 0;
			case 2:
				var sr = stored(row, x, 0, 3, depth), sg = stored(row, x, 1, 3, depth), sb = stored(row, x, 2, 3, depth);
				r = scaled(sr, depth);
				g = scaled(sg, depth);
				bl = scaled(sb, depth);
				var t = info.i32(TRNS_AT);
				if (info.i32(TRNS_LEN) >= 6 && sr == u16(png, t) && sg == u16(png, t + 2) && sb == u16(png, t + 4)) a = 0;
			case 3:
				var k = stored(row, x, 0, 1, depth), pal = png.add(info.i32(PLTE_AT));
				if (3 * k + 2 >= info.i32(PLTE_LEN)) {
					e = ERR_PALETTE;
					k = 0;
				}
				r = pal.u8(3 * k);
				g = pal.u8(3 * k + 1);
				bl = pal.u8(3 * k + 2);
				if (k < info.i32(TRNS_LEN)) a = png.u8(info.i32(TRNS_AT) + k);
			case 4:
				r = g = bl = scaled(stored(row, x, 0, 2, depth), depth);
				a = scaled(stored(row, x, 1, 2, depth), depth);
			case _:
				r = scaled(stored(row, x, 0, 4, depth), depth);
				g = scaled(stored(row, x, 1, 4, depth), depth);
				bl = scaled(stored(row, x, 2, 4, depth), depth);
				a = scaled(stored(row, x, 3, 4, depth), depth);
		}
		out.set8(o, r);
		out.set8(o + 1, g);
		out.set8(o + 2, bl);
		out.set8(o + 3, a);
		return e;
	}

	// (sample k of pixel x of a packed row, as stored)
	@:hxmc.unsafe static inline function stored(row:Raw, x:Int, k:Int, channels:Int, depth:Int):Int {
		return if (depth == 16) u16(row, 2 * (x * channels + k)) else if (depth == 8) row.u8(x * channels + k) else {
			var bit = x * depth;
			(row.u8(bit >> 3) >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
		}
	}

	// (a sample scaled to 8 bits: a 16-bit one's high byte)
	@:hxmc.unsafe static inline function scaled(v:Int, depth:Int):Int
		return depth == 16 ? v >> 8 : depth == 8 ? v : Std.int(v * 255 / ((1 << depth) - 1));

	// --- inflate: the state at s (the bit buffer, its count, the input's
	// position and end, the output's position, whether the fixed codes are
	// built), then each code's counts (16), symbols (288) and table (1024
	// entries), the code lengths (320) and the fixed codes'

	static inline var FAST = 10;
	static inline var CODE = 4 * (16 + 288 + 1024);
	static inline var BUF = 0;
	static inline var CNT = 4;
	static inline var P = 8;
	static inline var END = 12;
	static inline var POS = 16;
	static inline var BAD = 20; // (2: the input ran out; 1: a bad code)
	static inline var FIXED_BUILT = 24;
	static inline var LIT = 64;
	static inline var DIST = LIT + CODE;
	static inline var CL = DIST + CODE;
	static inline var LENS = CL + CODE;
	static inline var FIXED_LIT = LENS + 4 * 320;
	static inline var FIXED_DIST = FIXED_LIT + CODE;
	static inline var SCRATCH = FIXED_DIST + CODE;

	// (an inflate's failure: the data ended early, or does not decode)
	@:hxmc.unsafe static function failed(s:Raw):Int
		return s.i32(BAD) == 2 ? ERR_SHORT : ERR_DATA;

	// a zlib stream inflated into out (its size known): the bytes produced, or an error
	@:hxmc.unsafe static function inflate(s:Raw, src:Raw, n:Int, out:Raw, cap:Int):Int {
		if (n < 2) return ERR_DATA;
		var cmf = src.u8(0), flg = src.u8(1);
		if (cmf & 15 != 8 || ((cmf << 8) + flg) % 31 != 0 || flg & 32 != 0) return ERR_DATA;
		s.set32(BUF, 0);
		s.set32(CNT, 0);
		s.set32(P, 2);
		s.set32(END, n);
		s.set32(POS, 0);
		s.set32(BAD, 0);
		s.set32(FIXED_BUILT, 0);
		var last = false;
		while (!last) {
			last = bits(s, src, 1) == 1;
			var type = bits(s, src, 2);
			if (type == 0) {
				// (stored: from the next byte)
				giveBack(s);
				var p = s.i32(P);
				if (p + 4 > n) return ERR_DATA;
				var len = src.u8(p) | src.u8(p + 1) << 8, nlen = src.u8(p + 2) | src.u8(p + 3) << 8;
				p += 4;
				var pos = s.i32(POS);
				if (nlen != 0xFFFF - len || p + len > n || pos + len > cap) return ERR_DATA;
				out.add(pos).move(src.add(p), len);
				s.set32(POS, pos + len);
				s.set32(P, p + len);
			} else if (type == 1) {
				if (s.i32(FIXED_BUILT) == 0) {
					var l = s.add(LENS);
					for (i in 0...288)
						l.set32(4 * i, i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8);
					build(s.add(FIXED_LIT), l, 288);
					for (i in 0...30)
						l.set32(4 * i, 5);
					build(s.add(FIXED_DIST), l, 30);
					s.set32(FIXED_BUILT, 1);
				}
				if (!block(s, src, out, cap, s.add(FIXED_LIT), s.add(FIXED_DIST))) return failed(s);
			} else if (type == 2) {
				var hlit = bits(s, src, 5) + 257, hdist = bits(s, src, 5) + 1, hclen = bits(s, src, 4) + 4;
				var l = s.add(LENS);
				for (i in 0...19)
					l.set32(4 * i, 0);
				for (i in 0...hclen)
					l.set32(4 * order(i), bits(s, src, 3));
				build(s.add(CL), l, 19);
				var i = 0, total = hlit + hdist;
				while (i < total) {
					var sym = symbol(s, src, s.add(CL));
					if (sym < 16) l.set32(4 * i++, sym) else {
						var v = 0, r = 0;
						if (sym == 16) {
							if (i == 0) return ERR_DATA;
							v = l.i32(4 * (i - 1));
							r = 3 + bits(s, src, 2);
						} else r = sym == 17 ? 3 + bits(s, src, 3) : 11 + bits(s, src, 7);
						if (i + r > total) return ERR_DATA;
						for (k in 0...r)
							l.set32(4 * i++, v);
					}
					if (s.i32(BAD) != 0) return failed(s);
				}
				build(s.add(LIT), l, hlit);
				build(s.add(DIST), l.add(4 * hlit), hdist);
				if (!block(s, src, out, cap, s.add(LIT), s.add(DIST))) return failed(s);
			} else
				return ERR_DATA;
			if (s.i32(BAD) != 0) return failed(s);
		}
		giveBack(s);
		var p = s.i32(P), pos = s.i32(POS);
		// (zlib's Adler-32 of the output, big-endian, after the stream)
		if (p + 4 > n) return ERR_DATA;
		if (adler(out, pos) != (src.u8(p) << 24 | src.u8(p + 1) << 16 | src.u8(p + 2) << 8 | src.u8(p + 3))) return ERR_DATA;
		return pos;
	}

	// one block's symbols with the codes lit and dist: false when it does not decode
	@:hxmc.unsafe static function block(s:Raw, src:Raw, out:Raw, cap:Int, lit:Raw, dist:Raw):Bool {
		var pos = s.i32(POS);
		while (true) {
			var sym = symbol(s, src, lit);
			if (sym < 256) {
				if (pos >= cap) return false;
				out.set8(pos++, sym);
			} else if (sym == 256) {
				s.set32(POS, pos);
				return s.i32(BAD) == 0;
			} else {
				var k = sym - 257;
				if (k >= 29) return false;
				var len = lengthBase(k) + bits(s, src, lengthExtra(k));
				var d = symbol(s, src, dist);
				if (d >= 30) return false;
				var back = distBase(d) + bits(s, src, distExtra(d));
				if (back > pos || pos + len > cap || s.i32(BAD) != 0) return false;
				if (back >= len) out.add(pos).move(out.add(pos - back), len) else
					for (i in 0...len)
						out.set8(pos + i, out.u8(pos + i - back));
				pos += len;
			}
		}
	}

	// (past the input's end, zeros: no more than its reading ahead, else BAD)
	@:hxmc.unsafe static inline function need(s:Raw, src:Raw, n:Int) {
		var cnt = s.i32(CNT);
		if (cnt < n) {
			var buf = s.i32(BUF), p = s.i32(P), end = s.i32(END);
			while (cnt < n) {
				if (p < end) buf |= src.u8(p) << cnt else if (p >= end + 4) s.set32(BAD, 2);
				p++;
				cnt += 8;
			}
			s.set32(BUF, buf);
			s.set32(P, p);
			s.set32(CNT, cnt);
		}
	}

	@:hxmc.unsafe static inline function bits(s:Raw, src:Raw, n:Int):Int {
		need(s, src, n);
		var buf = s.i32(BUF);
		s.set32(BUF, buf >>> n);
		s.set32(CNT, s.i32(CNT) - n);
		return buf & ((1 << n) - 1);
	}

	// (the whole bytes the bit buffer holds unread: given back to the input)
	@:hxmc.unsafe static function giveBack(s:Raw) {
		s.set32(P, s.i32(P) - (s.i32(CNT) >> 3));
		s.set32(BUF, 0);
		s.set32(CNT, 0);
	}

	// a symbol: the table for codes up to FAST bits, else bit by bit from the
	// canonical counts (a code's first bit its most significant)
	@:hxmc.unsafe static inline function symbol(s:Raw, src:Raw, h:Raw):Int {
		need(s, src, 15);
		var buf = s.i32(BUF);
		var e = h.i32(4 * (16 + 288) + 4 * (buf & ((1 << FAST) - 1)));
		return if (e != 0) {
			var len = e >> 9;
			s.set32(BUF, buf >>> len);
			s.set32(CNT, s.i32(CNT) - len);
			e & 511;
		} else slow(s, src, h);
	}

	@:hxmc.unsafe static function slow(s:Raw, src:Raw, h:Raw):Int {
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(s, src, 1);
			var count = h.i32(4 * len);
			if (code - count < first) return h.i32(4 * 16 + 4 * (index + (code - first)));
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		s.set32(BAD, 1);
		return 999;
	}

	// a canonical code from n lengths at l: counts, symbols, the table of the
	// codes up to FAST bits (by their bits as read: reversed), each (length << 9) | symbol
	@:hxmc.unsafe static function build(h:Raw, l:Raw, n:Int) {
		h.fill(0, CODE);
		for (i in 0...n) {
			var len = l.i32(4 * i);
			if (len > 0) h.set32(4 * len, h.i32(4 * len) + 1);
		}
		// (the symbols by length, then by value; `at` in the table's room until it is filled)
		var at = h.add(4 * (16 + 288)), total = 0;
		for (len in 1...16) {
			at.set32(4 * len, total);
			total += h.i32(4 * len);
		}
		for (sym in 0...n) {
			var len = l.i32(4 * sym);
			if (len > 0) {
				var k = at.i32(4 * len);
				h.set32(4 * (16 + k), sym);
				at.set32(4 * len, k + 1);
			}
		}
		at.fill(0, 4 * 16);
		var code = 0, k = 0;
		for (len in 1...16) {
			for (i in 0...h.i32(4 * len)) {
				if (len <= FAST) {
					var r = 0, c = code;
					for (b in 0...len) {
						r = (r << 1) | (c & 1);
						c >>= 1;
					}
					var step = 1 << len, e = (len << 9) | h.i32(4 * (16 + k));
					var j = r;
					while (j < (1 << FAST)) {
						at.set32(4 * j, e);
						j += step;
					}
				}
				code++;
				k++;
			}
			code <<= 1;
		}
	}

	@:hxmc.unsafe static function adler(b:Raw, n:Int):Int {
		var a = 1, c = 0, i = 0;
		while (i < n) {
			// (3800 bytes at most between the reductions: the sums stay under 2^31, signed)
			var stop = i + 3800 < n ? i + 3800 : n;
			while (i < stop) {
				a += b.u8(i++);
				c += a;
			}
			a %= 65521;
			c %= 65521;
		}
		return (c << 16) | a;
	}

	// (deflate's tables as arithmetic: static arrays would be GC objects)
	static inline function lengthBase(k:Int):Int
		return k < 8 ? 3 + k : k == 28 ? 258 : ((4 + (k & 3)) << ((k >> 2) - 1)) + 3;

	static inline function lengthExtra(k:Int):Int
		return k < 8 || k == 28 ? 0 : (k >> 2) - 1;

	static inline function distBase(d:Int):Int
		return d < 4 ? 1 + d : ((2 + (d & 1)) << ((d >> 1) - 1)) + 1;

	static inline function distExtra(d:Int):Int
		return d < 4 ? 0 : (d >> 1) - 1;

	static inline function order(i:Int):Int
		return switch i {
			case 0: 16;
			case 1: 17;
			case 2: 18;
			case 3: 0;
			case _: (i & 1) == 0 ? 8 + ((i - 4) >> 1) : 7 - ((i - 5) >> 1);
		}

	static inline function u32(b:Raw, p:Int):Int
		return b.u8(p) << 24 | b.u8(p + 1) << 16 | b.u8(p + 2) << 8 | b.u8(p + 3);

	static inline function u16(b:Raw, p:Int):Int
		return b.u8(p) << 8 | b.u8(p + 1);

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;
}
