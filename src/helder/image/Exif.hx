package helder.image;

import haxe.io.Bytes;

// EXIF's orientation, and only it: tag 0x112 of IFD0, 1 to 8 (1: as
// stored; 2 to 4 mirrored or turned half; 5 to 8 a quarter turn, the sides
// swapped), from a JPEG's APP1 "Exif" segment or a WebP's EXIF chunk.
// Every offset is checked within the TIFF block, and only IFD0 is read (no
// chain of IFDs or sub-IFDs is followed: no loop, no depth); anything else
// is 1. JpegDecoder applies it as browsers do; a WebP's is the caller's
// (`apply`: helder's viewer).
class Exif {
	// a JPEG's or WebP's orientation (1 when it has none, or another file)
	public static function orientation(file:Bytes):Int {
		var n = file.length;
		if (n >= 4 && file.get(0) == 0xFF && file.get(1) == 0xD8) {
			// the markers before the first scan
			var p = 2;
			while (p + 4 <= n) {
				if (file.get(p) != 0xFF) return 1;
				var m = file.get(p + 1);
				if (m == 0xFF) {
					p++;
					continue;
				}
				if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) {
					p += 2;
					continue;
				}
				if (m == 0xDA || m == 0xD9) return 1;
				var len = (file.get(p + 2) << 8) | file.get(p + 3), end = p + 2 + len;
				if (len < 2 || end > n) return 1;
				if (m == 0xE1 && len >= 8 && file.getString(p + 4, 4) == "Exif" && file.get(p + 8) == 0 && file.get(p + 9) == 0) return tiff(file, p + 10, end);
				p = end;
			}
			return 1;
		}
		if (n >= 20 && file.getString(0, 4) == "RIFF" && file.getString(8, 4) == "WEBP") {
			var p = 12;
			while (p + 8 <= n) {
				var size = file.get(p + 4) | (file.get(p + 5) << 8) | (file.get(p + 6) << 16) | (file.get(p + 7) << 24), at = p + 8;
				if (size < 0 || size > n - at) return 1;
				if (file.getString(p, 4) == "EXIF") {
					// (some writers keep JPEG's "Exif\0\0" before the TIFF header)
					var t = size >= 6 && file.getString(at, 4) == "Exif" ? at + 6 : at;
					return tiff(file, t, at + size);
				}
				p = at + size + (size & 1);
			}
		}
		return 1;
	}

	// the orientation in a TIFF block at [start, end) of b (1 when none)
	public static function tiff(b:Bytes, start:Int, end:Int):Int {
		if (start < 0 || end > b.length || end - start < 8) return 1;
		var le = b.get(start) == 0x49 && b.get(start + 1) == 0x49;
		if (!le && !(b.get(start) == 0x4D && b.get(start + 1) == 0x4D)) return 1;
		inline function r16(q:Int):Int
			return le ? b.get(q) | (b.get(q + 1) << 8) : (b.get(q) << 8) | b.get(q + 1);
		inline function r32(q:Int):Float
			return le ? r16(q) + r16(q + 2) * 65536.0 : r16(q) * 65536.0 + r16(q + 2);
		if (r16(start + 2) != 42) return 1;
		// (IFD0's offset from the block's start, unsigned: within it)
		var off = r32(start + 4), size = end - start;
		if (off < 8 || off + 2 > size) return 1;
		var ifd = start + Std.int(off), count = r16(ifd);
		for (i in 0...count) {
			var e = ifd + 2 + 12 * i;
			if (e + 12 > end) return 1;
			// (SHORT, one value: in the entry itself)
			if (r16(e) == 0x112) {
				var v = r16(e + 2) == 3 ? r16(e + 8) : 1;
				return v >= 1 && v <= 8 ? v : 1;
			}
		}
		return 1;
	}

	// whether orientation o swaps the width and the height
	public static inline function swaps(o:Int):Bool
		return o >= 5 && o <= 8;

	// w x h RGBA8 pixels in orientation o shown upright: new pixels (the
	// same when o is 1), the width and height swapped for 5 to 8
	public static function apply(rgba:Bytes, width:Int, height:Int, o:Int):{width:Int, height:Int, rgba:Bytes} {
		if (o < 2 || o > 8) return {width: width, height: height, rgba: rgba};
		var w = swaps(o) ? height : width, h = swaps(o) ? width : height;
		var out = Bytes.alloc(w * h * 4);
		for (y in 0...height)
			for (x in 0...width) {
				var dx:Int, dy:Int;
				switch o {
					case 2: dx = width - 1 - x; dy = y;
					case 3: dx = width - 1 - x; dy = height - 1 - y;
					case 4: dx = x; dy = height - 1 - y;
					case 5: dx = y; dy = x;
					case 6: dx = height - 1 - y; dy = x;
					case 7: dx = height - 1 - y; dy = width - 1 - x;
					case _: dx = y; dy = width - 1 - x;
				}
				out.setInt32(4 * (dy * w + dx), rgba.getInt32(4 * (y * width + x)));
			}
		return {width: w, height: h, rgba: out};
	}
}
