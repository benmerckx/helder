package helder.pdf;

import haxe.io.Bytes;
import helder.pdf.PdfValue;

// CCITTFaxDecode (ITU-T T.4 and T.6), ported from leanpdf's core/ccitt.ts:
// Group 3 one-dimensional (MH), mixed one- and two-dimensional (MR) and
// Group 4 (MMR). Rows are decoded as lists of changing elements (where
// the colour flips), each the reference line of the next. Out: packed
// rows of 1-bit pixels, each padded to a byte, 0 black unless BlackIs1;
// what was decoded before damage (null when nothing was).
class Ccitt {
	static inline var MAX_COLUMNS = 1 << 20;

	// run-length codes as (1 << bits) | code: white and black terminating codes (runs 0-63), then
	// make-up codes (64-1728), then the extended make-up codes both share (1792-2560)
	static final WHITE = [
		309, 71, 23, 24, 27, 28, 30, 31, 51, 52, 39, 40, 72, 67, 116, 117, 106, 107, 167, 140, 136, 151, 131, 132, 168, 171, 147, 164, 152, 258, 259, 282,
		283, 274, 275, 276, 277, 278, 279, 296, 297, 298, 299, 300, 301, 260, 261, 266, 267, 338, 339, 340, 341, 292, 293, 344, 345, 346, 347, 330, 331, 306,
		307, 308, 59, 50, 87, 183, 310, 311, 356, 357, 360, 359, 716, 717, 722, 723, 724, 725, 726, 727, 728, 729, 730, 731, 664, 665, 666, 88, 667];
	static final BLACK = [
		1079, 10, 7, 6, 11, 19, 18, 35, 69, 68, 132, 133, 135, 260, 263, 536, 1047, 1048, 1032, 2151, 2152, 2156, 2103, 2088, 2071, 2072, 4298, 4299, 4300,
		4301, 4200, 4201, 4202, 4203, 4306, 4307, 4308, 4309, 4310, 4311, 4204, 4205, 4314, 4315, 4180, 4181, 4182, 4183, 4196, 4197, 4178, 4179, 4132, 4151,
		4152, 4135, 4136, 4184, 4185, 4139, 4140, 4186, 4198, 4199, 1039, 4296, 4297, 4187, 4147, 4148, 4149, 8300, 8301, 8266, 8267, 8268, 8269, 8306, 8307,
		8308, 8309, 8310, 8311, 8274, 8275, 8276, 8277, 8282, 8283, 8292, 8293];
	static final EXTENDED = [2056, 2060, 2061, 4114, 4115, 4116, 4117, 4118, 4119, 4124, 4125, 4126, 4127];

	static var tables:Null<Array<haxe.ds.Vector<Int>>> = null;

	// (a lookup on the next 13 bits: run << 4 | the code's length, 0 where no code matches)
	static function table(codes:Array<Int>):haxe.ds.Vector<Int> {
		var t = new haxe.ds.Vector<Int>(8192, 0);
		var all = codes.concat(EXTENDED);
		for (i in 0...all.length) {
			var s = all[i], len = 0;
			while ((s >> (len + 1)) != 0)
				len++;
			var at = (s ^ (1 << len)) << (13 - len);
			var v = ((i < 64 ? i : (i - 63) * 64) << 4) | len;
			for (k in at...at + (1 << (13 - len)))
				t[k] = v;
		}
		return t;
	}

	public static function decode(data:Bytes, p:Null<PdfDict>, budget:Int):Null<Bytes> {
		inline function int(k:String, d:Int)
			return p == null ? d : Values.int(p.get(k), d);
		inline function bool(k:String)
			return p != null && Values.bool(p.get(k));
		var k = int("K", 0), cols = int("Columns", 1728), rows = int("Rows", 0);
		var eol = bool("EndOfLine"), byteAlign = bool("EncodedByteAlign"), blackIs1 = bool("BlackIs1"), damagedMax = int("DamagedRowsBeforeError", 0);
		if (cols < 1 || cols > MAX_COLUMNS) return null;
		if (tables == null) tables = [table(WHITE), table(BLACK)];
		var T = tables;
		var rowBytes = (cols + 7) >> 3;
		var maxRows = Std.int(Math.min(rows > 0 ? rows : 0x7FFFFFFF, budget / rowBytes));
		var out = Bytes.alloc(rowBytes * Std.int(Math.max(1, Math.min(maxRows, 256))));
		var len = data.length, end = len * 8, pos = 0;
		inline function at(i:Int):Int
			return i < len ? data.get(i) : 0;
		// (the next n (at most 13) bits, zeros past the end)
		inline function peek(n:Int):Int
			return (((at(pos >> 3) << 16) | (at((pos >> 3) + 1) << 8) | at((pos >> 3) + 2)) >>> (24 - n - (pos & 7))) & ((1 << n) - 1);
		// (the changing elements of the reference and the coding line, then sentinels)
		var ref = new haxe.ds.Vector<Int>(cols + 4, cols);
		var cur = new haxe.ds.Vector<Int>(cols + 4, 0);
		var n = 0;
		function add(x:Int) {
			if (x >= cols) return;
			// (a zero-length run cancels the change before: damaged data may even go back)
			if (n > 0 && x <= cur[n - 1]) n-- else cur[n++] = x;
		}
		// (one run of a colour: make-up codes, then a terminating one; -1 when invalid)
		function run(color:Int):Int {
			var total = 0;
			while (true) {
				var e = T[color][peek(13)];
				pos += e & 15;
				if (e == 0 || pos > end) return -1;
				total += e >> 4;
				if (e >> 4 < 64) return total;
			}
		}
		function row1d():Bool {
			var a0 = 0, c = 0;
			while (a0 < cols) {
				var r = run(c);
				if (r < 0 || (a0 += r) > cols) return false;
				add(a0);
				c ^= 1;
			}
			return true;
		}
		function row2d():Bool {
			var a0 = -1, c = 0, b = 0;
			while (a0 < cols) {
				// (b1: the first change on the reference line right of a0, to the colour opposite a0's)
				while (b > 0 && ref[b - 1] > a0)
					b--;
				while (ref[b] <= a0)
					b++;
				if ((b & 1) != c) b++;
				var b7 = peek(7);
				// (z: the leading zeros of the 7 bits, as clz32's less 25)
				var z = 7, t = b7;
				while (t > 0) {
					t >>= 1;
					z--;
				}
				if (z == 3) {
					// (pass: a0 under b2)
					pos += 4;
					a0 = ref[b + 1];
				} else if (z == 2) {
					// (horizontal: two runs from a0)
					pos += 3;
					var r1 = run(c), r2 = run(c ^ 1);
					if (r1 < 0 || r2 < 0) return false;
					var a1 = Std.int(Math.min(Math.max(a0, 0) + r1, cols));
					add(a1);
					a0 = Std.int(Math.min(a1 + r2, cols));
					add(a0);
				} else if (z < 6) {
					// (vertical: a1 = b1 + d, |d| at most 3)
					var l = z > 0 ? z + 2 : 1;
					var d = z < 2 ? z : z - 2;
					pos += l;
					a0 = Std.int(Math.min(Math.max(Math.max(ref[b] + ((b7 >> (7 - l)) & 1 != 0 ? d : -d), a0), 0), cols));
					add(a0);
					c ^= 1;
				} else
					return false; // (an EOL, uncompressed mode or garbage)
				if (pos > end) return false;
			}
			return true;
		}
		inline function align()
			if (byteAlign) pos = (pos + 7) & ~7;
		var done = 0, damaged = 0;
		while (done < maxRows) {
			var twoD = k < 0;
			if (k < 0) {
				// (Group 4's rows have no EOL: one here starts the end of the block)
				align();
				if (peek(12) == 1) break;
			} else {
				// (fill bits and an EOL, then for K > 0 a tag bit, 1 for a 1-D row; EOL EOL ends the block)
				if (!eol) align();
				while (pos < end && peek(12) == 0)
					pos++;
				if (peek(12) == 1) {
					pos += 12;
					if (peek(12) == 1 || (k > 0 && peek(13) == 0x1001)) break;
				} else
					align();
				if (k > 0) {
					twoD = peek(1) == 0;
					pos++;
				}
			}
			if (pos >= end) break;
			n = 0;
			if (!(twoD ? row2d() : row1d())) {
				// (with EOLs to resynchronize on, past a few damaged rows)
				if (k < 0 || !eol || damaged++ >= damagedMax) break;
				while (++pos < end && peek(12) != 1) {}
			}
			if ((done + 1) * rowBytes > out.length) {
				var grown = Bytes.alloc(Std.int(Math.min(out.length * 2.0, maxRows * 1.0 * rowBytes)));
				grown.blit(0, out, 0, out.length);
				out = grown;
			}
			var o = done++ * rowBytes;
			out.fill(o, rowBytes, blackIs1 ? 0 : 255);
			var i = 0;
			while (i < n) {
				var e = i + 1 < n ? cur[i + 1] : cols;
				for (x in cur[i]...e)
					out.set(o + (x >> 3), out.get(o + (x >> 3)) ^ (0x80 >> (x & 7)));
				i += 2;
			}
			var t = ref;
			ref = cur;
			cur = t;
			for (j in n...n + 3)
				ref[j] = cols;
		}
		return done > 0 ? out.sub(0, done * rowBytes) : null;
	}
}
