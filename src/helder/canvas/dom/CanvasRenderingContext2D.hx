package helder.canvas.dom;

import haxe.io.Bytes;
import helder.canvas.Blend;
import helder.canvas.Gradient;
import helder.canvas.Matrix;
import helder.canvas.Paint;
import helder.canvas.Path;
import helder.canvas.Stroke;
import helder.text.FontFile;
import helder.text.FontSet;
import helder.text.TextLayout;

// The browser's CanvasRenderingContext2D on helder.canvas: the standard
// API (paths, fills and strokes, transforms, clips, gradients, patterns,
// images, compositing, text, pixels), its string-valued state parsed as
// the browser parses it (an invalid value ignored). The default path is
// kept in the user units of the transform now: a change of transform moves
// it, so it stays where it was drawn, as the browser's.
class CanvasRenderingContext2D {
	public var canvas(default, null):Canvas;

	var core:helder.canvas.Painter;
	var s:DrawState = new DrawState();
	final stack:Array<DrawState> = [];
	final path = new Path();
	final paint = new Paint();
	final stroker = new helder.canvas.Stroker();
	final old = new Matrix();
	final tmp = new Matrix();
	final scratch = new Path();

	@:noCompletion public function new(canvas:Canvas) {
		this.canvas = canvas;
		attach(canvas.core);
	}

	@:noCompletion public function attach(core:helder.canvas.Painter) {
		this.core = core;
		stack.resize(0);
		s = new DrawState();
		path.clear();
	}

	// ---- state

	public function save() {
		stack.push(s.copy());
		core.save();
	}

	public function restore() {
		if (stack.length == 0) return;
		var prev = stack.pop();
		beforeTransform();
		core.restore();
		afterTransform();
		s = prev;
	}

	// everything back to its initial state, the pixels transparent
	public function reset() {
		core.restoreToCount(0);
		core.resetTransform();
		core.clear();
		stack.resize(0);
		s = new DrawState();
		path.clear();
	}

	public function isContextLost():Bool
		return false;

	public function getContextAttributes():Dynamic
		return {alpha: true, colorSpace: "srgb", desynchronized: false, willReadFrequently: false};

	// ---- transforms

	inline function beforeTransform()
		old.copyFrom(core.matrix);

	// (the default path moved so it stays where it was: through the new transform's inverse and the old)
	function afterTransform() {
		if (path.isEmpty()) return;
		if (!core.matrix.invertInto(tmp)) return;
		tmp.multiply(old);
		if (!tmp.isIdentity()) path.transform(tmp);
	}

	public function translate(x:Float, y:Float) {
		if (!Math.isFinite(x) || !Math.isFinite(y)) return;
		beforeTransform();
		core.translate(x, y);
		afterTransform();
	}

	public function scale(x:Float, y:Float) {
		if (!Math.isFinite(x) || !Math.isFinite(y)) return;
		beforeTransform();
		core.scale(x, y);
		afterTransform();
	}

	public function rotate(angle:Float) {
		if (!Math.isFinite(angle)) return;
		beforeTransform();
		core.rotate(angle);
		afterTransform();
	}

	public function transform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float) {
		if (!finite6(a, b, c, d, e, f)) return;
		beforeTransform();
		core.transform(a, b, c, d, e, f);
		afterTransform();
	}

	// (a, b, c, d, e, f), a DOMMatrix or {a...f}, or nothing (the identity)
	public function setTransform(?a:Dynamic, ?b:Float, ?c:Float, ?d:Float, ?e:Float, ?f:Float) {
		var m = [1.0, 0, 0, 1, 0, 0];
		if (a == null) {} else if (Std.isOfType(a, DOMMatrix)) {
			var x:DOMMatrix = a;
			m = [x.a, x.b, x.c, x.d, x.e, x.f];
		} else if (Std.isOfType(a, Float) || Std.isOfType(a, Int)) {
			m = [a, b ?? 0, c ?? 0, d ?? 0, e ?? 0, f ?? 0];
		} else {
			inline function field(n:String, def:Float):Float {
				var v:Null<Float> = Reflect.field(a, n);
				return v ?? def;
			}
			m = [field("a", 1), field("b", 0), field("c", 0), field("d", 1), field("e", 0), field("f", 0)];
		}
		if (!finite6(m[0], m[1], m[2], m[3], m[4], m[5])) return;
		beforeTransform();
		core.setTransform(m[0], m[1], m[2], m[3], m[4], m[5]);
		afterTransform();
	}

	public function resetTransform() {
		beforeTransform();
		core.resetTransform();
		afterTransform();
	}

	public function getTransform():DOMMatrix
		return DOMMatrix.of(core.matrix);

	static inline function finite6(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Bool
		return Math.isFinite(a) && Math.isFinite(b) && Math.isFinite(c) && Math.isFinite(d) && Math.isFinite(e) && Math.isFinite(f);

	// ---- styles

	public var fillStyle(get, set):Dynamic;
	public var strokeStyle(get, set):Dynamic;

	function get_fillStyle():Dynamic
		return s.fill.value();

	function set_fillStyle(v:Dynamic):Dynamic {
		s.fill.set(v);
		return v;
	}

	function get_strokeStyle():Dynamic
		return s.stroke.value();

	function set_strokeStyle(v:Dynamic):Dynamic {
		s.stroke.set(v);
		return v;
	}

	public var globalAlpha(get, set):Float;

	function get_globalAlpha()
		return s.alpha;

	function set_globalAlpha(v:Float) {
		if (v >= 0 && v <= 1) s.alpha = v;
		return v;
	}

	public var globalCompositeOperation(get, set):String;

	function get_globalCompositeOperation()
		return s.composite;

	function set_globalCompositeOperation(v:String) {
		var b:Null<Blender> = null, known = true;
		switch v {
			case "source-over":
			case "source-in": b = Blend.sourceIn;
			case "source-out": b = Blend.sourceOut;
			case "source-atop": b = Blend.sourceAtop;
			case "destination-over": b = Blend.destinationOver;
			case "destination-in": b = Blend.destinationIn;
			case "destination-out": b = Blend.destinationOut;
			case "destination-atop": b = Blend.destinationAtop;
			case "lighter": b = Blend.lighter;
			case "copy": b = Blend.copy;
			case "clear": b = Blend.clear;
			case "xor": b = Blend.xor;
			case "multiply": b = Blend.multiply;
			case "screen": b = Blend.screen;
			case "overlay": b = Blend.overlay;
			case "darken": b = Blend.darken;
			case "lighten": b = Blend.lighten;
			case "color-dodge": b = Blend.colorDodge;
			case "color-burn": b = Blend.colorBurn;
			case "hard-light": b = Blend.hardLight;
			case "soft-light": b = Blend.softLight;
			case "difference": b = Blend.difference;
			case "exclusion": b = Blend.exclusion;
			case "hue": b = Blend.hue;
			case "saturation": b = Blend.saturation;
			case "color": b = Blend.color;
			case "luminosity": b = Blend.luminosity;
			case _: known = false;
		}
		if (known) {
			s.composite = v;
			s.blend = b;
		}
		return v;
	}

	public var imageSmoothingEnabled(get, set):Bool;
	public var imageSmoothingQuality(get, set):String;

	function get_imageSmoothingEnabled()
		return s.smoothing;

	function set_imageSmoothingEnabled(v:Bool)
		return s.smoothing = v;

	function get_imageSmoothingQuality()
		return s.smoothingQuality;

	function set_imageSmoothingQuality(v:String) {
		if (v == "low" || v == "medium" || v == "high") s.smoothingQuality = v;
		return v;
	}

	// (stored; not drawn yet: helder.canvas has no blur or shadows in this phase)
	public var shadowBlur(get, set):Float;
	public var shadowColor(get, set):String;
	public var shadowOffsetX(get, set):Float;
	public var shadowOffsetY(get, set):Float;
	public var filter(get, set):String;

	function get_shadowBlur()
		return s.shadowBlur;

	function set_shadowBlur(v:Float) {
		if (v >= 0 && Math.isFinite(v)) s.shadowBlur = v;
		return v;
	}

	function get_shadowColor()
		return Colors.serialize(s.shadowColor);

	function set_shadowColor(v:String) {
		var c = Colors.parse(v);
		if (c != null) s.shadowColor = c;
		return v;
	}

	function get_shadowOffsetX()
		return s.shadowX;

	function set_shadowOffsetX(v:Float) {
		if (Math.isFinite(v)) s.shadowX = v;
		return v;
	}

	function get_shadowOffsetY()
		return s.shadowY;

	function set_shadowOffsetY(v:Float) {
		if (Math.isFinite(v)) s.shadowY = v;
		return v;
	}

	function get_filter()
		return s.filter;

	function set_filter(v:String)
		return s.filter = v;

	// ---- lines

	public var lineWidth(get, set):Float;
	public var lineCap(get, set):String;
	public var lineJoin(get, set):String;
	public var miterLimit(get, set):Float;
	public var lineDashOffset(get, set):Float;

	function get_lineWidth()
		return s.line.width;

	function set_lineWidth(v:Float) {
		if (v > 0 && Math.isFinite(v)) s.line.width = v;
		return v;
	}

	function get_lineCap()
		return s.cap;

	function set_lineCap(v:String) {
		switch v {
			case "butt": s.line.cap = Cap.butt;
			case "round": s.line.cap = Cap.round;
			case "square": s.line.cap = Cap.square;
			case _: return v;
		}
		s.cap = v;
		return v;
	}

	function get_lineJoin()
		return s.join;

	function set_lineJoin(v:String) {
		switch v {
			case "miter": s.line.join = Join.miter;
			case "round": s.line.join = Join.round;
			case "bevel": s.line.join = Join.bevel;
			case _: return v;
		}
		s.join = v;
		return v;
	}

	function get_miterLimit()
		return s.line.miterLimit;

	function set_miterLimit(v:Float) {
		if (v > 0 && Math.isFinite(v)) s.line.miterLimit = v;
		return v;
	}

	function get_lineDashOffset()
		return s.dashOffset;

	function set_lineDashOffset(v:Float) {
		if (Math.isFinite(v)) {
			s.dashOffset = v;
			if (s.line.dash != null) s.line.dash = new Dash(s.dash, v);
		}
		return v;
	}

	public function setLineDash(segments:Array<Float>) {
		for (x in segments)
			if (!Math.isFinite(x) || x < 0) return;
		s.dash = segments.length % 2 == 1 ? segments.concat(segments) : segments.copy();
		s.line.dash = s.dash.length == 0 ? null : new Dash(s.dash, s.dashOffset);
	}

	public function getLineDash():Array<Float>
		return s.dash.copy();

	// ---- text styles

	public var font(get, set):String;
	public var textAlign(get, set):String;
	public var textBaseline(get, set):String;
	public var direction(get, set):String;
	public var letterSpacing(get, set):String;
	public var wordSpacing(get, set):String;
	public var fontKerning(get, set):String;
	public var fontStretch(get, set):String;
	public var fontVariantCaps(get, set):String;
	public var textRendering(get, set):String;

	function get_font()
		return s.font.serialized;

	function set_font(v:String) {
		var f = FontSpec.parse(v);
		if (f != null) s.font = f;
		return v;
	}

	function get_textAlign()
		return s.align;

	function set_textAlign(v:String) {
		if (v == "start" || v == "end" || v == "left" || v == "right" || v == "center") s.align = v;
		return v;
	}

	function get_textBaseline()
		return s.baseline;

	function set_textBaseline(v:String) {
		if (v == "top" || v == "hanging" || v == "middle" || v == "alphabetic" || v == "ideographic" || v == "bottom") s.baseline = v;
		return v;
	}

	function get_direction()
		return s.direction;

	function set_direction(v:String) {
		if (v == "ltr" || v == "rtl" || v == "inherit") s.direction = v;
		return v;
	}

	function get_letterSpacing()
		return s.letterSpacingText;

	function set_letterSpacing(v:String) {
		var px = FontSpec.length(v, s.font.size);
		if (px != null) {
			s.letterSpacing = px;
			s.letterSpacingText = v;
		}
		return v;
	}

	function get_wordSpacing()
		return s.wordSpacingText;

	function set_wordSpacing(v:String) {
		var px = FontSpec.length(v, s.font.size);
		if (px != null) {
			s.wordSpacing = px;
			s.wordSpacingText = v;
		}
		return v;
	}

	function get_fontKerning()
		return s.kerning;

	function set_fontKerning(v:String) {
		if (v == "auto" || v == "normal" || v == "none") s.kerning = v;
		return v;
	}

	function get_fontStretch()
		return s.stretch;

	function set_fontStretch(v:String)
		return s.stretch = v;

	function get_fontVariantCaps()
		return s.variantCaps;

	function set_fontVariantCaps(v:String)
		return s.variantCaps = v;

	function get_textRendering()
		return s.textRendering;

	function set_textRendering(v:String)
		return s.textRendering = v;

	// ---- gradients and patterns

	public function createLinearGradient(x0:Float, y0:Float, x1:Float, y1:Float):CanvasGradient {
		if (!finite4(x0, y0, x1, y1)) throw new Path2D.DOMException("TypeError", "The provided double value is non-finite.");
		return new CanvasGradient(new LinearGradient(x0, y0, x1, y1));
	}

	public function createRadialGradient(x0:Float, y0:Float, r0:Float, x1:Float, y1:Float, r1:Float):CanvasGradient {
		if (!finite6(x0, y0, r0, x1, y1, r1)) throw new Path2D.DOMException("TypeError", "The provided double value is non-finite.");
		if (r0 < 0 || r1 < 0) throw new Path2D.DOMException("IndexSizeError", "The radius provided is negative.");
		return new CanvasGradient(new RadialGradient(x0, y0, r0, x1, y1, r1));
	}

	public function createConicGradient(startAngle:Float, x:Float, y:Float):CanvasGradient {
		if (!finite4(startAngle, x, y, 0)) throw new Path2D.DOMException("TypeError", "The provided double value is non-finite.");
		return new CanvasGradient(new ConicGradient(startAngle, x, y));
	}

	// image: an Image or a Canvas (its pixels now); repetition: "repeat" (null, ""), "repeat-x", "repeat-y", "no-repeat"
	public function createPattern(image:Dynamic, ?repetition:String):Null<CanvasPattern> {
		var rx = true, ry = true;
		switch repetition {
			case null | "" | "repeat":
			case "repeat-x": ry = false;
			case "repeat-y": rx = false;
			case "no-repeat": rx = ry = false;
			case _: throw new Path2D.DOMException("SyntaxError", "The provided type ('" + repetition + "') is not one of 'repeat', 'no-repeat', 'repeat-x', or 'repeat-y'.");
		}
		var b = bitmapOf(image, true);
		if (b == null) return null;
		return new CanvasPattern(new helder.canvas.Pattern(b, rx, ry));
	}

	// (an image's pixels: an Image's, a Canvas's (copied when asked: a pattern keeps its own), ImageData's)
	function bitmapOf(image:Dynamic, copy:Bool):Null<helder.canvas.Bitmap> {
		if (Std.isOfType(image, Image)) return (image : Image).bitmap;
		if (Std.isOfType(image, Canvas)) {
			var b = (image : Canvas).core.snapshot();
			if (!copy && (image : Canvas) != canvas) return b;
			return new helder.canvas.Bitmap(b.width, b.height, b.pixels.sub(0, b.pixels.length));
		}
		if (Std.isOfType(image, ImageData)) {
			var d:ImageData = image;
			return helder.canvas.Bitmap.fromStraight(d.width, d.height, d.bytes);
		}
		throw new Path2D.DOMException("TypeError", "The provided value is not of type '(CanvasImageSource)'.");
	}

	// ---- paths

	public function beginPath()
		path.clear();

	public function closePath()
		path.close();

	public function moveTo(x:Float, y:Float)
		path.moveTo(x, y);

	public function lineTo(x:Float, y:Float)
		path.lineTo(x, y);

	public function quadraticCurveTo(cpx:Float, cpy:Float, x:Float, y:Float)
		path.quadTo(cpx, cpy, x, y);

	public function bezierCurveTo(cp1x:Float, cp1y:Float, cp2x:Float, cp2y:Float, x:Float, y:Float)
		path.cubicTo(cp1x, cp1y, cp2x, cp2y, x, y);

	public function arc(x:Float, y:Float, radius:Float, startAngle:Float, endAngle:Float, anticlockwise = false) {
		if (!finite4(x, y, radius, startAngle) || !Math.isFinite(endAngle)) return;
		if (radius < 0) throw new Path2D.DOMException("IndexSizeError", "The radius provided (" + radius + ") is negative.");
		path.arc(x, y, radius, startAngle, endAngle, anticlockwise);
	}

	public function arcTo(x1:Float, y1:Float, x2:Float, y2:Float, radius:Float) {
		if (!finite4(x1, y1, x2, y2) || !Math.isFinite(radius)) return;
		if (radius < 0) throw new Path2D.DOMException("IndexSizeError", "The radius provided (" + radius + ") is negative.");
		path.arcTo(x1, y1, x2, y2, radius);
	}

	public function ellipse(x:Float, y:Float, radiusX:Float, radiusY:Float, rotation:Float, startAngle:Float, endAngle:Float, anticlockwise = false) {
		if (!finite4(x, y, radiusX, radiusY) || !finite4(rotation, startAngle, endAngle, 0)) return;
		if (radiusX < 0 || radiusY < 0) throw new Path2D.DOMException("IndexSizeError", "The radius provided is negative.");
		path.ellipse(x, y, radiusX, radiusY, rotation, startAngle, endAngle, anticlockwise);
	}

	public function rect(x:Float, y:Float, w:Float, h:Float)
		path.rect(x, y, w, h);

	public function roundRect(x:Float, y:Float, w:Float, h:Float, ?radii:Dynamic)
		Path2D.roundRectInto(path, x, y, w, h, radii);

	// ---- drawing

	// (a), (rule) or (path, rule): the path and whether it is even-odd
	function pathArg(a:Dynamic):Path
		return Std.isOfType(a, Path2D) ? (a : Path2D).path : path;

	function ruleArg(a:Dynamic, b:Dynamic):Bool {
		var r:Dynamic = Std.isOfType(a, Path2D) ? b : a;
		return r == "evenodd";
	}

	public function fill(?a:Dynamic, ?b:Dynamic) {
		var p = pathArg(a);
		if (!s.fill.ready(paint, s, this)) return;
		core.fill(p, paint, ruleArg(a, b));
	}

	public function stroke(?a:Path2D) {
		var p = a == null ? path : a.path;
		if (!s.stroke.ready(paint, s, this)) return;
		core.stroke(p, s.line, paint);
	}

	public function clip(?a:Dynamic, ?b:Dynamic)
		core.clip(pathArg(a), ruleArg(a, b));

	public function fillRect(x:Float, y:Float, w:Float, h:Float) {
		if (!finite4(x, y, w, h)) return;
		scratch.clear();
		scratch.rect(x, y, w, h);
		if (!s.fill.ready(paint, s, this)) return;
		core.fill(scratch, paint);
	}

	public function strokeRect(x:Float, y:Float, w:Float, h:Float) {
		if (!finite4(x, y, w, h)) return;
		scratch.clear();
		// (a rectangle of no width or height: a closed line, joined at its ends, not capped; of neither: nothing)
		if (w == 0 && h == 0) return;
		if (w == 0 || h == 0) {
			scratch.moveTo(x, y);
			scratch.lineTo(x + w, y + h);
			scratch.close();
		} else
			scratch.rect(x, y, w, h);
		if (!s.stroke.ready(paint, s, this)) return;
		core.stroke(scratch, s.line, paint);
	}

	public function clearRect(x:Float, y:Float, w:Float, h:Float) {
		if (!finite4(x, y, w, h)) return;
		core.clearRect(x, y, w, h);
	}

	static inline function finite4(a:Float, b:Float, c:Float, d:Float):Bool
		return Math.isFinite(a) && Math.isFinite(b) && Math.isFinite(c) && Math.isFinite(d);

	// whether (x, y), in the canvas's pixels, is inside the path: (x, y, rule?) or (path, x, y, rule?)
	public function isPointInPath(a:Dynamic, b:Dynamic, ?c:Dynamic, ?d:Dynamic):Bool {
		var p = path, x:Float, y:Float, rule:Dynamic;
		if (Std.isOfType(a, Path2D)) {
			p = (a : Path2D).path;
			x = b;
			y = c;
			rule = d;
		} else {
			x = a;
			y = b;
			rule = c;
		}
		if (!Math.isFinite(x) || !Math.isFinite(y)) return false;
		if (!core.matrix.invertInto(tmp)) return false;
		return p.contains(tmp.mapX(x, y), tmp.mapY(x, y), rule == "evenodd");
	}

	// whether (x, y) is inside the path's stroke with the line styles now: (x, y) or (path, x, y)
	public function isPointInStroke(a:Dynamic, b:Dynamic, ?c:Dynamic):Bool {
		var p = path, x:Float, y:Float;
		if (Std.isOfType(a, Path2D)) {
			p = (a : Path2D).path;
			x = b;
			y = c;
		} else {
			x = a;
			y = b;
		}
		if (!Math.isFinite(x) || !Math.isFinite(y)) return false;
		if (!core.matrix.invertInto(tmp)) return false;
		var w = helder.canvas.Path.Winding.shared;
		w.reset(tmp.mapX(x, y), tmp.mapY(x, y));
		stroker.stroke(p, s.line, Matrix.IDENTITY, w, 0.05);
		return w.winding != 0 || w.onEdge;
	}

	// ---- images

	// (image, dx, dy), (image, dx, dy, dw, dh), (image, sx, sy, sw, sh, dx, dy, dw, dh)
	public function drawImage(image:Dynamic, a:Float, b:Float, ?c:Float, ?d:Float, ?e:Float, ?f:Float, ?g:Float, ?h:Float) {
		var bm = bitmapOf(image, Std.isOfType(image, Canvas) && (image : Canvas) == canvas);
		if (bm == null) return;
		var sx = 0.0, sy = 0.0, sw:Float = bm.width, sh:Float = bm.height, dx = a, dy = b, dw:Float = bm.width, dh:Float = bm.height;
		if (e != null) {
			sx = a;
			sy = b;
			sw = c;
			sh = d;
			dx = e;
			dy = f ?? 0;
			dw = g ?? 0;
			dh = h ?? 0;
		} else if (c != null) {
			dw = c;
			dh = d ?? 0;
		}
		if (!finite4(sx, sy, sw, sh) || !finite4(dx, dy, dw, dh)) return;
		if (bm.width == 0 || bm.height == 0) return;
		paint.color = 0xFF000000;
		paint.shader = null;
		paint.alpha = s.alpha;
		paint.blend = s.blend;
		core.drawImage(bm, sx, sy, sw, sh, dx, dy, dw, dh, paint, s.smoothing);
	}

	// ---- pixels

	public function createImageData(a:Dynamic, ?h:Int):ImageData {
		if (Std.isOfType(a, ImageData)) return new ImageData((a : ImageData).width, (a : ImageData).height);
		var w:Int = Std.int(Math.abs(a)), hh = h == null ? 0 : (h < 0 ? -h : h);
		return new ImageData(w, hh);
	}

	public function getImageData(sx:Int, sy:Int, sw:Int, sh:Int):ImageData {
		if (sw == 0 || sh == 0) throw new Path2D.DOMException("IndexSizeError", "The source width or height is 0.");
		if (sw < 0) {
			sx += sw;
			sw = -sw;
		}
		if (sh < 0) {
			sy += sh;
			sh = -sh;
		}
		var out = Bytes.alloc(sw * sh * 4);
		core.readPixels(out, sx, sy, sw, sh);
		return ImageData.of(sw, sh, out);
	}

	public function putImageData(data:ImageData, dx:Int, dy:Int, ?dirtyX:Int, ?dirtyY:Int, ?dirtyW:Int, ?dirtyH:Int) {
		var x0 = dirtyX ?? 0, y0 = dirtyY ?? 0, w = dirtyW ?? data.width, h = dirtyH ?? data.height;
		if (w < 0) {
			x0 += w;
			w = -w;
		}
		if (h < 0) {
			y0 += h;
			h = -h;
		}
		if (x0 < 0) {
			w += x0;
			x0 = 0;
		}
		if (y0 < 0) {
			h += y0;
			y0 = 0;
		}
		if (x0 + w > data.width) w = data.width - x0;
		if (y0 + h > data.height) h = data.height - y0;
		if (w <= 0 || h <= 0) return;
		var rows = Bytes.alloc(w * h * 4);
		for (j in 0...h)
			rows.blit(j * w * 4, data.bytes, ((y0 + j) * data.width + x0) * 4, w * 4);
		core.writePixels(rows, dx + x0, dy + y0, w, h);
	}

	// ---- text

	public function fillText(text:String, x:Float, y:Float, ?maxWidth:Float)
		drawText(text, x, y, maxWidth, true);

	public function strokeText(text:String, x:Float, y:Float, ?maxWidth:Float)
		drawText(text, x, y, maxWidth, false);

	public function measureText(text:String):TextMetrics {
		var t = Text.get();
		var m = new TextMetrics();
		t.layout(text, s);
		t.metrics(s, m);
		return m;
	}

	function drawText(text:String, x:Float, y:Float, maxWidth:Null<Float>, fill:Bool) {
		if (!Math.isFinite(x) || !Math.isFinite(y)) return;
		if (maxWidth != null && (!(maxWidth > 0) || !Math.isFinite(maxWidth))) return;
		var t = Text.get();
		t.layout(text, s);
		var w = t.width, k = 1.0;
		if (maxWidth != null && w > maxWidth) k = maxWidth / w;
		var ox = t.alignOffset(s) * k, oy = t.baselineOffset(s);
		var glyphs = t.glyphs;
		glyphs.path.clear();
		glyphs.add(t.lines, x + ox, y + oy, k);
		if (fill) {
			if (!s.fill.ready(paint, s, this)) return;
			core.fill(glyphs.path, paint);
		} else {
			if (!s.stroke.ready(paint, s, this)) return;
			core.stroke(glyphs.path, s.line, paint);
		}
	}
}

// A fill or stroke style: a colour, a gradient or a pattern
@:allow(helder.canvas.dom)
private class Style {
	var color = 0xFF000000;
	var object:Dynamic = null;

	public function new() {}

	public function copy():Style {
		var s = new Style();
		s.color = color;
		s.object = object;
		return s;
	}

	public function value():Dynamic
		return object != null ? object : Colors.serialize(color);

	public function set(v:Dynamic) {
		if (Std.isOfType(v, String)) {
			var c = Colors.parse(v);
			if (c != null) {
				color = c;
				object = null;
			}
		} else if (Std.isOfType(v, CanvasGradient) || Std.isOfType(v, CanvasPattern)) object = v;
	}

	// the paint set to it with the state's alpha and blend (false: nothing to draw)
	public function ready(p:Paint, s:DrawState, ctx:CanvasRenderingContext2D):Bool {
		p.alpha = s.alpha;
		p.blend = s.blend;
		p.color = color;
		p.shader = null;
		if (object != null) {
			if (Std.isOfType(object, CanvasGradient)) p.shader = (object : CanvasGradient).gradient else {
				var pat = (object : CanvasPattern).pattern;
				pat.smooth = s.smoothing;
				p.shader = pat;
			}
		}
		return true;
	}
}

@:allow(helder.canvas.dom)
private class DrawState {
	public var fill = new Style();
	public var stroke = new Style();
	public var alpha = 1.0;
	public var composite = "source-over";
	public var blend:Null<Blender> = null;
	public var smoothing = true;
	public var smoothingQuality = "low";
	public var shadowBlur = 0.0;
	public var shadowColor = 0;
	public var shadowX = 0.0;
	public var shadowY = 0.0;
	public var filter = "none";
	public var line = lineStyle();

	static function lineStyle():Stroke {
		var s = new Stroke(1);
		s.dots = false;
		return s;
	}
	public var cap = "butt";
	public var join = "miter";
	public var dash:Array<Float> = [];
	public var dashOffset = 0.0;
	public var font:FontSpec = FontSpec.parse("10px sans-serif");
	public var align = "start";
	public var baseline = "alphabetic";
	public var direction = "inherit";
	public var letterSpacing = 0.0;
	public var letterSpacingText = "0px";
	public var wordSpacing = 0.0;
	public var wordSpacingText = "0px";
	public var kerning = "auto";
	public var stretch = "normal";
	public var variantCaps = "normal";
	public var textRendering = "auto";

	public function new() {}

	public function copy():DrawState {
		var d = new DrawState();
		d.fill = fill.copy();
		d.stroke = stroke.copy();
		d.alpha = alpha;
		d.composite = composite;
		d.blend = blend;
		d.smoothing = smoothing;
		d.smoothingQuality = smoothingQuality;
		d.shadowBlur = shadowBlur;
		d.shadowColor = shadowColor;
		d.shadowX = shadowX;
		d.shadowY = shadowY;
		d.filter = filter;
		d.line = new Stroke().copyFrom(line);
		d.cap = cap;
		d.join = join;
		d.dash = dash.copy();
		d.dashOffset = dashOffset;
		d.font = font;
		d.align = align;
		d.baseline = baseline;
		d.direction = direction;
		d.letterSpacing = letterSpacing;
		d.letterSpacingText = letterSpacingText;
		d.wordSpacing = wordSpacing;
		d.wordSpacingText = wordSpacingText;
		d.kerning = kerning;
		d.stretch = stretch;
		d.variantCaps = variantCaps;
		d.textRendering = textRendering;
		return d;
	}
}

// CSS's font shorthand as Canvas 2D reads it: style, variant, weight,
// stretch, the size (px, pt, em of 10px...), a line height (ignored), the
// families
@:allow(helder.canvas.dom)
private class FontSpec {
	public var size = 10.0;
	public var weight = 400;
	public var italic = false;
	public var smallCaps = false;
	public var families:Array<String> = [];
	public var serialized = "10px sans-serif";

	function new() {}

	public static function length(v:String, em:Float):Null<Float> {
		var t = StringTools.trim(v).toLowerCase();
		var names = ["px", "pt", "pc", "in", "cm", "mm", "rem", "em"], factors = [1.0, 4 / 3, 16, 96, 96 / 2.54, 96 / 25.4, 10, em];
		for (k in 0...names.length) {
			var name = names[k];
			if (StringTools.endsWith(t, name)) {
				var n = t.substr(0, t.length - name.length);
				var f = Std.parseFloat(n);
				if (Math.isNaN(f) || !~/^[-+]?[0-9]*\.?[0-9]+(e[-+]?[0-9]+)?$/.match(n)) return null;
				return f * factors[k];
			}
		}
		if (t == "0") return 0;
		return null;
	}

	public static function parse(v:String):Null<FontSpec> {
		var f = new FontSpec();
		var t = StringTools.trim(v);
		// (the families: after the size, up to the end)
		var re = ~/^((?:(?:normal|italic|oblique|small-caps|bold|bolder|lighter|[1-9]00|ultra-condensed|extra-condensed|condensed|semi-condensed|semi-expanded|expanded|extra-expanded|ultra-expanded)\s+)*)([-+]?[0-9]*\.?[0-9]+(?:px|pt|pc|in|cm|mm|em|rem|%))(?:\s*\/\s*[^\s]+)?\s+(.+)$/i;
		if (!re.match(t)) return null;
		var mods = StringTools.trim(re.matched(1)).toLowerCase(), sizeText = re.matched(2).toLowerCase(), fams = re.matched(3);
		for (m in mods.split(" ")) {
			if (m == "") continue;
			switch m {
				case "italic" | "oblique": f.italic = true;
				case "small-caps": f.smallCaps = true;
				case "bold" | "bolder": f.weight = 700;
				case "lighter": f.weight = 300;
				case "normal":
				case _:
					var n = Std.parseInt(m);
					if (n != null) f.weight = n;
			}
		}
		var size = StringTools.endsWith(sizeText, "%") ? Std.parseFloat(sizeText) / 100 * 10 : length(sizeText, 10);
		if (size == null || size < 0) return null;
		f.size = size;
		for (part in fams.split(",")) {
			var name = StringTools.trim(part);
			if (name.length >= 2 && (name.charAt(0) == '"' || name.charAt(0) == "'")) name = name.substr(1, name.length - 2);
			if (name != "") f.families.push(name);
		}
		if (f.families.length == 0) return null;
		// (as the browser serializes it: style, variant, weight, the size in px, the families)
		var parts = [];
		if (f.italic) parts.push("italic");
		if (f.smallCaps) parts.push("small-caps");
		if (f.weight != 400) parts.push(Std.string(f.weight));
		parts.push(fmt(f.size) + "px");
		parts.push([for (n in f.families) ~/[^a-zA-Z0-9-]/.match(n) ? '"$n"' : n].join(", "));
		f.serialized = parts.join(" ");
		return f;
	}

	static function fmt(x:Float):String
		return x == Math.ffloor(x) ? Std.string(Std.int(x)) : Std.string(x);
}

// A context's text: the font's faces, a layout kept and reset for each
// text, the glyphs' outlines
@:allow(helder.canvas.dom)
private class Text {
	static var shared:Null<Text> = null;

	public static function get():Text {
		if (shared == null) shared = new Text();
		return shared;
	}

	final sets = new Map<String, FontSet>();
	var current:Null<TextLayout> = null;
	public var lines(get, never):TextLayout;
	public var width = 0.0;
	public final glyphs = new helder.canvas.Glyphs();
	var set:Null<FontSet> = null;

	function new() {}

	inline function get_lines()
		return current;

	function fontSet(spec:FontSpec, kerning:String):FontSet {
		var key = spec.serialized + "|" + kerning;
		var fs = sets.get(key);
		if (fs != null) return fs;
		var face:Null<FontFile> = null;
		for (fam in spec.families) {
			face = FontLibrary.face(fam, spec.weight, spec.italic);
			if (face != null) break;
		}
		if (face == null) face = helder.text.SystemFonts.get().match(spec.families[0], spec.weight, spec.italic);
		if (face == null) throw new Path2D.DOMException("InvalidStateError", "no font for " + spec.serialized);
		var fallbacks = [for (f in FontLibrary.all()) if (f != face) f];
		if (fallbacks.length == 0) fallbacks = helder.text.SystemFonts.get().fallbacks();
		fs = new FontSet(face, fallbacks, spec.size);
		if (spec.italic && !face.italic) fs.oblique = true;
		if (kerning == "none") fs.features = helder.text.FontFeature.parse("'kern' 0");
		sets.set(key, fs);
		return fs;
	}

	public function layout(text:String, s:DrawState) {
		var fs = fontSet(s.font, s.kerning);
		set = fs;
		// (one line: newlines and tabs are spaces, as Canvas 2D's)
		var t = ~/[\t\n\r\x0C]/g.replace(text, " ");
		var base = s.direction == "rtl" ? 1 : 0;
		if (current == null) current = new TextLayout(t, fs, 1.0, Math.POSITIVE_INFINITY, null, 0, s.letterSpacing, s.wordSpacing, base, Math.NaN, 0)
		else current.reset(t, fs, 1.0, Math.POSITIVE_INFINITY, null, 0, s.letterSpacing, s.wordSpacing, base, Math.NaN, 0);
		width = 0;
		for (l in current.lines)
			if (l.advance > width) width = l.advance;
	}

	public function alignOffset(s:DrawState):Float {
		var rtl = s.direction == "rtl";
		return switch s.align {
			case "left": 0;
			case "right": -width;
			case "center": -width / 2;
			case "end": rtl ? 0 : -width;
			case _: rtl ? -width : 0;
		}
	}

	// the alphabetic baseline's offset below the point textBaseline names
	public function baselineOffset(s:DrawState):Float {
		var a = ascent(), d = descent();
		return switch s.baseline {
			case "top": a;
			case "hanging": a * 0.8;
			case "middle": (a - d) / 2;
			case "ideographic" | "bottom": -d;
			case _: 0;
		}
	}

	inline function ascent():Float
		return set.ascent;

	inline function descent():Float
		return set.descent;

	public function metrics(s:DrawState, m:TextMetrics) {
		var a = ascent(), d = descent(), oy = baselineOffset(s), ox = alignOffset(s);
		var l = current;
		var x0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		if (l.lines.length > 0) {
			var line = l.lines[0];
			for (i in line.glyphStart...line.glyphEnd) {
				if (l.glyphHidden(i)) continue;
				var face = l.glyphFont(i), k = l.glyphFontSet(i).scale(face);
				var b = face.bounds(l.glyphId(i));
				if (b == null || b.length < 4 || (b[2] <= b[0] && b[3] <= b[1])) continue;
				var gx = l.glyphX(i) + l.glyphOffsetX(i), gy = l.glyphOffsetY(i);
				x0 = Math.min(x0, gx + b[0] * k);
				x1 = Math.max(x1, gx + b[2] * k);
				y0 = Math.min(y0, gy - b[3] * k);
				y1 = Math.max(y1, gy - b[1] * k);
			}
		}
		if (x0 > x1) {
			x0 = x1 = 0;
			y0 = y1 = 0;
		}
		var em = s.font.size, ea = em * a / (a + d);
		m.set(width, -(x0 + ox), x1 + ox, -(y0 + oy), y1 + oy, a - oy, d + oy, ea - oy, em - ea + oy, a * 0.8 - oy, -oy, -d - oy);
	}
}
