import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// A GC-free PNG decode over malloc'ed memory (tests/bench/Jobs.hx, variant
// d): RGBA8, non-interlaced, as PngDecoder's path for it. The PNG's IDAT
// chunks gathered, inflated as hxmc's std does it (haxe.zip.InflateImpl's
// Fast: a 32-bit bit buffer, codes up to 10 bits by table, longer ones from
// their canonical counts) into a buffer of the image's filtered rows, which
// are unfiltered in place: the pixels are its first width * height * 4
// bytes, freed by the caller (LibC.free). Every function is @:hxmc.unsafe:
// the compiler checks it never touches the GC heap, so it may run in a safe
// region. Errors are results: < 0.
class OffHeapPng {
	public static inline var ERR_FORMAT = -1; // not a PNG, a bad chunk
	public static inline var ERR_UNSUPPORTED = -2; // not RGBA8 non-interlaced
	public static inline var ERR_DATA = -3; // the zlib stream does not decode
	public static inline var ERR_MEMORY = -4;

	// (the scratch memory's layout: the state, then each code's counts (16),
	// symbols (288) and table (1024 entries), then the code lengths (320))
	static inline var FAST = 10;
	static inline var CODE = 4 * (16 + 288 + 1024);
	static inline var LIT = 64;
	static inline var DIST = LIT + CODE;
	static inline var CL = DIST + CODE;
	static inline var LENS = CL + CODE;
	static inline var SCRATCH = LENS + 4 * 320;
	// (the fixed codes', built once)
	static var fixed:Ptr;

	// the result of the last decode
	public static var width = 0;
	public static var height = 0;
	public static var pixels:Ptr;

	// png's n bytes decoded: 0, pixels and its size set; else an error
	@:hxmc.unsafe public static function decode(png:Ptr, n:Int):Int {
		if (n < 8 || Mem.getI32(png, 0) != 0x474E5089 || Mem.getI32(png, 4) != 0x0A1A0A0D) return ERR_FORMAT;
		// the header, and the image data's size
		var p = 8, idatLen = 0, w = 0, h = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = Mem.getI32(png, p + 4);
			if (len < 0 || p + 12 + len > n) return ERR_FORMAT;
			if (name == 0x52444849) { // IHDR
				w = u32(png, p + 8);
				h = u32(png, p + 12);
				if (Mem.getU8(png, p + 16) != 8 || Mem.getU8(png, p + 17) != 6 || Mem.getU8(png, p + 20) != 0) return ERR_UNSUPPORTED;
			} else if (name == 0x54414449) // IDAT
				idatLen += len;
			else if (name == 0x444E4549) // IEND
				break;
			p += 12 + len;
		}
		if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return ERR_FORMAT;
		var idat = LibC.malloc((idatLen : I64) + 8);
		var stride = w * 4, rawLen = h * (stride + 1);
		var raw = LibC.malloc((rawLen : I64));
		var scratch = LibC.malloc(SCRATCH);
		if (idat.isNull() || raw.isNull() || scratch.isNull()) return ERR_MEMORY;
		p = 8;
		var at = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = Mem.getI32(png, p + 4);
			if (name == 0x54414449) {
				LibC.memcpy(idat.add(at), png.add(p + 8), (len : I64));
				at += len;
			} else if (name == 0x444E4549)
				break;
			p += 12 + len;
		}
		var r = inflate(scratch, idat, idatLen, raw, rawLen);
		LibC.free(idat);
		LibC.free(scratch);
		if (r != rawLen) {
			LibC.free(raw);
			return r < 0 ? r : ERR_DATA;
		}
		r = unfilter(raw, w, h);
		if (r < 0) {
			LibC.free(raw);
			return r;
		}
		width = w;
		height = h;
		pixels = raw;
		return 0;
	}

	// the rows unfiltered in place: row j's bytes from j * (stride + 1) + 1 to
	// j * stride (always before them), the row above already in place
	@:hxmc.unsafe static function unfilter(b:Ptr, w:Int, h:Int):Int {
		var stride = w * 4;
		for (j in 0...h) {
			var f = Mem.getU8(b, j * (stride + 1)), r = j * (stride + 1) + 1, d = j * stride, u = d - stride;
			switch f {
				case 0:
					LibC.memmove(b.add(d), b.add(r), (stride : I64));
				case 1:
					for (x in 0...4)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x));
					for (x in 4...stride)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, d + x - 4));
				case 2:
					if (j == 0) LibC.memmove(b.add(d), b.add(r), (stride : I64)) else
						for (x in 0...stride)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, u + x));
				case 3:
					for (x in 0...4)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x) + (j == 0 ? 0 : Mem.getU8(b, u + x) >> 1));
					for (x in 4...stride)
						Mem.setI8(b, d + x, Mem.getU8(b, r + x) + ((Mem.getU8(b, d + x - 4) + (j == 0 ? 0 : Mem.getU8(b, u + x))) >> 1));
				case 4:
					if (j == 0) {
						// (Paeth with nothing above: the byte to the left)
						for (x in 0...4)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x));
						for (x in 4...stride)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, d + x - 4));
					} else {
						for (x in 0...4)
							Mem.setI8(b, d + x, Mem.getU8(b, r + x) + Mem.getU8(b, u + x));
						for (x in 4...stride) {
							var a = Mem.getU8(b, d + x - 4), c = Mem.getU8(b, u + x - 4), bb = Mem.getU8(b, u + x);
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

	// --- inflate: the state at s (the bit buffer, its count, the input's
	// position and end, the output's position)

	static inline var BUF = 0;
	static inline var CNT = 4;
	static inline var P = 8;
	static inline var END = 12;
	static inline var POS = 16;
	static inline var BAD = 20; // (the input ran out, or a bad code)

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
		if (fixed.isNull()) {
			fixed = LibC.malloc(2 * CODE);
			var l = s.add(LENS);
			for (i in 0...288)
				Mem.setI32(l, 4 * i, i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8);
			build(fixed, l, 288);
			for (i in 0...30)
				Mem.setI32(l, 4 * i, 5);
			build(fixed.add(CODE), l, 30);
		}
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
				LibC.memcpy(out.add(pos), src.add(p), (len : I64));
				Mem.setI32(s, POS, pos + len);
				Mem.setI32(s, P, p + len);
			} else if (type == 1) {
				if (!block(s, src, out, cap, fixed, fixed.add(CODE))) return ERR_DATA;
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
				if (back >= len) LibC.memcpy(out.add(pos), out.add(pos - back), (len : I64)) else
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

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;
}
