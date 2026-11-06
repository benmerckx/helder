package helder.canvas.doc;

import haxe.io.Bytes;
import helder.canvas.Blend.Blender;

// A Painter that keeps what is drawn instead of drawing it: a page of a
// Document, written out as vectors (PdfWriter, SvgWriter) or replayed on
// any other Painter (replay: the CPU's, the GPU's). Each call's path,
// paint and stroke are copied (a recording outlives the caller's values);
// pixels written in (writePixels) are kept as an image.
class Recorder implements Painter {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var matrix(get, never):Matrix;

	public final ops:Array<Op> = [];
	final matrices:Array<Matrix> = [new Matrix()];
	var depth = 0;

	public function new(width:Int, height:Int) {
		this.width = width;
		this.height = height;
	}

	inline function get_matrix()
		return matrices[depth];

	function push(kind:OpKind):Op {
		var o = new Op(kind, matrix.clone());
		ops.push(o);
		return o;
	}

	public function save() {
		depth++;
		if (matrices.length <= depth) matrices.push(new Matrix());
		matrices[depth].copyFrom(matrices[depth - 1]);
		push(Save);
	}

	public function saveLayer(alpha = 1.0, ?blend:Blender, ?mask:Mask, ?filter:Filter) {
		depth++;
		if (matrices.length <= depth) matrices.push(new Matrix());
		matrices[depth].copyFrom(matrices[depth - 1]);
		var o = push(Layer);
		o.alpha = alpha;
		o.blend = blend;
		o.mask = mask;
		o.filter = filter;
	}

	public function restore() {
		if (depth == 0) return;
		depth--;
		push(Restore);
	}

	public function restoreToCount(count:Int)
		while (depth > count)
			restore();

	public function translate(x:Float, y:Float)
		matrix.translate(x, y);

	public function scale(x:Float, y:Float)
		matrix.scale(x, y);

	public function rotate(angle:Float)
		matrix.rotate(angle);

	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		matrix.transform(a, b, c, d, e, f);

	public function setTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float)
		matrix.set(a, b, c, d, e, f);

	public function resetTransform()
		matrix.identity();

	public function clip(path:Path, evenOdd = false) {
		var o = push(Clip);
		o.path = path.copy();
		o.evenOdd = evenOdd;
	}

	public function fill(path:Path, paint:Paint, evenOdd = false) {
		var o = push(Fill);
		o.path = path.copy();
		o.paint = new Paint().copyFrom(paint);
		o.evenOdd = evenOdd;
	}

	public function stroke(path:Path, style:Stroke, paint:Paint) {
		var o = push(StrokePath);
		o.path = path.copy();
		o.paint = new Paint().copyFrom(paint);
		o.stroke = new Stroke().copyFrom(style);
	}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {
		var o = push(ClearRect);
		o.rect = [x, y, w, h];
	}

	public function clear(color = 0) {
		// (everything before it gone: a page cleared starts again)
		if (depth == 0) ops.resize(0);
		var o = push(Clear);
		o.color = color;
	}

	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth = true) {
		var o = push(Image);
		o.image = img;
		o.rect = [sx, sy, sw, sh, dx, dy, dw, dh];
		o.paint = new Paint().copyFrom(paint);
		o.smooth = smooth;
	}

	// (pixels as they are: replayed onto a canvas of this size to read them)
	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int)
		snapshot().readStraight(out, x, y, w, h);

	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1) {
		var b = new Bitmap(w, h);
		b.writeStraight(rgba, 0, 0, w, h, srcStride);
		var o = push(Pixels);
		o.image = b;
		o.rect = [x, y];
	}

	public function offscreen(width:Int, height:Int):Painter
		return new Recorder(width, height);

	// the page drawn on the CPU
	public function snapshot():Bitmap {
		var c = new Canvas(width, height);
		replay(c);
		return c.bitmap;
	}

	// everything recorded drawn on another Painter
	public function replay(p:Painter) {
		for (o in ops) {
			var m = o.matrix;
			switch o.kind {
				case Save:
					p.save();
				case Layer:
					p.saveLayer(o.alpha, o.blend, o.mask, o.filter);
				case Restore:
					p.restore();
				case Clip:
					p.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
					p.clip(o.path, o.evenOdd);
				case Fill:
					p.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
					p.fill(o.path, o.paint, o.evenOdd);
				case StrokePath:
					p.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
					p.stroke(o.path, o.stroke, o.paint);
				case ClearRect:
					p.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
					p.clearRect(o.rect[0], o.rect[1], o.rect[2], o.rect[3]);
				case Clear:
					p.clear(o.color);
				case Image:
					p.setTransform(m.a, m.b, m.c, m.d, m.e, m.f);
					var r = o.rect;
					p.drawImage(o.image, r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], o.paint, o.smooth);
				case Pixels:
					p.writePixels(o.image.straight(), Std.int(o.rect[0]), Std.int(o.rect[1]), o.image.width, o.image.height);
			}
		}
		p.resetTransform();
	}
}

enum abstract OpKind(Int) {
	var Save;
	var Layer;
	var Restore;
	var Clip;
	var Fill;
	var StrokePath;
	var ClearRect;
	var Clear;
	var Image;
	var Pixels;
}

// One recorded call: its transform and what it was given
class Op {
	public final kind:OpKind;
	public final matrix:Matrix;
	public var path:Null<Path> = null;
	public var paint:Null<Paint> = null;
	public var stroke:Null<Stroke> = null;
	public var evenOdd = false;
	public var alpha = 1.0;
	public var blend:Null<Blender> = null;
	public var mask:Null<Mask> = null;
	public var filter:Null<Filter> = null;
	public var image:Null<Bitmap> = null;
	public var rect:Null<Array<Float>> = null;
	public var smooth = true;
	public var color = 0;

	public function new(kind, matrix) {
		this.kind = kind;
		this.matrix = matrix;
	}
}

