package helder.text;

import haxe.ds.Vector;

// An anti-aliased rasterizer of outlines into a coverage bitmap, after
// Raph Levien's font-rs: each line adds its exact signed area to an
// accumulation buffer, a running sum along each row then gives every
// pixel's coverage (the nonzero rule, overlaps clamped). Quadratic and
// cubic curves are flattened into lines within a third of a pixel. Coordinates are
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

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		var x1 = c1x * scaleX + offsetX, y1 = c1y * scaleY + offsetY;
		var x2 = c2x * scaleX + offsetX, y2 = c2y * scaleY + offsetY;
		var x3 = x * scaleX + offsetX, y3 = y * scaleY + offsetY;
		// (the second differences bound the distance to the chords: 3/4 of
		// the larger over n squared)
		var ax = px - 2 * x1 + x2, ay = py - 2 * y1 + y2, bx = x1 - 2 * x2 + x3, by = y1 - 2 * y2 + y3;
		var dev = Math.sqrt(Math.max(ax * ax + ay * ay, bx * bx + by * by));
		var n = 1 + Math.floor(Math.sqrt(dev * 0.75 / 0.2));
		var lx = px, ly = py;
		for (i in 1...n + 1) {
			var t = i / n, u = 1 - t;
			var a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
			var qx = a * px + b * x1 + c * x2 + d * x3, qy = a * py + b * y1 + c * y2 + d * y3;
			line(lx, ly, qx, qy);
			lx = qx;
			ly = qy;
		}
		px = x3;
		py = y3;
	}

	public function close() {
		if (px != sx || py != sy) line(px, py, sx, sy);
		px = sx;
		py = sy;
	}

	// a line clipped to the bitmap's columns: a part left of it as the
	// same rise at its left edge (it winds every pixel to its right), a part
	// right of it dropped (it winds none)
	function line(x0:Float, y0:Float, x1:Float, y1:Float) {
		if (Math.abs(y0 - y1) <= 1e-9) return;
		if (x0 >= 0 && x1 >= 0 && x0 <= width && x1 <= width) {
			scan(x0, y0, x1, y1);
			return;
		}
		if (x0 >= width && x1 >= width) return;
		if (x0 <= 0 && x1 <= 0) {
			scan(0, y0, 0, y1);
			return;
		}
		// (split where it crosses an edge, each part again)
		var edge = (x0 < 0 || x1 < 0) && !((x0 - 0) * (x1 - 0) > 0) ? 0.0 : width;
		var t = (edge - x0) / (x1 - x0), ym = y0 + (y1 - y0) * t;
		line(x0, y0, edge, ym);
		line(edge, ym, x1, y1);
	}

	function scan(x0:Float, y0:Float, x1:Float, y1:Float) {
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

	// the coverage as bytes (0 to 255), rows of width at dst's offset with a
	// stride; evenOdd: by the even-odd rule (a winding of 2 is outside)
	public function writeTo(dst:haxe.io.Bytes, offset:Int, dstStride:Int, evenOdd = false) {
		for (y in 0...height) {
			var sum = 0.0, row = y * stride, o = offset + y * dstStride;
			for (x in 0...width) {
				sum += acc[row + x];
				var c = Math.abs(sum);
				if (evenOdd) {
					c = c % 2;
					if (c > 1) c = 2 - c;
				}
				dst.set(o + x, c >= 1 ? 255 : Std.int(c * 255 + 0.5));
			}
		}
	}

	public function clear() {
		for (i in 0...acc.length)
			acc[i] = 0;
	}
}
