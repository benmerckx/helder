package helder.canvas;

import helder.canvas.Paint.Rgba;

// How a drawn pixel (premultiplied, its coverage already in) combines
// with the one under it: d = op(s, d). Porter-Duff's operators share one
// class (two factors), each separable blend mode is a class of its own,
// the four non-separable ones share their helpers: an executable keeps the
// modes it names (Blend.multiply...), source-over (null) none.
// `unbounded`: the operator changes what it does not cover (copy,
// source-in...), so the canvas applies it to the whole clip, as Chromium
// does for Canvas 2D.
interface Blender {
	var unbounded(get, never):Bool;
	// which it is, for a back end that blends elsewhere (the GPU's shader):
	// -1 - (fa * 4 + fb) for Porter-Duff's, 0 to 10 the separable modes in
	// Blend's order, 11 to 14 hue, saturation, color, luminosity
	var code(get, never):Int;
	function blend(s:Rgba, d:Rgba):Void;
}

class Blend {
	// Porter-Duff
	public static var clear(get, never):Blender;
	public static var copy(get, never):Blender;
	public static var destination(get, never):Blender;
	public static var sourceOver(get, never):Blender;
	public static var destinationOver(get, never):Blender;
	public static var sourceIn(get, never):Blender;
	public static var destinationIn(get, never):Blender;
	public static var sourceOut(get, never):Blender;
	public static var destinationOut(get, never):Blender;
	public static var sourceAtop(get, never):Blender;
	public static var destinationAtop(get, never):Blender;
	public static var xor(get, never):Blender;
	public static var lighter(get, never):Blender;
	// separable
	public static var multiply(get, never):Blender;
	public static var screen(get, never):Blender;
	public static var overlay(get, never):Blender;
	public static var darken(get, never):Blender;
	public static var lighten(get, never):Blender;
	public static var colorDodge(get, never):Blender;
	public static var colorBurn(get, never):Blender;
	public static var hardLight(get, never):Blender;
	public static var softLight(get, never):Blender;
	public static var difference(get, never):Blender;
	public static var exclusion(get, never):Blender;
	// non-separable
	public static var hue(get, never):Blender;
	public static var saturation(get, never):Blender;
	public static var color(get, never):Blender;
	public static var luminosity(get, never):Blender;

	static inline function get_clear():Blender
		return PorterDuff.clear;

	static inline function get_copy():Blender
		return PorterDuff.copy;

	static inline function get_destination():Blender
		return PorterDuff.destination;

	static inline function get_sourceOver():Blender
		return PorterDuff.sourceOver;

	static inline function get_destinationOver():Blender
		return PorterDuff.destinationOver;

	static inline function get_sourceIn():Blender
		return PorterDuff.sourceIn;

	static inline function get_destinationIn():Blender
		return PorterDuff.destinationIn;

	static inline function get_sourceOut():Blender
		return PorterDuff.sourceOut;

	static inline function get_destinationOut():Blender
		return PorterDuff.destinationOut;

	static inline function get_sourceAtop():Blender
		return PorterDuff.sourceAtop;

	static inline function get_destinationAtop():Blender
		return PorterDuff.destinationAtop;

	static inline function get_xor():Blender
		return PorterDuff.xor;

	static inline function get_lighter():Blender
		return PorterDuff.lighter;

	static inline function get_multiply():Blender
		return Multiply.instance;

	static inline function get_screen():Blender
		return Screen.instance;

	static inline function get_overlay():Blender
		return Overlay.instance;

	static inline function get_darken():Blender
		return Darken.instance;

	static inline function get_lighten():Blender
		return Lighten.instance;

	static inline function get_colorDodge():Blender
		return ColorDodge.instance;

	static inline function get_colorBurn():Blender
		return ColorBurn.instance;

	static inline function get_hardLight():Blender
		return HardLight.instance;

	static inline function get_softLight():Blender
		return SoftLight.instance;

	static inline function get_difference():Blender
		return Difference.instance;

	static inline function get_exclusion():Blender
		return Exclusion.instance;

	static inline function get_hue():Blender
		return NonSeparable.hue;

	static inline function get_saturation():Blender
		return NonSeparable.saturation;

	static inline function get_color():Blender
		return NonSeparable.color;

	static inline function get_luminosity():Blender
		return NonSeparable.luminosity;
}

// d = s Fa + d Fb, each factor 0, 1, the other's alpha or one minus it
final class PorterDuff implements Blender {
	// (lazily made: a mode's object only when it is asked for)
	public static var clear(get, never):PorterDuff;
	public static var copy(get, never):PorterDuff;
	public static var destination(get, never):PorterDuff;
	public static var sourceOver(get, never):PorterDuff;
	public static var destinationOver(get, never):PorterDuff;
	public static var sourceIn(get, never):PorterDuff;
	public static var destinationIn(get, never):PorterDuff;
	public static var sourceOut(get, never):PorterDuff;
	public static var destinationOut(get, never):PorterDuff;
	public static var sourceAtop(get, never):PorterDuff;
	public static var destinationAtop(get, never):PorterDuff;
	public static var xor(get, never):PorterDuff;
	public static var lighter(get, never):PorterDuff;

	static inline function get_clear()
		return of(ZERO, ZERO);

	static inline function get_copy()
		return of(ONE, ZERO);

	static inline function get_destination()
		return of(ZERO, ONE);

	static inline function get_sourceOver()
		return of(ONE, INV);

	static inline function get_destinationOver()
		return of(INV, ONE);

	static inline function get_sourceIn()
		return of(ALPHA, ZERO);

	static inline function get_destinationIn()
		return of(ZERO, ALPHA);

	static inline function get_sourceOut()
		return of(INV, ZERO);

	static inline function get_destinationOut()
		return of(ZERO, INV);

	static inline function get_sourceAtop()
		return of(ALPHA, INV);

	static inline function get_destinationAtop()
		return of(INV, ALPHA);

	static inline function get_xor()
		return of(INV, INV);

	static inline function get_lighter()
		return of(ONE, ONE);

	static inline var ZERO = 0;
	static inline var ONE = 1;
	// the other's alpha, one minus it
	static inline var ALPHA = 2;
	static inline var INV = 3;

	static final made:Array<PorterDuff> = [];

	static function of(fa:Int, fb:Int):PorterDuff {
		var k = fa * 4 + fb;
		if (made[k] == null) made[k] = new PorterDuff(fa, fb);
		return made[k];
	}

	final fa:Int;
	final fb:Int;

	public var unbounded(get, never):Bool;

	inline function get_unbounded()
		return fb == ZERO || fb == ALPHA;

	public var code(get, never):Int;

	inline function get_code()
		return -1 - (fa * 4 + fb);

	function new(fa, fb) {
		this.fa = fa;
		this.fb = fb;
	}

	static inline function factor(f:Int, other:Float):Float
		return f == ZERO ? 0 : f == ONE ? 1 : f == ALPHA ? other : 1 - other;

	public function blend(s:Rgba, d:Rgba) {
		var ka = factor(fa, d.a), kb = factor(fb, s.a);
		d.r = s.r * ka + d.r * kb;
		d.g = s.g * ka + d.g * kb;
		d.b = s.b * ka + d.b * kb;
		d.a = s.a * ka + d.a * kb;
		if (fa == ONE && fb == ONE) {
			if (d.r > 1) d.r = 1;
			if (d.g > 1) d.g = 1;
			if (d.b > 1) d.b = 1;
			if (d.a > 1) d.a = 1;
		}
	}
}

// W3C Compositing's separable modes: each channel by B(Cb, Cs) on
// straight colours, composited source-over:
// co = cs (1 - ab) + cb (1 - as) + as ab B(cb / ab, cs / as)
abstract class Separable implements Blender {
	public var unbounded(get, never):Bool;
	public var code(get, never):Int;

	inline function get_unbounded()
		return false;

	function get_code()
		return 0;

	function new() {}

	abstract function channel(cb:Float, cs:Float):Float;

	public function blend(s:Rgba, d:Rgba) {
		var as = s.a, ab = d.a;
		if (as <= 0) return;
		if (ab <= 0) {
			d.r = s.r;
			d.g = s.g;
			d.b = s.b;
			d.a = s.a;
			return;
		}
		var both = as * ab;
		d.r = s.r * (1 - ab) + d.r * (1 - as) + both * channel(d.r / ab, s.r / as);
		d.g = s.g * (1 - ab) + d.g * (1 - as) + both * channel(d.g / ab, s.g / as);
		d.b = s.b * (1 - ab) + d.b * (1 - as) + both * channel(d.b / ab, s.b / as);
		d.a = as + ab - both;
	}
}

final class Multiply extends Separable {
	public static final instance = new Multiply();

	override function get_code()
		return 0;

	function channel(cb:Float, cs:Float):Float
		return cb * cs;
}

final class Screen extends Separable {
	public static final instance = new Screen();

	override function get_code()
		return 1;

	function channel(cb:Float, cs:Float):Float
		return cb + cs - cb * cs;
}

final class Overlay extends Separable {
	public static final instance = new Overlay();

	override function get_code()
		return 2;

	function channel(cb:Float, cs:Float):Float
		return cb <= 0.5 ? cs * 2 * cb : cs + (2 * cb - 1) - cs * (2 * cb - 1);
}

final class Darken extends Separable {
	public static final instance = new Darken();

	override function get_code()
		return 3;

	function channel(cb:Float, cs:Float):Float
		return cb < cs ? cb : cs;
}

final class Lighten extends Separable {
	public static final instance = new Lighten();

	override function get_code()
		return 4;

	function channel(cb:Float, cs:Float):Float
		return cb > cs ? cb : cs;
}

final class ColorDodge extends Separable {
	public static final instance = new ColorDodge();

	override function get_code()
		return 5;

	function channel(cb:Float, cs:Float):Float
		return cb <= 0 ? 0 : cs >= 1 ? 1 : Math.min(1, cb / (1 - cs));
}

final class ColorBurn extends Separable {
	public static final instance = new ColorBurn();

	override function get_code()
		return 6;

	function channel(cb:Float, cs:Float):Float
		return cb >= 1 ? 1 : cs <= 0 ? 0 : 1 - Math.min(1, (1 - cb) / cs);
}

final class HardLight extends Separable {
	public static final instance = new HardLight();

	override function get_code()
		return 7;

	function channel(cb:Float, cs:Float):Float
		return cs <= 0.5 ? cb * 2 * cs : cb + (2 * cs - 1) - cb * (2 * cs - 1);
}

final class SoftLight extends Separable {
	public static final instance = new SoftLight();

	override function get_code()
		return 8;

	function channel(cb:Float, cs:Float):Float {
		if (cs <= 0.5) return cb - (1 - 2 * cs) * cb * (1 - cb);
		var d = cb <= 0.25 ? ((16 * cb - 12) * cb + 4) * cb : Math.sqrt(cb);
		return cb + (2 * cs - 1) * (d - cb);
	}
}

final class Difference extends Separable {
	public static final instance = new Difference();

	override function get_code()
		return 9;

	function channel(cb:Float, cs:Float):Float
		return Math.abs(cb - cs);
}

final class Exclusion extends Separable {
	public static final instance = new Exclusion();

	override function get_code()
		return 10;

	function channel(cb:Float, cs:Float):Float
		return cb + cs - 2 * cb * cs;
}

// hue, saturation, color, luminosity: the straight colours' luminosity
// and saturation set from one and the other (W3C Compositing's SetLum,
// SetSat, ClipColor)
final class NonSeparable implements Blender {
	public static var hue(get, never):NonSeparable;
	public static var saturation(get, never):NonSeparable;
	public static var color(get, never):NonSeparable;
	public static var luminosity(get, never):NonSeparable;

	static inline function get_hue()
		return of(0);

	static inline function get_saturation()
		return of(1);

	static inline function get_color()
		return of(2);

	static inline function get_luminosity()
		return of(3);

	static final made:Array<NonSeparable> = [];

	static function of(k:Int):NonSeparable {
		if (made[k] == null) made[k] = new NonSeparable(k);
		return made[k];
	}

	final kind:Int;

	public var unbounded(get, never):Bool;
	public var code(get, never):Int;

	inline function get_unbounded()
		return false;

	inline function get_code()
		return 11 + kind;

	function new(kind) {
		this.kind = kind;
	}

	var r = 0.0;
	var g = 0.0;
	var b = 0.0;

	static inline function lum(r:Float, g:Float, b:Float):Float
		return 0.3 * r + 0.59 * g + 0.11 * b;

	static inline function sat(r:Float, g:Float, b:Float):Float
		return Math.max(r, Math.max(g, b)) - Math.min(r, Math.min(g, b));

	function setLum(r:Float, g:Float, b:Float, l:Float) {
		var d = l - lum(r, g, b);
		r += d;
		g += d;
		b += d;
		var L = lum(r, g, b), n = Math.min(r, Math.min(g, b)), x = Math.max(r, Math.max(g, b));
		if (n < 0) {
			r = L + (r - L) * L / (L - n);
			g = L + (g - L) * L / (L - n);
			b = L + (b - L) * L / (L - n);
		}
		if (x > 1) {
			r = L + (r - L) * (1 - L) / (x - L);
			g = L + (g - L) * (1 - L) / (x - L);
			b = L + (b - L) * (1 - L) / (x - L);
		}
		this.r = r;
		this.g = g;
		this.b = b;
	}

	// (r, g, b) given saturation s, into this.r, g, b
	function setSat(r:Float, g:Float, b:Float, s:Float) {
		var mx = Math.max(r, Math.max(g, b)), mn = Math.min(r, Math.min(g, b));
		if (mx > mn) {
			inline function f(c:Float):Float
				return c == mx ? s : c == mn ? 0 : (c - mn) * s / (mx - mn);
			this.r = f(r);
			this.g = f(g);
			this.b = f(b);
		} else this.r = this.g = this.b = 0;
	}

	public function blend(s:Rgba, d:Rgba) {
		var as = s.a, ab = d.a;
		if (as <= 0) return;
		if (ab <= 0) {
			d.r = s.r;
			d.g = s.g;
			d.b = s.b;
			d.a = s.a;
			return;
		}
		var sr = s.r / as, sg = s.g / as, sb = s.b / as, br = d.r / ab, bg = d.g / ab, bb = d.b / ab;
		switch kind {
			case 0:
				setSat(sr, sg, sb, sat(br, bg, bb));
				setLum(r, g, b, lum(br, bg, bb));
			case 1:
				setSat(br, bg, bb, sat(sr, sg, sb));
				setLum(r, g, b, lum(br, bg, bb));
			case 2:
				setLum(sr, sg, sb, lum(br, bg, bb));
			case _:
				setLum(br, bg, bb, lum(sr, sg, sb));
		}
		var both = as * ab;
		d.r = s.r * (1 - ab) + d.r * (1 - as) + both * r;
		d.g = s.g * (1 - ab) + d.g * (1 - as) + both * g;
		d.b = s.b * (1 - ab) + d.b * (1 - as) + both * b;
		d.a = as + ab - both;
	}
}
