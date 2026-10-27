import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;
import helder.scoped.*;

// OffHeapPng's decode on helder.scoped's memory (tests/bench/Jobs.hx,
// variant c): the same steps, the IDAT chunks, the inflate's state and codes
// and the filtered rows in Slices of the caller's scope, the rows unfiltered
// in place; the pixels are a Slice of the result's first width * height * 4
// bytes. The PNG itself is read from the host's memory (a Ptr: an I/O
// buffer), which a Slice cannot view. Errors: `error` < 0 and an empty Slice.
@:build(helder.scoped.Scoped.build())
class ScopedPng {
	// (each code's Slice<Int>: counts (16), symbols (288), the table (1024))
	static inline var FAST = 10;
	static inline var SYMBOLS = 16;
	static inline var TABLE = 16 + 288;
	static inline var CODE = 16 + 288 + 1024;
	// (the state: the bit buffer, its count, the input's position and end, the output's position, BAD)
	static inline var BUF = 0;
	static inline var CNT = 1;
	static inline var P = 2;
	static inline var END = 3;
	static inline var POS = 4;
	static inline var BAD = 5;

	public static var error = 0;
	public static var width = 0;
	public static var height = 0;

	// png's n bytes decoded: the pixels, in the caller's scope
	@:scoped public static function decode(png:Ptr, n:Int):Slice<U8> {
		error = OffHeapPng.ERR_FORMAT;
		if (n < 8 || Mem.getI32(png, 0) != 0x474E5089 || Mem.getI32(png, 4) != 0x0A1A0A0D) return Scope.slice(U8, 0);
		var p = 8, idatLen = 0, w = 0, h = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = Mem.getI32(png, p + 4);
			if (len < 0 || p + 12 + len > n) return Scope.slice(U8, 0);
			if (name == 0x52444849) {
				w = u32(png, p + 8);
				h = u32(png, p + 12);
				if (Mem.getU8(png, p + 16) != 8 || Mem.getU8(png, p + 17) != 6 || Mem.getU8(png, p + 20) != 0) {
					error = OffHeapPng.ERR_UNSUPPORTED;
					return Scope.slice(U8, 0);
				}
			} else if (name == 0x54414449)
				idatLen += len;
			else if (name == 0x444E4549)
				break;
			p += 12 + len;
		}
		if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return Scope.slice(U8, 0);
		var stride = w * 4, rawLen = h * (stride + 1);
		var idat = Scope.slice(U8, idatLen + 8);
		var raw = Scope.slice(U8, rawLen);
		// (from the host's memory: a word at a time, as scoped has no copy from a Ptr)
		p = 8;
		var at = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = Mem.getI32(png, p + 4);
			if (name == 0x54414449) {
				var k = 0;
				while (k + 4 <= len) {
					idat.setI32At(at + k, Mem.getI32(png, p + 8 + k));
					k += 4;
				}
				while (k < len) {
					idat[at + k] = Mem.getU8(png, p + 8 + k);
					k++;
				}
				at += len;
			} else if (name == 0x444E4549)
				break;
			p += 12 + len;
		}
		var r = inflate(idat, idatLen, raw);
		if (r != rawLen) {
			error = r < 0 ? r : OffHeapPng.ERR_DATA;
			return Scope.slice(U8, 0);
		}
		error = unfilter(raw, w, h);
		if (error < 0) return Scope.slice(U8, 0);
		width = w;
		height = h;
		return raw.sub(0, w * h * 4);
	}

	@:scoped static function unfilter(b:Slice<U8>, w:Int, h:Int):Int {
		var stride = w * 4;
		for (j in 0...h) {
			var f:Int = b[j * (stride + 1)], r = j * (stride + 1) + 1, d = j * stride, u = d - stride;
			switch f {
				case 0:
					b.blit(d, b, r, stride);
				case 1:
					for (x in 0...4)
						b[d + x] = b[r + x];
					for (x in 4...stride)
						b[d + x] = (b[r + x] + b[d + x - 4]) & 0xFF;
				case 2:
					if (j == 0) b.blit(d, b, r, stride) else
						for (x in 0...stride)
							b[d + x] = (b[r + x] + b[u + x]) & 0xFF;
				case 3:
					for (x in 0...4)
						b[d + x] = (b[r + x] + (j == 0 ? 0 : b[u + x] >> 1)) & 0xFF;
					for (x in 4...stride)
						b[d + x] = (b[r + x] + ((b[d + x - 4] + (j == 0 ? 0 : (b[u + x] : Int))) >> 1)) & 0xFF;
				case 4:
					if (j == 0) {
						for (x in 0...4)
							b[d + x] = b[r + x];
						for (x in 4...stride)
							b[d + x] = (b[r + x] + b[d + x - 4]) & 0xFF;
					} else {
						for (x in 0...4)
							b[d + x] = (b[r + x] + b[u + x]) & 0xFF;
						for (x in 4...stride) {
							var a:Int = b[d + x - 4], c:Int = b[u + x - 4], bb:Int = b[u + x];
							var pa = abs(bb - c), pb = abs(a - c), pc = abs(a + bb - c - c);
							b[d + x] = (b[r + x] + (pa <= pb && pa <= pc ? a : pb <= pc ? bb : c)) & 0xFF;
						}
					}
				case _:
					return OffHeapPng.ERR_DATA;
			}
		}
		return 0;
	}

	// --- inflate

	@:scoped static function inflate(src:Slice<U8>, n:Int, out:Slice<U8>):Int {
		if (n < 2) return OffHeapPng.ERR_DATA;
		var cmf:Int = src[0], flg:Int = src[1];
		if (cmf & 15 != 8 || ((cmf << 8) + flg) % 31 != 0 || flg & 32 != 0) return OffHeapPng.ERR_DATA;
		var s = Scope.slice(Int, 6);
		s[P] = 2;
		s[END] = n;
		var lit = Scope.slice(Int, CODE), dist = Scope.slice(Int, CODE), cl = Scope.slice(Int, CODE), l = Scope.slice(Int, 320);
		var cap = out.length;
		var last = false;
		while (!last) {
			last = bits(s, src, 1) == 1;
			var type = bits(s, src, 2);
			if (type == 0) {
				giveBack(s);
				var p = s[P];
				if (p + 4 > n) return OffHeapPng.ERR_DATA;
				var len = src[p] | src[p + 1] << 8, nlen = src[p + 2] | src[p + 3] << 8;
				p += 4;
				var pos = s[POS];
				if (nlen != 0xFFFF - len || p + len > n || pos + len > cap) return OffHeapPng.ERR_DATA;
				out.blit(pos, src, p, len);
				s[POS] = pos + len;
				s[P] = p + len;
			} else if (type == 1) {
				// (the fixed codes: built for the block, a Slice cannot be kept in a static)
				for (i in 0...288)
					l[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8;
				build(lit, l, 0, 288);
				for (i in 0...30)
					l[i] = 5;
				build(dist, l, 0, 30);
				if (!block(s, src, out, lit, dist)) return OffHeapPng.ERR_DATA;
			} else if (type == 2) {
				var hlit = bits(s, src, 5) + 257, hdist = bits(s, src, 5) + 1, hclen = bits(s, src, 4) + 4;
				for (i in 0...19)
					l[i] = 0;
				for (i in 0...hclen)
					l[order(i)] = bits(s, src, 3);
				build(cl, l, 0, 19);
				var i = 0, total = hlit + hdist;
				while (i < total) {
					var sym = symbol(s, src, cl);
					if (sym < 16) l[i++] = sym else {
						var v = 0, r = 0;
						if (sym == 16) {
							if (i == 0) return OffHeapPng.ERR_DATA;
							v = l[i - 1];
							r = 3 + bits(s, src, 2);
						} else r = sym == 17 ? 3 + bits(s, src, 3) : 11 + bits(s, src, 7);
						if (i + r > total) return OffHeapPng.ERR_DATA;
						for (k in 0...r)
							l[i++] = v;
					}
					if (s[BAD] != 0) return OffHeapPng.ERR_DATA;
				}
				build(lit, l, 0, hlit);
				build(dist, l, hlit, hdist);
				if (!block(s, src, out, lit, dist)) return OffHeapPng.ERR_DATA;
			} else
				return OffHeapPng.ERR_DATA;
			if (s[BAD] != 0) return OffHeapPng.ERR_DATA;
		}
		giveBack(s);
		var p = s[P], pos = s[POS];
		if (p + 4 > n) return OffHeapPng.ERR_DATA;
		if (adler(out, pos) != (src[p] << 24 | src[p + 1] << 16 | src[p + 2] << 8 | src[p + 3])) return OffHeapPng.ERR_DATA;
		return pos;
	}

	@:scoped static function block(s:Slice<Int>, src:Slice<U8>, out:Slice<U8>, lit:Slice<Int>, dist:Slice<Int>):Bool {
		var pos = s[POS], cap = out.length;
		while (true) {
			var sym = symbol(s, src, lit);
			if (sym < 256) {
				if (pos >= cap) return false;
				out[pos++] = sym;
			} else if (sym == 256) {
				s[POS] = pos;
				return s[BAD] == 0;
			} else {
				var k = sym - 257;
				if (k >= 29) return false;
				var len = lengthBase(k) + bits(s, src, lengthExtra(k));
				var d = symbol(s, src, dist);
				if (d >= 30) return false;
				var back = distBase(d) + bits(s, src, distExtra(d));
				if (back > pos || pos + len > cap || s[BAD] != 0) return false;
				if (back >= len) out.blit(pos, out, pos - back, len) else
					for (i in 0...len)
						out[pos + i] = out[pos + i - back];
				pos += len;
			}
		}
		// (the scope macro's loop is no `while (true)` to the typer)
		return false;
	}

	static inline function need(s:Slice<Int>, src:Slice<U8>, n:Int) {
		var cnt = s[CNT];
		if (cnt < n) {
			var buf = s[BUF], p = s[P], end = s[END];
			while (cnt < n) {
				if (p < end) buf |= src[p] << cnt else if (p >= end + 4) s[BAD] = 1;
				p++;
				cnt += 8;
			}
			s[BUF] = buf;
			s[P] = p;
			s[CNT] = cnt;
		}
	}

	static inline function bits(s:Slice<Int>, src:Slice<U8>, n:Int):Int {
		need(s, src, n);
		var buf = s[BUF];
		s[BUF] = buf >>> n;
		s[CNT] = s[CNT] - n;
		return buf & ((1 << n) - 1);
	}

	static function giveBack(s:Slice<Int>) {
		s[P] = s[P] - (s[CNT] >> 3);
		s[BUF] = 0;
		s[CNT] = 0;
	}

	static inline function symbol(s:Slice<Int>, src:Slice<U8>, h:Slice<Int>):Int {
		need(s, src, 15);
		var buf = s[BUF];
		var e = h[TABLE + (buf & ((1 << FAST) - 1))];
		return if (e != 0) {
			var len = e >> 9;
			s[BUF] = buf >>> len;
			s[CNT] = s[CNT] - len;
			e & 511;
		} else slow(s, src, h);
	}

	@:scoped static function slow(s:Slice<Int>, src:Slice<U8>, h:Slice<Int>):Int {
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(s, src, 1);
			var count = h[len];
			if (code - count < first) return h[SYMBOLS + index + (code - first)];
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		s[BAD] = 1;
		return 999;
	}

	// a canonical code from the n lengths of l from `from`
	@:scoped static function build(h:Slice<Int>, l:Slice<Int>, from:Int, n:Int) {
		for (i in 0...h.length)
			h[i] = 0;
		for (i in 0...n) {
			var len = l[from + i];
			if (len > 0) h[len] = h[len] + 1;
		}
		// (the symbols by length, then by value; their places in the table's room until it is filled)
		var total = 0;
		for (len in 1...16) {
			h[TABLE + len] = total;
			total += h[len];
		}
		for (sym in 0...n) {
			var len = l[from + sym];
			if (len > 0) {
				var k = h[TABLE + len];
				h[SYMBOLS + k] = sym;
				h[TABLE + len] = k + 1;
			}
		}
		for (i in 0...16)
			h[TABLE + i] = 0;
		var code = 0, k = 0;
		for (len in 1...16) {
			for (i in 0...h[len]) {
				if (len <= FAST) {
					var r = 0, c = code;
					for (b in 0...len) {
						r = (r << 1) | (c & 1);
						c >>= 1;
					}
					var step = 1 << len, e = (len << 9) | h[SYMBOLS + k];
					var j = r;
					while (j < (1 << FAST)) {
						h[TABLE + j] = e;
						j += step;
					}
				}
				code++;
				k++;
			}
			code <<= 1;
		}
	}

	@:scoped static function adler(b:Slice<U8>, n:Int):Int {
		var a = 1, c = 0, i = 0;
		while (i < n) {
			var stop = i + 3800 < n ? i + 3800 : n;
			while (i < stop) {
				a += b[i++];
				c += a;
			}
			a %= 65521;
			c %= 65521;
		}
		return (c << 16) | a;
	}

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
