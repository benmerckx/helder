package helder.image;

import haxe.io.Bytes;
import hxmc.ReadOnlySpan;
import hxmc.Span;
import hxmc.unsafe.UInt8;
#if (target.name == "hxmc")
import helder.image.SpanDce; // (a workaround: see there)
#end

// PNG decoding, helder's one implementation: every colour type and bit
// depth, tRNS, Adam7 interlacing, to RGBA8 (rows top to bottom, straight
// alpha; 16-bit samples their high byte). A kernel (@:hxmc.kernel,
// docs/interop.md in hxmc, "Kernels"): on hxmc it touches no GC object and
// reads and writes memory only through checked spans (the compiler checks
// both), so the same code decodes a Bytes for PngDecoder on the calling
// thread (ReadOnlySpan.ofBytes, no copy) and an off-heap buffer for
// ImageJobs in a GC-free job's safe region; elsewhere (Eval, JavaScript)
// the spans are views of Bytes (hxmc's fallback), and the same code runs.
//
// The caller reads the header (info, into INFO bytes), gives a buffer of
// bufferLength bytes and decodes into it (decode: the file's IDAT chunks,
// read where they are; decodeStream: a zlib stream of any size with the
// header's format, an APNG frame's): the data inflated (as hxmc's std's
// InflateImpl: a 32-bit bit buffer, codes up to 10 bits by table, longer
// ones from their canonical counts), the rows unfiltered in place and
// packed, then widened to RGBA8 in place (from the end when a pixel has 32
// bits or fewer, from the start when more); an interlaced image's passes
// are inflated after the pixels and put in place. The pixels are the
// buffer's first width * height * 4 bytes. Its other memory (scratch: the
// inflater's state and tables) is allocated and freed by each decode:
// decodes on several threads are independent. Errors are results < 0, PngDecoder's messages (message).
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

	// the header's (info's 4-byte slots, by their byte offsets: Bytes.getInt32's)
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

	// what an error says (PngDecoder's), info as info left it
	public static function message(code:Int, info:Bytes):String {
		var d = info.getInt32(DETAIL);
		return "PngDecoder: " + switch code {
			case ERR_SIGNATURE: "not a PNG file";
			case ERR_TRUNCATED: "a truncated " + String.fromCharCode(d & 0xFF) + String.fromCharCode((d >> 8) & 0xFF) + String.fromCharCode((d >> 16) & 0xFF)
				+ String.fromCharCode(d >>> 24) + " chunk";
			case ERR_METHOD: "an unknown compression or filter method";
			case ERR_FORMAT: 'colour type ${info.getInt32(TYPE)} at bit depth ${info.getInt32(DEPTH)}';
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

	// the file's header into info (INFO bytes): 0, else an error
	@:hxmc.kernel public static function info(png:ReadOnlySpan<UInt8>, info:Span<UInt8>):Int {
		var f:Span<Int> = info.reinterpret();
		f.fill(0, INFO >> 2, 0);
		f[TYPE >> 2] = -1;
		var n = png.length;
		if (n < 8 || u32(png, 0) != 0x89504E47 || u32(png, 4) != 0x0D0A1A0A) return ERR_SIGNATURE;
		var p = 8, idat = 0;
		while (p + 8 <= n) {
			var len = u32(png, p), name = name(png, p + 4);
			if (len < 0 || p + 12 + len > n) {
				f[DETAIL >> 2] = name;
				return ERR_TRUNCATED;
			}
			if (name == 0x52444849) { // IHDR
				if (len < 13) return ERR_SHORT;
				f[WIDTH >> 2] = u32(png, p + 8);
				f[HEIGHT >> 2] = u32(png, p + 12);
				var d:Int = png[p + 16], t:Int = png[p + 17];
				f[DEPTH >> 2] = d;
				f[TYPE >> 2] = t;
				if (png[p + 18] != 0 || png[p + 19] != 0) return ERR_METHOD;
				f[INTERLACE >> 2] = png[p + 20];
				var ok = switch t {
					case 0: d == 1 || d == 2 || d == 4 || d == 8 || d == 16;
					case 3: d == 1 || d == 2 || d == 4 || d == 8;
					case 2 | 4 | 6: d == 8 || d == 16;
					case _: false;
				}
				if (!ok) return ERR_FORMAT;
				if (f[WIDTH >> 2] <= 0 || f[HEIGHT >> 2] <= 0) return ERR_EMPTY;
			} else if (name == 0x45544C50) { // PLTE
				f[PLTE_AT >> 2] = p + 8;
				f[PLTE_LEN >> 2] = len;
			} else if (name == 0x534E5274) { // tRNS
				f[TRNS_AT >> 2] = p + 8;
				f[TRNS_LEN >> 2] = len;
			} else if (name == 0x54414449) // IDAT
				idat += len;
			else if (name == 0x444E4549) // IEND
				break;
			p += 12 + len;
		}
		f[IDAT >> 2] = idat;
		var w = f[WIDTH >> 2], h = f[HEIGHT >> 2], t = f[TYPE >> 2];
		if (t < 0) return ERR_NO_IHDR;
		if (t == 3 && f[PLTE_LEN >> 2] == 0) return ERR_NO_PLTE;
		if (f[INTERLACE >> 2] > 1) {
			f[DETAIL >> 2] = f[INTERLACE >> 2];
			return ERR_INTERLACE;
		}
		// (the rows and the pixels within an Int: 2 GB)
		if (w > 1 << 24 || h > 1 << 24 || (h : Float) * (stride(f, w) + 2) * 2 + (w : Float) * h * 4 > 2147483000.0) return ERR_LARGE;
		return 0;
	}

	// the buffer decode needs for w x h pixels of the header's format (the
	// image, or an APNG frame): the rows with their filter bytes, or the
	// pixels if more; interlaced: the pixels, then the passes' rows
	@:hxmc.kernel public static function bufferLength(info:ReadOnlySpan<UInt8>, w:Int, h:Int):Int {
		var f:ReadOnlySpan<Int> = info.reinterpret();
		var rows = rawLength(f, w, h), px = w * h * 4;
		return f[INTERLACE >> 2] == 1 ? px + rows : rows > px ? rows : px;
	}

	// (the inflated data's length: each pass's rows, a filter byte each)
	@:hxmc.kernel static function rawLength(f:ReadOnlySpan<Int>, w:Int, h:Int):Int {
		if (f[INTERLACE >> 2] != 1) return h * (stride(f, w) + 1);
		var n = 0;
		for (k in 0...7) {
			var pw = passWidth(k, w), ph = passHeight(k, h);
			if (pw > 0 && ph > 0) n += ph * (stride(f, pw) + 1);
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
	static inline function stride(f:ReadOnlySpan<Int>, w:Int):Int
		return (w * pixelBits(f) + 7) >> 3;

	// (a pixel's bits)
	static inline function pixelBits(f:ReadOnlySpan<Int>):Int {
		var t = f[TYPE >> 2];
		return f[DEPTH >> 2] * (t == 2 ? 3 : t == 4 ? 2 : t == 6 ? 4 : 1);
	}

	// the file (info read) decoded into buf (bufferLength(info, width,
	// height) bytes): 0, the RGBA8 pixels at its start; else an error. The
	// IDAT chunks are inflated where they are, one after the other.
	@:hxmc.kernel public static function decode(png:ReadOnlySpan<UInt8>, info:Span<UInt8>, buf:Span<UInt8>):Int {
		var f:Span<Int> = info.reinterpret();
		var p = 8, n = png.length;
		while (p + 8 <= n) {
			var len = u32(png, p), name = name(png, p + 4);
			if (name == 0x54414449 && len > 0) return run(png, f, png, p + 8, p + 8 + len, true, f[WIDTH >> 2], f[HEIGHT >> 2], buf);
			if (name == 0x444E4549 || len < 0) break;
			p += 12 + len;
		}
		return ERR_DATA;
	}

	// a zlib stream (src), w x h pixels of the header's format, decoded into
	// buf (bufferLength(info, w, h) bytes): 0, else an error
	@:hxmc.kernel public static function decodeStream(png:ReadOnlySpan<UInt8>, info:Span<UInt8>, src:ReadOnlySpan<UInt8>, w:Int, h:Int, buf:Span<UInt8>):Int {
		var f:Span<Int> = info.reinterpret();
		return run(png, f, src, 0, src.length, false, w, h, buf);
	}

	// (the stream at src's [at, end), the IDAT chunks after it too when chunked)
	@:hxmc.kernel static function run(png:ReadOnlySpan<UInt8>, f:Span<Int>, src:ReadOnlySpan<UInt8>, at:Int, end:Int, chunked:Bool, w:Int, h:Int, buf:Span<UInt8>):Int {
		var interlaced = f[INTERLACE >> 2] == 1, rawLen = rawLength(f, w, h), px = w * h * 4;
		if (buf.length < (interlaced ? px + rawLen : rawLen > px ? rawLen : px)) return ERR_MEMORY;
		var raw = interlaced ? buf.sub(px, rawLen) : buf.sub(0, rawLen);
		var r = PngScratch.inflate(src, at, end, chunked, raw);
		if (r < 0) return r;
		if (r < rawLen) return ERR_SHORT;
		var b = pixelBits(f), bpp = b < 8 ? 1 : b >> 3;
		if (!interlaced) {
			var e = unfilter(f, raw, stride(f, w), h, bpp);
			if (e != 0) return e;
			return widen(png, f, buf, w, h);
		}
		var depth = f[DEPTH >> 2], type = f[TYPE >> 2], at = 0;
		for (k in 0...7) {
			var pw = passWidth(k, w), ph = passHeight(k, h);
			if (pw <= 0 || ph <= 0) continue;
			var s = stride(f, pw), rows = raw.sub(at, ph * (s + 1));
			var e = unfilter(f, rows, s, ph, bpp);
			if (e != 0) return e;
			for (j in 0...ph)
				for (i in 0...pw) {
					var e = pixel(png, f, depth, type, rows, j * s, i, buf, 4 * ((passY(k) + j * passDy(k)) * w + passX(k) + i * passDx(k)));
					if (e != 0) return e;
				}
			at += ph * (s + 1);
		}
		return 0;
	}

	// the rows unfiltered in place and packed: row j's bytes from
	// j * (stride + 1) + 1 to j * stride (always before them: read before
	// they are written over, front to back), the row above in place
	// already; bpp the bytes a filter looks back. Each row's spans (the
	// row, its filtered bytes, the row above, the bytes bpp back) of one
	// tested length, so that the loops' element checks are dropped.
	@:hxmc.kernel static function unfilter(f:Span<Int>, b:Span<UInt8>, stride:Int, h:Int, bpp:Int):Int {
		var lead = bpp < stride ? bpp : stride, m = stride - lead;
		for (j in 0...h) {
			var r = j * (stride + 1) + 1, d = j * stride;
			var filter:Int = b[r - 1];
			var cur = b.sub(d, stride), raw:ReadOnlySpan<UInt8> = b.sub(r, stride);
			// (the bytes from lead on, and those bpp before them: the row's own, the row above's)
			var cur2 = cur.sub(lead, m), raw2:ReadOnlySpan<UInt8> = raw.sub(lead, m), left:ReadOnlySpan<UInt8> = cur.sub(0, m);
			if (raw.length != stride || cur.length != stride || cur2.length != m || raw2.length != m || left.length != m) return ERR_DATA;
			if (j == 0) {
				// (nothing above: Up is None, Average halves the left, Paeth is Sub)
				switch filter {
					case 0 | 2:
						cur.blit(0, raw, 0, stride);
					case 1 | 4:
						cur.blit(0, raw, 0, lead);
						for (x in 0...m)
							cur2[x] = raw2[x] + left[x];
					case 3:
						cur.blit(0, raw, 0, lead);
						for (x in 0...m)
							cur2[x] = raw2[x] + (left[x] >> 1);
					case _:
						f[DETAIL >> 2] = filter;
						return ERR_FILTER;
				}
				continue;
			}
			var up:ReadOnlySpan<UInt8> = b.sub(d - stride, stride), up2:ReadOnlySpan<UInt8> = up.sub(lead, m), upLeft:ReadOnlySpan<UInt8> = up.sub(0, m);
			if (up.length != stride || up2.length != m || upLeft.length != m) return ERR_DATA;
			switch filter {
				case 0:
					cur.blit(0, raw, 0, stride);
				case 1:
					cur.blit(0, raw, 0, lead);
					for (x in 0...m)
						cur2[x] = raw2[x] + left[x];
				case 2:
					for (x in 0...stride)
						cur[x] = raw[x] + up[x];
				case 3:
					for (x in 0...lead)
						cur[x] = raw[x] + (up[x] >> 1);
					for (x in 0...m)
						cur2[x] = raw2[x] + ((left[x] + (up2[x] : Int)) >> 1);
				case 4:
					for (x in 0...lead)
						cur[x] = raw[x] + up[x];
					for (x in 0...m) {
						var a:Int = left[x], c:Int = upLeft[x], bb:Int = up2[x];
						var pa = abs(bb - c), pb = abs(a - c), pc = abs(a + bb - c - c);
						cur2[x] = raw2[x] + (pa <= pb && pa <= pc ? a : pb <= pc ? bb : c);
					}
				case _:
					f[DETAIL >> 2] = filter;
					return ERR_FILTER;
			}
		}
		return 0;
	}

	// the packed rows of w x h pixels widened to RGBA8 in place: from the
	// end when a pixel has 32 bits or fewer (each one's RGBA at or after its
	// own bytes), from the start when more (at or before)
	@:hxmc.kernel static function widen(png:ReadOnlySpan<UInt8>, f:Span<Int>, b:Span<UInt8>, w:Int, h:Int):Int {
		var depth = f[DEPTH >> 2], type = f[TYPE >> 2];
		if (type == 6 && depth == 8) return 0;
		var s = stride(f, w), back = pixelBits(f) <= 32;
		for (qy in 0...h)
			for (qx in 0...w) {
				var y = back ? h - 1 - qy : qy, x = back ? w - 1 - qx : qx;
				var e = pixel(png, f, depth, type, b, y * s, x, b, 4 * (y * w + x));
				if (e != 0) return e;
			}
		return 0;
	}

	// pixel x of the packed row at rows' at as RGBA8 at out's o (its samples
	// read before any is written: the same memory, widened in place): 0,
	// else an error
	static inline function pixel(png:ReadOnlySpan<UInt8>, f:Span<Int>, depth:Int, type:Int, rows:ReadOnlySpan<UInt8>, at:Int, x:Int, out:Span<UInt8>,
			o:Int):Int {
		var r = 0, g = 0, bl = 0, a = 255, e = 0;
		switch type {
			case 0:
				var v = stored(rows, at, x, 0, 1, depth);
				r = g = bl = scaled(v, depth);
				if (f[TRNS_LEN >> 2] >= 2 && v == u16(png, f[TRNS_AT >> 2])) a = 0;
			case 2:
				var sr = stored(rows, at, x, 0, 3, depth), sg = stored(rows, at, x, 1, 3, depth), sb = stored(rows, at, x, 2, 3, depth);
				r = scaled(sr, depth);
				g = scaled(sg, depth);
				bl = scaled(sb, depth);
				var t = f[TRNS_AT >> 2];
				if (f[TRNS_LEN >> 2] >= 6 && sr == u16(png, t) && sg == u16(png, t + 2) && sb == u16(png, t + 4)) a = 0;
			case 3:
				var k = stored(rows, at, x, 0, 1, depth), pal = f[PLTE_AT >> 2];
				if (3 * k + 2 >= f[PLTE_LEN >> 2]) {
					e = ERR_PALETTE;
					k = 0;
				}
				r = png[pal + 3 * k];
				g = png[pal + 3 * k + 1];
				bl = png[pal + 3 * k + 2];
				if (k < f[TRNS_LEN >> 2]) a = png[f[TRNS_AT >> 2] + k];
			case 4:
				r = g = bl = scaled(stored(rows, at, x, 0, 2, depth), depth);
				a = scaled(stored(rows, at, x, 1, 2, depth), depth);
			case _:
				r = scaled(stored(rows, at, x, 0, 4, depth), depth);
				g = scaled(stored(rows, at, x, 1, 4, depth), depth);
				bl = scaled(stored(rows, at, x, 2, 4, depth), depth);
				a = scaled(stored(rows, at, x, 3, 4, depth), depth);
		}
		out[o] = r;
		out[o + 1] = g;
		out[o + 2] = bl;
		out[o + 3] = a;
		return e;
	}

	// (sample k of pixel x of the packed row at rows' at, as stored)
	static inline function stored(rows:ReadOnlySpan<UInt8>, at:Int, x:Int, k:Int, channels:Int, depth:Int):Int {
		return if (depth == 16) u16(rows, at + 2 * (x * channels + k)) else if (depth == 8) (rows[at + x * channels + k] : Int) else {
			var bit = x * depth;
			(rows[at + (bit >> 3)] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
		}
	}

	// (a sample scaled to 8 bits: a 16-bit one's high byte)
	static inline function scaled(v:Int, depth:Int):Int
		return depth == 16 ? v >> 8 : depth == 8 ? v : Std.int(v * 255 / ((1 << depth) - 1));

	// --- inflate: the scratch (SCRATCH bytes, PngScratch's) holds the state
	// (a Bits) in its first STATE bytes, then Ints: each code's table (1024
	// entries), counts (16) and symbols (288), the code lengths (320), and
	// the fixed codes, built when a block uses them (fixed)

	static inline var FAST = 10;
	static inline var TABLE = 1 << FAST;
	static inline var COUNTS = TABLE;
	static inline var SYMBOLS = COUNTS + 16;
	static inline var CODE = SYMBOLS + 288;
	static inline var STATE = 64;
	static inline var LIT = STATE >> 2;
	static inline var DIST = LIT + CODE;
	static inline var CL = DIST + CODE;
	static inline var LENS = CL + CODE;
	static inline var FIXED_LIT = LENS + 320;
	static inline var FIXED_DIST = FIXED_LIT + CODE;
	public static inline var SCRATCH = 4 * (FIXED_DIST + CODE);

	// (the fixed codes, into the scratch)
	@:hxmc.kernel public static function fixed(scratch:Span<UInt8>) {
		var words:Span<Int> = scratch.reinterpret();
		var l = words.sub(LENS, 320);
		for (i in 0...288)
			l[i] = i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8;
		build(words.sub(FIXED_LIT, CODE), l, 288);
		for (i in 0...30)
			l[i] = 5;
		build(words.sub(FIXED_DIST, CODE), l, 30);
	}

	// (an inflate's failure: the data ended early, or does not decode)
	static inline function failed(st:Span<PngBits>):Int
		return st[0].bad == 2 ? ERR_SHORT : ERR_DATA;

	// a zlib stream at src's [at, end) (chunked: continued by the IDAT
	// chunks after it) inflated into out (its size known): the bytes
	// produced, or an error
	@:hxmc.kernel static function inflate(scratch:Span<UInt8>, src:ReadOnlySpan<UInt8>, at:Int, end:Int, chunked:Bool, out:Span<UInt8>):Int {
		var words:Span<Int> = scratch.reinterpret();
		var st:Span<PngBits> = scratch.sub(0, STATE).reinterpret();
		var lit = words.sub(LIT, CODE), dist = words.sub(DIST, CODE), cl = words.sub(CL, CODE), l = words.sub(LENS, 320);
		var flit = words.sub(FIXED_LIT, CODE), fdist = words.sub(FIXED_DIST, CODE);
		st[0].buf = 0;
		st[0].cnt = 0;
		st[0].p = at;
		st[0].end = end;
		st[0].pos = 0;
		st[0].bad = 0;
		st[0].chunked = chunked ? 1 : 0;
		var cmf = bits(st, src, 8), flg = bits(st, src, 8);
		if (st[0].bad != 0 || st[0].p > st[0].end || cmf & 15 != 8 || ((cmf << 8) + flg) % 31 != 0 || flg & 32 != 0) return ERR_DATA;
		var last = false, fixedBuilt = false;
		while (!last) {
			last = bits(st, src, 1) == 1;
			var type = bits(st, src, 2);
			if (type == 0) {
				// (stored: from the next byte, the bit buffer's whole bytes first)
				var skip = st[0].cnt & 7;
				st[0].buf = st[0].buf >>> skip;
				st[0].cnt -= skip;
				var len = bits(st, src, 16), nlen = bits(st, src, 16), pos = st[0].pos;
				if (st[0].bad != 0 || nlen != 0xFFFF - len || pos + len > out.length) return ERR_DATA;
				while (len > 0 && st[0].cnt >= 8) {
					out[pos++] = bits(st, src, 8);
					len--;
				}
				while (len > 0) {
					var p = st[0].p, e = st[0].end;
					if (p >= e) {
						if (st[0].chunked == 0) return ERR_DATA;
						hop(st, src);
						continue;
					}
					var k = e - p < len ? e - p : len;
					out.blit(pos, src, p, k);
					pos += k;
					len -= k;
					st[0].p = p + k;
				}
				st[0].pos = pos;
			} else if (type == 1) {
				if (!fixedBuilt) {
					fixed(scratch);
					fixedBuilt = true;
				}
				if (!block(st, src, out, flit, fdist)) return failed(st);
			} else if (type == 2) {
				var hlit = bits(st, src, 5) + 257, hdist = bits(st, src, 5) + 1, hclen = bits(st, src, 4) + 4;
				l.fill(0, 19, 0);
				for (i in 0...hclen)
					l[order(i)] = bits(st, src, 3);
				build(cl, l, 19);
				var i = 0, total = hlit + hdist;
				while (i < total) {
					var sym = symbol(st, src, cl);
					if (sym < 16) l[i++] = sym else {
						var v = 0, r = 0;
						if (sym == 16) {
							if (i == 0) return ERR_DATA;
							v = l[i - 1];
							r = 3 + bits(st, src, 2);
						} else r = sym == 17 ? 3 + bits(st, src, 3) : 11 + bits(st, src, 7);
						if (i + r > total) return ERR_DATA;
						l.fill(i, r, v);
						i += r;
					}
					if (st[0].bad != 0) return failed(st);
				}
				build(lit, l, hlit);
				build(dist, l.sub(hlit, hdist), hdist);
				if (!block(st, src, out, lit, dist)) return failed(st);
			} else
				return ERR_DATA;
			if (st[0].bad != 0) return failed(st);
		}
		// (zlib's Adler-32 of the output, big-endian, after the stream, from the next byte)
		var skip = st[0].cnt & 7;
		st[0].buf = st[0].buf >>> skip;
		st[0].cnt -= skip;
		var want = bits(st, src, 8) << 24;
		want |= bits(st, src, 8) << 16;
		want |= bits(st, src, 8) << 8;
		want |= bits(st, src, 8);
		// (no byte of it past the input's end)
		if (st[0].bad != 0 || st[0].p - (st[0].cnt >> 3) > st[0].end) return ERR_DATA;
		var pos = st[0].pos;
		if (adler(out.sub(0, pos)) != want) return ERR_DATA;
		return pos;
	}

	// one block's symbols with the codes lit and dist: false when it does
	// not decode. The hot loop: the bit buffer in locals (st's on the way
	// out, and around slow), refilled to 25 bits or more before a literal or
	// length (15 bits at most, its extra bits 5) and before a distance (15,
	// then 13); the tables' length tested, so that their masked lookups
	// are unchecked.
	@:hxmc.kernel static function block(st:Span<PngBits>, src:ReadOnlySpan<UInt8>, out:Span<UInt8>, lit:ReadOnlySpan<Int>, dist:ReadOnlySpan<Int>):Bool {
		if (lit.length < TABLE || dist.length < TABLE) return false;
		var pos = st[0].pos, cap = out.length;
		var buf = st[0].buf, cnt = st[0].cnt, p = st[0].p, end = st[0].end, ok = false;
		while (true) {
			while (cnt <= 24) {
				if (p < end) {
					buf |= src[p] << cnt;
					p++;
					cnt += 8;
				} else if (st[0].chunked != 0) {
					st[0].p = p;
					hop(st, src);
					p = st[0].p;
					end = st[0].end;
				} else {
					// (past the input's end: zeros, a few)
					if (p >= end + 4) break;
					p++;
					cnt += 8;
				}
			}
			var e = lit[buf & (TABLE - 1)], sym = 0;
			if (e != 0) {
				var len = e >> 9;
				buf >>>= len;
				cnt -= len;
				sym = e & 511;
			} else {
				st[0].buf = buf;
				st[0].cnt = cnt;
				st[0].p = p;
				sym = slow(st, src, lit);
				buf = st[0].buf;
				cnt = st[0].cnt;
				p = st[0].p;
				end = st[0].end;
			}
			if (sym < 256) {
				if (pos >= cap) break;
				out[pos++] = sym;
				continue;
			}
			if (sym == 256) {
				ok = true;
				break;
			}
			var k = sym - 257;
			if (k >= 29 || cnt < 5) break;
			var x = lengthExtra(k), len = lengthBase(k) + (buf & ((1 << x) - 1));
			buf >>>= x;
			cnt -= x;
			while (cnt <= 24) {
				if (p < end) {
					buf |= src[p] << cnt;
					p++;
					cnt += 8;
				} else if (st[0].chunked != 0) {
					st[0].p = p;
					hop(st, src);
					p = st[0].p;
					end = st[0].end;
				} else {
					// (past the input's end: zeros, a few)
					if (p >= end + 4) break;
					p++;
					cnt += 8;
				}
			}
			var e = dist[buf & (TABLE - 1)], d = 0;
			if (e != 0) {
				var n = e >> 9;
				buf >>>= n;
				cnt -= n;
				d = e & 511;
			} else {
				st[0].buf = buf;
				st[0].cnt = cnt;
				st[0].p = p;
				d = slow(st, src, dist);
				buf = st[0].buf;
				cnt = st[0].cnt;
				p = st[0].p;
				end = st[0].end;
			}
			if (d >= 30) break;
			var y = distExtra(d);
			if (cnt < y) {
				while (cnt <= 24) {
					if (p < end) {
						buf |= src[p] << cnt;
						p++;
						cnt += 8;
					} else if (st[0].chunked != 0) {
						st[0].p = p;
						hop(st, src);
						p = st[0].p;
						end = st[0].end;
					} else {
						// (past the input's end: zeros, a few)
						if (p >= end + 4) break;
						p++;
						cnt += 8;
					}
				}
				if (cnt < y) break;
			}
			var back = distBase(d) + (buf & ((1 << y) - 1));
			buf >>>= y;
			cnt -= y;
			if (back > pos || pos + len > cap || st[0].bad != 0) break;
			// (a copy from back bytes before: whole periods at a time, each copy's source before its target)
			var from = pos - back;
			while (len > 0) {
				var n = pos - from < len ? pos - from : len;
				out.blit(pos, out, from, n);
				pos += n;
				len -= n;
			}
		}
		st[0].buf = buf;
		st[0].cnt = cnt;
		st[0].p = p;
		st[0].pos = pos;
		// (bits taken from past the input's end: it ended early)
		if (st[0].chunked == 0 && p - (cnt >> 3) > end) st[0].bad = 2;
		return ok && st[0].bad == 0;
	}

	// (n bits in the buffer: the input's next bytes, the next IDAT chunk's
	// when one ends; past the input's end, zeros: no more than its reading
	// ahead, else bad)
	static inline function need(st:Span<PngBits>, src:ReadOnlySpan<UInt8>, n:Int) {
		var cnt = st[0].cnt;
		if (cnt < n) {
			var buf = st[0].buf, p = st[0].p, end = st[0].end;
			while (cnt < n) {
				if (p >= end && st[0].chunked != 0) {
					st[0].p = p;
					hop(st, src);
					p = st[0].p;
					end = st[0].end;
				}
				if (p < end) buf |= src[p] << cnt else if (p >= end + 4) st[0].bad = 2;
				p++;
				cnt += 8;
			}
			st[0].buf = buf;
			st[0].p = p;
			st[0].cnt = cnt;
		}
	}

	// (the chunk ended: the next IDAT chunk with data, else the stream's end)
	@:hxmc.kernel static function hop(st:Span<PngBits>, src:ReadOnlySpan<UInt8>) {
		var q = st[0].end + 4;
		while (q + 8 <= src.length) {
			var len = u32(src, q);
			if (name(src, q + 4) != 0x54414449 || len < 0 || q + 12 + len > src.length) break;
			if (len > 0) {
				st[0].p = q + 8;
				st[0].end = q + 8 + len;
				return;
			}
			q += 12;
		}
		st[0].chunked = 0;
	}

	static inline function bits(st:Span<PngBits>, src:ReadOnlySpan<UInt8>, n:Int):Int {
		need(st, src, n);
		var buf = st[0].buf;
		st[0].buf = buf >>> n;
		st[0].cnt -= n;
		return buf & ((1 << n) - 1);
	}

	// a symbol: the table for codes up to FAST bits, else bit by bit from the
	// canonical counts (a code's first bit its most significant)
	static inline function symbol(st:Span<PngBits>, src:ReadOnlySpan<UInt8>, h:ReadOnlySpan<Int>):Int {
		need(st, src, 15);
		var buf = st[0].buf;
		var e = h[buf & (TABLE - 1)];
		return if (e != 0) {
			var len = e >> 9;
			st[0].buf = buf >>> len;
			st[0].cnt -= len;
			e & 511;
		} else slow(st, src, h);
	}

	@:hxmc.kernel static function slow(st:Span<PngBits>, src:ReadOnlySpan<UInt8>, h:ReadOnlySpan<Int>):Int {
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(st, src, 1);
			var count = h[COUNTS + len];
			if (code - count < first) return h[SYMBOLS + index + (code - first)];
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		st[0].bad = 1;
		return 999;
	}

	// a canonical code from n lengths: the table of the codes up to FAST
	// bits (by their bits as read: reversed), each (length << 9) | symbol,
	// the counts, the symbols
	@:hxmc.kernel static function build(h:Span<Int>, l:ReadOnlySpan<Int>, n:Int) {
		h.fill(0, CODE, 0);
		for (i in 0...n) {
			var len = l[i];
			if (len > 0) h[COUNTS + len] += 1;
		}
		// (the symbols by length, then by value; the next one's place by length in the table's room until it is filled)
		var total = 0;
		for (len in 1...16) {
			h[len] = total;
			total += h[COUNTS + len];
		}
		for (sym in 0...n) {
			var len = l[sym];
			if (len > 0) {
				var k = h[len];
				h[SYMBOLS + k] = sym;
				h[len] = k + 1;
			}
		}
		h.fill(0, 16, 0);
		var code = 0, k = 0;
		for (len in 1...16) {
			for (i in 0...h[COUNTS + len]) {
				if (len <= FAST) {
					var r = 0, c = code;
					for (b in 0...len) {
						r = (r << 1) | (c & 1);
						c >>= 1;
					}
					var step = 1 << len, e = (len << 9) | h[SYMBOLS + k];
					var j = r;
					while (j < TABLE) {
						h[j] = e;
						j += step;
					}
				}
				code++;
				k++;
			}
			code <<= 1;
		}
	}

	@:hxmc.kernel static function adler(b:ReadOnlySpan<UInt8>):Int {
		var a = 1, c = 0, i = 0, n = b.length;
		while (i < n) {
			// (3800 bytes at most between the reductions: the sums stay under 2^31, signed)
			var m = b.sub(i, n - i < 3800 ? n - i : 3800);
			for (j in 0...m.length) {
				a += m[j];
				c += a;
			}
			i += m.length;
			a %= 65521;
			c %= 65521;
		}
		return (c << 16) | a;
	}

	// (deflate's tables as arithmetic)
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

	// (big-endian, as PNG's numbers are; a chunk's name as its bytes in memory, little-endian)
	static inline function u32(b:ReadOnlySpan<UInt8>, p:Int):Int
		return (b[p] : Int) << 24 | (b[p + 1] : Int) << 16 | (b[p + 2] : Int) << 8 | (b[p + 3] : Int);

	static inline function name(b:ReadOnlySpan<UInt8>, p:Int):Int
		return (b[p] : Int) | (b[p + 1] : Int) << 8 | (b[p + 2] : Int) << 16 | (b[p + 3] : Int) << 24;

	static inline function u16(b:ReadOnlySpan<UInt8>, p:Int):Int
		return (b[p] : Int) << 8 | (b[p + 1] : Int);

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;
}

// (the inflater's state, public: hxmc's span fallback reinterprets to no private type: the bit buffer, its count, the input's position
// and its chunk's end, the output's position, a failure (2: the input ran
// out; 1: a bad code), whether IDAT chunks continue the input)
@:noCompletion @:hxmc.struct @:publicFields class PngBits {
	var buf:Int;
	var cnt:Int;
	var p:Int;
	var end:Int;
	var pos:Int;
	var bad:Int;
	var chunked:Int;

	function new() {}
}

// (the scratch for an inflate: PngCore.SCRATCH bytes, malloc'ed and freed
// on hxmc, a Bytes elsewhere)
@:access(helder.image.PngCore)
private class PngScratch {
	#if (target.name == "hxmc")
	@:hxmc.unsafe @:hxmc.kernel public static function inflate(src:ReadOnlySpan<UInt8>, at:Int, end:Int, chunked:Bool, out:Span<UInt8>):Int {
		var p:hxmc.unsafe.Ptr<UInt8> = cast hxmc.unsafe.LibC.malloc(PngCore.SCRATCH);
		if (p.isNull()) return PngCore.ERR_MEMORY;
		var r = PngCore.inflate(Span.unsafeOf(p, PngCore.SCRATCH), src, at, end, chunked, out);
		hxmc.unsafe.LibC.free(p);
		return r;
	}
	#else
	@:hxmc.kernel public static function inflate(src:ReadOnlySpan<UInt8>, at:Int, end:Int, chunked:Bool, out:Span<UInt8>):Int
		return PngCore.inflate(Span.ofBytes(Bytes.alloc(PngCore.SCRATCH)), src, at, end, chunked, out);
	#end
}
