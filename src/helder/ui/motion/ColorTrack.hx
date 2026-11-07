package helder.ui.motion;

import helder.ui.Color;

// A colour as four tracks in premultiplied OKLab (Björn Ottosson's: L, a
// and b, each times the alpha, and the alpha), so that a colour moves
// through what the eye sees as between (no muddy midpoint, no grey between
// complementary hues) and a transparent end fades rather than passing
// through black. value() is where it is, back in sRGB.
class ColorTrack {
	public final l:Track;
	public final a:Track;
	public final b:Track;
	public final alpha:Track;
	public var target(default, null):Color;

	public function new(c:Color) {
		l = new Track(0, 1e-4);
		a = new Track(0, 1e-4);
		b = new Track(0, 1e-4);
		alpha = new Track(0, 1e-4);
		set(c);
	}

	public inline function moving():Bool
		return l.moving() || a.moving() || b.moving() || alpha.moving();

	public function set(c:Color) {
		target = c;
		toLab(c);
		l.set(ol);
		a.set(oa);
		b.set(ob);
		alpha.set(oal);
	}

	public function animate(now:Float, c:Color, curve:Curve) {
		target = c;
		toLab(c);
		l.animate(now, ol, curve);
		a.animate(now, oa, curve);
		b.animate(now, ob, curve);
		alpha.animate(now, oal, curve);
	}

	public function sample(now:Float) {
		l.sample(now);
		a.sample(now);
		b.sample(now);
		alpha.sample(now);
	}

	// where it is (sampled last), in sRGB
	public function value():Color
		return moving() ? fromLab(l.value, a.value, b.value, alpha.value) : target;

	// (toLab's result: premultiplied L, a, b and the alpha)
	static var ol = 0.0;
	static var oa = 0.0;
	static var ob = 0.0;
	static var oal = 0.0;

	static inline function linear(c:Int):Float {
		var v = c / 255;
		return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
	}

	static inline function encode(v:Float):Int {
		var s = v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
		var i = Std.int(s * 255 + 0.5);
		return i < 0 ? 0 : i > 255 ? 255 : i;
	}

	static inline function cbrt(x:Float):Float
		return x < 0 ? -Math.pow(-x, 1 / 3) : Math.pow(x, 1 / 3);

	// premultiplied OKLab of c, into ol, oa, ob, oal
	public static function toLab(c:Color) {
		var r = linear(c.r), g = linear(c.g), bl = linear(c.b), al = c.a / 255;
		var lm = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl);
		var mm = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl);
		var sm = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl);
		ol = (0.2104542553 * lm + 0.7936177850 * mm - 0.0040720468 * sm) * al;
		oa = (1.9779984951 * lm - 2.4285922050 * mm + 0.4505937099 * sm) * al;
		ob = (0.0259040371 * lm + 0.7827717662 * mm - 0.8086757660 * sm) * al;
		oal = al;
	}

	// sRGB of premultiplied OKLab
	public static function fromLab(pl:Float, pa:Float, pb:Float, al:Float):Color {
		if (al <= 1e-4) return Color.TRANSPARENT;
		if (al > 1) al = 1;
		var L = pl / al, A = pa / al, B = pb / al;
		var lm = L + 0.3963377774 * A + 0.2158037573 * B;
		var mm = L - 0.1055613458 * A - 0.0638541728 * B;
		var sm = L - 0.0894841775 * A - 1.2914855480 * B;
		lm = lm * lm * lm;
		mm = mm * mm * mm;
		sm = sm * sm * sm;
		var r = 4.0767416621 * lm - 3.3077115913 * mm + 0.2309699292 * sm;
		var g = -1.2684380046 * lm + 2.6097574011 * mm - 0.3413193965 * sm;
		var b = -0.0041960863 * lm - 0.7034186147 * mm + 1.7076147010 * sm;
		var ai = Std.int(al * 255 + 0.5);
		return (ai << 24) | (encode(r) << 16) | (encode(g) << 8) | encode(b);
	}

	// the colour a fraction k of the way from x to y in premultiplied OKLab (tests, a still frame)
	public static function between(x:Color, y:Color, k:Float):Color {
		toLab(x);
		var l0 = ol, a0 = oa, b0 = ob, al0 = oal;
		toLab(y);
		return fromLab(l0 + (ol - l0) * k, a0 + (oa - a0) * k, b0 + (ob - b0) * k, al0 + (oal - al0) * k);
	}
}
