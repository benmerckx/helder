package helder.canvas.doc;

import haxe.io.Bytes;
import helder.canvas.Blend.Blender;

// Two Painters drawn alike: the pixels (a), and a recording beside them
// (b: the DOM facade's pages, for PDF and SVG); pixels are a's
class Tee implements Painter {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var matrix(get, never):Matrix;

	public final a:Painter;
	public final b:Painter;

	public function new(a:Painter, b:Painter) {
		this.a = a;
		this.b = b;
		width = a.width;
		height = a.height;
	}

	inline function get_matrix()
		return a.matrix;

	// (b's transform made a's before each call that draws)
	inline function sync() {
		var m = a.matrix;
		b.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
	}

	public function save() {
		a.save();
		b.save();
	}

	public function saveLayer(alpha = 1.0, ?blend:Blender, ?mask:Mask, ?filter:Filter) {
		a.saveLayer(alpha, blend, mask, filter);
		b.saveLayer(alpha, blend, mask, filter);
	}

	public function restore() {
		a.restore();
		b.restore();
	}

	public function restoreToCount(count:Int) {
		a.restoreToCount(count);
		b.restoreToCount(count);
	}

	public function translate(x:Float, y:Float)
		a.translate(x, y);

	public function scale(x:Float, y:Float)
		a.scale(x, y);

	public function rotate(angle:Float)
		a.rotate(angle);

	public function transform(p:Float, q:Float, r:Float, s:Float, t:Float, u:Float)
		a.transform(p, q, r, s, t, u);

	public function setTransform(p:Float, q:Float, r:Float, s:Float, t:Float, u:Float)
		a.setTransform(p, q, r, s, t, u);

	public function resetTransform()
		a.resetTransform();

	public function clip(path:Path, evenOdd = false) {
		a.clip(path, evenOdd);
		sync();
		b.clip(path, evenOdd);
	}

	public function fill(path:Path, paint:Paint, evenOdd = false) {
		a.fill(path, paint, evenOdd);
		sync();
		b.fill(path, paint, evenOdd);
	}

	public function stroke(path:Path, style:Stroke, paint:Paint) {
		a.stroke(path, style, paint);
		sync();
		b.stroke(path, style, paint);
	}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {
		a.clearRect(x, y, w, h);
		sync();
		b.clearRect(x, y, w, h);
	}

	public function clear(color = 0) {
		a.clear(color);
		b.clear(color);
	}

	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth = true) {
		a.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh, paint, smooth);
		sync();
		b.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh, paint, smooth);
	}

	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int)
		a.readPixels(out, x, y, w, h);

	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1) {
		a.writePixels(rgba, x, y, w, h, srcStride);
		b.writePixels(rgba, x, y, w, h, srcStride);
	}

	public function snapshot():Bitmap
		return a.snapshot();
}
