package helder.pdf.web;

import helder.canvas.web.BrowserImages;
import helder.pdf.Colors;
import helder.pdf.Document;
import helder.pdf.Interpreter;
import helder.pdf.Pdf;
import helder.pdf.PdfError;
import helder.pdf.PdfValue;

// helder.pdf on the web back end with the browser decoding its JPEGs
// (helder.canvas.web.BrowserImages): prepare(page, scale, done) finds the
// images the page draws at that scale (the page run once, nothing drawn),
// hands each JPEG the browser can take (DCTDecode, gray or RGB, 8 bits, no
// Decode array, no mask) to it at the size it is shown, and calls done
// once they have arrived, each in the document's image cache
// (PdfLimits.imageCache); Pdf.draw on a WebCanvas then draws them by
// handle. Images already cached are not decoded again: a page drawn again
// is prepared at once. What the browser did not take is decoded by helder
// when drawn (JPEG 2000, CMYK JPEGs: PdfImage.useJpeg links its JPEG
// decoder; without it such an image is left out).
//
//   PdfWeb.prepare(page, 1.0, () -> Pdf.draw(page, webCanvas, 1.0));
class PdfWeb {
	public static function prepare(page:Page, scale:Float, done:() -> Void) {
		var doc = page.doc;
		var found = [];
		var it = new Interpreter(doc, new Pdf.NoPainter(), Pdf.pageMatrix(page, scale));
		it.textOnly = true;
		it.collect = found;
		try {
			it.run(page.contents(), page.resources);
			it.annotations(page.dict.get("Annots"), page.resources);
		} catch (e:PdfError) {
			if (e.kind == TooLarge) throw e;
		}
		var seen = new Map<String, Bool>(), keys = [], requests = [];
		for (f in found) {
			if (seen.exists(f.key) || doc.images.get(f.key) != null) continue;
			seen.set(f.key, true);
			var r = browserJpeg(doc, f.dict, f.value, f.width, f.height);
			if (r == null) continue;
			keys.push(f.key);
			requests.push(r);
		}
		BrowserImages.all(requests, images -> {
			for (i in 0...images.length) {
				var img = images[i];
				if (img != null) doc.images.put(keys[i], img, img.width * img.height * 4, img.release);
			}
			done();
		});
	}

	// (a JPEG the browser decodes as helder would: its bytes, at the size shown, at most its own)
	static function browserJpeg(doc:Document, d:PdfDict, v:PdfValue, shownW:Int, shownH:Int):Null<{bytes:haxe.io.Bytes, type:String, width:Int, height:Int}> {
		inline function get(k:String, s:String)
			return doc.resolve(d.has(k) ? d.get(k) : d.get(s));
		if (Values.bool(get("ImageMask", "IM")) || get("Decode", "D") != PNull || doc.resolve(d.get("SMask")) != PNull || doc.resolve(d.get("Mask")) != PNull)
			return null;
		if (Values.int(get("BitsPerComponent", "BPC"), 8) != 8) return null;
		var csv = get("ColorSpace", "CS");
		// (ICCBased read as its device space: gray or RGB only; CMYK is helder's)
		var cs = try ColorSpace.load(doc, csv, null) catch (e:Dynamic) null;
		if (cs == null || (cs.kind != "DeviceGray" && cs.kind != "DeviceRGB")) return null;
		var r = try doc.streamWith(v, ["DCTDecode", "DCT"]) catch (e:Dynamic) null;
		if (r == null || r.rest == null) return null;
		var w = Values.int(get("Width", "W")), h = Values.int(get("Height", "H"));
		if (w <= 0 || h <= 0 || w * 1.0 * h > doc.limits.maxImagePixels) return null;
		return {bytes: r.data, type: "image/jpeg", width: Std.int(Math.min(w, Math.max(1, shownW))), height: Std.int(Math.min(h, Math.max(1, shownH)))};
	}
}
