package helder.image;

import haxe.io.Bytes;

// RGBA8 pixels as a PNG file (8-bit RGBA, not interlaced): each row
// filtered as libpng's heuristic picks (the filter of the smallest sum of
// its bytes as signed), then deflated with the fixed Huffman codes and
// LZ77 matches found by a hash of three bytes (a short chain): a flat
// colour's rows down to a few bytes, an icon's to a fraction. For what is
// written once, by a build (helder's app icons and splash images), not a
// frame's: no zlib, pure Haxe.
class PngEncoder {
	public static function encode(rgba:Bytes, width:Int, height:Int):Bytes {
		if (rgba.length != width * height * 4) throw 'PngEncoder: ${rgba.length} bytes are not ${width}x$height RGBA';
		var stride = width * 4;
		var raw = Bytes.alloc((stride + 1) * height);
		var trial = [for (_ in 0...5) Bytes.alloc(stride)];
		for (y in 0...height) {
			var row = y * stride, up = (y - 1) * stride;
			var best = 0, bestSum = -1;
			for (f in 0...5) {
				var t = trial[f], sum = 0;
				for (i in 0...stride) {
					var x = rgba.get(row + i);
					var a = i >= 4 ? rgba.get(row + i - 4) : 0, b = y > 0 ? rgba.get(up + i) : 0, c = i >= 4 && y > 0 ? rgba.get(up + i - 4) : 0;
					var v:Int = switch f {
						case 0: x;
						case 1: x - a;
						case 2: x - b;
						case 3: x - ((a + b) >> 1);
						case _:
							var p = a + b - c, pa = abs(p - a), pb = abs(p - b), pc = abs(p - c);
							x - (pa <= pb && pa <= pc ? a : pb <= pc ? b : c);
					}
					v &= 0xFF;
					t.set(i, v);
					sum += v < 128 ? v : 256 - v;
				}
				if (bestSum < 0 || sum < bestSum) {
					best = f;
					bestSum = sum;
				}
			}
			raw.set(y * (stride + 1), best);
			raw.blit(y * (stride + 1) + 1, trial[best], 0, stride);
		}
		var o = new haxe.io.BytesOutput();
		o.bigEndian = true;
		for (b in [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
			o.writeByte(b);
		var ihdr = Bytes.alloc(13);
		ihdr.set(0, width >>> 24);
		ihdr.set(1, width >> 16);
		ihdr.set(2, width >> 8);
		ihdr.set(3, width);
		ihdr.set(4, height >>> 24);
		ihdr.set(5, height >> 16);
		ihdr.set(6, height >> 8);
		ihdr.set(7, height);
		ihdr.set(8, 8);
		ihdr.set(9, 6);
		chunk(o, "IHDR", ihdr);
		chunk(o, "IDAT", zlib(raw));
		chunk(o, "IEND", Bytes.alloc(0));
		return o.getBytes();
	}

	static inline function abs(v:Int):Int
		return v < 0 ? -v : v;

	static function chunk(o:haxe.io.BytesOutput, type:String, data:Bytes) {
		o.writeInt32(data.length);
		var td = Bytes.alloc(4 + data.length);
		td.blit(0, Bytes.ofString(type), 0, 4);
		td.blit(4, data, 0, data.length);
		o.writeFullBytes(td, 0, td.length);
		o.writeInt32(haxe.crypto.Crc32.make(td));
	}

	// a zlib stream: one deflate block of the fixed codes, its Adler-32
	public static function zlib(data:Bytes):Bytes {
		var w = new BitWriter(data.length >> 2);
		w.bits(0x78, 8);
		w.bits(0x01, 8);
		w.bits(1, 1); // the last block
		w.bits(1, 2); // fixed Huffman codes
		var n = data.length, HASH = 1 << 15, WINDOW = 32768;
		var head = new haxe.ds.Vector<Int>(HASH), prev = new haxe.ds.Vector<Int>(WINDOW);
		for (i in 0...HASH)
			head[i] = -1;
		inline function hash(i:Int):Int
			return ((data.get(i) << 10) ^ (data.get(i + 1) << 5) ^ data.get(i + 2)) & (HASH - 1);
		inline function insert(i:Int) {
			var h = hash(i);
			prev[i & (WINDOW - 1)] = head[h];
			head[h] = i;
		}
		var i = 0;
		while (i < n) {
			var bestLen = 0, bestDist = 0;
			if (i + 2 < n) {
				var cand = head[hash(i)], chain = 16, max = n - i < 258 ? n - i : 258;
				while (cand >= 0 && i - cand <= WINDOW && chain-- > 0) {
					var l = 0;
					while (l < max && data.get(cand + l) == data.get(i + l))
						l++;
					if (l > bestLen) {
						bestLen = l;
						bestDist = i - cand;
						if (l == max) break;
					}
					var p = prev[cand & (WINDOW - 1)];
					if (p >= cand) break;
					cand = p;
				}
			}
			if (bestLen >= 3) {
				w.length(bestLen);
				w.distance(bestDist);
				var end = i + bestLen;
				while (i < end) {
					if (i + 2 < n) insert(i);
					i++;
				}
			} else {
				w.literal(data.get(i));
				if (i + 2 < n) insert(i);
				i++;
			}
		}
		w.literal(256);
		w.flush();
		var a = haxe.crypto.Adler32.make(data);
		w.byte(a >>> 24);
		w.byte(a >> 16);
		w.byte(a >> 8);
		w.byte(a);
		return w.bytes();
	}
}

private class BitWriter {
	var out:haxe.io.BytesBuffer;
	var acc = 0;
	var count = 0;

	static final LENGTH_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
	static final LENGTH_EXTRA = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0];
	static final DIST_BASE = [
		1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
	];
	static final DIST_EXTRA = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

	public function new(_:Int)
		out = new haxe.io.BytesBuffer();

	// n bits of v, least significant first
	public inline function bits(v:Int, n:Int) {
		acc |= (v & ((1 << n) - 1)) << count;
		count += n;
		while (count >= 8) {
			out.addByte(acc & 0xFF);
			acc >>>= 8;
			count -= 8;
		}
	}

	// a Huffman code: its bits most significant first
	inline function code(c:Int, n:Int) {
		var r = 0;
		for (k in 0...n)
			r |= ((c >> k) & 1) << (n - 1 - k);
		bits(r, n);
	}

	// a literal or the end (256) or a length's symbol, in the fixed codes
	public function literal(v:Int) {
		if (v < 144) code(0x30 + v, 8) else if (v < 256) code(0x190 + v - 144, 9) else if (v < 280) code(v - 256, 7) else code(0xC0 + v - 280, 8);
	}

	public function length(l:Int) {
		var k = 28;
		while (LENGTH_BASE[k] > l)
			k--;
		literal(257 + k);
		if (LENGTH_EXTRA[k] > 0) bits(l - LENGTH_BASE[k], LENGTH_EXTRA[k]);
	}

	public function distance(d:Int) {
		var k = 29;
		while (DIST_BASE[k] > d)
			k--;
		code(k, 5);
		if (DIST_EXTRA[k] > 0) bits(d - DIST_BASE[k], DIST_EXTRA[k]);
	}

	public function flush() {
		if (count > 0) out.addByte(acc & 0xFF);
		acc = 0;
		count = 0;
	}

	public inline function byte(b:Int)
		out.addByte(b & 0xFF);

	public function bytes():Bytes
		return out.getBytes();
}
