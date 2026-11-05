package helder.canvas;

import haxe.ds.Vector;

// An image filter applied to a layer's pixels (premultiplied) before it is
// composited (saveLayer's filter): a Gaussian blur, a drop shadow, a
// colour matrix (CSS's grayscale, sepia, saturate, hue-rotate, invert,
// brightness, contrast, opacity), a chain of them; each a class of its
// own, so an app keeps those it uses. css() is the same filter as CSS's
// filter function (the web back end's).
interface Filter {
	function apply(b:Bitmap):Void;
	function css():String;
}

// A Gaussian blur of standard deviation sigma (CSS's blur(radius): sigma
// = radius), as three box blurs (W3C Filter Effects' approximation)
final class Blur implements Filter {
	public final sigma:Float;

	public function new(sigma:Float) {
		this.sigma = sigma;
	}

	public function css():String
		return 'blur(${sigma}px)';

	public function apply(b:Bitmap) {
		if (!(sigma > 0)) return;
		var d = Std.int(Math.floor(sigma * 3 * Math.sqrt(2 * Math.PI) / 4 + 0.5));
		if (d < 1) return;
		var w = b.width, h = b.height, px = b.pixels;
		var line = new Vector<Int>(Std.int(Math.max(w, h)) * 4), tmp = new Vector<Int>(Std.int(Math.max(w, h)) * 4);
		// (three boxes of d: odd d centred; even d one off centre, then the other way, then of d + 1 centred)
		var passes = d % 2 == 1 ? [[d, d >> 1], [d, d >> 1], [d, d >> 1]] : [[d, d >> 1], [d, (d >> 1) - 1], [d + 1, d >> 1]];
		for (axis in 0...2) {
			var n = axis == 0 ? w : h, lines = axis == 0 ? h : w;
			for (l in 0...lines) {
				for (i in 0...n) {
					var o = axis == 0 ? (l * w + i) * 4 : (i * w + l) * 4;
					for (c in 0...4)
						line[i * 4 + c] = px.get(o + c);
				}
				for (p in passes) {
					box(line, tmp, n, p[0], p[1]);
					var t = line;
					line = tmp;
					tmp = t;
				}
				for (i in 0...n) {
					var o = axis == 0 ? (l * w + i) * 4 : (i * w + l) * 4;
					for (c in 0...4)
						px.set(o + c, line[i * 4 + c]);
				}
			}
		}
	}

	// a box of size s, its left side off back pixels from each one: src into dst (transparent past the ends)
	static function box(src:Vector<Int>, dst:Vector<Int>, n:Int, s:Int, back:Int) {
		for (c in 0...4) {
			var sum = 0;
			for (i in -back...s - back)
				if (i >= 0 && i < n) sum += src[i * 4 + c];
			for (i in 0...n) {
				dst[i * 4 + c] = Std.int((sum + (s >> 1)) / s);
				var out = i - back, inn = i - back + s;
				if (out >= 0 && out < n) sum -= src[out * 4 + c];
				if (inn >= 0 && inn < n) sum += src[inn * 4 + c];
			}
		}
	}
}

// The layer's alpha blurred (sigma), coloured (0xAARRGGBB) and moved by
// (dx, dy), drawn under it: CSS's drop-shadow, Canvas 2D's shadows
final class DropShadow implements Filter {
	public final dx:Float;
	public final dy:Float;
	public final sigma:Float;
	public final color:Int;

	public function new(dx:Float, dy:Float, sigma:Float, color:Int) {
		this.dx = dx;
		this.dy = dy;
		this.sigma = sigma;
		this.color = color;
	}

	public function css():String {
		var c = color, a = ((c >>> 24) & 255) / 255;
		return 'drop-shadow(${dx}px ${dy}px ${sigma}px rgba(${(c >> 16) & 255}, ${(c >> 8) & 255}, ${c & 255}, $a))';
	}

	public function apply(b:Bitmap) {
		var w = b.width, h = b.height, px = b.pixels;
		var shadow = new Bitmap(w, h);
		var ca = (color >>> 24) & 255, cr = (color >> 16) & 255, cg = (color >> 8) & 255, cb = color & 255;
		var ox = Std.int(Math.round(dx)), oy = Std.int(Math.round(dy));
		for (y in 0...h)
			for (x in 0...w) {
				var sx = x - ox, sy = y - oy;
				if (sx < 0 || sy < 0 || sx >= w || sy >= h) continue;
				var a = px.get((sy * w + sx) * 4 + 3) * ca / 255, o = (y * w + x) * 4;
				shadow.pixels.set(o, Std.int(cr * a / 255 + 0.5));
				shadow.pixels.set(o + 1, Std.int(cg * a / 255 + 0.5));
				shadow.pixels.set(o + 2, Std.int(cb * a / 255 + 0.5));
				shadow.pixels.set(o + 3, Std.int(a + 0.5));
			}
		new Blur(sigma).apply(shadow);
		// (the layer over its shadow)
		for (i in 0...w * h) {
			var o = i * 4, sa = px.get(o + 3), k = 255 - sa;
			for (c in 0...4)
				px.set(o + c, px.get(o + c) + Std.int((shadow.pixels.get(o + c) * k + 127) / 255));
		}
	}
}

// A 4x5 colour matrix on straight RGBA (0 to 1), row by row (SVG's
// feColorMatrix): CSS's colour filters are its constructors
final class ColorMatrix implements Filter {
	public final m:Array<Float>;
	final name:String;

	public function new(m:Array<Float>, ?name:String) {
		this.m = m;
		this.name = name ?? "";
	}

	public function css():String
		return name;

	public static function grayscale(amount = 1.0):ColorMatrix {
		var a = 1 - Math.min(1, amount);
		return new ColorMatrix([
			0.2126 + 0.7874 * a, 0.7152 - 0.7152 * a, 0.0722 - 0.0722 * a, 0, 0,
			0.2126 - 0.2126 * a, 0.7152 + 0.2848 * a, 0.0722 - 0.0722 * a, 0, 0,
			0.2126 - 0.2126 * a, 0.7152 - 0.7152 * a, 0.0722 + 0.9278 * a, 0, 0,
			0, 0, 0, 1, 0
		], 'grayscale($amount)');
	}

	public static function sepia(amount = 1.0):ColorMatrix {
		var a = 1 - Math.min(1, amount);
		return new ColorMatrix([
			0.393 + 0.607 * a, 0.769 - 0.769 * a, 0.189 - 0.189 * a, 0, 0,
			0.349 - 0.349 * a, 0.686 + 0.314 * a, 0.168 - 0.168 * a, 0, 0,
			0.272 - 0.272 * a, 0.534 - 0.534 * a, 0.131 + 0.869 * a, 0, 0,
			0, 0, 0, 1, 0
		], 'sepia($amount)');
	}

	public static function saturate(s:Float):ColorMatrix
		return new ColorMatrix([
			0.213 + 0.787 * s, 0.715 - 0.715 * s, 0.072 - 0.072 * s, 0, 0,
			0.213 - 0.213 * s, 0.715 + 0.285 * s, 0.072 - 0.072 * s, 0, 0,
			0.213 - 0.213 * s, 0.715 - 0.715 * s, 0.072 + 0.928 * s, 0, 0,
			0, 0, 0, 1, 0
		], 'saturate($s)');

	public static function hueRotate(degrees:Float):ColorMatrix {
		var r = degrees * Math.PI / 180, c = Math.cos(r), s = Math.sin(r);
		return new ColorMatrix([
			0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0, 0,
			0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0, 0,
			0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0, 0,
			0, 0, 0, 1, 0
		], 'hue-rotate(${degrees}deg)');
	}

	public static function invert(amount = 1.0):ColorMatrix {
		var a = Math.min(1, amount), k = 1 - 2 * a;
		return new ColorMatrix([k, 0, 0, 0, a, 0, k, 0, 0, a, 0, 0, k, 0, a, 0, 0, 0, 1, 0], 'invert($amount)');
	}

	public static function brightness(b:Float):ColorMatrix
		return new ColorMatrix([b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0], 'brightness($b)');

	public static function contrast(c:Float):ColorMatrix {
		var o = 0.5 - 0.5 * c;
		return new ColorMatrix([c, 0, 0, 0, o, 0, c, 0, 0, o, 0, 0, c, 0, o, 0, 0, 0, 1, 0], 'contrast($c)');
	}

	public static function opacity(a:Float):ColorMatrix
		return new ColorMatrix([1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, Math.min(1, a), 0], 'opacity($a)');

	public function apply(b:Bitmap) {
		var px = b.pixels;
		for (i in 0...b.width * b.height) {
			var o = i * 4, a = px.get(o + 3) / 255;
			var r = a > 0 ? px.get(o) / 255 / a : 0, g = a > 0 ? px.get(o + 1) / 255 / a : 0, bl = a > 0 ? px.get(o + 2) / 255 / a : 0;
			inline function row(k:Int):Float
				return m[k] * r + m[k + 1] * g + m[k + 2] * bl + m[k + 3] * a + m[k + 4];
			var nr = row(0), ng = row(5), nb = row(10), na = Math.max(0, Math.min(1, row(15)));
			inline function ch(v:Float):Int
				return Std.int(Math.max(0, Math.min(1, v)) * na * 255 + 0.5);
			px.set(o, ch(nr));
			px.set(o + 1, ch(ng));
			px.set(o + 2, ch(nb));
			px.set(o + 3, Std.int(na * 255 + 0.5));
		}
	}
}

// The layer's shape as its shadow: its alpha in a colour (0xAARRGGBB),
// blurred (sigma). Canvas 2D's shadows draw a shape twice: through this,
// moved by the offset, then itself
final class Shadow implements Filter {
	public final sigma:Float;
	public final color:Int;

	public function new(sigma:Float, color:Int) {
		this.sigma = sigma;
		this.color = color;
	}

	public function css():String {
		var c = color;
		return 'drop-shadow(0 0 ${sigma}px rgba(${(c >> 16) & 255}, ${(c >> 8) & 255}, ${c & 255}, ${((c >>> 24) & 255) / 255})) opacity(0)';
	}

	public function apply(b:Bitmap) {
		var px = b.pixels, ca = (color >>> 24) & 255, cr = (color >> 16) & 255, cg = (color >> 8) & 255, cb = color & 255;
		for (i in 0...b.width * b.height) {
			var o = i * 4, a = px.get(o + 3) * ca / 255;
			px.set(o, Std.int(cr * a / 255 + 0.5));
			px.set(o + 1, Std.int(cg * a / 255 + 0.5));
			px.set(o + 2, Std.int(cb * a / 255 + 0.5));
			px.set(o + 3, Std.int(a + 0.5));
		}
		new Blur(sigma).apply(b);
	}
}

// Filters one after another
final class FilterChain implements Filter {
	public final filters:Array<Filter>;

	public function new(filters:Array<Filter>) {
		this.filters = filters;
	}

	public function css():String
		return [for (f in filters) f.css()].join(" ");

	public function apply(b:Bitmap)
		for (f in filters)
			f.apply(b);
}
