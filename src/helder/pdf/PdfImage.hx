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
	// JPEG 2000's decoder (Jpx), linked by Pdf.open; Pdf.openPlain leaves it out (a JPX image: Unsupported)
	public static var jpx:Null<(data:Bytes, reduce:Int, maxPixels:Int) -> Null<Jpx.JpxImage>> = null;
	public static var jpxInfo:Null<(data:Bytes) -> Null<{width:Int, height:Int, levels:Int}>> = null;

	// (shownW x shownH: the pixels it covers on the device, when known: a JPEG decoded reduced to no
	// fewer, by its DCT's scaling, as libjpeg's scale_denom)
	public static function decode(doc:Document, dict:PdfDict, raw:PdfValue, resources:Null<PdfDict>, fill:Int, ?inlineData:Bytes, shownW = 0, shownH = 0):Bitmap {
		var w = Values.int(doc.resolve(dict.has("Width") ? dict.get("Width") : dict.get("W")));
		var h = Values.int(doc.resolve(dict.has("Height") ? dict.get("Height") : dict.get("H")));
		if (w <= 0 || h <= 0) throw PdfError.corrupt("an image of no size");
		if (w * 1.0 * h > doc.limits.maxImagePixels) throw PdfError.tooLarge('an image of ${w}x$h');
		var mask = Values.bool(doc.resolve(dict.has("ImageMask") ? dict.get("ImageMask") : dict.get("IM")));
		var bpc = mask ? 1 : Values.int(doc.resolve(dict.has("BitsPerComponent") ? dict.get("BitsPerComponent") : dict.get("BPC")), 8);
		var decodeArr = Values.nums(doc.resolve(dict.has("Decode") ? dict.get("Decode") : dict.get("D")));
		var data:Bytes, jpeg = false;
		var jpxSpace:Null<String> = null, jpxAlpha:Null<Bytes> = null;
		if (inlineData != null) {
			var d = new PdfDict();
			for (k => v in dict.map)
				d.set(k == "F" ? "Filter" : k == "DP" ? "DecodeParms" : k, v);
			var r = Filters.decode(inlineData, d, doc.limits.maxStream, doc, ["DCTDecode", "DCT"]);
			data = r.data;
			jpeg = r.rest != null;
		} else {
			var r = doc.streamWith(raw, ["DCTDecode", "DCT", "JPXDecode", "JBIG2Decode"]);
			if (r.rest == "JBIG2Decode") throw PdfError.unsupported("the " + r.rest + " filter");
			data = r.data;
			jpeg = r.rest == "DCTDecode" || r.rest == "DCT";
			if (r.rest == "JPXDecode") {
				// (JPEG 2000: reduced by whole resolution levels to no smaller than shown; 8-bit samples,
				// its own colour space unless the dictionary says one, its alpha when /SMaskInData)
				if (jpx == null) throw PdfError.unsupported("the JPXDecode filter (not linked: Pdf.open links it)");
				var info = jpxInfo(data), reduce = 0;
				if (info != null && shownW > 0 && shownH > 0)
					while (reduce + 1 < info.levels && Math.ceil(info.width / Math.pow(2, reduce + 1)) >= shownW && Math.ceil(info.height / Math.pow(2, reduce + 1)) >= shownH)
						reduce++;
				var img = jpx(data, reduce, doc.limits.maxImagePixels);
				if (img == null) throw PdfError.corrupt("a JPEG 2000 image");
				w = img.width;
				h = img.height;
				bpc = 8;
				decodeArr = null;
				jpxSpace = img.colorSpace;
				var nc = img.components - (img.alpha >= 0 ? 1 : 0);
				if (img.alpha < 0) data = img.data else {
					data = Bytes.alloc(w * h * nc);
					var smaskIn = Values.int(doc.resolve(dict.get("SMaskInData"))) != 0;
					if (smaskIn) jpxAlpha = Bytes.alloc(w * h);
					for (i in 0...w * h) {
						var o = 0;
						for (c in 0...img.components) {
							var v = img.data.get(i * img.components + c);
							if (c == img.alpha) {
								if (jpxAlpha != null) jpxAlpha.set(i, v);
							} else
								data.set(i * nc + o++, v);
						}
					}
				}
				if (jpxSpace == null) jpxSpace = nc == 1 ? "gray" : nc == 4 ? "cmyk" : "rgb";
			}
		}
		var jpg:Null<{width:Int, height:Int, rgba:Bytes}> = null;
		if (jpeg && !mask) {
			var scale = shownW > 0 && shownH > 0 ? helder.image.JpegDecoder.scaleFor(w, h, shownW, shownH) : 1;
			jpg = try helder.image.JpegDecoder.decode(data, null, scale) catch (e:Dynamic) throw PdfError.corrupt("a JPEG image: " + Std.string(e));
			// (the image at the decoder's size: the masks below resampled to it)
			w = jpg.width;
			h = jpg.height;
			data = null;
		}
		var out = jpg != null ? new Bitmap(w, h, jpg.rgba) : new Bitmap(w, h);
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
		var cs = csv == PNull ? (jpxSpace == "gray" ? ColorSpace.GRAY : jpxSpace == "cmyk" ? ColorSpace.CMYK : ColorSpace.RGB) : ColorSpace.load(doc, csv,
			resources);
		if (jpeg) {
			// (the decoder's RGBA is the bitmap's, opaque: premultiplied as it is; an Adobe CMYK JPEG in a
			// DeviceCMYK image: the decoder's RGB as it is)
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
		var alpha:Null<Bytes> = jpxAlpha;
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
		return shrink(out, shownW, shownH);
	}

	// an image of at least twice the pixels it is shown at, a side, averaged down by a whole factor to
	// no fewer (premultiplied: a box filter), so what is kept and drawn is near the size shown
	static function shrink(b:Bitmap, shownW:Int, shownH:Int):Bitmap {
		if (shownW <= 0 || shownH <= 0) return b;
		var k = Std.int(Math.min(b.width / shownW, b.height / shownH));
		if (k < 2) return b;
		var w = Std.int(b.width / k), h = Std.int(b.height / k), src = b.pixels, out = new Bitmap(w, h), px = out.pixels, n = k * k;
		var sum = [0, 0, 0, 0];
		for (y in 0...h)
			for (x in 0...w) {
				sum[0] = sum[1] = sum[2] = sum[3] = 0;
				for (j in 0...k) {
					var o = ((y * k + j) * b.width + x * k) * 4;
					for (_ in 0...k) {
						sum[0] += src.get(o);
						sum[1] += src.get(o + 1);
						sum[2] += src.get(o + 2);
						sum[3] += src.get(o + 3);
						o += 4;
					}
				}
				var o = (y * w + x) * 4;
				for (c in 0...4)
					px.set(o + c, Std.int((sum[c] + (n >> 1)) / n));
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
