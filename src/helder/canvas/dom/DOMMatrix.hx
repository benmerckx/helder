package helder.canvas.dom;

// The browser's DOMMatrix, its 2D part (a to f, m11 to m42): what
// getTransform gives, setTransform and a pattern's setTransform take. The
// *Self methods change it, the others return a new one.
class DOMMatrix {
	public var a:Float;
	public var b:Float;
	public var c:Float;
	public var d:Float;
	public var e:Float;
	public var f:Float;

	public var m11(get, set):Float;
	public var m12(get, set):Float;
	public var m21(get, set):Float;
	public var m22(get, set):Float;
	public var m41(get, set):Float;
	public var m42(get, set):Float;
	public var is2D(get, never):Bool;
	public var isIdentity(get, never):Bool;

	// (none: the identity; six numbers: a to f)
	public function new(?init:Array<Float>) {
		if (init != null && init.length >= 6) {
			a = init[0];
			b = init[1];
			c = init[2];
			d = init[3];
			e = init[4];
			f = init[5];
		} else {
			a = d = 1;
			b = c = e = f = 0;
		}
	}

	@:noCompletion public static function of(m:helder.canvas.Matrix):DOMMatrix
		return new DOMMatrix([m.a, m.b, m.c, m.d, m.e, m.f]);

	@:noCompletion public function into(m:helder.canvas.Matrix):helder.canvas.Matrix
		return m.set(a, b, c, d, e, f);

	inline function get_m11()
		return a;

	inline function set_m11(v)
		return a = v;

	inline function get_m12()
		return b;

	inline function set_m12(v)
		return b = v;

	inline function get_m21()
		return c;

	inline function set_m21(v)
		return c = v;

	inline function get_m22()
		return d;

	inline function set_m22(v)
		return d = v;

	inline function get_m41()
		return e;

	inline function set_m41(v)
		return e = v;

	inline function get_m42()
		return f;

	inline function set_m42(v)
		return f = v;

	inline function get_is2D()
		return true;

	function get_isIdentity()
		return a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

	function copy():DOMMatrix
		return new DOMMatrix([a, b, c, d, e, f]);

	public function multiplySelf(o:DOMMatrix):DOMMatrix {
		var na = a * o.a + c * o.b, nb = b * o.a + d * o.b, nc = a * o.c + c * o.d, nd = b * o.c + d * o.d;
		var ne = a * o.e + c * o.f + e, nf = b * o.e + d * o.f + f;
		a = na;
		b = nb;
		c = nc;
		d = nd;
		e = ne;
		f = nf;
		return this;
	}

	public function preMultiplySelf(o:DOMMatrix):DOMMatrix {
		var m = o.copy().multiplySelf(this);
		a = m.a;
		b = m.b;
		c = m.c;
		d = m.d;
		e = m.e;
		f = m.f;
		return this;
	}

	public function translateSelf(tx = 0.0, ty = 0.0):DOMMatrix
		return multiplySelf(new DOMMatrix([1, 0, 0, 1, tx, ty]));

	public function scaleSelf(sx = 1.0, ?sy:Float):DOMMatrix
		return multiplySelf(new DOMMatrix([sx, 0, 0, sy ?? sx, 0, 0]));

	// (degrees, as the browser's)
	public function rotateSelf(deg = 0.0):DOMMatrix {
		var r = deg * Math.PI / 180, cs = Math.cos(r), sn = Math.sin(r);
		return multiplySelf(new DOMMatrix([cs, sn, -sn, cs, 0, 0]));
	}

	public function skewXSelf(deg = 0.0):DOMMatrix
		return multiplySelf(new DOMMatrix([1, 0, Math.tan(deg * Math.PI / 180), 1, 0, 0]));

	public function skewYSelf(deg = 0.0):DOMMatrix
		return multiplySelf(new DOMMatrix([1, Math.tan(deg * Math.PI / 180), 0, 1, 0, 0]));

	public function invertSelf():DOMMatrix {
		var det = a * d - b * c;
		if (det == 0 || !Math.isFinite(det)) {
			a = b = c = d = e = f = Math.NaN;
			return this;
		}
		var na = d / det, nb = -b / det, nc = -c / det, nd = a / det, ne = (c * f - d * e) / det, nf = (b * e - a * f) / det;
		a = na;
		b = nb;
		c = nc;
		d = nd;
		e = ne;
		f = nf;
		return this;
	}

	public function multiply(o:DOMMatrix):DOMMatrix
		return copy().multiplySelf(o);

	public function translate(tx = 0.0, ty = 0.0):DOMMatrix
		return copy().translateSelf(tx, ty);

	public function scale(sx = 1.0, ?sy:Float):DOMMatrix
		return copy().scaleSelf(sx, sy);

	public function rotate(deg = 0.0):DOMMatrix
		return copy().rotateSelf(deg);

	public function skewX(deg = 0.0):DOMMatrix
		return copy().skewXSelf(deg);

	public function skewY(deg = 0.0):DOMMatrix
		return copy().skewYSelf(deg);

	public function inverse():DOMMatrix
		return copy().invertSelf();

	// a point's x and y through it, as [x, y]
	public function transformPoint(x = 0.0, y = 0.0):Array<Float>
		return [a * x + c * y + e, b * x + d * y + f];

	public function toFloat64Array():Array<Float>
		return [a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1];

	public function toString():String
		return 'matrix($a, $b, $c, $d, $e, $f)';
}
