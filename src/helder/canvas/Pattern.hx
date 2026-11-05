package helder.canvas;

import haxe.ds.Vector;
import helder.canvas.Paint.Shader;

// An image as a paint: a bitmap repeated across x, y, both or neither
// (transparent outside it), sampled at the nearest pixel or bilinearly.
// `matrix` places the image's pixels in the drawing's units. drawImage
// draws through one (clamped to its source rectangle).
final class Pattern implements Shader {
	public var bitmap:Bitmap;
	public var repeatX:Bool;
	public var repeatY:Bool;
	public var smooth:Bool;
	public final matrix = new Matrix();

	// (drawImage's: samples clamped to the source rectangle, sx0...sx1)
	public var clamp = false;
	public var sx0 = 0.0;
	public var sy0 = 0.0;
	public var sx1 = 0.0;
	public var sy1 = 0.0;

	final inv = new Matrix();
	final local = new Matrix();

	public function new(bitmap:Bitmap, repeatX = true, repeatY = true, smooth = true) {
		this.bitmap = bitmap;
		this.repeatX = repeatX;
		this.repeatY = repeatY;
		this.smooth = smooth;
	}

	public function begin(inverse:Matrix):Bool {
		if (bitmap.width == 0 || bitmap.height == 0) return false;
		if (!matrix.invertInto(inv)) return false;
		local.copyFrom(inv).multiply(inverse);
		return true;
	}

	public function shade(x:Int, y:Int, n:Int, out:Vector<Float>) {
		var m = local, cy = y + 0.5, px = bitmap.pixels, w = bitmap.width, h = bitmap.height;
		for (i in 0...n) {
			var cx = x + i + 0.5, o = i * 4;
			var u = m.a * cx + m.c * cy + m.e, v = m.b * cx + m.d * cy + m.f;
			if (smooth) {
				// (the four pixels around (u, v), their centres at k + 0.5)
				var fu = u - 0.5, fv = v - 0.5;
				var iu = Math.floor(fu), iv = Math.floor(fv);
				var tu = fu - iu, tv = fv - iv;
				var x0 = Std.int(iu), y0 = Std.int(iv);
				var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
				for (k in 0...4) {
					var sx = x0 + (k & 1), sy = y0 + (k >> 1);
					var wgt = ((k & 1) == 1 ? tu : 1 - tu) * ((k >> 1) == 1 ? tv : 1 - tv);
					if (wgt == 0) continue;
					var p = texel(sx, sy, w, h);
					if (p < 0) continue;
					r += px.get(p) * wgt;
					g += px.get(p + 1) * wgt;
					b += px.get(p + 2) * wgt;
					a += px.get(p + 3) * wgt;
				}
				out[o] = r / 255;
				out[o + 1] = g / 255;
				out[o + 2] = b / 255;
				out[o + 3] = a / 255;
			} else {
				var p = texel(Std.int(Math.floor(u)), Std.int(Math.floor(v)), w, h);
				if (p < 0) out[o] = out[o + 1] = out[o + 2] = out[o + 3] = 0 else {
					out[o] = px.get(p) / 255;
					out[o + 1] = px.get(p + 1) / 255;
					out[o + 2] = px.get(p + 2) / 255;
					out[o + 3] = px.get(p + 3) / 255;
				}
			}
		}
	}

	// a texel's offset by the repeat modes (-1: none, transparent)
	function texel(sx:Int, sy:Int, w:Int, h:Int):Int {
		if (clamp) {
			var lx = Std.int(sx0), hx = Std.int(Math.ceil(sx1)) - 1, ly = Std.int(sy0), hy = Std.int(Math.ceil(sy1)) - 1;
			if (sx < lx) sx = lx;
			if (sx > hx) sx = hx;
			if (sy < ly) sy = ly;
			if (sy > hy) sy = hy;
			if (sx < 0) sx = 0;
			if (sy < 0) sy = 0;
			if (sx >= w) sx = w - 1;
			if (sy >= h) sy = h - 1;
		} else {
			if (repeatX) {
				sx %= w;
				if (sx < 0) sx += w;
			} else if (sx < 0 || sx >= w) return -1;
			if (repeatY) {
				sy %= h;
				if (sy < 0) sy += h;
			} else if (sy < 0 || sy >= h) return -1;
		}
		return (sy * w + sx) * 4;
	}
}
