package helder.canvas;

// Boolean operations on paths (union, intersect, difference, xor) and
// simplify: both paths flattened (within tolerance), their edges swept
// into bands between every end and crossing (as Trapezoids), each band's
// spans inside by the operation on the two paths' insides (each by its own
// fill rule), then the result's outline: the spans' sides and the pieces of
// band boundaries where inside changes, chained into closed contours
// (outer ones clockwise in y-down units, holes the other way: non-zero
// and even-odd fill them alike), collinear points dropped. The result is
// polygonal: curves come back as their flattening.
class PathOps {
	public static inline var UNION = 0;
	public static inline var INTERSECT = 1;
	public static inline var DIFFERENCE = 2;
	public static inline var XOR = 3;

	public static function union(a:Path, b:Path, tolerance = 0.05):Path
		return op(a, false, b, false, UNION, tolerance);

	public static function intersect(a:Path, b:Path, tolerance = 0.05):Path
		return op(a, false, b, false, INTERSECT, tolerance);

	public static function difference(a:Path, b:Path, tolerance = 0.05):Path
		return op(a, false, b, false, DIFFERENCE, tolerance);

	public static function xor(a:Path, b:Path, tolerance = 0.05):Path
		return op(a, false, b, false, XOR, tolerance);

	// the path's inside by its rule as non-overlapping contours
	public static function simplify(a:Path, evenOdd = false, tolerance = 0.05):Path
		return op(a, evenOdd, null, false, UNION, tolerance);

	public static function op(a:Path, aEvenOdd:Bool, b:Null<Path>, bEvenOdd:Bool, kind:Int, tolerance = 0.05):Path {
		var s = new Sweep();
		s.source = 0;
		a.flatten(s, Matrix.IDENTITY, tolerance);
		if (b != null) {
			s.source = 1;
			b.flatten(s, Matrix.IDENTITY, tolerance);
		}
		s.run(aEvenOdd, bEvenOdd, kind);
		return s.outline();
	}
}

// (the sweep: edges x0, y0, x1, y1 (y0 < y1), winding, source)
private class Sweep implements Path.Sink {
	public var source = 0;

	final e:Array<Float> = [];
	var px = 0.0;
	var py = 0.0;
	var sx = 0.0;
	var sy = 0.0;
	// the result's segments: x0, y0, x1, y1 (inside on their right in y-down units)
	final segs:Array<Float> = [];

	public function new() {}

	public function moveTo(x:Float, y:Float) {
		px = sx = x;
		py = sy = y;
	}

	public function lineTo(x:Float, y:Float) {
		edge(px, py, x, y);
		px = x;
		py = y;
	}

	public function close() {
		edge(px, py, sx, sy);
		px = sx;
		py = sy;
	}

	function edge(x0:Float, y0:Float, x1:Float, y1:Float) {
		// (ends a hair apart made one: bands then meet exactly)
		y0 = Math.fround(y0 * 1048576) / 1048576;
		y1 = Math.fround(y1 * 1048576) / 1048576;
		if (y0 == y1) return;
		if (y0 < y1) e.push(x0) + e.push(y0) + e.push(x1) + e.push(y1) + e.push(1) + e.push(source);
		else e.push(x1) + e.push(y1) + e.push(x0) + e.push(y0) + e.push(-1) + e.push(source);
	}

	inline function xAt(k:Int, y:Float):Float {
		var o = k * 6;
		return e[o] + (e[o + 2] - e[o]) * (y - e[o + 1]) / (e[o + 3] - e[o + 1]);
	}

	// the bands' spans: [ya, yb, then per span left top x, left bottom x, right top x, right bottom x]
	final bands:Array<Array<Float>> = [];

	public function run(aEvenOdd:Bool, bEvenOdd:Bool, kind:Int) {
		var n = Std.int(e.length / 6);
		var ys = [];
		for (k in 0...n) {
			ys.push(e[k * 6 + 1]);
			ys.push(e[k * 6 + 3]);
		}
		ys.sort((p, q) -> p < q ? -1 : p > q ? 1 : 0);
		var k = 0;
		while (k < ys.length - 1) {
			var ya = ys[k], yb = ys[k + 1];
			k++;
			if (yb <= ya) continue;
			var active = [for (j in 0...n) if (e[j * 6 + 1] <= ya && e[j * 6 + 3] >= yb) j];
			while (true) {
				var xa = [for (j in active) xAt(j, ya)], xb = [for (j in active) xAt(j, yb)];
				var order = [for (i in 0...active.length) i];
				order.sort((i, j) -> {
					var d = xa[i] - xa[j];
					if (Math.abs(d) < 1e-6 * (1 + Math.abs(xa[i]))) d = xb[i] - xb[j];
					return d < 0 ? -1 : d > 0 ? 1 : 0;
				});
				var cut = yb;
				for (m in 0...order.length - 1) {
					var i = order[m], j = order[m + 1];
					if (xb[i] > xb[j] + 1e-9) {
						var d0 = xa[j] - xa[i], d1 = xb[j] - xb[i];
						var yc = ya + (yb - ya) * (d0 / (d0 - d1));
						if (yc > ya + 1e-9 && yc < cut) cut = yc;
					}
				}
				band(ya, cut, active, order, aEvenOdd, bEvenOdd, kind);
				if (cut >= yb) break;
				ya = cut;
			}
		}
		boundaries();
	}

	function band(ya:Float, yb:Float, active:Array<Int>, order:Array<Int>, aEO:Bool, bEO:Bool, kind:Int) {
		var wa = 0, wb = 0, inside = false, left = -1;
		var spans = [ya, yb];
		for (m in 0...order.length) {
			var j = active[order[m]];
			if (e[j * 6 + 5] == 0) wa += Std.int(e[j * 6 + 4]) else wb += Std.int(e[j * 6 + 4]);
			var ia = aEO ? (wa & 1) != 0 : wa != 0, ib = bEO ? (wb & 1) != 0 : wb != 0;
			var now = switch kind {
				case PathOps.INTERSECT: ia && ib;
				case PathOps.DIFFERENCE: ia && !ib;
				case PathOps.XOR: ia != ib;
				case _: ia || ib;
			}
			if (now && !inside) left = j else if (!now && inside) {
				var lt = xAt(left, ya), lb = xAt(left, yb), rt = xAt(j, ya), rb = xAt(j, yb);
				// (spans that touch the one before it joined: no side between them)
				if (spans.length > 2 && Math.abs(spans[spans.length - 2] - lt) < 1e-9 && Math.abs(spans[spans.length - 1] - lb) < 1e-9) {
					spans[spans.length - 2] = rt;
					spans[spans.length - 1] = rb;
				} else
					for (v in [lt, lb, rt, rb])
						spans.push(v);
			}
			inside = now;
		}
		bands.push(spans);
	}

	// each span's sides (left going up, right going down: inside on their right in y-down), and the
	// horizontal pieces between bands where inside changes
	function boundaries() {
		var prevY = Math.NaN, prev:Array<Array<Float>> = [];
		for (b in bands) {
			var ya = b[0], yb = b[1];
			var s = Std.int((b.length - 2) / 4);
			for (k in 0...s) {
				var o = 2 + k * 4;
				seg(b[o + 1], yb, b[o], ya);
				seg(b[o + 2], ya, b[o + 3], yb);
			}
			// (the boundary at ya: the bottoms of the band above (prev, if it ends at ya) against these tops)
			var above = prevY == ya ? prev : [];
			var below = [for (k in 0...s) [b[2 + k * 4], b[4 + k * 4]]];
			horizontal(ya, above, below);
			prev = [for (k in 0...s) [b[3 + k * 4], b[5 + k * 4]]];
			prevY = yb;
			// (a band that is not followed at its bottom: its bottoms close it)
			var next = bands.indexOf(b) + 1;
			if (next >= bands.length || bands[next][0] != yb) {
				horizontal(yb, prev, []);
				prev = [];
			}
		}
	}

	// intervals above and below at y: where only one side is inside, a segment
	function horizontal(y:Float, up:Array<Array<Float>>, below:Array<Array<Float>>) {
		// (the breakpoints, each piece between two inside above or below)
		var xs = [];
		for (i in up) {
			xs.push(i[0]);
			xs.push(i[1]);
		}
		for (i in below) {
			xs.push(i[0]);
			xs.push(i[1]);
		}
		xs.sort((p, q) -> p < q ? -1 : p > q ? 1 : 0);
		inline function within(list:Array<Array<Float>>, x:Float):Bool {
			var r = false;
			for (i in list)
				if (x > i[0] && x < i[1]) r = true;
			return r;
		}
		for (k in 0...xs.length - 1) {
			var x0 = xs[k], x1 = xs[k + 1];
			if (x1 - x0 < 1e-9) continue;
			var mid = (x0 + x1) / 2, u = within(up, mid), d = within(below, mid);
			// (inside below only: the top of a region, going right; above only: a bottom, going left)
			if (d && !u) seg(x0, y, x1, y) else if (u && !d) seg(x1, y, x0, y);
		}
	}

	inline function seg(x0:Float, y0:Float, x1:Float, y1:Float) {
		if (Math.abs(x0 - x1) < 1e-12 && Math.abs(y0 - y1) < 1e-12) return;
		segs.push(x0);
		segs.push(y0);
		segs.push(x1);
		segs.push(y1);
	}

	// the segments chained end to start into closed contours
	public function outline():Path {
		var n = Std.int(segs.length / 4);
		inline function key(x:Float, y:Float):String
			return Math.round(x * 1e6) + "," + Math.round(y * 1e6);
		var starts = new Map<String, Array<Int>>();
		for (k in 0...n) {
			var kk = key(segs[k * 4], segs[k * 4 + 1]);
			if (!starts.exists(kk)) starts.set(kk, []);
			starts.get(kk).push(k);
		}
		var used = [for (_ in 0...n) false];
		var out = new Path();
		for (k0 in 0...n) {
			if (used[k0]) continue;
			var xs = [], ys = [];
			var k = k0;
			while (k >= 0 && !used[k]) {
				used[k] = true;
				xs.push(segs[k * 4]);
				ys.push(segs[k * 4 + 1]);
				var list = starts.get(key(segs[k * 4 + 2], segs[k * 4 + 3]));
				k = -1;
				if (list != null)
					for (c in list)
						if (!used[c]) {
							k = c;
							break;
						}
			}
			// (collinear points dropped)
			var m = xs.length;
			if (m < 3) continue;
			var first = true;
			for (i in 0...m) {
				var ax = xs[(i + m - 1) % m], ay = ys[(i + m - 1) % m], bx = xs[i], by = ys[i], cx = xs[(i + 1) % m], cy = ys[(i + 1) % m];
				var cross = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
				if (Math.abs(cross) < 1e-9 * (1 + Math.abs(bx) + Math.abs(by))) continue;
				if (first) out.moveTo(bx, by) else out.lineTo(bx, by);
				first = false;
			}
			if (!first) out.close();
		}
		return out;
	}
}
