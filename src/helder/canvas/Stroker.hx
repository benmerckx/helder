package helder.canvas;

import helder.canvas.Path.Sink;
import helder.canvas.Stroke;

// A stroke's outline (grown from helder.ui's SVG stroker): each subpath
// flattened in the path's units, each side offset by half the width,
// joined on the outer side of a turn by the stroke's join and through the
// point on the inner side (the overlap wound the same way, so non-zero
// fills it once), the open ends capped, the dashes cut first; a closed
// subpath's two sides as loops wound against each other. The outline's
// points go through the transform into a sink (the rasterizer: device
// pixels; Winding: isPointInStroke). Its buffers are kept: nothing
// allocated per stroke once they have grown.
final class Stroker {
	public var halfWidth(default, null) = 0.5;
	public var miterLimit(default, null) = 10.0;

	var join:JoinStyle = Join.miter;
	var cap:CapStyle = Cap.butt;
	var m:Matrix = Matrix.IDENTITY;
	var sink:Sink;
	// the flattening tolerance in the path's units
	var tolerance = 0.1;

	// the subpath's points, its dashes', the segments' directions, the outline
	final xs:Array<Float> = [];
	final ys:Array<Float> = [];
	final cx:Array<Float> = [];
	final cy:Array<Float> = [];
	final dx:Array<Float> = [];
	final dy:Array<Float> = [];
	final len:Array<Float> = [];
	final ox:Array<Float> = [];
	final oy:Array<Float> = [];
	final px:Array<Float> = [];
	final py:Array<Float> = [];

	var dash:Null<Dash> = null;
	var dots = true;
	// the subpath's own directions at its start and end (a curve's tangent, not its first or last chord's)
	var t0x = 0.0;
	var t0y = 0.0;
	var t1x = 0.0;
	var t1y = 0.0;
	var tangents = false;
	// (the ends' offsets and caps by those directions)
	var exact = false;

	public function new() {}

	// path stroked by style, its outline through m into sink; tolerance in
	// the sink's units
	public function stroke(path:Path, style:Stroke, m:Matrix, sink:Sink, tolerance = 0.1) {
		halfWidth = style.width / 2;
		miterLimit = style.miterLimit;
		join = style.join;
		cap = style.cap;
		dots = style.dots;
		dash = style.dash != null && style.dash.valid() ? style.dash : null;
		this.m = m;
		this.sink = sink;
		var s = m.maxScale();
		this.tolerance = tolerance / (s > 0 ? s : 1);
		walk(path);
	}

	function walk(p:Path) {
		var pts = p.points, pi = 0, closed = false;
		xs.resize(0);
		ys.resize(0);
		for (i in 0...p.verbCount)
			switch p.verbs[i] {
				case Path.MOVE:
					if (xs.length > 0) subpath(false);
					xs.resize(0);
					ys.resize(0);
					xs.push(pts[pi]);
					ys.push(pts[pi + 1]);
					tangents = false;
					pi += 2;
				case Path.LINE:
					var x0 = xs[xs.length - 1], y0 = ys[ys.length - 1];
					tangent(pts[pi] - x0, pts[pi + 1] - y0, pts[pi] - x0, pts[pi + 1] - y0);
					xs.push(pts[pi]);
					ys.push(pts[pi + 1]);
					pi += 2;
				case Path.QUAD:
					var x0 = xs[xs.length - 1], y0 = ys[ys.length - 1];
					var x1 = pts[pi], y1 = pts[pi + 1], x2 = pts[pi + 2], y2 = pts[pi + 3];
					if (x1 == x0 && y1 == y0 || x1 == x2 && y1 == y2) tangent(x2 - x0, y2 - y0, x2 - x0, y2 - y0) else tangent(x1 - x0, y1 - y0, x2 - x1, y2 - y1);
					var ddx = x0 - 2 * x1 + x2, ddy = y0 - 2 * y1 + y2;
					var n = 1 + Std.int(Math.sqrt(Math.sqrt(ddx * ddx + ddy * ddy) / (4 * tolerance)));
					if (n > 1000) n = 1000;
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						xs.push(u * u * x0 + 2 * u * t * x1 + t * t * x2);
						ys.push(u * u * y0 + 2 * u * t * y1 + t * t * y2);
					}
					pi += 4;
				case Path.CUBIC:
					var x0 = xs[xs.length - 1], y0 = ys[ys.length - 1];
					var x1 = pts[pi], y1 = pts[pi + 1], x2 = pts[pi + 2], y2 = pts[pi + 3], x3 = pts[pi + 4], y3 = pts[pi + 5];
					var sx = x1 - x0, sy = y1 - y0;
					if (sx == 0 && sy == 0) {
						sx = x2 - x0;
						sy = y2 - y0;
					}
					if (sx == 0 && sy == 0) {
						sx = x3 - x0;
						sy = y3 - y0;
					}
					var ex = x3 - x2, ey = y3 - y2;
					if (ex == 0 && ey == 0) {
						ex = x3 - x1;
						ey = y3 - y1;
					}
					if (ex == 0 && ey == 0) {
						ex = x3 - x0;
						ey = y3 - y0;
					}
					tangent(sx, sy, ex, ey);
					var ax = x0 - 2 * x1 + x2, ay = y0 - 2 * y1 + y2, bx = x1 - 2 * x2 + x3, by = y1 - 2 * y2 + y3;
					var dev = Math.sqrt(Math.max(ax * ax + ay * ay, bx * bx + by * by));
					var n = 1 + Std.int(Math.sqrt(dev * 0.75 / tolerance));
					if (n > 1000) n = 1000;
					for (k in 1...n + 1) {
						var t = k / n, u = 1 - t;
						var a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
						xs.push(a * x0 + b * x1 + c * x2 + d * x3);
						ys.push(a * y0 + b * y1 + c * y2 + d * y3);
					}
					pi += 6;
				case _:
					if (xs.length > 0) subpath(true);
					xs.resize(0);
					ys.resize(0);
			}
		// (a subpath of a lone point: a dot for round and square caps; Canvas 2D's moveTo alone draws none)
		if (xs.length > 1) subpath(false);
	}

	// (a segment's directions at its ends: the subpath's start's if it is the first, its end's)
	function tangent(sx:Float, sy:Float, ex:Float, ey:Float) {
		var sl = Math.sqrt(sx * sx + sy * sy), el = Math.sqrt(ex * ex + ey * ey);
		if (sl == 0 || el == 0) return;
		if (!tangents) {
			t0x = sx / sl;
			t0y = sy / sl;
			tangents = true;
		}
		t1x = ex / el;
		t1y = ey / el;
	}

	function subpath(closed:Bool) {
		if (dash == null) {
			exact = tangents;
			outline(xs, ys, closed, dots);
			exact = false;
		} else
			dashed(closed);
	}

	// the dashes along the subpath (from its start, at the offset into the
	// pattern), each stroked as an open subpath
	function dashed(closed:Bool) {
		px.resize(0);
		py.resize(0);
		for (i in 0...xs.length) {
			px.push(xs[i]);
			py.push(ys[i]);
		}
		if (closed) {
			px.push(xs[0]);
			py.push(ys[0]);
		}
		var d = dash.intervals, n = d.length;
		var pos = dash.offset % dash.total;
		if (pos < 0) pos += dash.total;
		var k = 0;
		// (a dash ending where the offset puts the start is past; a zero length one there is not)
		while (pos > d[k] || (pos == d[k] && d[k] > 0)) {
			pos -= d[k];
			k = (k + 1) % n;
		}
		var remain = d[k] - pos, on = k % 2 == 0;
		cx.resize(0);
		cy.resize(0);
		if (on) {
			cx.push(px[0]);
			cy.push(py[0]);
		}
		for (i in 0...px.length - 1) {
			var ax = px[i], ay = py[i], sx = px[i + 1] - ax, sy = py[i + 1] - ay, l = Math.sqrt(sx * sx + sy * sy), done = 0.0;
			while (l - done > remain) {
				done += remain;
				var x = ax + sx * done / l, y = ay + sy * done / l;
				cx.push(x);
				cy.push(y);
				if (on) outline(cx, cy, false, true);
				cx.resize(0);
				cy.resize(0);
				if (!on) {
					cx.push(x);
					cy.push(y);
				}
				on = !on;
				k = (k + 1) % n;
				remain = d[k];
			}
			remain -= l - done;
			if (on) {
				cx.push(px[i + 1]);
				cy.push(py[i + 1]);
			}
		}
		if (on && cx.length > 0) outline(cx, cy, false, true);
	}

	function outline(xs0:Array<Float>, ys0:Array<Float>, closed:Bool, dot:Bool) {
		// (points that repeat dropped, in place into dx/dy's spare: px, py are the dash's input, so use len as scratch)
		var n = 0;
		for (k in 0...xs0.length)
			if (n == 0 || Math.abs(xs0[k] - xs0[n - 1]) > 1e-9 || Math.abs(ys0[k] - ys0[n - 1]) > 1e-9) {
				xs0[n] = xs0[k];
				ys0[n] = ys0[k];
				n++;
			}
		if (closed && n > 1 && Math.abs(xs0[0] - xs0[n - 1]) <= 1e-9 && Math.abs(ys0[0] - ys0[n - 1]) <= 1e-9) n--;
		var xs = xs0, ys = ys0;
		if (n == 0) return;
		if (n == 1) {
			if (dot) cap.dot(this, xs[0], ys[0]);
			return;
		}
		// (a closed subpath of two points: one loop, joined at both ends, as Canvas 2D's strokeRect of no height)
		var loops = closed && n == 2 ? 1 : 2;
		var segs = closed ? n : n - 1;
		dx.resize(0);
		dy.resize(0);
		len.resize(0);
		for (k in 0...segs) {
			var b = (k + 1) % n, ex = xs[b] - xs[k], ey = ys[b] - ys[k], l = Math.sqrt(ex * ex + ey * ey);
			dx.push(ex / l);
			dy.push(ey / l);
			len.push(l);
		}
		var hw = halfWidth;
		if (closed) {
			for (side in 0...loops) {
				var s = side == 0 ? 1.0 : -1.0;
				for (k in 0...n) {
					var pk = (k + n - 1) % n;
					joinAt(xs[k], ys[k], dx[pk], dy[pk], dx[k], dy[k], s, len[pk], len[k]);
				}
				// (the right side backwards: the loops wound against each other)
				if (s < 0) {
					ox.reverse();
					oy.reverse();
				}
				emit();
			}
			return;
		}
		// left side forwards, the end's cap, right side backwards, the start's cap
		// (at the ends the subpath's own directions: a curve's tangent there)
		var sx = exact ? t0x : dx[0], sy = exact ? t0y : dy[0], ex = exact ? t1x : dx[segs - 1], ey = exact ? t1y : dy[segs - 1];
		point(xs[0] - sy * hw, ys[0] + sx * hw);
		for (k in 1...n - 1)
			joinAt(xs[k], ys[k], dx[k - 1], dy[k - 1], dx[k], dy[k], 1, len[k - 1], len[k]);
		capAt(xs[n - 1], ys[n - 1], ex, ey);
		var k = n - 2;
		while (k >= 1) {
			joinAt(xs[k], ys[k], -dx[k], -dy[k], -dx[k - 1], -dy[k - 1], 1, len[k], len[k - 1]);
			k--;
		}
		capAt(xs[0], ys[0], -sx, -sy);
		emit();
	}

	public inline function point(x:Float, y:Float) {
		ox.push(x);
		oy.push(y);
	}

	// the outline so far, closed, into the sink
	public function emit() {
		if (ox.length > 2) {
			sink.moveTo(m.mapX(ox[0], oy[0]), m.mapY(ox[0], oy[0]));
			for (k in 1...ox.length)
				sink.lineTo(m.mapX(ox[k], oy[k]), m.mapY(ox[k], oy[k]));
			sink.close();
		}
		ox.resize(0);
		oy.resize(0);
	}

	// the side s (1: left, -1: right) at (x, y) between the directions in
	// and out, of segments lenIn and lenOut long
	function joinAt(x:Float, y:Float, ix:Float, iy:Float, jx:Float, jy:Float, s:Float, lenIn:Float, lenOut:Float) {
		var hw = halfWidth;
		var ax = x - iy * hw * s, ay = y + ix * hw * s, bx = x - jy * hw * s, by = y + jx * hw * s;
		var cross = ix * jy - iy * jx, dot = ix * jx + iy * jy;
		if (Math.abs(cross) < 1e-9 && dot > 0) {
			point(ax, ay);
			return;
		}
		// (a turn toward this side: the inner one; where the sides cross when
		// that is within both segments, else through the point)
		if (cross * s > 0) {
			var cosHalf = Math.sqrt(Math.max(0, (1 + dot) / 2)), sinHalf = Math.sqrt(Math.max(0, (1 - dot) / 2));
			if (cosHalf > 1e-9 && hw * sinHalf / cosHalf <= Math.min(lenIn, lenOut)) {
				var mx = -iy - jy, my = ix + jx, ml = Math.sqrt(mx * mx + my * my);
				var l = hw / cosHalf;
				point(x + mx / ml * l * s, y + my / ml * l * s);
				return;
			}
			point(ax, ay);
			point(x, y);
			point(bx, by);
			return;
		}
		point(ax, ay);
		join.outer(this, x, y, ax, ay, bx, by, ix, iy, jx, jy, s, cross, dot);
		point(bx, by);
	}

	function capAt(x:Float, y:Float, dx:Float, dy:Float) {
		var hw = halfWidth;
		var lx = x - dy * hw, ly = y + dx * hw, rx = x + dy * hw, ry = y - dx * hw;
		point(lx, ly);
		cap.end(this, x, y, lx, ly, rx, ry, dx, dy);
		point(rx, ry);
	}

	// the points of an arc of the stroke's radius around (x, y), from the
	// angle from, turning by turn (its ends not included)
	public function arcPoints(x:Float, y:Float, from:Float, turn:Float) {
		var hw = halfWidth;
		var step = hw > tolerance ? 2 * Math.acos(1 - tolerance / hw) : Math.PI / 2;
		var steps = Std.int(Math.ceil(Math.abs(turn) / step));
		// (the points a little outside the circle: the chords as much outside it as in)
		var r = steps > 0 ? hw * (1 + 1 / Math.cos(Math.abs(turn) / steps / 2)) / 2 : hw;
		for (k in 1...steps) {
			var t = from + turn * k / steps;
			point(x + Math.cos(t) * r, y + Math.sin(t) * r);
		}
	}
}
