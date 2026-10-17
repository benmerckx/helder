package hxmc.ui;

import haxe.io.Bytes;

// GIF files decoded to RGBA8 (Image.decode), as browsers show an image of
// one: the first frame, on the logical screen's size (what it leaves
// uncovered transparent), with its local or the global colour table, its
// transparent index (the graphic control extension), interlaced or not;
// the LZW codes from the minimum size up to 12 bits, clear and end codes.
// Later frames (an animation) are not decoded.
class GifDecoder {
	public static function decode(gif:Bytes):{width:Int, height:Int, rgba:Bytes} {
		if (gif.length < 13 || gif.getString(0, 3) != "GIF") throw "GifDecoder: not a GIF file";
		inline function u16(p:Int):Int
			return gif.get(p) | (gif.get(p + 1) << 8);
		var width = u16(6), height = u16(8), packed = gif.get(10);
		if (width == 0 || height == 0) throw "GifDecoder: an empty image";
		var p = 13;
		var global:Null<Int> = null, globalSize = 0;
		if (packed & 0x80 != 0) {
			globalSize = 1 << ((packed & 7) + 1);
			global = p;
			p += 3 * globalSize;
		}
		var transparent = -1;
		while (p < gif.length) {
			var b = gif.get(p++);
			if (b == 0x3B) break;
			if (b == 0x21) {
				var label = gif.get(p++);
				// the graphic control extension: the transparent index
				if (label == 0xF9 && gif.get(p) >= 4) transparent = gif.get(p + 1) & 1 != 0 ? gif.get(p + 4) : -1;
				while (p < gif.length && gif.get(p) != 0)
					p += gif.get(p) + 1;
				p++;
				continue;
			}
			if (b != 0x2C) throw "GifDecoder: an unknown block 0x" + StringTools.hex(b);
			var left = u16(p), top = u16(p + 2), w = u16(p + 4), h = u16(p + 6), ip = gif.get(p + 8);
			p += 9;
			var table = global, tableSize = globalSize;
			if (ip & 0x80 != 0) {
				tableSize = 1 << ((ip & 7) + 1);
				table = p;
				p += 3 * tableSize;
			}
			if (table == null) throw "GifDecoder: no colour table";
			var minCode = gif.get(p++);
			// the image data's sub-blocks, joined
			var data = new haxe.io.BytesBuffer();
			while (p < gif.length && gif.get(p) != 0) {
				var n = gif.get(p);
				data.addBytes(gif, p + 1, n);
				p += n + 1;
			}
			var indices = lzw(data.getBytes(), minCode, w * h);
			var rgba = Bytes.alloc(width * height * 4);
			rgba.fill(0, rgba.length, 0);
			var interlaced = ip & 0x40 != 0;
			// (interlaced: rows 0, 8, 16..., then 4, 12..., then 2, 6..., then 1, 3...)
			var rows = interlaced ? [for (pass in [[0, 8], [4, 8], [2, 4], [1, 2]]) for (r in 0...Std.int((h - pass[0] + pass[1] - 1) / pass[1])) pass[0] + r * pass[1]] : [for (r in 0...h) r];
			for (k in 0...h) {
				var y = top + rows[k];
				if (y >= height) continue;
				for (x in 0...w) {
					var X = left + x;
					if (X >= width) continue;
					var i = indices.get(k * w + x);
					if (i == transparent || i >= tableSize) continue;
					var o = 4 * (y * width + X), c = table + 3 * i;
					rgba.set(o, gif.get(c));
					rgba.set(o + 1, gif.get(c + 1));
					rgba.set(o + 2, gif.get(c + 2));
					rgba.set(o + 3, 255);
				}
			}
			return {width: width, height: height, rgba: rgba};
		}
		throw "GifDecoder: no image";
	}

	// the LZW codes to n colour indices (what is missing: 0)
	static function lzw(data:Bytes, minCode:Int, n:Int):Bytes {
		if (minCode < 2 || minCode > 8) throw "GifDecoder: an LZW code size of " + minCode;
		var out = Bytes.alloc(n);
		var clear = 1 << minCode, end = clear + 1;
		// the dictionary: each code's prefix code and last index, and its length
		var prefix = new haxe.ds.Vector<Int>(4096), suffix = new haxe.ds.Vector<Int>(4096), length = new haxe.ds.Vector<Int>(4096);
		for (i in 0...clear) {
			prefix[i] = -1;
			suffix[i] = i;
			length[i] = 1;
		}
		var size = minCode + 1, next = end + 1, old = -1;
		var acc = 0, bits = 0, pos = 0, o = 0;
		while (o < n) {
			while (bits < size) {
				if (pos >= data.length) return out;
				acc |= data.get(pos++) << bits;
				bits += 8;
			}
			var code = acc & ((1 << size) - 1);
			acc >>>= size;
			bits -= size;
			if (code == clear) {
				size = minCode + 1;
				next = end + 1;
				old = -1;
				continue;
			}
			if (code == end) break;
			// (a code not made yet: the old string and its own first index, KwKwK)
			if (code > next || (code == next && old < 0)) break;
			var c = code == next ? old : code;
			var len = length[c];
			// the string of c, written backwards
			var k = c, w = o + len - 1;
			while (k >= 0) {
				if (w < n) out.set(w, suffix[k]);
				w--;
				k = prefix[k];
			}
			var first = out.get(o);
			if (code == next) {
				if (o + len < n) out.set(o + len, first);
				len++;
			}
			if (old >= 0 && next < 4096) {
				prefix[next] = old;
				suffix[next] = first;
				length[next] = length[old] + 1;
				next++;
				if (next == 1 << size && size < 12) size++;
			}
			o += len;
			old = code;
		}
		return out;
	}
}
