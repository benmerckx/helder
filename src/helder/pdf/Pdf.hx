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
//   var bitmap = Pdf.render(pdf, 0, 2.0);      // page 1 at 2 pixels a point, on the CPU
//   Pdf.draw(pdf.pages[0], painter, scale);    // onto any Painter (the GPU's, a recording)
class Pdf {
	public static function open(bytes:Bytes, password = "", ?limits:PdfLimits):Document
		return new Document(bytes, password, limits);

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
		painter.resetTransform();
	}

	// the page's pixels at scale (pixels a point), on the CPU
	public static function render(doc:Document, index:Int, scale = 1.0):Bitmap {
		if (index < 0 || index >= doc.pages.length) throw PdfError.corrupt("no page " + (index + 1));
		var page = doc.pages[index];
		var w = Std.int(Math.ceil(page.width * scale)), h = Std.int(Math.ceil(page.height * scale));
		if (w * 1.0 * h > doc.limits.maxImagePixels) throw PdfError.tooLarge('a page of ${w}x$h pixels');
		var c = new helder.canvas.Canvas(w, h);
		draw(page, c, scale);
		return c.bitmap;
	}
}
