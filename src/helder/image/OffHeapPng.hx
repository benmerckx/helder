package helder.image;

#if (target.name == "hxmc")
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// PNG decoded over native memory, touching no GC object (every function
// @:hxmc.unsafe: the compiler checks it), for a GC-free job (ImageJobs):
// every colour type and bit depth, tRNS, to RGBA8 as PngDecoder decodes
// them; not Adam7 interlacing nor APNG's frames (PngDecoder's: then
// ERR_UNSUPPORTED). The caller reads the header (info), gives a buffer of
// bufferLength bytes and decodes into it: the IDAT chunks gathered and
// inflated (as hxmc's std's InflateImpl: a 32-bit bit buffer, codes up to
// 10 bits by table, longer ones from their canonical counts) into it, the
// rows unfiltered in place and packed, then widened to RGBA8 in place: the
// pixels are its first width * height * 4 bytes. Its own state is in
// memory it allocates and frees, so decodes on several threads at once are
// independent. Errors are results < 0.
//   tests/bench/results/jobs.md: from the prototype (RGBA8 only), 168 ms
//   for a 4K photo natively, against PngDecoder's 224.
class OffHeapPng {
	public static inline var ERR_FORMAT = -1; // not a PNG, a bad chunk
	public static inline var ERR_UNSUPPORTED = -2; // interlaced, too large
	public static inline var ERR_DATA = -3; // the image data does not decode
	public static inline var ERR_MEMORY = -4;

	// the header's (info's 4-byte slots)
	public static inline var WIDTH = 0;
	public static inline var HEIGHT = 4;
	static inline var DEPTH = 8;
	static inline var TYPE = 12;
	static inline var INTERLACE = 16;
	static inline var IDAT = 20;
	static inline var PLTE_AT = 24;
	static inline var PLTE_LEN = 28;
	static inline var TRNS_AT = 32;
	static inline var TRNS_LEN = 36;
	public static inline var INFO = 40;

	// png's n bytes' header into info (INFO bytes): 0, else an error
	@:hxmc.unsafe public static function info(png:Ptr, n:Int, info:Ptr):Int {
		LibC.memset(info, 0, INFO);
		Mem.setI32(info, TYPE, -1);
		if (n < 8 || Mem.getI32(png, 0) != 0x474E5089 || Mem.getI32(png, 4) != 0x0A1A0A0D) return ERR_FORMAT;
		var p = 8, idat = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = Mem.getI32(png, p + 4);
			if (len < 0 || p + 12 + len > n) return ERR_FORMAT;
			if (name == 0x52444849) { // IHDR
				if (len < 13) return ERR_FORMAT;
				Mem.setI32(info, WIDTH, u32(png, p + 8));
				Mem.setI32(info, HEIGHT, u32(png, p + 12));
				Mem.setI32(info, DEPTH, Mem.getU8(png, p + 16));
				Mem.setI32(info, TYPE, Mem.getU8(png, p + 17));
				if (Mem.getU8(png, p + 18) != 0 || Mem.getU8(png, p + 19) != 0) return ERR_FORMAT;
				Mem.setI32(info, INTERLACE, Mem.getU8(png, p + 20));
			} else if (name == 0x45544C50) { // PLTE
				Mem.setI32(info, PLTE_AT, p + 8);
				Mem.setI32(info, PLTE_LEN, len);
			} else if (name == 0x534E5274) { // tRNS
				Mem.setI32(info, TRNS_AT, p + 8);
				Mem.setI32(info, TRNS_LEN, len);
			} else if (name == 0x54414449) // IDAT
				idat += len;
			else if (name == 0x444E4549) // IEND
				break;
			p += 12 + len;
		}
		Mem.setI32(info, IDAT, idat);
		var w = Mem.getI32(info, WIDTH), h = Mem.getI32(info, HEIGHT), d = Mem.getI32(info, DEPTH), t = Mem.getI32(info, TYPE);
		if (t < 0 || w <= 0 || h <= 0) return ERR_FORMAT;
		var ok = switch t {
			case 0: d == 1 || d == 2 || d == 4 || d == 8 || d == 16;
			case 3: d == 1 || d == 2 || d == 4 || d == 8;
			case 2 | 4 | 6: d == 8 || d == 16;
			case _: false;
		}
		if (!ok) return ERR_FORMAT;
		if (t == 3 && Mem.getI32(info, PLTE_LEN) == 0) return ERR_FORMAT;
		if (w > 1 << 24 || h > 1 << 24) return ERR_UNSUPPORTED;
		if (Mem.getI32(info, INTERLACE) != 0) return ERR_UNSUPPORTED;
		// (the rows and the pixels within an Int: 2 GB)
		if ((h : Float) * (stride(info) + 1) > 2147483000.0 || (w : Float) * h * 4 > 2147483000.0) return ERR_UNSUPPORTED;
		return 0;
	}

	// the buffer decode needs (info read): the rows with their filter bytes, or the pixels if more
	@:hxmc.unsafe public static function bufferLength(info:Ptr):Int {
		var rows = Mem.getI32(info, HEIGHT) * (stride(info) + 1), px = Mem.getI32(info, WIDTH) * Mem.getI32(info, HEIGHT) * 4;
		return rows > px ? rows : px;
	}

	// (a row's bytes, without its filter byte)
	@:hxmc.unsafe static inline function stride(info:Ptr):Int
		return (Mem.getI32(info, WIDTH) * pixelBits(info) + 7) >> 3;

	// (a pixel's bits)
	@:hxmc.unsafe static inline function pixelBits(info:Ptr):Int {
		var t = Mem.getI32(info, TYPE);
		return Mem.getI32(info, DEPTH) * (t == 2 ? 3 : t == 4 ? 2 : t == 6 ? 4 : 1);
	}

	// png's n bytes (info read) decoded into buf (bufferLength(info) bytes):
	// 0, the RGBA8 pixels at its start; else an error
	@:hxmc.unsafe public static function decode(png:Ptr, n:Int, info:Ptr, buf:Ptr):Int {
		var idatLen = Mem.getI32(info, IDAT);
		var idat = LibC.malloc(idatLen + 8), scratch = LibC.malloc(SCRATCH);
		if (idat.isNull() || scratch.isNull()) {
			if (!idat.isNull()) LibC.free(idat);
			if (!scratch.isNull()) LibC.free(scratch);
			return ERR_MEMORY;
		}
		var p = 8, at = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = Mem.getI32(png, p + 4);
			if (name == 0x54414449) {
				LibC.memcpy(idat.add(at), png.add(p + 8), len);
				at += len;
			} else if (name == 0x444E4549)
				break;
			p += 12 + len;
		}
		var h = Mem.getI32(info, HEIGHT), s = stride(info), rawLen = h * (s + 1);
		var r = inflate(scratch, idat, idatLen, buf, rawLen);
		LibC.free(idat);
		LibC.free(scratch);
		if (r != rawLen) return r < 0 ? r : ERR_DATA;
		var b = pixelBits(info);
		var e = unfilter(buf, s, h, b < 8 ? 1 : b >> 3);
		if (e != 0) return e;
		return widen(png, info, buf);
	}

	// the rows unfiltered in place and packed: row j's bytes from
	// j * (stride + 1) + 1 to j * stride (always before them), the row above
	// in place already; bpp the bytes a filter looks back
	@:hxmc.unsafe static function unfilter(b:Ptr, stride:Int, h:Int, bpp:Int):Int {
		var lead = bpp < stride ? bpp : stride;
		for (j in 0...h) {
			var f = Mem.getU8(b, j * (stride + 1)), r = j * (stride + 1) + 1, d = j * stride, u = d - stride;
			switch f {
				case 0:
					LibC.memmove(b.add(d), b.add(r), stride);
				case 1:
					LibC.memmove(b.add(d), b.add(r), lead);
					for (x in lead...stride)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, d + x - bpp));
				case 2:
					if (j == 0) LibC.memmove(b.add(d), b.add(r), stride) else
						for (x in 0...stride)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, u + x));
				case 3:
					for (x in 0...lead)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x) + (j == 0 ? 0 : Mem.getU8(b, u + x) >> 1));
					for (x in lead...stride)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x) + ((Mem.getU8(b, d + x - bpp) + (j == 0 ? 0 : Mem.getU8(b, u + x))) >> 1));
				case 4:
					if (j == 0) {
						// (Paeth with nothing above: the byte to the left)
						LibC.memmove(b.add(d), b.add(r), lead);
						for (x in lead...stride)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, d + x - bpp));
					} else {
						for (x in 0...lead)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, u + x));
						for (x in lead...stride) {
							var a = Mem.getU8(b, d + x - bpp), c = Mem.getU8(b, u + x - bpp), bb = Mem.getU8(b, u + x);
							var pa = abs(bb - c), pb = abs(a - c), pc = abs(a + bb - c - c);
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + (pa <= pb && pa <= pc ? a : pb <= pc ? bb : c));
						}
					}
				case _:
					return ERR_DATA;
			}
		}
		return 0;
	}

	// the packed rows widened to RGBA8 in place, as PngDecoder's pixel: from
	// the end when a pixel has 32 bits or fewer (each one's RGBA at or after
	// its own bytes), from the start when more (at or before)
	@:hxmc.unsafe static function widen(png:Ptr, info:Ptr, b:Ptr):Int {
		var w = Mem.getI32(info, WIDTH), h = Mem.getI32(info, HEIGHT), depth = Mem.getI32(info, DEPTH), type = Mem.getI32(info, TYPE);
		if (type == 6 && depth == 8) return 0;
		var s = stride(info), back = pixelBits(info) <= 32;
		var pal = png.add(Mem.getI32(info, PLTE_AT)), palLen = Mem.getI32(info, PLTE_LEN);
		var trns = png.add(Mem.getI32(info, TRNS_AT)), trnsLen = Mem.getI32(info, TRNS_LEN);
		var channels = type == 2 ? 3 : type == 4 ? 2 : type == 6 ? 4 : 1;
		// (a colour key: grey's or RGB's samples as stored, -1 for none)
		var k0 = -1, k1 = -1, k2 = -1;
		if (type == 0 && trnsLen >= 2) k0 = u16(trns, 0);
		if (type == 2 && trnsLen >= 6) {
			k0 = u16(trns, 0);
			k1 = u16(trns, 2);
			k2 = u16(trns, 4);
		}
		for (qy in 0...h) for (qx in 0...w) {
			var y = back ? h - 1 - qy : qy, x = back ? w - 1 - qx : qx;
			var row = b.add(y * s), o = 4 * (y * w + x);
			switch type {
				case 0:
					var g = stored(row, x, 0, 1, depth);
					var v = scaled(g, depth);
					Mem.setI8(b, o, v);
					Mem.setI8(b, o + 1, v);
					Mem.setI8(b, o + 2, v);
					Mem.setI8(b, o + 3, g == k0 ? 0 : 255);
				case 2:
					var r = stored(row, x, 0, 3, depth), g = stored(row, x, 1, 3, depth), bl = stored(row, x, 2, 3, depth);
					Mem.setI8(b, o, scaled(r, depth));
					Mem.setI8(b, o + 1, scaled(g, depth));
					Mem.setI8(b, o + 2, scaled(bl, depth));
					Mem.setI8(b, o + 3, r == k0 && g == k1 && bl == k2 ? 0 : 255);
				case 3:
					var k = stored(row, x, 0, 1, depth);
					if (3 * k + 2 >= palLen) return ERR_DATA;
					var a = k < trnsLen ? Mem.getU8(trns, k) : 255;
					Mem.setI8(b, o, Mem.getU8(pal, 3 * k));
					Mem.setI8(b, o + 1, Mem.getU8(pal, 3 * k + 1));
					Mem.setI8(b, o + 2, Mem.getU8(pal, 3 * k + 2));
					Mem.setI8(b, o + 3, a);
				case 4:
					var v = scaled(stored(row, x, 0, 2, depth), depth), a = scaled(stored(row, x, 1, 2, depth), depth);
					Mem.setI8(b, o, v);
					Mem.setI8(b, o + 1, v);
					Mem.setI8(b, o + 2, v);
					Mem.setI8(b, o + 3, a);
				case _:
					var r = scaled(stored(row, x, 0, 4, depth), depth), g = scaled(stored(row, x, 1, 4, depth), depth);
					var bl = scaled(stored(row, x, 2, 4, depth), depth), a = scaled(stored(row, x, 3, 4, depth), depth);
					Mem.setI8(b, o, r);
					Mem.setI8(b, o + 1, g);
					Mem.setI8(b, o + 2, bl);
					Mem.setI8(b, o + 3, a);
			}
		}
		return 0;
	}

	// (sample k of pixel x of a packed row, as stored)
	@:hxmc.unsafe static inline function stored(row:Ptr, x:Int, k:Int, channels:Int, depth:Int):Int {
		return if (depth == 16) u16(row, 2 * (x * channels + k)) else if (depth == 8) Mem.getU8(row, x * channels + k) else {
			var bit = x * depth;
			(Mem.getU8(row, bit >> 3) >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
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
	static inline var BAD = 20; // (the input ran out, or a bad code)
	static inline var FIXED_BUILT = 24;
	static inline var LIT = 64;
	static inline var DIST = LIT + CODE;
	static inline var CL = DIST + CODE;
	static inline var LENS = CL + CODE;
	static inline var FIXED_LIT = LENS + 4 * 320;
	static inline var FIXED_DIST = FIXED_LIT + CODE;
	static inline var SCRATCH = FIXED_DIST + CODE;

	// a zlib stream inflated into out (its size known): the bytes produced, or an error
	@:hxmc.unsafe static function inflate(s:Ptr, src:Ptr, n:Int, out:Ptr, cap:Int):Int {
		if (n < 2) return ERR_DATA;
		var cmf = Mem.getU8(src, 0), flg = Mem.getU8(src, 1);
		if (cmf & 15 != 8 || ((cmf << 8) + flg) % 31 != 0 || flg & 32 != 0) return ERR_DATA;
		Mem.setI32(s, BUF, 0);
		Mem.setI32(s, CNT, 0);
		Mem.setI32(s, P, 2);
		Mem.setI32(s, END, n);
		Mem.setI32(s, POS, 0);
		Mem.setI32(s, BAD, 0);
		Mem.setI32(s, FIXED_BUILT, 0);
		var last = false;
		while (!last) {
			last = bits(s, src, 1) == 1;
			var type = bits(s, src, 2);
			if (type == 0) {
				// (stored: from the next byte)
				giveBack(s);
				var p = Mem.getI32(s, P);
				if (p + 4 > n) return ERR_DATA;
				var len = Mem.getU8(src, p) | Mem.getU8(src, p + 1) << 8, nlen = Mem.getU8(src, p + 2) | Mem.getU8(src, p + 3) << 8;
				p += 4;
				var pos = Mem.getI32(s, POS);
				if (nlen != 0xFFFF - len || p + len > n || pos + len > cap) return ERR_DATA;
				LibC.memcpy(out.add(pos), src.add(p), len);
				Mem.setI32(s, POS, pos + len);
				Mem.setI32(s, P, p + len);
			} else if (type == 1) {
				if (Mem.getI32(s, FIXED_BUILT) == 0) {
					var l = s.add(LENS);
					for (i in 0...288)
						Mem.setI32(l, 4 * i, i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8);
					build(s.add(FIXED_LIT), l, 288);
					for (i in 0...30)
						Mem.setI32(l, 4 * i, 5);
					build(s.add(FIXED_DIST), l, 30);
					Mem.setI32(s, FIXED_BUILT, 1);
				}
				if (!block(s, src, out, cap, s.add(FIXED_LIT), s.add(FIXED_DIST))) return ERR_DATA;
			} else if (type == 2) {
				var hlit = bits(s, src, 5) + 257, hdist = bits(s, src, 5) + 1, hclen = bits(s, src, 4) + 4;
				var l = s.add(LENS);
				for (i in 0...19)
					Mem.setI32(l, 4 * i, 0);
				for (i in 0...hclen)
					Mem.setI32(l, 4 * order(i), bits(s, src, 3));
				build(s.add(CL), l, 19);
				var i = 0, total = hlit + hdist;
				while (i < total) {
					var sym = symbol(s, src, s.add(CL));
					if (sym < 16) Mem.setI32(l, 4 * i++, sym) else {
						var v = 0, r = 0;
						if (sym == 16) {
							if (i == 0) return ERR_DATA;
							v = Mem.getI32(l, 4 * (i - 1));
							r = 3 + bits(s, src, 2);
						} else r = sym == 17 ? 3 + bits(s, src, 3) : 11 + bits(s, src, 7);
						if (i + r > total) return ERR_DATA;
						for (k in 0...r)
							Mem.setI32(l, 4 * i++, v);
					}
					if (Mem.getI32(s, BAD) != 0) return ERR_DATA;
				}
				build(s.add(LIT), l, hlit);
				build(s.add(DIST), l.add(4 * hlit), hdist);
				if (!block(s, src, out, cap, s.add(LIT), s.add(DIST))) return ERR_DATA;
			} else
				return ERR_DATA;
			if (Mem.getI32(s, BAD) != 0) return ERR_DATA;
		}
		giveBack(s);
		var p = Mem.getI32(s, P), pos = Mem.getI32(s, POS);
		// (zlib's Adler-32 of the output, big-endian, after the stream)
		if (p + 4 > n) return ERR_DATA;
		if (adler(out, pos) != (Mem.getU8(src, p) << 24 | Mem.getU8(src, p + 1) << 16 | Mem.getU8(src, p + 2) << 8 | Mem.getU8(src, p + 3))) return ERR_DATA;
		return pos;
	}

	// one block's symbols with the codes lit and dist: false when it does not decode
	@:hxmc.unsafe static function block(s:Ptr, src:Ptr, out:Ptr, cap:Int, lit:Ptr, dist:Ptr):Bool {
		var pos = Mem.getI32(s, POS);
		while (true) {
			var sym = symbol(s, src, lit);
			if (sym < 256) {
				if (pos >= cap) return false;
				Mem.setI8(out, pos++, sym);
			} else if (sym == 256) {
				Mem.setI32(s, POS, pos);
				return Mem.getI32(s, BAD) == 0;
			} else {
				var k = sym - 257;
				if (k >= 29) return false;
				var len = lengthBase(k) + bits(s, src, lengthExtra(k));
				var d = symbol(s, src, dist);
				if (d >= 30) return false;
				var back = distBase(d) + bits(s, src, distExtra(d));
				if (back > pos || pos + len > cap || Mem.getI32(s, BAD) != 0) return false;
				if (back >= len) LibC.memcpy(out.add(pos), out.add(pos - back), len) else
					for (i in 0...len)
						Mem.setI8(out, pos + i, Mem.getU8(out, pos + i - back));
				pos += len;
			}
		}
	}

	// (past the input's end, zeros: no more than its reading ahead, else BAD)
	@:hxmc.unsafe static inline function need(s:Ptr, src:Ptr, n:Int) {
		var cnt = Mem.getI32(s, CNT);
		if (cnt < n) {
			var buf = Mem.getI32(s, BUF), p = Mem.getI32(s, P), end = Mem.getI32(s, END);
			while (cnt < n) {
				if (p < end) buf |= Mem.getU8(src, p) << cnt else if (p >= end + 4) Mem.setI32(s, BAD, 1);
				p++;
				cnt += 8;
			}
			Mem.setI32(s, BUF, buf);
			Mem.setI32(s, P, p);
			Mem.setI32(s, CNT, cnt);
		}
	}

	@:hxmc.unsafe static inline function bits(s:Ptr, src:Ptr, n:Int):Int {
		need(s, src, n);
		var buf = Mem.getI32(s, BUF);
		Mem.setI32(s, BUF, buf >>> n);
		Mem.setI32(s, CNT, Mem.getI32(s, CNT) - n);
		return buf & ((1 << n) - 1);
	}

	// (the whole bytes the bit buffer holds unread: given back to the input)
	@:hxmc.unsafe static function giveBack(s:Ptr) {
		Mem.setI32(s, P, Mem.getI32(s, P) - (Mem.getI32(s, CNT) >> 3));
		Mem.setI32(s, BUF, 0);
		Mem.setI32(s, CNT, 0);
	}

	// a symbol: the table for codes up to FAST bits, else bit by bit from the
	// canonical counts (a code's first bit its most significant)
	@:hxmc.unsafe static inline function symbol(s:Ptr, src:Ptr, h:Ptr):Int {
		need(s, src, 15);
		var buf = Mem.getI32(s, BUF);
		var e = Mem.getI32(h, 4 * (16 + 288) + 4 * (buf & ((1 << FAST) - 1)));
		return if (e != 0) {
			var len = e >> 9;
			Mem.setI32(s, BUF, buf >>> len);
			Mem.setI32(s, CNT, Mem.getI32(s, CNT) - len);
			e & 511;
		} else slow(s, src, h);
	}

	@:hxmc.unsafe static function slow(s:Ptr, src:Ptr, h:Ptr):Int {
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(s, src, 1);
			var count = Mem.getI32(h, 4 * len);
			if (code - count < first) return Mem.getI32(h, 4 * 16 + 4 * (index + (code - first)));
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		Mem.setI32(s, BAD, 1);
		return 999;
	}

	// a canonical code from n lengths at l: counts, symbols, the table of the
	// codes up to FAST bits (by their bits as read: reversed), each (length << 9) | symbol
	@:hxmc.unsafe static function build(h:Ptr, l:Ptr, n:Int) {
		LibC.memset(h, 0, CODE);
		for (i in 0...n) {
			var len = Mem.getI32(l, 4 * i);
			if (len > 0) Mem.setI32(h, 4 * len, Mem.getI32(h, 4 * len) + 1);
		}
		// (the symbols by length, then by value; `at` in the table's room until it is filled)
		var at = h.add(4 * (16 + 288)), total = 0;
		for (len in 1...16) {
			Mem.setI32(at, 4 * len, total);
			total += Mem.getI32(h, 4 * len);
		}
		for (sym in 0...n) {
			var len = Mem.getI32(l, 4 * sym);
			if (len > 0) {
				var k = Mem.getI32(at, 4 * len);
				Mem.setI32(h, 4 * (16 + k), sym);
				Mem.setI32(at, 4 * len, k + 1);
			}
		}
		LibC.memset(at, 0, 4 * 16);
		var code = 0, k = 0;
		for (len in 1...16) {
			for (i in 0...Mem.getI32(h, 4 * len)) {
				if (len <= FAST) {
					var r = 0, c = code;
					for (b in 0...len) {
						r = (r << 1) | (c & 1);
						c >>= 1;
					}
					var step = 1 << len, e = (len << 9) | Mem.getI32(h, 4 * (16 + k));
					var j = r;
					while (j < (1 << FAST)) {
						Mem.setI32(at, 4 * j, e);
						j += step;
					}
				}
				code++;
				k++;
			}
			code <<= 1;
		}
	}

	@:hxmc.unsafe static function adler(b:Ptr, n:Int):Int {
		var a = 1, c = 0, i = 0;
		while (i < n) {
			// (3800 bytes at most between the reductions: the sums stay under 2^31, signed)
			var stop = i + 3800 < n ? i + 3800 : n;
			while (i < stop) {
				a += Mem.getU8(b, i++);
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

	static inline function u32(b:Ptr, p:Int):Int
		return Mem.getU8(b, p) << 24 | Mem.getU8(b, p + 1) << 16 | Mem.getU8(b, p + 2) << 8 | Mem.getU8(b, p + 3);

	static inline function u16(b:Ptr, p:Int):Int
		return Mem.getU8(b, p) << 8 | Mem.getU8(b, p + 1);

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;
}
#end
