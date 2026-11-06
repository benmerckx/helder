package helder.pdf;

import helder.pdf.PdfValue;
import helder.pdf.Document;
import helder.pdf.Colors;
import helder.pdf.PdfFont;

import haxe.io.Bytes;
import helder.canvas.Bitmap;
import helder.canvas.Matrix;
import helder.canvas.Painter;

// PDF reading and rendering on helder.canvas (src/helder/pdf/README.md):
//
//   var pdf = Pdf.open(bytes);                 // Document: PdfError when it is not one
//   Pdf.openPlain(bytes);                      // no decryption linked (an encrypted one: PdfError)
//   var bitmap = Pdf.render(pdf, 0, 2.0);      // page 1 at 2 pixels a point, on the CPU
//   Pdf.draw(pdf.pages[0], painter, scale);    // onto any Painter (the GPU's, a recording)
//   Pdf.text(pdf.pages[0]);                    // its text
class Pdf {
	public static function open(bytes:Bytes, password = "", ?limits:PdfLimits):Document {
		PdfImage.useJpeg();
		PdfImage.jpx = (d, r, m) -> Jpx.decode(d, r, m);
		PdfImage.jpxInfo = d -> Jpx.info(d);
		return new Document(bytes, password, limits, Crypto.open);
	}

	// the same without decryption, JPEG 2000 or the JPEG decoder linked (an encrypted file a PdfError,
	// Encrypted; a JPX image Unsupported; JPEGs by Pdf.render's decoder, or on the web PdfWeb.prepare's
	// browser or PdfImage.useJpeg): the smaller build
	public static function openPlain(bytes:Bytes, ?limits:PdfLimits):Document
		return new Document(bytes, "", limits);

	// the page's transform from its user space to pixels at scale (its box at the origin, its rotation)
	public static function pageMatrix(page:Page, scale:Float):Matrix {
		var b = page.box, w = (b[2] - b[0]) * scale, h = (b[3] - b[1]) * scale;
		var m = new Matrix(scale, 0, 0, -scale, -b[0] * scale, b[3] * scale);
		var r = switch page.rotate {
			case 90: new Matrix(0, 1, -1, 0, h, 0);
			case 180: new Matrix(-1, 0, 0, -1, w, h);
			case 270: new Matrix(0, -1, 1, 0, 0, w);
			case _: new Matrix();
		}
		return r.multiply(m);
	}

	// the page drawn onto painter (white first when background)
	public static function draw(page:Page, painter:Painter, scale:Float, background = true) {
		if (background) painter.clear(0xFFFFFFFF);
		var it = new Interpreter(page.doc, painter, pageMatrix(page, scale));
		it.run(page.contents(), page.resources);
		it.annotations(page.dict.get("Annots"), page.resources);
		painter.resetTransform();
	}

	// the page's text: its characters in content order (ToUnicode, else the glyph names), a space at a
	// gap, a newline at a new line; nothing painted
	public static function text(page:Page):String {
		var it = new Interpreter(page.doc, new NoPainter(), new Matrix());
		it.textOnly = true;
		it.text = new StringBuf();
		it.run(page.contents(), page.resources);
		return it.text.toString();
	}

	// the page's pixels at scale (pixels a point), on the CPU
	// (into: a canvas of the page's size drawn into again, its pixels the result: a viewer's pages
	// without a bitmap each; wasm memory does not shrink)
	public static function render(doc:Document, index:Int, scale = 1.0, ?into:helder.canvas.Canvas):Bitmap {
		if (index < 0 || index >= doc.pages.length) throw PdfError.corrupt("no page " + (index + 1));
		var page = doc.pages[index];
		var w = Std.int(Math.ceil(page.width * scale)), h = Std.int(Math.ceil(page.height * scale));
		if (w * 1.0 * h > doc.limits.maxImagePixels) throw PdfError.tooLarge('a page of ${w}x$h pixels');
		PdfImage.useJpeg();
		var c = into != null && into.width == w && into.height == h ? into : new helder.canvas.Canvas(w, h);
		c.resetTransform();
		c.restoreToCount(0);
		draw(page, c, scale);
		return c.bitmap;
	}
}

// (Pdf.text's painter: nothing drawn, no rasterizer brought in)
class NoPainter implements Painter {
	public var width(default, null) = 1;
	public var height(default, null) = 1;
	public var matrix(get, never):Matrix;

	final m = new Matrix();

	public function new() {}

	function get_matrix()
		return m;

	public function save() {}

	public function saveLayer(alpha = 1.0, ?blend:helder.canvas.Blend.Blender, ?mask:helder.canvas.Mask, ?filter:helder.canvas.Filter) {}

	public function restore() {}

	public function restoreToCount(count:Int) {}

	public function translate(x:Float, y:Float) {}

	public function scale(x:Float, y:Float) {}

	public function rotate(angle:Float) {}

	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function setTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {}

	public function resetTransform() {}

	public function clip(path:helder.canvas.Path, evenOdd = false) {}

	public function fill(path:helder.canvas.Path, paint:helder.canvas.Paint, evenOdd = false) {}

	public function stroke(path:helder.canvas.Path, style:helder.canvas.Stroke, paint:helder.canvas.Paint) {}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {}

	public function clear(color = 0) {}

	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:helder.canvas.Paint, smooth = true) {}

	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int) {}

	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1) {}

	public function snapshot():Bitmap
		return new Bitmap(1, 1);

	public function offscreen(width:Int, height:Int):Painter
		return this;
}
