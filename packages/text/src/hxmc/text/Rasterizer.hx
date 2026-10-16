package hxmc.text;

import haxe.ds.Vector;

// An anti-aliased rasterizer of outlines into a coverage bitmap, after
// Raph Levien's font-rs: each line adds its exact signed area to an
// accumulation buffer, a running sum along each row then gives every
// pixel's coverage (the nonzero rule, overlaps clamped). Quadratic curves
// are flattened into lines within a third of a pixel. Coordinates are
// pixels, y down; the transform maps outline units to them (scale, then
// offset).
class Rasterizer implements Outline {
	public final width:Int;
	public final height:Int;
	final acc:Vector<Float>;
	final stride:Int;

	// outline units to pixels: x * scaleX + offsetX, y * scaleY + offsetY
	public var scaleX = 1.0;
	public var scaleY = 1.0;
	public var offsetX = 0.0;
	public var offsetY = 0.0;

	var px = 0.0;
	var py = 0.0;
	var sx = 0.0;
	var sy = 0.0;

	public function new(width:Int, height:Int) {
		this.width = width;
		this.height = height;
		stride = width + 2;
		acc = new Vector(stride * height + 2);
		for (i in 0...acc.length)
			acc[i] = 0;
	}

	public function moveTo(x:Float, y:Float) {
		px = sx = x * scaleX + offsetX;
		py = sy = y * scaleY + offsetY;
	}

	public function lineTo(x:Float, y:Float) {
		var nx = x * scaleX + offsetX, ny = y * scaleY + offsetY;
		line(px, py, nx, ny);
		px = nx;
		py = ny;
	}

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		var x1 = cx * scaleX + offsetX, y1 = cy * scaleY + offsetY;
		var x2 = x * scaleX + offsetX, y2 = y * scaleY + offsetY;
		var devx = px - 2 * x1 + x2, devy = py - 2 * y1 + y2;
		var devsq = devx * devx + devy * devy;
		if (devsq < 0.333) {
			line(px, py, x2, y2);
		} else {
			var n = 1 + Math.floor(Math.sqrt(Math.sqrt(3 * devsq)));
			var lx = px, ly = py;
			for (i in 1...n + 1) {
				var t = i / n, u = 1 - t;
				var qx = u * u * px + 2 * u * t * x1 + t * t * x2, qy = u * u * py + 2 * u * t * y1 + t * t * y2;
				line(lx, ly, qx, qy);
				lx = qx;
				ly = qy;
			}
		}
		px = x2;
		py = y2;
	}

	public function close() {
		if (px != sx || py != sy) line(px, py, sx, sy);
		px = sx;
		py = sy;
	}

	function line(x0:Float, y0:Float, x1:Float, y1:Float) {
		if (Math.abs(y0 - y1) <= 1e-9) return;
		var dir = 1.0;
		if (y0 > y1) {
			dir = -1;
			var t = x0;
			x0 = x1;
			x1 = t;
			t = y0;
			y0 = y1;
			y1 = t;
		}
		var dxdy = (x1 - x0) / (y1 - y0);
		var x = x0;
		if (y0 < 0) x -= y0 * dxdy;
		var yStart = y0 < 0 ? 0 : Math.floor(y0), yEnd = Std.int(Math.min(height, Math.ceil(y1)));
		for (y in yStart...yEnd) {
			var row = y * stride;
			var dy = Math.min(y + 1, y1) - Math.max(y, y0);
			var xnext = x + dxdy * dy;
			var d = dy * dir;
			var a = x < xnext ? x : xnext, b = x < xnext ? xnext : x;
			// (clamped to the bitmap: coverage left of it lands in column 0)
			if (a < 0) a = 0;
			if (b < 0) b = 0;
			if (a > width) a = width;
			if (b > width) b = width;
			var a0f = Math.floor(a), a0 = Std.int(a0f), b1c = Math.ceil(b), b1 = Std.int(b1c);
			if (b1 <= a0 + 1) {
				var xm = 0.5 * (a + b) - a0f;
				acc[row + a0] += d - d * xm;
				acc[row + a0 + 1] += d * xm;
			} else {
				var s = 1 / (b - a);
				var af = a - a0f;
				var c0 = 0.5 * s * (1 - af) * (1 - af);
				var bf = b - b1c + 1;
				var cm = 0.5 * s * bf * bf;
				acc[row + a0] += d * c0;
				if (b1 == a0 + 2) acc[row + a0 + 1] += d * (1 - c0 - cm) else {
					var c1 = s * (1.5 - af);
					acc[row + a0 + 1] += d * (c1 - c0);
					for (xi in a0 + 2...b1 - 1)
						acc[row + xi] += d * s;
					var c2 = c1 + (b1 - a0 - 3) * s;
					acc[row + b1 - 1] += d * (1 - c2 - cm);
				}
				acc[row + b1] += d * cm;
			}
			x = xnext;
		}
	}

	// the coverage as bytes (0 to 255), rows of width at dst's offset with a stride
	public function writeTo(dst:haxe.io.Bytes, offset:Int, dstStride:Int) {
		for (y in 0...height) {
			var sum = 0.0, row = y * stride, o = offset + y * dstStride;
			for (x in 0...width) {
				sum += acc[row + x];
				var c = Math.abs(sum);
				dst.set(o + x, c >= 1 ? 255 : Std.int(c * 255 + 0.5));
			}
		}
	}

	public function clear() {
		for (i in 0...acc.length)
			acc[i] = 0;
	}
}
