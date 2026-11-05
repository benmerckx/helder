package helder.canvas;

import haxe.ds.Vector;
import haxe.io.Bytes;

// Analytic coverage of lines in device pixels (y down), as font-rs and
// tiny-skia's: each line adds its exact signed area to an accumulation
// buffer, a running sum along each row then gives each pixel's coverage
// (non-zero: the winding's magnitude clamped to one; even-odd: folded
// over two). Only the rows and columns the lines touched are read, and
// cleared as they are: a small shape on a large canvas costs its own size.
// One per canvas, kept: nothing allocated per path.
final class Raster implements Path.Sink {
	public final width:Int;
	public final height:Int;
	final stride:Int;
	final acc:Vector<Float>;

	// the touched region: rows y0...y1, columns x0...x1 (x1 one past, the carry's)
	public var y0(default, null) = 0;
	public var y1(default, null) = 0;
	public var x0(default, null) = 0;
	public var x1(default, null) = 0;

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
		reset();
	}

	public inline function reset() {
		y0 = height;
		y1 = 0;
		x0 = width;
		x1 = 0;
	}

	public inline function isEmpty():Bool
		return y1 <= y0 || x1 <= x0;

	public function moveTo(x:Float, y:Float) {
		px = sx = x;
		py = sy = y;
	}

	public function lineTo(x:Float, y:Float) {
		line(px, py, x, y);
		px = x;
		py = y;
	}

	public function close() {
		if (px != sx || py != sy) line(px, py, sx, sy);
		px = sx;
		py = sy;
	}

	// a line clipped to the columns: a part left of them as the same rise
	// at their left edge (it winds every pixel to its right), a part right
	// of them dropped (it winds none)
	public function line(ax:Float, ay:Float, bx:Float, by:Float) {
		if (ay == by || !(Math.isFinite(ax) && Math.isFinite(ay) && Math.isFinite(bx) && Math.isFinite(by))) return;
		if ((ay <= 0 && by <= 0) || (ay >= height && by >= height)) return;
		if (ax >= 0 && bx >= 0 && ax <= width && bx <= width) {
			scan(ax, ay, bx, by);
			return;
		}
		// (right of the columns: no coverage of its own, but what lies left of it
		// may cover every column up to the edge)
		if (ax >= width && bx >= width) {
			x1 = width;
			return;
		}
		if (ax <= 0 && bx <= 0) {
			scan(0, ay, 0, by);
			return;
		}
		// (split where it crosses an edge, each part again)
		var edge = (ax < 0 || bx < 0) ? 0.0 : width;
		var t = (edge - ax) / (bx - ax), ym = ay + (by - ay) * t;
		line(ax, ay, edge, ym);
		line(edge, ym, bx, by);
	}

	function scan(ax:Float, ay:Float, bx:Float, by:Float) {
		var dir = 1.0;
		if (ay > by) {
			dir = -1;
			var t = ax;
			ax = bx;
			bx = t;
			t = ay;
			ay = by;
			by = t;
		}
		var dxdy = (bx - ax) / (by - ay);
		var x = ax;
		if (ay < 0) x -= ay * dxdy;
		var yStart = ay < 0 ? 0 : Std.int(Math.floor(ay)), yEnd = by > height ? height : Std.int(Math.ceil(by));
		if (yStart < y0) y0 = yStart;
		if (yEnd > y1) y1 = yEnd;
		var lo = Std.int(Math.floor(ax < bx ? ax : bx)), hi = Std.int(Math.ceil(ax < bx ? bx : ax)) + 2;
		if (lo < x0) x0 = lo < 0 ? 0 : lo;
		if (hi > x1) x1 = hi > width ? width : hi;
		for (y in yStart...yEnd) {
			var row = y * stride;
			var dy = Math.min(y + 1, by) - Math.max(y, ay);
			var xnext = x + dxdy * dy;
			var d = dy * dir;
			var a = x < xnext ? x : xnext, b = x < xnext ? xnext : x;
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

	// row y's coverage (0 to 255) into out[x0...x1], its accumulation
	// cleared; the columns before x0 carry nothing (a line left of the
	// canvas lands in column 0)
	public function row(y:Int, out:Bytes, evenOdd:Bool) {
		var r = y * stride, sum = 0.0;
		for (x in 0...x0) {
			sum += acc[r + x];
			acc[r + x] = 0;
		}
		for (x in x0...x1) {
			sum += acc[r + x];
			acc[r + x] = 0;
			var c = sum < 0 ? -sum : sum;
			if (evenOdd) {
				c = c % 2;
				if (c > 1) c = 2 - c;
			}
			out.set(x, c >= 1 ? 255 : Std.int(c * 255 + 0.5));
		}
		acc[r + width] = 0;
		acc[r + width + 1] = 0;
	}

	// every touched row cleared without reading it
	public function discard() {
		for (y in y0...y1) {
			var r = y * stride;
			for (x in 0...stride)
				acc[r + x] = 0;
		}
		reset();
	}
}
