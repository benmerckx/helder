package helder.canvas;

import haxe.ds.Vector;
import helder.canvas.Paint.Shader;

// A gradient's colour stops and how a pixel finds its place along them:
// LinearGradient, RadialGradient (two circles, as Canvas 2D's), and
// ConicGradient, each a class of its own. Stops are interpolated in
// straight sRGB and premultiplied after (as Chromium's canvas gradients),
// padded past the ends; two at one offset make a hard edge. `matrix`
// places the gradient's space in the drawing's (identity: the user units
// at the time of the draw, as Canvas 2D's).
abstract class Gradient implements Shader {
	public final matrix = new Matrix();
	// past the ends: PAD (the end colours, Canvas 2D's), REFLECT, REPEAT (SVG's spreadMethod)
	public var spread = PAD;

	public static inline var PAD = 0;
	public static inline var REFLECT = 1;
	public static inline var REPEAT = 2;

	var offsets:Array<Float> = [];
	var reds:Array<Float> = [];
	var greens:Array<Float> = [];
	var blues:Array<Float> = [];
	var alphas:Array<Float> = [];
	// device to gradient space for the draw
	final local = new Matrix();
	final inv = new Matrix();

	function new() {}

	// a stop at offset (0 to 1), its colour 0xAARRGGBB; stops are kept in
	// offset order, one at an offset already there after it
	public function addStop(offset:Float, color:Int):Gradient {
		var i = offsets.length;
		while (i > 0 && offsets[i - 1] > offset)
			i--;
		offsets.insert(i, offset);
		reds.insert(i, ((color >> 16) & 255) / 255);
		greens.insert(i, ((color >> 8) & 255) / 255);
		blues.insert(i, (color & 255) / 255);
		alphas.insert(i, ((color >>> 24) & 255) / 255);
		return this;
	}

	public var stopCount(get, never):Int;

	inline function get_stopCount()
		return offsets.length;

	public inline function stopOffset(i:Int):Float
		return offsets[i];

	// (0xAARRGGBB, straight)
	public function stopColor(i:Int):Int
		return (Std.int(alphas[i] * 255 + 0.5) << 24) | (Std.int(reds[i] * 255 + 0.5) << 16) | (Std.int(greens[i] * 255 + 0.5) << 8)
			| Std.int(blues[i] * 255 + 0.5);

	public function clearStops() {
		offsets.resize(0);
		reds.resize(0);
		greens.resize(0);
		blues.resize(0);
		alphas.resize(0);
	}

	public function begin(inverse:Matrix):Bool {
		if (offsets.length == 0) return false;
		if (!matrix.invertInto(inv)) return false;
		local.copyFrom(inv).multiply(inverse);
		return prepare();
	}

	// (each kind's own set-up; false: nothing painted)
	function prepare():Bool
		return true;

	// the colour at t into out at o, premultiplied
	inline function colorAt(t:Float, out:Vector<Float>, o:Int) {
		var n = offsets.length;
		if (spread != PAD) {
			if (spread == REFLECT) {
				t = t % 2;
				if (t < 0) t += 2;
				if (t > 1) t = 2 - t;
			} else {
				t = t % 1;
				if (t < 0) t += 1;
			}
		}
		var r, g, b, a;
		if (!(t > offsets[0])) {
			r = reds[0];
			g = greens[0];
			b = blues[0];
			a = alphas[0];
		} else if (t >= offsets[n - 1]) {
			r = reds[n - 1];
			g = greens[n - 1];
			b = blues[n - 1];
			a = alphas[n - 1];
		} else {
			var i = 1;
			while (offsets[i] <= t)
				i++;
			var o0 = offsets[i - 1], f = (t - o0) / (offsets[i] - o0);
			r = reds[i - 1] + (reds[i] - reds[i - 1]) * f;
			g = greens[i - 1] + (greens[i] - greens[i - 1]) * f;
			b = blues[i - 1] + (blues[i] - blues[i - 1]) * f;
			a = alphas[i - 1] + (alphas[i] - alphas[i - 1]) * f;
		}
		out[o] = r * a;
		out[o + 1] = g * a;
		out[o + 2] = b * a;
		out[o + 3] = a;
	}

	// its colours at n offsets from 0 to 1, premultiplied RGBA8 into out at
	// offset (a table: the GPU's, its spread applied when it is read)
	public function table(out:haxe.io.Bytes, offset:Int, n:Int) {
		var c = new Vector<Float>(4), saved = spread;
		spread = PAD;
		for (i in 0...n) {
			colorAt(i / (n - 1), c, 0);
			for (k in 0...4)
				out.set(offset + i * 4 + k, Std.int(Math.max(0, Math.min(255, Math.round(c[k] * 255)))));
		}
		spread = saved;
	}

	inline function none(out:Vector<Float>, o:Int) {
		out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0;
	}

	public function shade(x:Int, y:Int, n:Int, out:Vector<Float>) {}
}

// Along the line from (x0, y0) to (x1, y1): 0 at the start, 1 at its end,
// constant across it
final class LinearGradient extends Gradient {
	public var x0:Float;
	public var y0:Float;
	public var x1:Float;
	public var y1:Float;

	var dx = 0.0;
	var dy = 0.0;

	public function new(x0:Float, y0:Float, x1:Float, y1:Float) {
		super();
		this.x0 = x0;
		this.y0 = y0;
		this.x1 = x1;
		this.y1 = y1;
	}

	override function prepare():Bool {
		var lx = x1 - x0, ly = y1 - y0, l2 = lx * lx + ly * ly;
		if (l2 == 0 || !Math.isFinite(l2)) return false;
		dx = lx / l2;
		dy = ly / l2;
		return true;
	}

	override public function shade(x:Int, y:Int, n:Int, out:Vector<Float>) {
		var m = local, cy = y + 0.5;
		for (i in 0...n) {
			var cx = x + i + 0.5;
			var u = m.a * cx + m.c * cy + m.e, v = m.b * cx + m.d * cy + m.f;
			colorAt((u - x0) * dx + (v - y0) * dy, out, i * 4);
		}
	}
}

// Between two circles, as Canvas 2D's createRadialGradient: t at a point
// is the largest for which the circle interpolated between them (its
// radius not negative) passes through it; none: transparent
final class RadialGradient extends Gradient {
	public var x0:Float;
	public var y0:Float;
	public var r0:Float;
	public var x1:Float;
	public var y1:Float;
	public var r1:Float;

	var cdx = 0.0;
	var cdy = 0.0;
	var dr = 0.0;
	var qa = 0.0;

	public function new(x0:Float, y0:Float, r0:Float, x1:Float, y1:Float, r1:Float) {
		super();
		this.x0 = x0;
		this.y0 = y0;
		this.r0 = r0;
		this.x1 = x1;
		this.y1 = y1;
		this.r1 = r1;
	}

	override function prepare():Bool {
		cdx = x1 - x0;
		cdy = y1 - y0;
		dr = r1 - r0;
		qa = cdx * cdx + cdy * cdy - dr * dr;
		return !(cdx == 0 && cdy == 0 && dr == 0);
	}

	override public function shade(x:Int, y:Int, n:Int, out:Vector<Float>) {
		var m = local, cy = y + 0.5;
		for (i in 0...n) {
			var cx = x + i + 0.5, o = i * 4;
			var px = m.a * cx + m.c * cy + m.e - x0, py = m.b * cx + m.d * cy + m.f - y0;
			var b = px * cdx + py * cdy + r0 * dr, c = px * px + py * py - r0 * r0;
			var t = Math.NaN;
			if (Math.abs(qa) < 1e-12) {
				if (b != 0) {
					var s = c / (2 * b);
					if (r0 + s * dr >= 0) t = s;
				}
			} else {
				var disc = b * b - qa * c;
				if (disc >= 0) {
					var sq = Math.sqrt(disc);
					var s1 = (b + sq) / qa, s2 = (b - sq) / qa;
					var hi = s1 > s2 ? s1 : s2, lo = s1 > s2 ? s2 : s1;
					if (r0 + hi * dr >= 0) t = hi else if (r0 + lo * dr >= 0) t = lo;
				}
			}
			if (Math.isNaN(t)) none(out, o) else colorAt(t, out, o);
		}
	}
}

// Around (x, y) from the angle start (radians, clockwise in y-down
// units): 0 there, 1 a turn later
final class ConicGradient extends Gradient {
	public var start:Float;
	public var x:Float;
	public var y:Float;

	public function new(start:Float, x:Float, y:Float) {
		super();
		this.start = start;
		this.x = x;
		this.y = y;
	}

	override public function shade(px:Int, py:Int, n:Int, out:Vector<Float>) {
		var m = local, cy = py + 0.5, tau = 2 * Math.PI;
		for (i in 0...n) {
			var cx = px + i + 0.5;
			var u = m.a * cx + m.c * cy + m.e - x, v = m.b * cx + m.d * cy + m.f - y;
			var t = (Math.atan2(v, u) - start) / tau;
			t -= Math.floor(t);
			colorAt(t, out, i * 4);
		}
	}
}
