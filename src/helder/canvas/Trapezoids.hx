package helder.canvas;

import haxe.ds.Vector;

// A path's inside as trapezoids that do not overlap (the GPU back end's
// tessellation, as pixman's and Cairo's): its lines (a Sink: a flattened
// path, any transform's units) cut into bands between every end and every
// crossing, each band's spans between edges by the fill rule (non-zero or
// even-odd), each span a trapezoid of two horizontal sides and two edges.
// The trapezoids tile the inside exactly, so their coverages add up: any
// fill rule, self-intersections and holes included. Kept and reset: its
// buffers grow to the largest path.
final class Trapezoids implements Path.Sink {
	// the edges: x0, y0, x1, y1 (y0 < y1), winding (+1 or -1)
	var edges:Vector<Float> = new Vector(256);
	var edgeCount = 0;
	// the trapezoids: top, bottom, top's left and right x, bottom's left and right x
	public var traps(default, null):Vector<Float> = new Vector(256);
	public var count(default, null) = 0;

	var ys:Array<Float> = [];
	var active:Array<Int> = [];
	var xa:Array<Float> = [];
	var xb:Array<Float> = [];
	var order:Array<Int> = [];

	var px = 0.0;
	var py = 0.0;
	var sx = 0.0;
	var sy = 0.0;

	public function new() {}

	public function reset() {
		edgeCount = 0;
		count = 0;
	}

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
		if (y0 == y1 || !Math.isFinite(x0 + y0 + x1 + y1)) return;
		var w = 1.0;
		if (y0 > y1) {
			var t = x0;
			x0 = x1;
			x1 = t;
			t = y0;
			y0 = y1;
			y1 = t;
			w = -1;
		}
		if ((edgeCount + 1) * 5 > edges.length) {
			var n = new Vector<Float>(edges.length * 2);
			Vector.blit(edges, 0, n, 0, edgeCount * 5);
			edges = n;
		}
		var o = edgeCount * 5;
		edges[o] = x0;
		edges[o + 1] = y0;
		edges[o + 2] = x1;
		edges[o + 3] = y1;
		edges[o + 4] = w;
		edgeCount++;
	}

	inline function xAt(e:Int, y:Float):Float {
		var o = e * 5, y0 = edges[o + 1], y1 = edges[o + 3];
		return edges[o] + (edges[o + 2] - edges[o]) * (y - y0) / (y1 - y0);
	}

	// the edges added cut into trapezoids by the rule
	public function build(evenOdd:Bool) {
		count = 0;
		ys.resize(0);
		for (e in 0...edgeCount) {
			ys.push(edges[e * 5 + 1]);
			ys.push(edges[e * 5 + 3]);
		}
		ys.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var k = 0;
		while (k < ys.length - 1) {
			var ya = ys[k], yb = ys[k + 1];
			k++;
			if (yb <= ya + 1e-12) continue;
			band(ya, yb, evenOdd);
		}
	}

	function band(ya:Float, yb:Float, evenOdd:Bool) {
		// (the edges across it, by x at its top, then at its bottom)
		active.resize(0);
		for (e in 0...edgeCount)
			if (edges[e * 5 + 1] <= ya && edges[e * 5 + 3] >= yb) active.push(e);
		if (active.length < 2) return;
		while (true) {
			xa.resize(0);
			xb.resize(0);
			for (e in active) {
				xa.push(xAt(e, ya));
				xb.push(xAt(e, yb));
			}
			order.resize(0);
			for (i in 0...active.length)
				order.push(i);
			order.sort((i, j) -> {
				// (edges meeting at the top, a crossing's split: by their bottoms)
				var d = xa[i] - xa[j];
				if (Math.abs(d) < 1e-6 * (1 + Math.abs(xa[i]))) d = xb[i] - xb[j];
				return d < 0 ? -1 : d > 0 ? 1 : 0;
			});
			// (two neighbours whose order changes cross inside: the band split at the first crossing)
			var cut = yb;
			for (n in 0...order.length - 1) {
				var i = order[n], j = order[n + 1];
				if (xb[i] > xb[j] + 1e-9) {
					var d0 = xa[j] - xa[i], d1 = xb[j] - xb[i];
					var t = d0 / (d0 - d1), yc = ya + (yb - ya) * t;
					if (yc > ya + 1e-9 && yc < cut) cut = yc;
				}
			}
			if (cut < yb) {
				spans(ya, cut, evenOdd);
				ya = cut;
				continue;
			}
			spans(ya, yb, evenOdd);
			return;
		}
	}

	// (the band's spans: order and the x's as band set them, at ya...yb)
	function spans(ya:Float, yb:Float, evenOdd:Bool) {
		// (the x's at this band's own ends: it may be a part of the one the order was made for)
		var wind = 0.0, left = -1;
		for (n in 0...order.length) {
			var i = order[n], e = active[i];
			var before = evenOdd ? (Std.int(Math.abs(wind)) & 1) != 0 : wind != 0;
			wind += edges[e * 5 + 4];
			var after = evenOdd ? (Std.int(Math.abs(wind)) & 1) != 0 : wind != 0;
			if (!before && after) left = e else if (before && !after && left >= 0) {
				emit(ya, yb, xAt(left, ya), xAt(e, ya), xAt(left, yb), xAt(e, yb));
				left = -1;
			}
		}
	}

	function emit(ya:Float, yb:Float, tl:Float, tr:Float, bl:Float, br:Float) {
		if ((count + 1) * 6 > traps.length) {
			var n = new Vector<Float>(traps.length * 2);
			Vector.blit(traps, 0, n, 0, count * 6);
			traps = n;
		}
		var o = count * 6;
		traps[o] = ya;
		traps[o + 1] = yb;
		traps[o + 2] = tl;
		traps[o + 3] = tr;
		traps[o + 4] = bl;
		traps[o + 5] = br;
		count++;
	}

	// the trapezoids' area (a check: the path's area by its rule)
	public function area():Float {
		var a = 0.0;
		for (k in 0...count) {
			var o = k * 6;
			a += ((traps[o + 3] - traps[o + 2]) + (traps[o + 5] - traps[o + 4])) / 2 * (traps[o + 1] - traps[o]);
		}
		return a;
	}
}
