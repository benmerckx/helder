package helder.pdf;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.pdf.PdfValue;
import helder.pdf.Document;
import helder.pdf.Colors;
import helder.pdf.PdfFont;

// An image XObject (or an inline image) as a premultiplied bitmap: its
// samples (1, 2, 4, 8 or 16 bits) through its Decode array and colour
// space, a DCTDecode image through helder.image's JPEG decoder; its alpha
// from /SMask (an image of its own), a stencil /Mask or a colour key mask;
// an image mask (/ImageMask) as the fill colour where it paints. Its
// pixels within PdfLimits.maxImagePixels.
class PdfImage {
	public static function decode(doc:Document, dict:PdfDict, raw:PdfValue, resources:Null<PdfDict>, fill:Int, ?inlineData:Bytes):Bitmap {
		var w = Values.int(doc.resolve(dict.has("Width") ? dict.get("Width") : dict.get("W")));
		var h = Values.int(doc.resolve(dict.has("Height") ? dict.get("Height") : dict.get("H")));
		if (w <= 0 || h <= 0) throw PdfError.corrupt("an image of no size");
		if (w * 1.0 * h > doc.limits.maxImagePixels) throw PdfError.tooLarge('an image of ${w}x$h');
		var mask = Values.bool(doc.resolve(dict.has("ImageMask") ? dict.get("ImageMask") : dict.get("IM")));
		var bpc = mask ? 1 : Values.int(doc.resolve(dict.has("BitsPerComponent") ? dict.get("BitsPerComponent") : dict.get("BPC")), 8);
		var decodeArr = Values.nums(doc.resolve(dict.has("Decode") ? dict.get("Decode") : dict.get("D")));
		var data:Bytes, jpeg = false;
		if (inlineData != null) {
			var d = new PdfDict();
			for (k => v in dict.map)
				d.set(k == "F" ? "Filter" : k == "DP" ? "DecodeParms" : k, v);
			var r = Filters.decode(inlineData, d, doc.limits.maxStream, doc, ["DCTDecode", "DCT"]);
			data = r.data;
			jpeg = r.rest != null;
		} else {
			var r = doc.streamWith(raw, ["DCTDecode", "DCT", "JPXDecode", "CCITTFaxDecode", "JBIG2Decode"]);
			if (r.rest == "JPXDecode" || r.rest == "CCITTFaxDecode" || r.rest == "JBIG2Decode") throw PdfError.unsupported("the " + r.rest + " filter");
			data = r.data;
			jpeg = r.rest != null;
		}
		var out = new Bitmap(w, h);
		var px = out.pixels;
		if (mask) {
			// (1 paints, unless Decode says [1 0])
			var paints = decodeArr != null && decodeArr.length >= 2 && decodeArr[0] == 1 ? 1 : 0;
			var row = (w + 7) >> 3;
			var a = (fill >>> 24) & 255, r = (fill >> 16) & 255, g = (fill >> 8) & 255, b = fill & 255;
			for (y in 0...h)
				for (x in 0...w) {
					var byte = y * row + (x >> 3);
					var bit = byte < data.length ? (data.get(byte) >> (7 - (x & 7))) & 1 : 1;
					if (bit == paints) {
						var o = (y * w + x) * 4;
						px.set(o, Std.int(r * a / 255));
						px.set(o + 1, Std.int(g * a / 255));
						px.set(o + 2, Std.int(b * a / 255));
						px.set(o + 3, a);
					}
				}
			return out;
		}
		var csv = dict.has("ColorSpace") ? dict.get("ColorSpace") : dict.get("CS");
		var cs = csv == PNull ? ColorSpace.RGB : ColorSpace.load(doc, csv, resources);
		if (jpeg) {
			var img = try helder.image.JpegDecoder.decode(data) catch (e:Dynamic) throw PdfError.corrupt("a JPEG image: " + Std.string(e));
			if (img.width != w || img.height != h) w = Std.int(Math.min(w, img.width));
			var rgba = img.rgba;
			// (an Adobe CMYK JPEG in a DeviceCMYK image: the decoder's RGB as it is)
			for (y in 0...Std.int(Math.min(h, img.height)))
				for (x in 0...Std.int(Math.min(w, img.width))) {
					var s = (y * img.width + x) * 4, o = (y * out.width + x) * 4;
					px.set(o, rgba.get(s));
					px.set(o + 1, rgba.get(s + 1));
					px.set(o + 2, rgba.get(s + 2));
					px.set(o + 3, 255);
				}
		} else {
			var n = cs.components == 0 ? 1 : cs.components;
			var dec = decodeArr ?? cs.defaultDecode(bpc);
			var max = Math.pow(2, bpc) - 1, row = Std.int(Math.ceil(w * n * bpc / 8));
			var comps = [for (_ in 0...n) 0.0];
			// (a lookup per sample value when one component of 8 bits or fewer: the common case fast)
			var cache = new Map<Int, Int>();
			for (y in 0...h) {
				var base = y * row;
				for (x in 0...w) {
					var key = 0;
					for (c in 0...n) {
						var bit = (x * n + c) * bpc, v:Int;
						if (bpc == 8) v = base + x * n + c < data.length ? data.get(base + x * n + c) : 0 else if (bpc == 16) {
							var o = base + (x * n + c) * 2;
							v = o + 1 < data.length ? (data.get(o) << 8) | data.get(o + 1) : 0;
						} else {
							var byte = base + (bit >> 3);
							v = byte < data.length ? (data.get(byte) >> (8 - bpc - (bit & 7))) & ((1 << bpc) - 1) : 0;
						}
						key = key * 65537 + v;
						comps[c] = dec[c * 2] + v * (dec[c * 2 + 1] - dec[c * 2]) / max;
					}
					var rgb:Int;
					if (n <= 3 && bpc <= 8) {
						var k = cache.get(key);
						if (k == null) {
							k = cs.rgb(comps);
							cache.set(key, k);
						}
						rgb = k;
					} else
						rgb = cs.rgb(comps);
					var o = (y * w + x) * 4;
					px.set(o, (rgb >> 16) & 255);
					px.set(o + 1, (rgb >> 8) & 255);
					px.set(o + 2, rgb & 255);
					px.set(o + 3, 255);
				}
			}
		}
		// the alpha: a soft mask, a stencil mask, a colour key
		var smask = doc.resolve(dict.get("SMask"));
		var alpha:Null<Bytes> = null;
		switch smask {
			case PStream(sd, _):
				var m = decodeGray(doc, sd, smask, w, h);
				alpha = m;
			case _:
		}
		var mk = doc.resolve(dict.get("Mask"));
		switch mk {
			case PStream(md, _):
				var stencil = decode(doc, md, mk, resources, 0xFF000000);
				alpha = Bytes.alloc(w * h);
				for (y in 0...h)
					for (x in 0...w) {
						var sx = Std.int(x * stencil.width / w), sy = Std.int(y * stencil.height / h);
						alpha.set(y * w + x, 255 - stencil.pixels.get((sy * stencil.width + sx) * 4 + 3));
					}
			case PArray(range) if (!jpeg):
				// (a colour key: samples within the ranges transparent; by the decoded colour's bytes)
				var r = [for (v in range) Values.num(doc.resolve(v))];
				if (r.length >= 2 && cs.components == 1 && bpc <= 8) {
					alpha = Bytes.alloc(w * h);
					alpha.fill(0, w * h, 255);
					var row = Std.int(Math.ceil(w * bpc / 8)), max = (1 << bpc) - 1;
					for (y in 0...h)
						for (x in 0...w) {
							var bit = x * bpc, byte = y * row + (bit >> 3);
							var v = byte < data.length ? (data.get(byte) >> (8 - bpc - (bit & 7))) & max : 0;
							if (v >= r[0] && v <= r[1]) alpha.set(y * w + x, 0);
						}
				}
			case _:
		}
		if (alpha != null)
			for (i in 0...w * h) {
				var a = alpha.get(i), o = i * 4;
				if (a == 255) continue;
				px.set(o, Std.int(px.get(o) * a / 255 + 0.5));
				px.set(o + 1, Std.int(px.get(o + 1) * a / 255 + 0.5));
				px.set(o + 2, Std.int(px.get(o + 2) * a / 255 + 0.5));
				px.set(o + 3, a);
			}
		return out;
	}

	// a soft mask's gray samples at w x h (scaled to them by its nearest sample)
	static function decodeGray(doc:Document, d:PdfDict, v:PdfValue, w:Int, h:Int):Bytes {
		var g = decode(doc, d, v, null, 0xFF000000);
		var out = Bytes.alloc(w * h);
		for (y in 0...h)
			for (x in 0...w) {
				var sx = Std.int(x * g.width / w), sy = Std.int(y * g.height / h);
				out.set(y * w + x, g.pixels.get((sy * g.width + sx) * 4));
			}
		return out;
	}
}
