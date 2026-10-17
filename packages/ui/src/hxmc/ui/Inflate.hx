package hxmc.ui;

import haxe.io.Bytes;
import haxe.ds.Vector;

// zlib streams inflated (RFC 1950 and 1951) for the image decoders: bits
// from a 32-bit buffer, prefix codes up to FAST bits by a table and longer
// ones from their canonical counts, matches copied in place; the output
// as large as the caller expects (PNG knows its size), grown when not.
// The checksum is not verified (PNG's chunks have their own).
class Inflate {
	static inline var FAST = 10;
	static final LENGTH_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
	static final LENGTH_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
	static final DIST_BASE = [
		1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
	];
	static final DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];
	static final ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

	// a zlib stream (its two-byte header, then deflate's blocks) at src[at...end]
	public static function zlib(src:Bytes, at:Int, end:Int, expected:Int):Bytes {
		if (end - at < 2 || src.get(at) & 15 != 8 || ((src.get(at) << 8) | src.get(at + 1)) % 31 != 0) throw "Inflate: not a zlib stream";
		if (src.get(at + 1) & 0x20 != 0) throw "Inflate: a preset dictionary";
		return new Inflate(src, at + 2, end, expected).run();
	}

	final src:Bytes;
	var p:Int;
	final end:Int;
	var buf = 0;
	var cnt = 0;
	var out:Bytes;
	var pos = 0;

	function new(src:Bytes, at:Int, end:Int, expected:Int) {
		this.src = src;
		this.p = at;
		this.end = end;
		out = Bytes.alloc(expected > 0 ? expected : 1024);
	}

	inline function need(n:Int)
		while (cnt < n) {
			buf |= (p < end ? src.get(p) : 0) << cnt;
			p++;
			cnt += 8;
		}

	inline function bits(n:Int):Int {
		need(n);
		var v = buf & ((1 << n) - 1);
		buf >>>= n;
		cnt -= n;
		return v;
	}

	inline function room(n:Int)
		if (pos + n > out.length) {
			var size = out.length * 2;
			while (size < pos + n)
				size *= 2;
			var b = Bytes.alloc(size);
			b.blit(0, out, 0, pos);
			out = b;
		}

	function run():Bytes {
		var last = false;
		while (!last) {
			if (p > end + 4) throw "Inflate: the data ends early";
			last = bits(1) == 1;
			switch bits(2) {
				case 0:
					// (stored: from the next byte)
					bits(cnt & 7);
					var len = bits(16);
					bits(16);
					room(len);
					for (k in 0...len)
						out.set(pos++, bits(8));
				case 1:
					block(fixedLit, fixedDist);
				case 2:
					var hlit = bits(5) + 257, hdist = bits(5) + 1, hclen = bits(4) + 4;
					var cl = [for (i in 0...19) 0];
					for (i in 0...hclen)
						cl[ORDER[i]] = bits(3);
					var clCode = new Huffman(cl);
					var lengths = [for (i in 0...hlit + hdist) 0], i = 0;
					while (i < hlit + hdist) {
						var s = decode(clCode);
						if (s < 16) lengths[i++] = s else {
							var v = 0, r = 0;
							if (s == 16) {
								if (i == 0) throw "Inflate: a repeat with nothing before it";
								v = lengths[i - 1];
								r = 3 + bits(2);
							} else r = s == 17 ? 3 + bits(3) : 11 + bits(7);
							for (k in 0...r)
								if (i < lengths.length) lengths[i++] = v;
						}
					}
					block(new Huffman(lengths.slice(0, hlit)), new Huffman(lengths.slice(hlit)));
				case _:
					throw "Inflate: an invalid block type";
			}
		}
		return pos == out.length ? out : out.sub(0, pos);
	}

	@:isVar static var fixedLit(get, null):Huffman;
	@:isVar static var fixedDist(get, null):Huffman;

	static function get_fixedLit():Huffman {
		if (fixedLit == null) fixedLit = new Huffman([for (i in 0...288) i < 144 ? 8 : i < 256 ? 9 : i < 280 ? 7 : 8]);
		return fixedLit;
	}

	static function get_fixedDist():Huffman {
		if (fixedDist == null) fixedDist = new Huffman([for (i in 0...30) 5]);
		return fixedDist;
	}

	function block(lit:Huffman, dist:Huffman) {
		while (true) {
			var s = decode(lit);
			if (s < 256) {
				room(1);
				out.set(pos++, s);
			} else if (s == 256) return else {
				var k = s - 257;
				if (k >= 29) throw "Inflate: an invalid length";
				var len = LENGTH_BASE[k] + bits(LENGTH_EXTRA[k]);
				var d = decode(dist);
				if (d >= 30) throw "Inflate: an invalid distance";
				var back = DIST_BASE[d] + bits(DIST_EXTRA[d]);
				if (back > pos) throw "Inflate: a distance before the start";
				room(len);
				if (back >= len) {
					out.blit(pos, out, pos - back, len);
					pos += len;
				} else
					for (i in 0...len) {
						out.set(pos, out.get(pos - back));
						pos++;
					}
			}
		}
	}

	// a symbol: the table for codes up to FAST bits, else bit by bit from the
	// canonical counts (the code's first bit its most significant)
	function decode(h:Huffman):Int {
		need(15);
		var e = h.fast[buf & ((1 << FAST) - 1)];
		if (e != 0) {
			var len = e >> 9;
			buf >>>= len;
			cnt -= len;
			return e & 511;
		}
		var code = 0, first = 0, index = 0;
		for (len in 1...16) {
			code |= bits(1);
			var count = h.counts[len];
			if (code - count < first) return h.symbols[index + (code - first)];
			index += count;
			first += count;
			first <<= 1;
			code <<= 1;
		}
		throw "Inflate: an invalid code";
	}
}

// a canonical prefix code from code lengths: a table of the codes up to
// FAST bits (by their bits as read: reversed), each (length << 9) | symbol
private class Huffman {
	public final counts = [for (i in 0...16) 0];
	public final symbols:Array<Int> = [];
	public final fast = new Vector<Int>(1 << 10);

	public function new(lengths:Array<Int>) {
		for (i in 0...fast.length)
			fast[i] = 0;
		for (l in lengths)
			if (l > 0) counts[l]++;
		for (len in 1...16)
			for (s in 0...lengths.length)
				if (lengths[s] == len) symbols.push(s);
		var code = 0, k = 0;
		for (len in 1...16) {
			for (i in 0...counts[len]) {
				if (len <= 10) {
					// (the code's bits reversed, filled in for every longer index)
					var r = 0, c = code;
					for (b in 0...len) {
						r = (r << 1) | (c & 1);
						c >>= 1;
					}
					var step = 1 << len, e = (len << 9) | symbols[k];
					var j = r;
					while (j < (1 << 10)) {
						fast[j] = e;
						j += step;
					}
				}
				code++;
				k++;
			}
			code <<= 1;
		}
	}
}
