package hxmc.ui;

import haxe.io.Bytes;

// PNG files decoded to RGBA8 (Image.decode): every colour type (grey, RGB,
// palette, grey with alpha, RGBA), bit depths 1 to 16 (16 kept to their
// high byte), tRNS transparency (a palette's alphas, a grey or RGB colour
// key), the five scanline filters, Adam7 interlacing. Ancillary chunks
// other than tRNS (gamma, colour profiles) are not applied.
class PngDecoder {
	// the pixels: width * height * 4 bytes, rows top to bottom, straight alpha
	public static function decode(png:Bytes):{width:Int, height:Int, rgba:Bytes} {
		var sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
		if (png.length < 8) throw "PngDecoder: not a PNG file";
		for (k in 0...8)
			if (png.get(k) != sig[k]) throw "PngDecoder: not a PNG file";
		var width = 0, height = 0, depth = 0, type = -1, interlace = 0;
		var palette:Null<Bytes> = null, trns:Null<Bytes> = null;
		var idat = new haxe.io.BytesBuffer();
		var p = 8;
		while (p + 8 <= png.length) {
			var n = u32(png, p), name = png.getString(p + 4, 4);
			if (p + 12 + n > png.length) throw "PngDecoder: a truncated " + name + " chunk";
			var at = p + 8;
			switch name {
				case "IHDR":
					width = u32(png, at);
					height = u32(png, at + 4);
					depth = png.get(at + 8);
					type = png.get(at + 9);
					if (png.get(at + 10) != 0 || png.get(at + 11) != 0) throw "PngDecoder: an unknown compression or filter method";
					interlace = png.get(at + 12);
					var depths = switch type {
						case 0: [1, 2, 4, 8, 16];
						case 3: [1, 2, 4, 8];
						case 2 | 4 | 6: [8, 16];
						case _: [];
					}
					if (depths.indexOf(depth) < 0) throw 'PngDecoder: colour type $type at bit depth $depth';
					if (width <= 0 || height <= 0) throw "PngDecoder: an empty image";
				case "PLTE":
					palette = png.sub(at, n);
				case "tRNS":
					trns = png.sub(at, n);
				case "IDAT":
					idat.addBytes(png, at, n);
				case "IEND":
					break;
				case _:
			}
			p += 12 + n;
		}
		if (type < 0) throw "PngDecoder: no IHDR chunk";
		if (type == 3 && palette == null) throw "PngDecoder: a palette image without PLTE";
		var channels = switch type {
			case 0: 1;
			case 2: 3;
			case 3: 1;
			case 4: 2;
			case _: 4;
		}
		var bits = channels * depth;
		// (the image data's size: each pass's rows, a filter byte each)
		var expected = 0;
		var passes = interlace == 1 ? [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]] : [[0, 0, 1, 1]];
		for (a in passes) {
			var w = Std.int((width - a[0] + a[2] - 1) / a[2]), h = Std.int((height - a[1] + a[3] - 1) / a[3]);
			if (w > 0 && h > 0) expected += h * (1 + ((w * bits + 7) >> 3));
		}
		var data = idat.getBytes();
		var raw = Inflate.zlib(data, 0, data.length, expected);
		// the bytes a filter looks back (at least one)
		var bpp = bits < 8 ? 1 : bits >> 3;
		var out = Bytes.alloc(width * height * 4);
		var pos = 0;
		// one pass (the whole image, or one of Adam7's): its rows unfiltered
		// and their pixels put at x0 + i * dx, y0 + j * dy
		function pass(x0:Int, y0:Int, dx:Int, dy:Int) {
			var w = Std.int((width - x0 + dx - 1) / dx), h = Std.int((height - y0 + dy - 1) / dy);
			if (w <= 0 || h <= 0) return;
			var stride = (w * bits + 7) >> 3;
			var prev = Bytes.alloc(stride), cur = Bytes.alloc(stride);
			for (j in 0...h) {
				if (pos + 1 + stride > raw.length) throw "PngDecoder: the image data ends early";
				var f = raw.get(pos), r = pos + 1;
				// (each filter its own loop, the first bpp bytes apart: nothing to their left)
				var lead = bpp < stride ? bpp : stride;
				switch f {
					case 0:
						cur.blit(0, raw, r, stride);
					case 1:
						cur.blit(0, raw, r, lead);
						for (x in lead...stride)
							cur.set(x, (raw.get(r + x) + cur.get(x - bpp)) & 0xFF);
					case 2:
						for (x in 0...stride)
							cur.set(x, (raw.get(r + x) + prev.get(x)) & 0xFF);
					case 3:
						for (x in 0...lead)
							cur.set(x, (raw.get(r + x) + (prev.get(x) >> 1)) & 0xFF);
						for (x in lead...stride)
							cur.set(x, (raw.get(r + x) + ((cur.get(x - bpp) + prev.get(x)) >> 1)) & 0xFF);
					case 4:
						// (with nothing to the left, Paeth takes the byte above)
						for (x in 0...lead)
							cur.set(x, (raw.get(r + x) + prev.get(x)) & 0xFF);
						for (x in lead...stride) {
							var a = cur.get(x - bpp), b = prev.get(x), c = prev.get(x - bpp);
							var pa = abs(b - c), pb = abs(a - c), pc = abs(a + b - c - c);
							cur.set(x, (raw.get(r + x) + (pa <= pb && pa <= pc ? a : pb <= pc ? b : c)) & 0xFF);
						}
					case _:
						throw "PngDecoder: filter " + f;
				}
				pos += 1 + stride;
				var y = y0 + j * dy;
				// (8-bit RGBA and RGB without a colour key, the common cases: copied)
				if (depth == 8 && type == 6 && dx == 1) out.blit(4 * y * width, cur, 0, 4 * w) else if (depth == 8 && type == 2 && dx == 1
					&& trns == null) {
					var o = 4 * y * width;
					for (i in 0...w) {
						out.set(o, cur.get(3 * i));
						out.set(o + 1, cur.get(3 * i + 1));
						out.set(o + 2, cur.get(3 * i + 2));
						out.set(o + 3, 255);
						o += 4;
					}
				} else if (depth == 16 && (type == 6 || type == 2 && trns == null) && dx == 1) {
					// (16-bit RGBA and RGB: each sample's high byte)
					var o = 4 * y * width, n = type == 6 ? 8 : 6;
					for (i in 0...w) {
						var k = n * i;
						out.set(o, cur.get(k));
						out.set(o + 1, cur.get(k + 2));
						out.set(o + 2, cur.get(k + 4));
						out.set(o + 3, type == 6 ? cur.get(k + 6) : 255);
						o += 4;
					}
				} else
					for (i in 0...w)
						pixel(cur, i, out, 4 * (y * width + x0 + i * dx), type, depth, palette, trns);
				var t = prev;
				prev = cur;
				cur = t;
			}
		}
		if (interlace > 1) throw "PngDecoder: interlace method " + interlace;
		for (a in passes)
			pass(a[0], a[1], a[2], a[3]);
		return {width: width, height: height, rgba: out};
	}

	// pixel i of an unfiltered row into out at o
	static function pixel(row:Bytes, i:Int, out:Bytes, o:Int, type:Int, depth:Int, palette:Null<Bytes>, trns:Null<Bytes>) {
		// a sample of the row (channel k of pixel i), scaled to 8 bits; and as stored (tRNS keys)
		inline function stored(k:Int, channels:Int):Int {
			return if (depth == 16) (row.get(2 * (i * channels + k)) << 8) | row.get(2 * (i * channels + k) + 1) else if (depth == 8)
				row.get(i * channels + k) else {
				var bit = i * depth, b = row.get(bit >> 3);
				(b >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
			}
		}
		inline function scaled(v:Int):Int
			return depth == 16 ? v >> 8 : depth == 8 ? v : Std.int(v * 255 / ((1 << depth) - 1));
		switch type {
			case 0:
				var g = stored(0, 1);
				var v = scaled(g);
				out.set(o, v);
				out.set(o + 1, v);
				out.set(o + 2, v);
				out.set(o + 3, trns != null && trns.length >= 2 && g == ((trns.get(0) << 8) | trns.get(1)) ? 0 : 255);
			case 2:
				var r = stored(0, 3), g = stored(1, 3), b = stored(2, 3);
				out.set(o, scaled(r));
				out.set(o + 1, scaled(g));
				out.set(o + 2, scaled(b));
				var key = trns != null && trns.length >= 6 && r == ((trns.get(0) << 8) | trns.get(1)) && g == ((trns.get(2) << 8) | trns.get(3))
					&& b == ((trns.get(4) << 8) | trns.get(5));
				out.set(o + 3, key ? 0 : 255);
			case 3:
				var k = stored(0, 1);
				if (3 * k + 2 >= palette.length) throw "PngDecoder: a colour outside the palette";
				out.set(o, palette.get(3 * k));
				out.set(o + 1, palette.get(3 * k + 1));
				out.set(o + 2, palette.get(3 * k + 2));
				out.set(o + 3, trns != null && k < trns.length ? trns.get(k) : 255);
			case 4:
				var v = scaled(stored(0, 2));
				out.set(o, v);
				out.set(o + 1, v);
				out.set(o + 2, v);
				out.set(o + 3, scaled(stored(1, 2)));
			case _:
				for (k in 0...4)
					out.set(o + k, scaled(stored(k, 4)));
		}
	}

	static inline function u32(b:Bytes, p:Int):Int
		return (b.get(p) << 24) | (b.get(p + 1) << 16) | (b.get(p + 2) << 8) | b.get(p + 3);

	static inline function abs(v:Int)
		return v < 0 ? -v : v;
}
