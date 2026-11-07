package helder.text;

import haxe.ds.Vector;
import haxe.io.FPHelper;

// CoreGraphics' glyph pipeline, as macOS's CoreText draws a glyph, in
// helder's own engine (GlyphAtlas's): the outline at the device ppem, its
// origin moved by the pen's phase, then
//
// 1. font smoothing (FontSmoothing.On): the outline dilated by a radius
//    set by the ink's luminance and the ppem (radius); every line and every
//    x- and y-monotonic piece of a curve moved by the signs of its
//    direction, sides ±d, tops +2d, bottoms not at all, pieces joined by
//    straight bevels (dilate);
// 2. at whole ppem 7 to 18, CoreGraphics' y autohinter: every point's y
//    through a piecewise linear map snapping the x-height ('o') and cap
//    height ('X') to whole pixels (hint; TrueType faces);
// 3. curves flattened with CoreGraphics' tolerances (flatten);
// 4. coverage drawn as is (Rasterizer: exact area).
//
// A port of Rune's (github.com/anomalyco/rune, MIT: crates/rune/src/text/
// macos/smoothing.rs, flatten.rs, hint.rs and coretext_match.rs), which
// recovered it from CoreGraphics on macOS 15.3 (24D60); its constants are
// Rune's measurements, kept as written. Its masks land within 3 levels of
// 255 of CoreGraphics' (tests/text/coretext: Rune's captures of them).
// Coordinates are device pixels, y up, until the coverage. CoreGraphics
// mixes f32 and f64 arithmetic, and which it uses moves branch decisions,
// so the casts (f32) are kept where Rune has them; Rust's fused multiply-adds
// are plain products and sums here (an ulp's difference, rarely a level).
// Everything is kept for the next glyph: a glyph drawn allocates nothing
// once its buffers are large enough.
@:allow(helder.text)
class GlyphPipeline {
	// (path commands)
	static inline var MOVE = 0;
	static inline var LINE = 1;
	static inline var QUAD = 2;
	static inline var CUBIC = 3;
	static inline var CLOSE = 4;

	// the phases a pixel holds: sixtieths, every step CoreGraphics quantises pens to (fifths to wholes)
	public static inline var PHASES = 60;

	// how many x positions per device pixel CoreGraphics' subpixel
	// quantisation draws a glyph of ppem device pixels at: one more than the
	// whole number of times ppem goes into 33⅓, at most five. Fifths below
	// 8⅓ ppem, quarters to 11.1, thirds to 16.7, halves to 33.3, whole
	// pixels above, at every scale (Rune's measurement on macOS 15.3, ppem 3 to 80)
	public static function steps(ppem:Float):Int {
		if (!(ppem > 0)) return 5;
		var n = 1 + Math.floor(100 / 3 / ppem);
		return n > 5 ? 5 : n;
	}

	// (a pen x in device pixels at a ppem: floored to its step, as
	// CoreGraphics' quantisation does, a pen just short of a step on it:
	// CoreText on CI's Mac puts pens 1/2048 short (1x) and 1/1024 short (2x)
	// on their step, ones 1.5/1024 and 1/512 short not (the text-quality lane's
	// 'g' and 'o' of DejaVu Sans 11, 'H' of Inter 20), so the tolerance is fitted
	// between, 1.25/1024 px. Rune snaps its pens to Parley's 1/256, which
	// puts the last on its step too)
	static inline function quantised(x:Float, ppem:Float):Float {
		var s = steps(ppem);
		return Math.ffloor((x + 1.25 / 1024) * s) / s;
	}

	// the device pixel a glyph whose pen is at x starts from (pen and pixel
	// as CoreGraphics places them: see phase)
	public static function penPixel(x:Float, ppem:Float):Int {
		var q = quantised(x, ppem), f = Math.ffloor(q), s = steps(ppem);
		return Std.int(f) + (Math.fround((q - f) * s) >= s ? 1 : 0);
	}

	// the pen's phase right of that pixel in sixtieths (PHASES): a multiple of 60 / steps(ppem)
	public static function penPhase(x:Float, ppem:Float):Int {
		var q = quantised(x, ppem), f = Math.ffloor(q), s = steps(ppem);
		var p = Std.int(Math.fround((q - f) * s));
		return p >= s ? 0 : Std.int(p * (PHASES / s));
	}

	// the luminance bucket (0 to 4) of an sRGB colour (0xRRGGBB): Rec. 709
	// luminance of its linear values, to quarters (half away from zero);
	// alpha and the background play no part (Rune's measurement)
	public static function bucket(rgb:Int):Int {
		var y = 0.2126 * linear((rgb >> 16) & 255) + 0.7152 * linear((rgb >> 8) & 255) + 0.0722 * linear(rgb & 255);
		var q = Math.fround(y * 4);
		return q < 0 ? 0 : q > 4 ? 4 : Std.int(q);
	}

	static inline function linear(v:Int):Float {
		var c = v / 255;
		return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
	}

	// font smoothing's dilation radius for a bucket at ppem device pixels:
	// min(ppem · (0.0058 + 0.01 q), 0.3f), a radius, not the growth (Rune's;
	// the cap is the f32 literal 0.3 widened, and there is no ppem cutoff)
	public static function radius(ppem:Float, bucket:Int):Float {
		var q = (bucket > 4 ? 4 : bucket < 0 ? 0 : bucket) * 0.25;
		var r = (q * 0.010000000000000002 + 0.0058) * ppem;
		var cap = f32(0.3);
		return r < cap ? r : cap;
	}

	// (a Float rounded to f32's precision, as a cast to f32 is)
	static inline function f32(v:Float):Float
		return FPHelper.i32ToFloat(FPHelper.floatToI32(v));

	// --- the stages chosen (all of them by default: tests turn some off)

	public var dilation = true;
	public var flattening = true;
	public var hinting = true;

	public function new() {
		sink.p = this;
	}

	// (per face, its autohinter's metrics: null when it takes none)
	final metricsOf = new Map<Int, Null<HintMetrics>>();

	// the glyph's outline through the pipeline, rasterised into r (reset to
	// its bounds, coverage as is): ppem device pixels; phase: its origin's x
	// right of a pixel's edge (0 to 1); d: the dilation radius (0: none,
	// font smoothing off); skew: an oblique's slant (x moves by skew times
	// y, in font units; not hinted). Its bitmap's top left is left, top
	// pixels from the origin (y down); false: nothing to draw
	public var left(default, null) = 0;
	public var top(default, null) = 0;

	public function draw(font:FontFile, glyph:Int, ppem:Float, phase:Float, d:Float, skew:Float, r:Rasterizer):Bool
		return drawAt(font, glyph, ppem, phase, 0, d, skew, r);

	// (the same with a vertical phase too, py up: the autohinter only at 0, as CoreGraphics')
	public function drawAt(font:FontFile, glyph:Int, ppem:Float, px:Float, py:Float, d:Float, skew:Float, r:Rasterizer):Bool {
		src.clear();
		scale = ppem / font.unitsPerEm;
		slant = skew;
		dx = px;
		dy = py;
		font.outline(glyph, sink);
		if (src.nc == 0) return false;
		var m = hinting && skew == 0 && py == 0 && eligible(ppem) ? metrics(font) : null;
		return prepared(src, ppem, d, m, r);
	}

	// a path (device pixels, y up, its phase applied) through the stages: tests give CoreGraphics' own paths
	public function prepared(p:GlyphPath, ppem:Float, d:Float, m:Null<HintMetrics>, r:Rasterizer):Bool {
		var path = p;
		if (dilation && d > 0) {
			dilate(path, d, d, dilated);
			path = dilated;
		} else d = 0;
		if (m != null) {
			var t = m.transform(ppem, d);
			if (t != null) {
				var pt = path.pt;
				for (i in 0...path.np >> 1)
					pt[2 * i + 1] = t.apply(pt[2 * i + 1]);
			}
		}
		if (flattening) {
			flatten(path, flat);
			path = flat;
		}
		return rasterize(path, r);
	}

	// (the outline read into src: scaled to device pixels in f64, at the phase)
	final src = new GlyphPath();
	final dilated = new GlyphPath();
	final flat = new GlyphPath();
	final normal = new GlyphPath();
	var scale = 1.0;
	var slant = 0.0;
	var dx = 0.0;
	var dy = 0.0;

	final sink = new Sink();

	// (a path's coverage: its bounds the bitmap's, y flipped; curves left flattened by the rasterizer)
	function rasterize(p:GlyphPath, r:Rasterizer):Bool {
		var pt = p.pt, n = p.np >> 1;
		if (n == 0) return false;
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (i in 0...n) {
			var x = f32(pt[2 * i]), y = f32(pt[2 * i + 1]);
			pt[2 * i] = x;
			pt[2 * i + 1] = y;
			if (x < x0) x0 = x;
			if (x > x1) x1 = x;
			if (y < y0) y0 = y;
			if (y > y1) y1 = y;
		}
		var l = Math.floor(x0), rr = Math.ceil(x1), b = Math.floor(y0), t = Math.ceil(y1);
		var w = rr - l, h = t - b;
		if (w <= 0 || h <= 0) return false;
		left = l;
		top = -t;
		r.reset(w, h);
		r.scaleX = 1;
		r.scaleY = -1;
		r.offsetX = -l;
		r.offsetY = t;
		r.skew = 0;
		var cmd = p.cmd, k = 0;
		for (i in 0...p.nc)
			switch cmd[i] {
				case MOVE:
					r.moveTo(pt[k], pt[k + 1]);
					k += 2;
				case LINE:
					r.lineTo(pt[k], pt[k + 1]);
					k += 2;
				case QUAD:
					r.quadTo(pt[k], pt[k + 1], pt[k + 2], pt[k + 3]);
					k += 4;
				case CUBIC:
					r.cubicTo(pt[k], pt[k + 1], pt[k + 2], pt[k + 3], pt[k + 4], pt[k + 5]);
					k += 6;
				case _:
					r.close();
			}
		r.close();
		return true;
	}

	// --- the outline, read

	inline function sx(x:Float, y:Float):Float
		return (slant == 0 ? x : x + slant * y) * scale + dx;

	inline function sy(y:Float):Float
		return y * scale + dy;

	// --- 1. dilation

	// (the whole glyph turned to a positive signed area: every contour
	// reversed together, so holes keep winding against the outer ones)
	function normalize(p:GlyphPath, out:GlyphPath) {
		var cmd = p.cmd, pt = p.pt, k = 0;
		var area = 0.0, px = 0.0, py = 0.0, fx = 0.0, fy = 0.0;
		for (i in 0...p.nc)
			switch cmd[i] {
				case MOVE:
					px = fx = pt[k];
					py = fy = pt[k + 1];
					k += 2;
				case LINE:
					var x = pt[k], y = pt[k + 1];
					area += px * y - x * py;
					px = x;
					py = y;
					k += 2;
				case QUAD:
					var qx = pt[k], qy = pt[k + 1], x = pt[k + 2], y = pt[k + 3];
					area += curveArea(px, py, lerp(px, qx, 2 / 3), lerp(py, qy, 2 / 3), lerp(x, qx, 2 / 3), lerp(y, qy, 2 / 3), x, y);
					px = x;
					py = y;
					k += 4;
				case CUBIC:
					var x = pt[k + 4], y = pt[k + 5];
					area += curveArea(px, py, pt[k], pt[k + 1], pt[k + 2], pt[k + 3], x, y);
					px = x;
					py = y;
					k += 6;
				case _:
					area += px * fy - fx * py;
					px = fx;
					py = fy;
			}
		out.clear();
		if (area >= 0) {
			out.copy(p);
			return;
		}
		// (each contour's pieces from their starts, then out backwards)
		segs.clear();
		var k = 0, startX = 0.0, startY = 0.0, cx = 0.0, cy = 0.0;
		for (i in 0...p.nc)
			switch cmd[i] {
				case MOVE:
					flushReversed(p, out, cx, cy);
					startX = cx = pt[k];
					startY = cy = pt[k + 1];
					k += 2;
				case CLOSE:
					flushReversed(p, out, cx, cy);
					cx = startX;
					cy = startY;
				case c:
					segs.seg(cx, cy, c, k);
					var n = c == LINE ? 2 : c == QUAD ? 4 : 6;
					cx = pt[k + n - 2];
					cy = pt[k + n - 1];
					k += n;
			}
		flushReversed(p, out, cx, cy);
	}

	final segs = new Segments();

	function flushReversed(p:GlyphPath, out:GlyphPath, cx:Float, cy:Float) {
		if (segs.n == 0) return;
		out.move(cx, cy);
		var pt = p.pt, i = segs.n;
		while (i-- > 0) {
			var x = segs.x[i], y = segs.y[i], k = segs.at[i];
			switch segs.cmd[i] {
				case QUAD: out.quad(pt[k], pt[k + 1], x, y);
				case CUBIC: out.cubic(pt[k + 2], pt[k + 3], pt[k], pt[k + 1], x, y);
				case _: out.line(x, y);
			}
		}
		out.close();
		segs.clear();
	}

	// (signed area integral of a cubic, exact in its polynomial form)
	final ax = new Vector<Float>(4);
	final ay = new Vector<Float>(4);

	function curveArea(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float):Float {
		var ax = ax, ay = ay;
		ax[0] = x0;
		ax[1] = 3 * (x1 - x0);
		ax[2] = 3 * (x0 - 2 * x1 + x2);
		ax[3] = -x0 + 3 * x1 - 3 * x2 + x3;
		ay[0] = y0;
		ay[1] = 3 * (y1 - y0);
		ay[2] = 3 * (y0 - 2 * y1 + y2);
		ay[3] = -y0 + 3 * y1 - 3 * y2 + y3;
		var area = 0.0;
		for (i in 0...4)
			for (j in 1...4)
				area += (ax[i] * ay[j] - ay[i] * ax[j]) * j / (i + j);
		return area;
	}

	static inline function lerp(a:Float, b:Float, t:Float):Float
		return (b - a) * t + a;

	// (the dilator's state: the pen, the contour's start, f32 like CoreGraphics')
	var curX = 0.0;
	var curY = 0.0;
	var firstX = 0.0;
	var firstY = 0.0;
	var started = false;
	var rx = 0.0;
	var ry = 0.0;
	var dout:GlyphPath;

	// CoreGraphics' direction-sign dilation by radii x, y (y also gains +y):
	// quadratics become cubics, cubics split at their x then y extrema,
	// pieces joined by bevel lines
	public function dilate(p:GlyphPath, x:Float, y:Float, out:GlyphPath) {
		normalize(p, normal);
		out.clear();
		dout = out;
		rx = f32(x);
		ry = f32(y);
		started = false;
		curX = curY = firstX = firstY = 0;
		var q = normal, cmd = q.cmd, pt = q.pt, k = 0;
		for (i in 0...q.nc)
			switch cmd[i] {
				case MOVE:
					closeDilated();
					curX = firstX = f32(pt[k]);
					curY = firstY = f32(pt[k + 1]);
					k += 2;
				case LINE:
					emit(pt[k], pt[k + 1], false, 0, 0, 0, 0);
					k += 2;
				case QUAD:
					var qcx = f32(2 * pt[k] / 3), qcy = f32(2 * pt[k + 1] / 3);
					var ax = f32(f32(curX / 3) + qcx), ay = f32(f32(curY / 3) + qcy);
					var x2 = pt[k + 2], y2 = pt[k + 3];
					var bx = x2 / 3 + qcx, by = y2 / 3 + qcy;
					dilateCubic(curX, curY, ax, ay, bx, by, x2, y2);
					k += 4;
				case CUBIC:
					dilateCubic(curX, curY, pt[k], pt[k + 1], pt[k + 2], pt[k + 3], pt[k + 4], pt[k + 5]);
					k += 6;
				case _:
					closeDilated();
			}
		closeDilated();
	}

	static inline function sign(v:Float):Float
		return v > 0 ? 1 : v < 0 ? -1 : 0;

	// (one piece moved, from the pen to x, y, joined to the one before by a line)
	function emit(x:Float, y:Float, curve:Bool, ax:Float, ay:Float, bx:Float, by:Float) {
		var ddx = f32(x - curX), ddy = f32(y - curY);
		var sx = sign(ddy) * rx, sy = -sign(ddx) * ry, d = ry;
		var startX = f32(curX + sx), startY = f32(f32(curY + sy) + d);
		if (started) dout.line(startX, startY) else dout.move(startX, startY);
		started = true;
		if (curve) dout.cubic(sx + ax, sy + ay + d, sx + bx, sy + by + d, sx + x, sy + y + d) else dout.line(sx + x, sy + y + d);
		curX = f32(x);
		curY = f32(y);
	}

	function closeDilated() {
		if (started) {
			emit(firstX, firstY, false, 0, 0, 0, 0);
			dout.close();
			started = false;
		}
	}

	// (the cubic's x-monotonic parts, each split at its y extrema, each emitted)
	final partsX = new Vector<Float>(8 * 3);
	final partsY = new Vector<Float>(8 * 3);

	function dilateCubic(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float) {
		var n = monotonic(x0, y0, x1, y1, x2, y2, x3, y3, 0, partsX);
		for (i in 0...n) {
			var o = i * 8;
			var m = monotonic(partsX[o], partsX[o + 1], partsX[o + 2], partsX[o + 3], partsX[o + 4], partsX[o + 5], partsX[o + 6], partsX[o + 7], 1, partsY);
			for (j in 0...m) {
				var q = j * 8;
				emit(partsY[q + 6], partsY[q + 7], true, partsY[q + 2], partsY[q + 3], partsY[q + 4], partsY[q + 5]);
			}
		}
	}

	// (a cubic's parts between the roots of its derivative along axis (0: x, 1: y), into out, 8 floats each: how many)
	final roots = new Vector<Float>(2);

	function monotonic(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, axis:Int, out:Vector<Float>):Int {
		var n = findRoots(x0, y0, x1, y1, x2, y2, x3, y3, axis);
		var prev = 0.0, k = 0;
		var r0 = x0, r1 = y0, r2 = x1, r3 = y1, r4 = x2, r5 = y2, r6 = x3, r7 = y3;
		for (i in 0...n) {
			var t = roots[i], u = (t - prev) / (1 - prev);
			// (de Casteljau at u)
			var ax = lerp(r0, r2, u), ay = lerp(r1, r3, u);
			var bx = lerp(r2, r4, u), by = lerp(r3, r5, u);
			var cx = lerp(r4, r6, u), cy = lerp(r5, r7, u);
			var dx = lerp(ax, bx, u), dy = lerp(ay, by, u);
			var ex = lerp(bx, cx, u), ey = lerp(by, cy, u);
			var fx = lerp(dx, ex, u), fy = lerp(dy, ey, u);
			var o = k * 8;
			out[o] = r0;
			out[o + 1] = r1;
			out[o + 2] = ax;
			out[o + 3] = ay;
			out[o + 4] = dx;
			out[o + 5] = dy;
			out[o + 6] = fx;
			out[o + 7] = fy;
			k++;
			r0 = fx;
			r1 = fy;
			r2 = ex;
			r3 = ey;
			r4 = cx;
			r5 = cy;
			prev = t;
		}
		var o = k * 8;
		out[o] = r0;
		out[o + 1] = r1;
		out[o + 2] = r2;
		out[o + 3] = r3;
		out[o + 4] = r4;
		out[o + 5] = r5;
		out[o + 6] = r6;
		out[o + 7] = r7;
		return k + 1;
	}

	// (the derivative's roots along axis inside 1e-10 to 0.9999999999, in
	// order: CoreGraphics' second root divides the y delta p1.y - p0.y for
	// both axes, a quirk the x stage inherits)
	function findRoots(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, axis:Int):Int {
		var p0 = axis == 0 ? x0 : y0, p1 = axis == 0 ? x1 : y1, p2 = axis == 0 ? x2 : y2, p3 = axis == 0 ? x3 : y3;
		var a = (p1 - p2) * 3 + (p3 - p0);
		var b = p1 * -2 + (p0 + p2);
		var disc = (p0 - p1) * p3 + (p2 * (p2 - p0) + (p1 - p2) * p1);
		if (disc < 0) return 0;
		var n = 0, t0 = 0.0, t1 = 0.0;
		if (a == 0) {
			if (b != 0) {
				t0 = (p0 - p1) * 0.5 / b;
				n = 1;
			}
		} else if (!(b == 0 && disc == 0)) {
			var q = -((b < 0 ? -1 : 1) * Math.sqrt(disc) + b);
			t0 = q / a;
			t1 = (y1 - y0) / q;
			n = 2;
		}
		var k = 0;
		inline function keep(t:Float)
			return Math.isFinite(t) && t >= 1e-10 && t <= 0.9999999999;
		if (n >= 1 && keep(t0)) roots[k++] = t0;
		if (n == 2 && keep(t1)) roots[k++] = t1;
		if (k == 2) {
			if (roots[1] < roots[0]) {
				var t = roots[0];
				roots[0] = roots[1];
				roots[1] = t;
			}
			if (Math.abs(roots[1] - roots[0]) < 1e-12) k = 1;
		}
		return k;
	}

	// --- 2. the autohinter

	// integer ppem 7 to 18
	public static function eligible(ppem:Float):Bool
		return ppem >= 7 && ppem <= 18 && ppem == Math.ffloor(ppem);

	// (a face's metrics, once: TrueType faces' alone)
	function metrics(font:FontFile):Null<HintMetrics> {
		if (metricsOf.exists(font.id)) return metricsOf.get(font.id);
		var m = HintMetrics.of(font);
		metricsOf.set(font.id, m);
		return m;
	}

	// the transform for radius d at ppem, or null when the size or the metrics do not take it
	public static function autohint(m:HintMetrics, ppem:Float, d:Float):Null<HintTransform> {
		if (!eligible(ppem) || m.xHeight == m.capHeight) return null;
		var scale = ppem / m.upem;
		// (targets chosen at a reference radius that does not depend on the ink)
		var reference = Math.min(ppem * 0.015125, 0.3);
		inline function r(v:Float)
			return trunc(v + 0.5);
		var xt = r(m.xHeight * scale + 2 * reference), ct = r(m.capHeight * scale + 2 * reference);
		var plainX = r(m.xHeight * scale), plainCap = r(m.capHeight * scale);
		if (plainX != xt) {
			function cost(x:Float, c:Float):Float {
				var s = 0.0;
				for (dd in [reference, 0.0]) {
					var t = eval(m, scale, dd, x, c);
					s += Math.abs(t.values[8] - 1) + Math.abs(t.values[9] - 1);
				}
				return s;
			}
			if (cost(xt, ct) > cost(plainX, plainCap)) {
				xt = plainX;
				ct = plainCap;
			}
		}
		var t = eval(m, scale, d, xt, ct);
		return m.xHeight / m.capHeight > 0.85 && t.values[9] < 0.33 ? null : t;
	}

	static inline function trunc(v:Float):Float
		return v < 0 ? Math.fceil(v) : Math.ffloor(v);

	static function eval(m:HintMetrics, scale:Float, d:Float, xTarget:Float, capTarget:Float):HintTransform {
		var stem = Math.min(Math.min(m.stemHeight == 0 ? m.capHeight : m.stemHeight, m.xHeight * 0.333), (m.capHeight - m.xHeight) * 0.5) * scale;
		var lo = stem + d;
		var x = m.xHeight * scale + d;
		var xt = xTarget - d;
		var cap = m.capHeight * scale + d;
		var ct = capTarget - d;
		var middle = m.capHeight * scale - stem - d;
		var mt = -2 * d + (ct - stem);
		var top = m.maxY * scale + d;
		inline function slope(a:Float, b:Float)
			return b == 0 ? 0.0 : a / b;
		var s1 = slope(xt - lo, x - lo);
		var s2 = slope(mt - xt, middle - x);
		var s3 = slope(top - ct, top - cap);
		// (a cap height that would squash the middle band is not snapped)
		if (s2 < 0.75 || s2 - s1 > 0.3) {
			ct = cap;
			mt = -2 * d + (cap - stem);
			s2 = slope(mt - xt, middle - x);
			s3 = 1;
		}
		return new HintTransform([-d, lo, x, xt, middle, mt, cap, ct, s1, s2, s3]);
	}

	// --- 3. flattening

	// (CoreGraphics' aa_create's tolerances: coordinates cast to f32, curves
	// halved in f64 until their squared second differences are within them
	// on both axes, each piece's end a line)
	static inline var QUAD_FLATNESS = 0.6400000000000001;
	static inline var CUBIC_FLATNESS = 0.07111111111111111;
	static inline var MAX_DEPTH = 22;

	var fout:GlyphPath;

	public function flatten(p:GlyphPath, out:GlyphPath) {
		out.clear();
		fout = out;
		var cmd = p.cmd, pt = p.pt, k = 0;
		var cx = 0.0, cy = 0.0, fx = 0.0, fy = 0.0;
		for (i in 0...p.nc)
			switch cmd[i] {
				case MOVE:
					cx = fx = f32(pt[k]);
					cy = fy = f32(pt[k + 1]);
					out.move(cx, cy);
					k += 2;
				case LINE:
					cx = f32(pt[k]);
					cy = f32(pt[k + 1]);
					out.line(cx, cy);
					k += 2;
				case QUAD:
					var x = f32(pt[k + 2]), y = f32(pt[k + 3]);
					quad(cx, cy, f32(pt[k]), f32(pt[k + 1]), x, y, 0);
					cx = x;
					cy = y;
					k += 4;
				case CUBIC:
					var x = f32(pt[k + 4]), y = f32(pt[k + 5]);
					cubic(cx, cy, f32(pt[k]), f32(pt[k + 1]), f32(pt[k + 2]), f32(pt[k + 3]), x, y, 0);
					cx = x;
					cy = y;
					k += 6;
				case _:
					out.close();
					cx = fx;
					cy = fy;
			}
	}

	function cubic(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, depth:Int) {
		var ax = (x0 + x2) - 2 * x1, bx = (x1 + x3) - 2 * x2;
		var ay = (y0 + y2) - 2 * y1, by = (y1 + y3) - 2 * y2;
		if (depth > MAX_DEPTH
			|| ax * ax <= CUBIC_FLATNESS && bx * bx <= CUBIC_FLATNESS && ay * ay <= CUBIC_FLATNESS && by * by <= CUBIC_FLATNESS) {
			fout.line(x3, y3);
			return;
		}
		var abx = lerp(x0, x1, 0.5), aby = lerp(y0, y1, 0.5);
		var bcx = lerp(x1, x2, 0.5), bcy = lerp(y1, y2, 0.5);
		var cdx = lerp(x2, x3, 0.5), cdy = lerp(y2, y3, 0.5);
		var ex = lerp(abx, bcx, 0.5), ey = lerp(aby, bcy, 0.5);
		var gx = lerp(bcx, cdx, 0.5), gy = lerp(bcy, cdy, 0.5);
		var mx = lerp(ex, gx, 0.5), my = lerp(ey, gy, 0.5);
		cubic(x0, y0, abx, aby, ex, ey, mx, my, depth + 1);
		cubic(mx, my, gx, gy, cdx, cdy, x3, y3, depth + 1);
	}

	function quad(x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, depth:Int) {
		var ax = x0 + x2 - 2 * x1, ay = y0 + y2 - 2 * y1;
		if (depth > MAX_DEPTH || ax * ax <= QUAD_FLATNESS && ay * ay <= QUAD_FLATNESS) {
			fout.line(x2, y2);
			return;
		}
		var abx = lerp(x0, x1, 0.5), aby = lerp(y0, y1, 0.5);
		var bcx = lerp(x1, x2, 0.5), bcy = lerp(y1, y2, 0.5);
		var mx = lerp(abx, bcx, 0.5), my = lerp(aby, bcy, 0.5);
		quad(x0, y0, abx, aby, mx, my, depth + 1);
		quad(mx, my, bcx, bcy, x2, y2, depth + 1);
	}
}

// A path's commands and points, kept and grown (y up, device pixels)
@:allow(helder.text) class GlyphPath {
	public var cmd = new Vector<Int>(64);
	public var pt = new Vector<Float>(256);
	public var nc = 0;
	public var np = 0;

	public function new() {}

	public inline function clear() {
		nc = 0;
		np = 0;
	}

	function room(c:Int, p:Int) {
		if (nc + c > cmd.length) {
			var v = new Vector<Int>((nc + c) * 2);
			Vector.blit(cmd, 0, v, 0, nc);
			cmd = v;
		}
		if (np + p > pt.length) {
			var v = new Vector<Float>((np + p) * 2);
			Vector.blit(pt, 0, v, 0, np);
			pt = v;
		}
	}

	public function move(x:Float, y:Float) {
		room(1, 2);
		cmd[nc++] = 0;
		pt[np++] = x;
		pt[np++] = y;
	}

	public function line(x:Float, y:Float) {
		room(1, 2);
		cmd[nc++] = 1;
		pt[np++] = x;
		pt[np++] = y;
	}

	public function quad(cx:Float, cy:Float, x:Float, y:Float) {
		room(1, 4);
		cmd[nc++] = 2;
		pt[np++] = cx;
		pt[np++] = cy;
		pt[np++] = x;
		pt[np++] = y;
	}

	public function cubic(ax:Float, ay:Float, bx:Float, by:Float, x:Float, y:Float) {
		room(1, 6);
		cmd[nc++] = 3;
		pt[np++] = ax;
		pt[np++] = ay;
		pt[np++] = bx;
		pt[np++] = by;
		pt[np++] = x;
		pt[np++] = y;
	}

	public function close() {
		room(1, 0);
		cmd[nc++] = 4;
	}

	public function copy(o:GlyphPath) {
		clear();
		room(o.nc, o.np);
		Vector.blit(o.cmd, 0, cmd, 0, o.nc);
		Vector.blit(o.pt, 0, pt, 0, o.np);
		nc = o.nc;
		np = o.np;
	}
}

// (FontFile's outline into the pipeline's path: scaled, slanted and moved
// by the phase; a contour's last line back to its start left to its close,
// as swash's outlines have it, which the dilation's bevels depend on)
private class Sink implements Outline {
	public var p:Null<GlyphPipeline> = null;
	var startX = 0.0;
	var startY = 0.0;

	public function new() {}

	public function moveTo(x:Float, y:Float) {
		var g = owner;
		startX = g.sx(x, y);
		startY = g.sy(y);
		g.src.move(startX, startY);
	}

	public function lineTo(x:Float, y:Float) {
		var g = owner;
		g.src.line(g.sx(x, y), g.sy(y));
	}

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		var g = owner;
		g.src.quad(g.sx(cx, cy), g.sy(cy), g.sx(x, y), g.sy(y));
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		var g = owner;
		g.src.cubic(g.sx(c1x, c1y), g.sy(c1y), g.sx(c2x, c2y), g.sy(c2y), g.sx(x, y), g.sy(y));
	}

	public function close() {
		var s = owner.src;
		if (s.nc > 0 && s.cmd[s.nc - 1] == 1 && s.pt[s.np - 2] == startX && s.pt[s.np - 1] == startY) {
			s.nc--;
			s.np -= 2;
		}
		s.close();
	}

	var owner(get, never):GlyphPipeline;

	inline function get_owner():GlyphPipeline
		return p;
}

// (each contour's pieces while it is reversed: where each starts, its command, its points' offset)
private class Segments {
	public var x = new Vector<Float>(64);
	public var y = new Vector<Float>(64);
	public var cmd = new Vector<Int>(64);
	public var at = new Vector<Int>(64);
	public var n = 0;

	public function new() {}

	public inline function clear()
		n = 0;

	public function seg(sx:Float, sy:Float, c:Int, k:Int) {
		if (n == x.length) {
			var m = n * 2;
			var nx = new Vector<Float>(m), ny = new Vector<Float>(m), nc = new Vector<Int>(m), na = new Vector<Int>(m);
			Vector.blit(x, 0, nx, 0, n);
			Vector.blit(y, 0, ny, 0, n);
			Vector.blit(cmd, 0, nc, 0, n);
			Vector.blit(at, 0, na, 0, n);
			x = nx;
			y = ny;
			cmd = nc;
			at = na;
		}
		x[n] = sx;
		y[n] = sy;
		cmd[n] = c;
		at[n] = k;
		n++;
	}
}

// A face's metrics for the autohinter, in font units: xHeight and
// capHeight the tops of 'o' and 'X' (their points', not OS/2's fields),
// maxY the head table's yMax, stemHeight the stemH CoreGraphics' font
// descriptor reports (0 for most TrueType faces)
class HintMetrics {
	public final upem:Float;
	public final xHeight:Float;
	public final capHeight:Float;
	public final maxY:Float;
	public final stemHeight:Float;

	// (the transforms asked for, by ppem and radius: NONE where there is none)
	final transforms = new IntTable<HintTransform>();
	static final NONE = new HintTransform([]);

	// GlyphPipeline.autohint's, kept
	public function transform(ppem:Float, d:Float):Null<HintTransform> {
		var key = Std.int(ppem) * 100000 + Std.int(Math.fround(d * 10000));
		var t = transforms.get(key, null);
		if (t == null) {
			t = GlyphPipeline.autohint(this, ppem, d);
			if (t == null) t = NONE;
			transforms.set(key, t);
		}
		return t == NONE ? null : t;
	}

	public function new(upem, xHeight, capHeight, maxY, stemHeight) {
		this.upem = upem;
		this.xHeight = xHeight;
		this.capHeight = capHeight;
		this.maxY = maxY;
		this.stemHeight = stemHeight;
	}

	// a TrueType (glyf) face's; null for others (CFF faces are not hinted),
	// and for a face without TrueType instructions (no fpgm, prep or cvt:
	// CoreGraphics on CI's Mac hints none of the text-quality lane's subsets,
	// cut with fontTools' --no-hinting, while it hints the whole fonts:
	// tests/text/TextQuality.hx)
	public static function of(font:FontFile):Null<HintMetrics> {
		if (!font.trueType || !(font.hasTable("fpgm") || font.hasTable("prep") || font.hasTable("cvt "))) return null;
		var o = font.glyph("o".code), x = font.glyph("X".code);
		if (o == 0 || x == 0) return null;
		var xh = Top.of(font, o), cap = Top.of(font, x);
		if (!Math.isFinite(xh) || !Math.isFinite(cap)) return null;
		return new HintMetrics(font.unitsPerEm, xh, cap, font.yMax, stem(font.postScriptName));
	}

	// (the stemH macOS 15.3 reports for the faces Rune measured, in no table
	// a parser reads: SF Pro at every weight and optical size, and
	// Helvetica; every other TrueType face 0)
	static function stem(name:String):Float
		return StringTools.startsWith(name, ".SFNS") ? 79 : name == "Helvetica" ? 85 : 0;
}

// (a glyph's highest point, control points too)
private class Top implements Outline {
	var y = Math.NEGATIVE_INFINITY;

	function new() {}

	public static function of(font:FontFile, g:Int):Float {
		var t = new Top();
		font.outline(g, t);
		return t.y;
	}

	inline function see(v:Float)
		if (v > y) y = v;

	public function moveTo(x:Float, y:Float)
		see(y);

	public function lineTo(x:Float, y:Float)
		see(y);

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		see(cy);
		see(y);
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		see(c1y);
		see(c2y);
		see(y);
	}

	public function close() {}
}

// The autohinter's piecewise linear map of y: [-d, a, b, B, c, C, e, E, l, m, u] in Rune's names
class HintTransform {
	public final values:Array<Float>;

	public function new(values)
		this.values = values;

	public function apply(y:Float):Float {
		var v = values;
		return if (y < v[1]) y else if (y <= v[2]) (y - v[1]) * v[8] + v[1] else if (y <= v[4]) (y - v[2]) * v[9] + v[3] else if (y <= v[6]) y + (v[5] - v[4]) else
			(y - v[6]) * v[10] + v[7];
	}
}
