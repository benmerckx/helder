package helder.canvas;

// An affine transform, as Canvas 2D's and SVG's: x' = a x + c y + e,
// y' = b x + d y + f. Mutable, so a canvas's stack and a paint's own keep
// theirs without allocating: the operations change it in place and return
// it (pre-multiplied, as Canvas 2D's translate, scale and rotate: the new
// transform applies first).
final class Matrix {
	public var a:Float;
	public var b:Float;
	public var c:Float;
	public var d:Float;
	public var e:Float;
	public var f:Float;

	public static final IDENTITY = new Matrix();

	public inline function new(a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0) {
		this.a = a;
		this.b = b;
		this.c = c;
		this.d = d;
		this.e = e;
		this.f = f;
	}

	public inline function set(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Matrix {
		this.a = a;
		this.b = b;
		this.c = c;
		this.d = d;
		this.e = e;
		this.f = f;
		return this;
	}

	public inline function identity():Matrix
		return set(1, 0, 0, 1, 0, 0);

	public inline function copyFrom(m:Matrix):Matrix
		return set(m.a, m.b, m.c, m.d, m.e, m.f);

	public function clone():Matrix
		return new Matrix(a, b, c, d, e, f);

	public inline function isIdentity():Bool
		return a == 1 && b == 0 && c == 0 && d == 1 && e == 0 && f == 0;

	// this = this * m (m applies first)
	public function multiply(m:Matrix):Matrix
		return transform(m.a, m.b, m.c, m.d, m.e, m.f);

	// this = this * (a b c d e f): Canvas 2D's transform()
	public function transform(ma:Float, mb:Float, mc:Float, md:Float, me:Float, mf:Float):Matrix
		return set(a * ma + c * mb, b * ma + d * mb, a * mc + c * md, b * mc + d * md, a * me + c * mf + e, b * me + d * mf + f);

	// this = m * this (this applies first)
	public function premultiply(m:Matrix):Matrix
		return set(m.a * a + m.c * b, m.b * a + m.d * b, m.a * c + m.c * d, m.b * c + m.d * d, m.a * e + m.c * f + m.e, m.b * e + m.d * f + m.f);

	public function translate(x:Float, y:Float):Matrix {
		e += a * x + c * y;
		f += b * x + d * y;
		return this;
	}

	public function scale(sx:Float, sy:Float):Matrix {
		a *= sx;
		b *= sx;
		c *= sy;
		d *= sy;
		return this;
	}

	public function rotate(angle:Float):Matrix {
		var cos = Math.cos(angle), sin = Math.sin(angle);
		return transform(cos, sin, -sin, cos, 0, 0);
	}

	public inline function determinant():Float
		return a * d - b * c;

	public inline function invertible():Bool {
		var det = determinant();
		return det != 0 && Math.isFinite(det) && Math.isFinite(e) && Math.isFinite(f);
	}

	// its inverse into out (false: it has none, out untouched)
	public function invertInto(out:Matrix):Bool {
		var det = determinant();
		if (det == 0 || !Math.isFinite(det)) return false;
		var id = 1 / det;
		out.set(d * id, -b * id, -c * id, a * id, (c * f - d * e) * id, (b * e - a * f) * id);
		return true;
	}

	public inline function mapX(x:Float, y:Float):Float
		return a * x + c * y + e;

	public inline function mapY(x:Float, y:Float):Float
		return b * x + d * y + f;

	// the largest factor it scales a length by (a stroke's flattening, a curve's tolerance)
	public function maxScale():Float {
		var sx = Math.sqrt(a * a + b * b), sy = Math.sqrt(c * c + d * d);
		return sx > sy ? sx : sy;
	}

	public function toString():String
		return 'Matrix($a, $b, $c, $d, $e, $f)';
}
