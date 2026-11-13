package helder.canvas.web;

import haxe.io.Bytes;
import helder.canvas.Blend.Blender;
import helder.canvas.Gradient;

// helder.canvas on the browser's own Canvas 2D (wasm32 in a page:
// src/helder/canvas/imports.mjs, the module "hxmc_canvas"): the same
// Painter, its calls recorded as commands into a buffer (opcodes and
// float64s, the paths' verbs and points as they are) and run by the page
// in one import call at a time (when the buffer fills, when pixels are
// read, at the end of a frame: flush()), so a frame of drawing is a few
// crossings, and a web build carries no rasterizer. Each canvas is an
// OffscreenCanvas of the page's (a handle); layers are canvases of their
// own composited at restore; gradients and patterns are made by the page
// from the commands (a bitmap uploaded once, a handle).
@:hxmc.unsafe(gc)
class WebCanvas implements Painter implements GlyphCache implements HandleImages {
	public var width(default, null):Int;
	public var height(default, null):Int;
	public var matrix(get, never):Matrix;

	final handle:Int;
	var buf:Bytes = Bytes.alloc(1 << 16);
	var used = 0;
	final matrices:Array<Matrix> = [new Matrix()];
	var depth = 0;
	final images = new haxe.ds.ObjectMap<Bitmap, Int>();

	public function new(width:Int, height:Int) {
		if (width < 1) width = 1;
		if (height < 1) height = 1;
		this.width = width;
		this.height = height;
		handle = WebCanvasImports.canvas_create(width, height);
	}

	inline function get_matrix()
		return matrices[depth];

	// ---- the buffer

	// (n numbers more without a flush between them: a path's whole, the buffer grown for one past it)
	inline function room(n:Int)
		if (used + n * 8 > buf.length) {
			flush();
			if (n * 8 > buf.length) buf = Bytes.alloc(n * 8);
		}

	inline function num(v:Float) {
		buf.setDouble(used, v);
		used += 8;
	}

	inline function op(code:Int, n:Int) {
		room(n + 1);
		num(code);
	}

	// the commands so far run by the page
	public function flush() {
		if (used == 0) return;
		WebCanvasImports.canvas_run(handle, hxmc.unsafe.BytesPtr.of(buf, 0, used), used);
		used = 0;
	}

	static inline var SAVE = 1;
	static inline var RESTORE = 2;
	static inline var TRANSFORM = 3;
	static inline var CLIP = 4;
	static inline var FILL = 5;
	static inline var STROKE = 6;
	static inline var CLEAR_RECT = 7;
	static inline var CLEAR = 8;
	static inline var IMAGE = 9;
	static inline var LAYER = 10;
	static inline var PATH = 11;
	static inline var PAINT = 12;
	static inline var STOP = 13;
	static inline var LINE = 14;
	static inline var DASH = 15;
	static inline var GLYPH_DEF = 16;
	static inline var GLYPH = 17;

	// ---- glyphs kept in the page (GlyphCache): a Path2D each, by key, for every canvas

	static final defined = new Map<Int, Bool>();

	public function glyphs(paint:Paint) {
		sendPaint(paint);
	}

	public function glyph(key:Int, outline:() -> Path, m:Matrix) {
		if (!defined.exists(key)) {
			defined.set(key, true);
			var p = outline();
			room(4 + p.verbCount * 7);
			op(GLYPH_DEF, 1);
			num(key);
			sendPath(p);
		}
		op(GLYPH, 7);
		num(key);
		num(m.a);
		num(m.b);
		num(m.c);
		num(m.d);
		num(m.e);
		num(m.f);
	}

	// ---- the state

	public function save() {
		depth++;
		if (matrices.length <= depth) matrices.push(new Matrix());
		matrices[depth].copyFrom(matrices[depth - 1]);
		op(SAVE, 0);
	}

	public function saveLayer(alpha = 1.0, ?blend:Blender, ?mask:Mask, ?filter:Filter) {
		depth++;
		if (matrices.length <= depth) matrices.push(new Matrix());
		matrices[depth].copyFrom(matrices[depth - 1]);
		if (filter != null) {
			flush();
			var css = haxe.io.Bytes.ofString(filter.css());
			WebCanvasImports.canvas_filter(handle, hxmc.unsafe.BytesPtr.of(css, 0, css.length), css.length);
		}
		op(LAYER, 3);
		num(alpha);
		num(blend == null ? 1000 : blend.code);
		num(mask == null ? 0 : imageOf(Bitmap.fromStraight(mask.width, mask.height, maskBytes(mask))));
	}

	static function maskBytes(m:Mask):Bytes {
		var b = Bytes.alloc(m.width * m.height * 4);
		for (i in 0...m.width * m.height) {
			var a = m.coverage.get(i);
			b.set(i * 4 + 3, a);
		}
		return b;
	}

	public function restore() {
		if (depth == 0) return;
		depth--;
		op(RESTORE, 0);
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

	// (the transform now, before a draw)
	function sendTransform(m:Matrix) {
		op(TRANSFORM, 6);
		num(m.a);
		num(m.b);
		num(m.c);
		num(m.d);
		num(m.e);
		num(m.f);
	}

	function sendPath(p:Path) {
		var pts = p.points, pi = 0;
		room(2 + p.verbCount * 7);
		op(PATH, 1);
		num(p.verbCount);
		for (i in 0...p.verbCount) {
			var v = p.verbs[i], n = v == Path.MOVE || v == Path.LINE ? 2 : v == Path.QUAD ? 4 : v == Path.CUBIC ? 6 : 0;
			room(n + 1);
			num(v);
			for (k in 0...n)
				num(pts[pi + k]);
			pi += n;
		}
	}

	// (a paint: its kind, colour, alpha, blend; a gradient's geometry and stops; a pattern's image)
	function sendPaint(paint:Paint) {
		var s = paint.shader;
		var kind = s == null ? 0 : Std.isOfType(s, LinearGradient) ? 1 : Std.isOfType(s, RadialGradient) ? 2 : Std.isOfType(s, ConicGradient) ? 3 : 4;
		var img = kind == 4 ? imageOf((cast s : Pattern).bitmap) : 0;
		op(PAINT, 17);
		num(kind);
		num(paint.color);
		num(paint.alpha);
		num(paint.blend == null ? 1000 : paint.blend.code);
		var m:Matrix = kind == 0 ? Matrix.IDENTITY : kind == 4 ? (cast s : Pattern).matrix : (cast s : Gradient).matrix;
		num(m.a);
		num(m.b);
		num(m.c);
		num(m.d);
		num(m.e);
		num(m.f);
		switch kind {
			case 1:
				var g:LinearGradient = cast s;
				for (v in [g.x0, g.y0, g.x1, g.y1, 0, 0])
					num(v);
			case 2:
				var g:RadialGradient = cast s;
				for (v in [g.x0, g.y0, g.r0, g.x1, g.y1, g.r1])
					num(v);
			case 3:
				var g:ConicGradient = cast s;
				for (v in [g.start, g.x, g.y, 0, 0, 0])
					num(v);
			case 4:
				var p:Pattern = cast s;
				for (v in [img, p.repeatX ? 1 : 0, p.repeatY ? 1 : 0, p.smooth ? 1 : 0, 0, 0])
					num(v);
			case _:
				for (_ in 0...6)
					num(0);
		}
		num(kind >= 1 && kind <= 3 ? (cast s : Gradient).spread : 0);
		if (kind >= 1 && kind <= 3) {
			var g:Gradient = cast s;
			for (i in 0...g.stopCount) {
				op(STOP, 2);
				num(g.stopOffset(i));
				num(g.stopColor(i));
			}
		}
	}

	// a bitmap's handle in the page (uploaded once)
	function imageOf(b:Bitmap):Int {
		var h = images.get(b);
		if (h != null) return h;
		flush();
		h = WebCanvasImports.canvas_image(b.width, b.height, hxmc.unsafe.BytesPtr.of(b.pixels, 0, b.pixels.length));
		images.set(b, h);
		return h;
	}

	public function clip(path:Path, evenOdd = false) {
		sendTransform(matrix);
		sendPath(path);
		op(CLIP, 1);
		num(evenOdd ? 1 : 0);
	}

	public function fill(path:Path, paint:Paint, evenOdd = false) {
		sendTransform(matrix);
		sendPaint(paint);
		sendPath(path);
		op(FILL, 1);
		num(evenOdd ? 1 : 0);
	}

	public function stroke(path:Path, style:Stroke, paint:Paint) {
		sendTransform(matrix);
		sendPaint(paint);
		op(LINE, 4);
		num(style.width);
		num(style.join.kind);
		num(style.cap.kind);
		num(style.miterLimit);
		var d = style.dash;
		room(3 + (d == null ? 0 : d.intervals.length));
		op(DASH, 2);
		num(d == null ? 0 : d.intervals.length);
		num(d == null ? 0 : d.offset);
		if (d != null)
			for (v in d.intervals) {
				room(1);
				num(v);
			}
		sendPath(path);
		op(STROKE, 0);
	}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {
		sendTransform(matrix);
		op(CLEAR_RECT, 4);
		num(x);
		num(y);
		num(w);
		num(h);
	}

	public function clear(color = 0) {
		op(CLEAR, 1);
		num(color);
	}

	public function drawImage(img:Bitmap, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth = true) {
		var h = imageOf(img);
		sendTransform(matrix);
		op(IMAGE, 12);
		num(h);
		for (v in [sx, sy, sw, sh, dx, dy, dw, dh])
			num(v);
		num(paint.alpha);
		num(paint.blend == null ? 1000 : paint.blend.code);
		num(smooth ? 1 : 0);
	}

	// an image the page holds (BrowserImages' WebImage: its handle), drawn as drawImage draws
	public function drawHandle(handle:Int, sx:Float, sy:Float, sw:Float, sh:Float, dx:Float, dy:Float, dw:Float, dh:Float, paint:Paint, smooth = true) {
		sendTransform(matrix);
		op(IMAGE, 12);
		num(handle);
		for (v in [sx, sy, sw, sh, dx, dy, dw, dh])
			num(v);
		num(paint.alpha);
		num(paint.blend == null ? 1000 : paint.blend.code);
		num(smooth ? 1 : 0);
	}

	// a bitmap drawImage uploaded, let go of in the page (it is uploaded again if drawn again)
	public function forget(b:Bitmap) {
		var h = images.get(b);
		if (h == null) return;
		flush();
		images.remove(b);
		WebCanvasImports.canvas_release(h);
	}

	public function readPixels(out:Bytes, x:Int, y:Int, w:Int, h:Int) {
		flush();
		var p = hxmc.unsafe.BytesPtr.of(out, 0, w * h * 4);
		WebCanvasImports.canvas_read(handle, x, y, w, h, p);
		hxmc.unsafe.BytesPtr.written(out, 0, p, w * h * 4);
	}

	public function writePixels(rgba:Bytes, x:Int, y:Int, w:Int, h:Int, srcStride = -1) {
		flush();
		var rows = rgba;
		if (srcStride >= 0 && srcStride != w * 4) {
			rows = Bytes.alloc(w * h * 4);
			for (j in 0...h)
				rows.blit(j * w * 4, rgba, j * srcStride, w * 4);
		}
		WebCanvasImports.canvas_write(handle, x, y, w, h, hxmc.unsafe.BytesPtr.of(rows, 0, w * h * 4));
	}

	public function offscreen(width:Int, height:Int):Painter
		return new WebCanvas(width, height);

	public function snapshot():Bitmap {
		var b = Bytes.alloc(width * height * 4);
		readPixels(b, 0, 0, width, height);
		return Bitmap.fromStraight(width, height, b);
	}
}

@:hxmc.c @:hxmc.fast @:hxmc.lib("hxmc_canvas") extern class WebCanvasImports {
	static function canvas_create(width:Int, height:Int):Int;
	static function canvas_run(canvas:Int, commands:hxmc.unsafe.Ptr, bytes:Int):Void;
	// premultiplied RGBA8: an ImageBitmap's handle
	static function canvas_image(width:Int, height:Int, pixels:hxmc.unsafe.Ptr):Int;
	// straight RGBA8 (getImageData's, putImageData's)
	static function canvas_read(canvas:Int, x:Int, y:Int, w:Int, h:Int, out:hxmc.unsafe.Ptr):Void;
	// the next layer's filter (CSS's)
	static function canvas_filter(canvas:Int, css:hxmc.unsafe.Ptr, bytes:Int):Void;
	static function canvas_write(canvas:Int, x:Int, y:Int, w:Int, h:Int, pixels:hxmc.unsafe.Ptr):Void;
	static function canvas_decode(bytes:hxmc.unsafe.Ptr, n:Int, type:hxmc.unsafe.Ptr, typeLength:Int, w:Int, h:Int, ticket:Int, done:hxmc.unsafe.Ptr):Void;
	static function canvas_release(image:Int):Void;
}
