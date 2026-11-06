package helder.canvas;

import haxe.ds.Vector;
import haxe.io.Bytes;
import hxmc.simd.F32x4;
import hxmc.simd.I16x8;
import hxmc.simd.U8x16;

// Analytic coverage of lines in device pixels (y down), as font-rs and
// tiny-skia's: each line adds its exact signed area to an accumulation
// buffer, a running sum along each row then gives each pixel's coverage
// (non-zero: the winding's magnitude clamped to one; even-odd: folded
// over two).
//
// The lines are kept first (clipped to the columns), with their box; the
// accumulation is the box's alone, in bands of rows small enough to stay
// in the cache, each made when row() first asks for one of its rows. Of a
// row only the columns its lines wrote in are read (lo to hi), and within
// those a block of 16 columns no line wrote in has one coverage throughout
// (the sum carried into it), a run read without its pixels, and one
// written in is read four columns at a time (the sum's steps in a
// vector: single precision, its coverage the same as double's to within
// a level in a few pixels in a million): a small shape
// on a large canvas costs its own size, a thin diagonal stroke its own
// pixels rather than its box's, a large fill its edges and its runs.
// One per canvas, kept: nothing allocated per path once its buffers have
// grown.
final class Raster implements Path.Sink {
	// (the accumulation's size, in values: a band's rows of the box)
	static inline var BUDGET = 32768;

	public final width:Int;
	public final height:Int;

	// the touched region: rows y0...y1, columns x0...x1 (x1 one past, the carry's)
	public var y0(default, null) = 0;
	public var y1(default, null) = 0;
	public var x0(default, null) = 0;
	public var x1(default, null) = 0;

	// row()'s span: the columns of coverage it wrote into out
	public var spanStart(default, null) = 0;
	public var spanEnd(default, null) = 0;
	// row()'s runs of coverage (in its span, those not 0): runCount of
	// start, end, and the coverage throughout (0 to 255) or -1 (each
	// pixel's own, in out)
	public final runs:Vector<Int>;
	public var runCount(default, null) = 0;

	// the lines: ax, ay, bx, by, top to bottom (ay < by), and their winding (1 or -1)
	var lines:Vector<Float>;
	var lineCount = 0;
	// the lines' columns: floor of the least x, ceil of the most
	var minX = 0;
	var maxX = 0;

	// the band: rows bandY0...bandY1, columns from bx (stride a row, the
	// carry's two past the box, to a whole block), each row's columns
	// written (lo to hi, relative to bx), its blocks of 16 written in (a
	// byte each, blocks a row); the accumulation in single floats
	final acc:Bytes;
	var bx = 0;
	var stride = 0;
	var blocks = 0;
	var bandY0 = 0;
	var bandY1 = 0;
	var banded = false;
	final rowLo:Vector<Int>;
	final rowHi:Vector<Int>;
	final marks:Bytes;

	var px = 0.0;
	var py = 0.0;
	var sx = 0.0;
	var sy = 0.0;

	public function new(width:Int, height:Int) {
		this.width = width;
		this.height = height;
		var full = (width + 2) * height, wide = (width + 2 + 15) & ~15;
		var size = full < BUDGET ? full : BUDGET;
		if (size < wide) size = wide;
		acc = Bytes.alloc(size * 4);
		acc.fill(0, size * 4, 0);
		var rows = size < height ? size : height;
		rowLo = new Vector(rows);
		rowHi = new Vector(rows);
		for (i in 0...rows) {
			rowLo[i] = EMPTY;
			rowHi[i] = 0;
		}
		// (a block for every 16 values, and two more a row: its start not aligned, its end)
		marks = Bytes.alloc((size >> 4) + 2 * rows + 2);
		marks.fill(0, marks.length, 0);
		runs = new Vector(3 * (((width + 2) >> 4) + 3));
		lines = new Vector(320);
		reset();
	}

	static inline var EMPTY = 1 << 30;

	public function reset() {
		if (banded) clearBand();
		y0 = height;
		y1 = 0;
		x0 = width;
		x1 = 0;
		lineCount = 0;
		minX = width;
		maxX = 0;
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
	// of them as the same at their right edge (it winds none of them, but
	// what lies left of it may cover every column up to the edge)
	public function line(ax:Float, ay:Float, bx:Float, by:Float) {
		if (ay == by || !(Math.isFinite(ax) && Math.isFinite(ay) && Math.isFinite(bx) && Math.isFinite(by))) return;
		if ((ay <= 0 && by <= 0) || (ay >= height && by >= height)) return;
		if (ax >= 0 && bx >= 0 && ax <= width && bx <= width) {
			add(ax, ay, bx, by);
			return;
		}
		if (ax >= width && bx >= width) {
			add(width, ay, width, by);
			return;
		}
		if (ax <= 0 && bx <= 0) {
			add(0, ay, 0, by);
			return;
		}
		// (split where it crosses an edge, each part again)
		var edge = (ax < 0 || bx < 0) ? 0.0 : width;
		var t = (edge - ax) / (bx - ax), ym = ay + (by - ay) * t;
		line(ax, ay, edge, ym);
		line(edge, ym, bx, by);
	}

	function add(ax:Float, ay:Float, bx:Float, by:Float) {
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
		var i = lineCount * 5;
		if (i + 5 > lines.length) {
			var n = new Vector(lines.length * 2);
			Vector.blit(lines, 0, n, 0, i);
			lines = n;
		}
		lines[i] = ax;
		lines[i + 1] = ay;
		lines[i + 2] = bx;
		lines[i + 3] = by;
		lines[i + 4] = dir;
		lineCount++;
		var ys = ay < 0 ? 0 : Std.int(Math.floor(ay)), ye = by > height ? height : Std.int(Math.ceil(by));
		if (ys < y0) y0 = ys;
		if (ye > y1) y1 = ye;
		var lo = Std.int(Math.floor(ax < bx ? ax : bx)), hi = Std.int(Math.ceil(ax < bx ? bx : ax));
		if (lo < minX) minX = lo;
		if (hi > maxX) maxX = hi;
		if (lo < x0) x0 = lo;
		if (hi + 2 > x1) x1 = hi + 2 > width ? width : hi + 2;
	}

	// the band from row y made: the rows of the last one not read cleared,
	// the lines' parts in its rows accumulated
	function band(y:Int) {
		if (banded) clearBand();
		banded = true;
		bx = minX;
		stride = (maxX - minX + 2 + 15) & ~15;
		blocks = stride >> 4;
		var rows = Std.int((acc.length >> 2) / stride), mrows = Std.int(marks.length / blocks);
		if (mrows < rows) rows = mrows;
		if (rows > rowLo.length) rows = rowLo.length;
		if (rows < 1) rows = 1;
		bandY0 = y;
		bandY1 = y + rows > y1 ? y1 : y + rows;
		var top:Float = bandY0, bottom:Float = bandY1;
		for (i in 0...lineCount) {
			var o = i * 5;
			var ay = lines[o + 1], by = lines[o + 3];
			if (by <= top || ay >= bottom) continue;
			scan(lines[o], ay, lines[o + 2], by, lines[o + 4]);
		}
	}

	// a line's area into the band's rows (ay < by): where it enters and
	// leaves each row, its ends, else from its start along it
	function scan(ax:Float, ay:Float, bx:Float, by:Float, dir:Float) {
		var dxdy = (bx - ax) / (by - ay);
		var y = ay < bandY0 ? bandY0 : Std.int(Math.floor(ay)), yb = by > bandY1 ? bandY1 : Std.int(Math.ceil(by));
		var top:Float = y > ay ? y : ay;
		var x = top == ay ? ax : ax + (top - ay) * dxdy;
		while (y < yb) {
			var bot:Float = y + 1 < by ? y + 1 : by;
			var xnext = bot == by ? bx : ax + (bot - ay) * dxdy;
			cell(y - bandY0, x, xnext, (bot - top) * dir);
			x = xnext;
			top = bot;
			y++;
		}
	}

	// a line's part in band row ri, from x to xnext (each 0 to width, but
	// for rounding), d its rise (signed by its winding)
	inline function cell(ri:Int, x:Float, xnext:Float, d:Float) {
		var row = ri * stride, base = bx;
		var a = x < xnext ? x : xnext, b = x < xnext ? xnext : x;
		if (a < 0) a = 0;
		if (b < 0) b = 0;
		if (a > width) a = width;
		if (b > width) b = width;
		// (floor and ceiling: both at least 0)
		var a0 = Std.int(a), b1 = Std.int(b);
		if (b1 < b) b1++;
		var a0f:Float = a0, b1c:Float = b1;
		var c0 = a0 - base;
		var e = b1 <= a0 + 1 ? c0 + 2 : b1 - base + 1;
		if (c0 < rowLo[ri]) rowLo[ri] = c0;
		if (e > rowHi[ri]) rowHi[ri] = e;
		var mb = ri * blocks, k0 = c0 >> 4, k1 = (e - 1) >> 4;
		marks.set(mb + k0, 1);
		if (k1 != k0)
			for (k in k0 + 1...k1 + 1)
				marks.set(mb + k, 1);
		if (b1 <= a0 + 1) {
			var xm = 0.5 * (a + b) - a0f;
			put(row + c0, d - d * xm);
			put(row + c0 + 1, d * xm);
		} else {
			var s = 1 / (b - a);
			var af = a - a0f;
			var q0 = 0.5 * s * (1 - af) * (1 - af);
			var bf = b - b1c + 1;
			var cm = 0.5 * s * bf * bf;
			var c1 = b1 - base;
			put(row + c0, d * q0);
			if (b1 == a0 + 2) put(row + c0 + 1, d * (1 - q0 - cm)) else {
				var q1 = s * (1.5 - af);
				put(row + c0 + 1, d * (q1 - q0));
				for (xi in c0 + 2...c1 - 1)
					put(row + xi, d * s);
				var q2 = q1 + (b1 - a0 - 3) * s;
				put(row + c1 - 1, d * (1 - q2 - cm));
			}
			put(row + c1, d * cm);
		}
	}

	inline function put(i:Int, v:Float) {
		var p = i << 2;
		acc.setFloat(p, acc.getFloat(p) + v);
	}

	// row y's coverage (0 to 255) into out[spanStart...spanEnd], the
	// columns its lines wrote in (none before them: their coverage is 0;
	// past them the winding is back to 0 for a closed outline), as runs
	// too (runs, runCount), its accumulation cleared. Rows are read top to
	// bottom (one skipped is not read again).
	public function row(y:Int, out:Bytes, evenOdd:Bool) {
		runCount = 0;
		spanStart = spanEnd = 0;
		if (y < y0 || y >= y1 || lineCount == 0) return;
		if (!banded || y < bandY0 || y >= bandY1) band(y);
		var ri = y - bandY0;
		var a = rowLo[ri], b = rowHi[ri];
		rowLo[ri] = EMPTY;
		rowHi[ri] = 0;
		if (b <= a) return;
		var base = bx, r = ri * stride, mb = ri * blocks;
		// (the columns past the canvas not read)
		var e = b + base > width ? width - base : b, sum = 0.0;
		var x = a, n = 0, count = 0, rs = runs;
		var zero = F32x4.zero(), one = F32x4.splat(1), two = F32x4.splat(2), half = F32x4.splat(0.5), full = F32x4.splat(255);
		while (x < e) {
			var blk = x >> 4, end = (blk + 1) << 4;
			if (end > e) end = e;
			var ox = base + x, oend = base + end;
			if (marks.get(mb + blk) != 0) {
				// (written in: each pixel's own, the whole block four at a
				// time, the sum's steps added across each four, its columns
				// before x 0 and those past e not read)
				marks.set(mb + blk, 0);
				var p = (r + (blk << 4)) << 2, o = base + (blk << 4);
				var carry = F32x4.splat(sum);
				for (q in 0...4) {
					var v = F32x4.load(acc, p);
					zero.store(acc, p);
					v = v + v.shuffle(zero, 4, 0, 1, 2);
					v = v + v.shuffle(zero, 4, 5, 0, 1);
					v = v + carry;
					carry = v.swizzle(3, 3, 3, 3);
					var c = v.abs();
					// (even-odd: folded over two)
					if (evenOdd) {
						c = c - (c * half).floor() * two;
						c = c.min(two - c);
					}
					var k = (c.min(one) * full + half).toI32x4();
					var k16 = I16x8.narrow(k, k);
					U8x16.narrow(k16, k16).store32(out, o);
					p += 16;
					o += 4;
				}
				sum = carry.get(0);
				if (n > 0 && rs[n - 1] == -1 && rs[n - 2] == ox) rs[n - 2] = oend else {
					rs[n] = ox;
					rs[n + 1] = oend;
					rs[n + 2] = -1;
					n += 3;
					count++;
				}
			} else {
				// (no line in it: the sum carried in throughout)
				var k = evenOdd ? oddCoverage(sum) : coverage(sum);
				out.fill(ox, oend - ox, k);
				if (k != 0) {
					if (n > 0 && rs[n - 1] == k && rs[n - 2] == ox) rs[n - 2] = oend else {
						rs[n] = ox;
						rs[n + 1] = oend;
						rs[n + 2] = k;
						n += 3;
						count++;
					}
				}
			}
			x = end;
		}
		// (the columns past the canvas: cleared)
		if (e < a) e = a;
		clearRow(r, mb, e, b);
		runCount = count;
		spanStart = base + a;
		spanEnd = base + e;
	}

	inline function clearRow(r:Int, mb:Int, a:Int, b:Int) {
		if (b > a) {
			acc.fill((r + a) << 2, (b - a) << 2, 0);
			for (k in a >> 4...((b - 1) >> 4) + 1)
				marks.set(mb + k, 0);
		}
	}

	static inline function coverage(sum:Float):Int {
		var c = sum < 0 ? -sum : sum;
		return c >= 1 ? 255 : Std.int(c * 255 + 0.5);
	}

	static inline function oddCoverage(sum:Float):Int {
		var c = (sum < 0 ? -sum : sum) % 2;
		if (c > 1) c = 2 - c;
		return c >= 1 ? 255 : Std.int(c * 255 + 0.5);
	}

	// (the band's rows not read cleared)
	function clearBand() {
		for (ri in 0...bandY1 - bandY0) {
			clearRow(ri * stride, ri * blocks, rowLo[ri], rowHi[ri]);
			rowLo[ri] = EMPTY;
			rowHi[ri] = 0;
		}
		banded = false;
	}

	// every touched row cleared without reading it
	public function discard() {
		reset();
	}
}
