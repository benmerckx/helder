package helder.canvas;

import haxe.ds.Vector;

// A path: subpaths of lines, quadratic and cubic Bézier curves, each
// closed or open, in its own units. Arcs, ellipses and rounded rectangles
// are added as cubic curves (a quarter turn at most each, as Skia and
// Chromium's), with Canvas 2D's rules for where a subpath starts: a line
// with no subpath begins one, an arc draws a line to its start, a closed
// subpath's next segment starts where it began. Its verbs and points are
// in two buffers it keeps: clear() and adding again allocate nothing once
// they are large enough.
final class Path implements Sink {
	public static inline var MOVE = 0;
	public static inline var LINE = 1;
	public static inline var QUAD = 2;
	public static inline var CUBIC = 3;
	public static inline var CLOSE = 4;

	public var verbs(default, null):Vector<Int>;
	public var points(default, null):Vector<Float>;
	public var verbCount(default, null) = 0;
	public var pointCount(default, null) = 0;

	// the pen, the subpath's start, whether a subpath is open (a move made),
	// whether the next segment starts a subpath at the start (after a close)
	var penX = 0.0;
	var penY = 0.0;
	var startX = 0.0;
	var startY = 0.0;
	var open = false;
	var pending = false;

	public function new() {
		verbs = new Vector(16);
		points = new Vector(64);
	}

	public function clear():Path {
		verbCount = pointCount = 0;
		open = pending = false;
		penX = penY = startX = startY = 0;
		return this;
	}

	public inline function isEmpty():Bool
		return verbCount == 0;

	public function copy():Path {
		var p = new Path();
		p.addPath(this);
		return p;
	}

	function verb(v:Int) {
		if (verbCount == verbs.length) {
			var n = new Vector(verbs.length * 2);
			Vector.blit(verbs, 0, n, 0, verbCount);
			verbs = n;
		}
		verbs[verbCount++] = v;
	}

	inline function point(x:Float, y:Float) {
		if (pointCount + 2 > points.length) grow();
		points[pointCount++] = x;
		points[pointCount++] = y;
	}

	function grow() {
		var n = new Vector(points.length * 2);
		Vector.blit(points, 0, n, 0, pointCount);
		points = n;
	}

	// (a segment's start: a subpath begun where it is due)
	inline function ensure(x:Float, y:Float) {
		if (pending) {
			pending = false;
			moveTo(startX, startY);
		} else if (!open) moveTo(x, y);
	}

	public function moveTo(x:Float, y:Float) {
		if (!Math.isFinite(x) || !Math.isFinite(y)) return;
		// (a move right after a move replaces it)
		if (verbCount > 0 && verbs[verbCount - 1] == MOVE) {
			points[pointCount - 2] = x;
			points[pointCount - 1] = y;
		} else {
			verb(MOVE);
			point(x, y);
		}
		penX = startX = x;
		penY = startY = y;
		open = true;
		pending = false;
	}

	public function lineTo(x:Float, y:Float) {
		if (!Math.isFinite(x) || !Math.isFinite(y)) return;
		if (!open && !pending) {
			moveTo(x, y);
			return;
		}
		ensure(x, y);
		verb(LINE);
		point(x, y);
		penX = x;
		penY = y;
	}

	public function quadTo(cx:Float, cy:Float, x:Float, y:Float) {
		if (!Math.isFinite(cx) || !Math.isFinite(cy) || !Math.isFinite(x) || !Math.isFinite(y)) return;
		ensure(cx, cy);
		verb(QUAD);
		point(cx, cy);
		point(x, y);
		penX = x;
		penY = y;
	}

	public function cubicTo(c1x:Float, c1y:Float, c2x:Float, c2y:Float, x:Float, y:Float) {
		if (!Math.isFinite(c1x) || !Math.isFinite(c1y) || !Math.isFinite(c2x) || !Math.isFinite(c2y) || !Math.isFinite(x) || !Math.isFinite(y))
			return;
		ensure(c1x, c1y);
		verb(CUBIC);
		point(c1x, c1y);
		point(c2x, c2y);
		point(x, y);
		penX = x;
		penY = y;
	}

	public function close() {
		if (!open || pending) return;
		verb(CLOSE);
		penX = startX;
		penY = startY;
		pending = true;
	}

	public var currentX(get, never):Float;
	public var currentY(get, never):Float;
	public var hasCurrent(get, never):Bool;

	inline function get_currentX()
		return penX;

	inline function get_currentY()
		return penY;

	inline function get_hasCurrent()
		return open;

	// a rectangle as its own closed subpath, the next starting at (x, y)
	public function rect(x:Float, y:Float, w:Float, h:Float) {
		if (!Math.isFinite(x) || !Math.isFinite(y) || !Math.isFinite(w) || !Math.isFinite(h)) return;
		moveTo(x, y);
		lineTo(x + w, y);
		lineTo(x + w, y + h);
		lineTo(x, y + h);
		close();
	}

	// an arc of the circle around (x, y) from the angle start to end
	// (radians, clockwise in y-down units; anticlockwise the other way), a
	// line from the pen to its start (Canvas 2D's arc)
	public function arc(x:Float, y:Float, r:Float, start:Float, end:Float, anticlockwise = false)
		ellipse(x, y, r, r, 0, start, end, anticlockwise);

	// an arc of the ellipse around (x, y) with radii rx, ry turned by
	// rotation (Canvas 2D's ellipse)
	public function ellipse(x:Float, y:Float, rx:Float, ry:Float, rotation:Float, start:Float, end:Float, anticlockwise = false) {
		if (!Math.isFinite(x) || !Math.isFinite(y) || !Math.isFinite(rx) || !Math.isFinite(ry) || !Math.isFinite(rotation) || !Math.isFinite(start)
			|| !Math.isFinite(end))
			return;
		var tau = 2 * Math.PI;
		// (as Chromium's: the start in [0, 2π), the end where the sweep says)
		var s = start % tau;
		if (s < 0) s += tau;
		var delta = s - start;
		var e = end + delta;
		if (!anticlockwise && e - s >= tau) e = s + tau else if (anticlockwise && s - e >= tau) e = s - tau else if (!anticlockwise && s > e)
			e = s + (tau - ((s - e) % tau)) else if (anticlockwise && s < e) e = s - (tau - ((e - s) % tau));
		var cos = Math.cos(rotation), sin = Math.sin(rotation);
		inline function px(t:Float):Float
			return x + rx * Math.cos(t) * cos - ry * Math.sin(t) * sin;
		inline function py(t:Float):Float
			return y + rx * Math.cos(t) * sin + ry * Math.sin(t) * cos;
		var sx = px(s), sy = py(s);
		// (after a close too: the next subpath starts where that one began)
		if (open) lineTo(sx, sy) else moveTo(sx, sy);
		var sweep = e - s;
		if (sweep == 0 || rx == 0 || ry == 0) {
			if (sweep != 0) lineTo(px(e), py(e));
			return;
		}
		var n = Std.int(Math.ceil(Math.abs(sweep) / (Math.PI / 2) - 1e-9));
		if (n < 1) n = 1;
		var step = sweep / n, k = 4 / 3 * Math.tan(step / 4);
		var t = s;
		for (i in 0...n) {
			var t1 = i == n - 1 ? e : t + step;
			var c0 = Math.cos(t), s0 = Math.sin(t), c1 = Math.cos(t1), s1 = Math.sin(t1);
			// (in the ellipse's frame: the unit circle's control points, scaled and turned)
			var ax = c0 - k * s0, ay = s0 + k * c0, bx = c1 + k * s1, by = s1 - k * c1;
			inline function tx(u:Float, v:Float):Float
				return x + rx * u * cos - ry * v * sin;
			inline function ty(u:Float, v:Float):Float
				return y + rx * u * sin + ry * v * cos;
			cubicTo(tx(ax, ay), ty(ax, ay), tx(bx, by), ty(bx, by), tx(c1, s1), ty(c1, s1));
			t = t1;
		}
	}

	// Canvas 2D's arcTo: from the pen toward (x1, y1), turning toward
	// (x2, y2) along a circle of radius r touching both lines
	public function arcTo(x1:Float, y1:Float, x2:Float, y2:Float, r:Float) {
		if (!Math.isFinite(x1) || !Math.isFinite(y1) || !Math.isFinite(x2) || !Math.isFinite(y2) || !Math.isFinite(r)) return;
		ensure(x1, y1);
		var x0 = penX, y0 = penY;
		var dx0 = x0 - x1, dy0 = y0 - y1, dx2 = x2 - x1, dy2 = y2 - y1;
		var l0 = Math.sqrt(dx0 * dx0 + dy0 * dy0), l2 = Math.sqrt(dx2 * dx2 + dy2 * dy2);
		var cross = dx0 * dy2 - dy0 * dx2;
		if ((x0 == x1 && y0 == y1) || (x1 == x2 && y1 == y2) || r == 0 || l0 == 0 || l2 == 0 || Math.abs(cross) < 1e-12 * l0 * l2) {
			lineTo(x1, y1);
			return;
		}
		// (the angle at (x1, y1) between the two lines; the tangent points at r / tan(half of it))
		var cosA = (dx0 * dx2 + dy0 * dy2) / (l0 * l2);
		var half = Math.acos(Math.max(-1, Math.min(1, cosA))) / 2;
		var dist = r / Math.tan(half);
		var tx0 = x1 + dx0 / l0 * dist, ty0 = y1 + dy0 / l0 * dist;
		var tx2 = x1 + dx2 / l2 * dist, ty2 = y1 + dy2 / l2 * dist;
		// (the centre along the bisector)
		var bx = dx0 / l0 + dx2 / l2, by = dy0 / l0 + dy2 / l2, bl = Math.sqrt(bx * bx + by * by);
		var cd = r / Math.sin(half);
		var cx = x1 + bx / bl * cd, cy = y1 + by / bl * cd;
		var a0 = Math.atan2(ty0 - cy, tx0 - cx), a1 = Math.atan2(ty2 - cy, tx2 - cx);
		// (the turn from the first line to the second: cross < 0 is clockwise in y-down units)
		lineTo(tx0, ty0);
		ellipse(cx, cy, r, r, 0, a0, a1, cross > 0);
	}

	// a rectangle with rounded corners, each corner's radii (x and y):
	// upper left, upper right, lower right, lower left, scaled down together
	// where they overlap (Canvas 2D's roundRect)
	public function roundRectXY(x:Float, y:Float, w:Float, h:Float, ulx:Float, uly:Float, urx:Float, ury:Float, lrx:Float, lry:Float, llx:Float,
			lly:Float) {
		if (!Math.isFinite(x) || !Math.isFinite(y) || !Math.isFinite(w) || !Math.isFinite(h)) return;
		// (a negative width or height: the rectangle drawn mirrored from (x, y),
		// each radius at the corner it names in that frame, its winding the
		// other way round, as Chromium draws it)
		var fx = w < 0 ? -1.0 : 1.0, fy = h < 0 ? -1.0 : 1.0;
		var ax = x, ay = y;
		w = Math.abs(w);
		h = Math.abs(h);
		var top = ulx + urx, right = ury + lry, bottom = lrx + llx, left = uly + lly;
		var scale = 1.0;
		if (top > w) scale = Math.min(scale, w / top);
		if (bottom > w) scale = Math.min(scale, w / bottom);
		if (left > h) scale = Math.min(scale, h / left);
		if (right > h) scale = Math.min(scale, h / right);
		if (scale < 1) {
			ulx *= scale;
			uly *= scale;
			urx *= scale;
			ury *= scale;
			lrx *= scale;
			lry *= scale;
			llx *= scale;
			lly *= scale;
		}
		var hp = Math.PI / 2, back = fx * fy < 0;
		// (u, v in the rectangle's own frame, mirrored where its sides are negative)
		inline function X(u:Float):Float
			return ax + fx * u;
		inline function Y(v:Float):Float
			return ay + fy * v;
		inline function A(t:Float):Float
			return Math.atan2(fy * Math.sin(t), fx * Math.cos(t));
		inline function corner(cu:Float, cv:Float, rx:Float, ry:Float, t0:Float, t1:Float)
			if (rx > 0 && ry > 0) ellipse(X(cu), Y(cv), rx, ry, 0, A(t0), A(t1), back);
		moveTo(X(ulx), Y(0));
		lineTo(X(w - urx), Y(0));
		corner(w - urx, ury, urx, ury, -hp, 0);
		lineTo(X(w), Y(h - lry));
		corner(w - lrx, h - lry, lrx, lry, 0, hp);
		lineTo(X(llx), Y(h));
		corner(llx, h - lly, llx, lly, hp, Math.PI);
		lineTo(X(0), Y(uly));
		corner(ulx, uly, ulx, uly, Math.PI, 3 * hp);
		close();
		startX = penX = x;
		startY = penY = y;
	}

	public inline function roundRect(x:Float, y:Float, w:Float, h:Float, r:Float)
		roundRectXY(x, y, w, h, r, r, r, r, r, r, r, r);

	// another path's subpaths added, transformed by m when given
	public function addPath(p:Path, ?m:Matrix) {
		var pi = 0;
		inline function X(k:Int):Float
			return m == null ? p.points[k] : m.mapX(p.points[k], p.points[k + 1]);
		inline function Y(k:Int):Float
			return m == null ? p.points[k + 1] : m.mapY(p.points[k], p.points[k + 1]);
		for (i in 0...p.verbCount)
			switch p.verbs[i] {
				case MOVE:
					moveTo(X(pi), Y(pi));
					pi += 2;
				case LINE:
					lineTo(X(pi), Y(pi));
					pi += 2;
				case QUAD:
					quadTo(X(pi), Y(pi), X(pi + 2), Y(pi + 2));
					pi += 4;
				case CUBIC:
					cubicTo(X(pi), Y(pi), X(pi + 2), Y(pi + 2), X(pi + 4), Y(pi + 4));
					pi += 6;
				case _:
					close();
			}
	}

	// every point transformed in place
	public function transform(m:Matrix) {
		var i = 0;
		while (i < pointCount) {
			var x = points[i], y = points[i + 1];
			points[i] = m.mapX(x, y);
			points[i + 1] = m.mapY(x, y);
			i += 2;
		}
		var x = penX, y = penY;
		penX = m.mapX(x, y);
		penY = m.mapY(x, y);
		x = startX;
		y = startY;
		startX = m.mapX(x, y);
		startY = m.mapY(x, y);
	}

	// its segments flattened into lines within tolerance (in the sink's
	// units, after m), each subpath closed when close is true (a fill) or as
	// it was (a stroke's input keeps its own flattening)
	public function flatten(sink:Sink, m:Matrix, tolerance:Float) {
		var pi = 0, lx = 0.0, ly = 0.0, any = false;
		for (i in 0...verbCount)
			switch verbs[i] {
				case MOVE:
					if (any) sink.close();
					lx = m.mapX(points[pi], points[pi + 1]);
					ly = m.mapY(points[pi], points[pi + 1]);
					sink.moveTo(lx, ly);
					any = true;
					pi += 2;
				case LINE:
					lx = m.mapX(points[pi], points[pi + 1]);
					ly = m.mapY(points[pi], points[pi + 1]);
					sink.lineTo(lx, ly);
					pi += 2;
				case QUAD:
					var x1 = m.mapX(points[pi], points[pi + 1]), y1 = m.mapY(points[pi], points[pi + 1]);
					var x2 = m.mapX(points[pi + 2], points[pi + 3]), y2 = m.mapY(points[pi + 2], points[pi + 3]);
					Curves.quad(sink, lx, ly, x1, y1, x2, y2, tolerance);
					lx = x2;
					ly = y2;
					pi += 4;
				case CUBIC:
					var x1 = m.mapX(points[pi], points[pi + 1]), y1 = m.mapY(points[pi], points[pi + 1]);
					var x2 = m.mapX(points[pi + 2], points[pi + 3]), y2 = m.mapY(points[pi + 2], points[pi + 3]);
					var x3 = m.mapX(points[pi + 4], points[pi + 5]), y3 = m.mapY(points[pi + 4], points[pi + 5]);
					Curves.cubic(sink, lx, ly, x1, y1, x2, y2, x3, y3, tolerance);
					lx = x3;
					ly = y3;
					pi += 6;
				case _:
					sink.close();
					any = false;
			}
		if (any) sink.close();
	}

	// whether (x, y), in the path's units, is inside it by the rule
	public function contains(x:Float, y:Float, evenOdd = false):Bool {
		var w = Winding.shared;
		w.reset(x, y);
		flatten(w, Matrix.IDENTITY, 0.05);
		return evenOdd ? (w.winding & 1) != 0 : w.winding != 0 || w.onEdge;
	}

	// the bounds of its points (control points included): x0, y0, x1, y1 into out
	public function bounds(out:Vector<Float>):Bool {
		if (pointCount == 0) return false;
		var x0 = points[0], y0 = points[1], x1 = x0, y1 = y0, i = 2;
		while (i < pointCount) {
			var x = points[i], y = points[i + 1];
			if (x < x0) x0 = x;
			if (x > x1) x1 = x;
			if (y < y0) y0 = y;
			if (y > y1) y1 = y;
			i += 2;
		}
		out[0] = x0;
		out[1] = y0;
		out[2] = x1;
		out[3] = y1;
		return true;
	}
}

// Where a path's lines go: a rasterizer, a stroker, another path.
interface Sink {
	function moveTo(x:Float, y:Float):Void;
	function lineTo(x:Float, y:Float):Void;
	function close():Void;
}

// Curves into lines: as many as keep each within the tolerance of the
// curve (the second differences bound the distance to the chords).
class Curves {
	public static function quad(sink:Sink, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, tolerance:Float) {
		var dx = x0 - 2 * x1 + x2, dy = y0 - 2 * y1 + y2;
		var dev = Math.sqrt(dx * dx + dy * dy);
		var n = 1 + Std.int(Math.sqrt(dev / (4 * tolerance)));
		if (n > 1000) n = 1000;
		for (i in 1...n) {
			var t = i / n, u = 1 - t;
			sink.lineTo(u * u * x0 + 2 * u * t * x1 + t * t * x2, u * u * y0 + 2 * u * t * y1 + t * t * y2);
		}
		sink.lineTo(x2, y2);
	}

	public static function cubic(sink:Sink, x0:Float, y0:Float, x1:Float, y1:Float, x2:Float, y2:Float, x3:Float, y3:Float, tolerance:Float) {
		var ax = x0 - 2 * x1 + x2, ay = y0 - 2 * y1 + y2, bx = x1 - 2 * x2 + x3, by = y1 - 2 * y2 + y3;
		var dev = Math.sqrt(Math.max(ax * ax + ay * ay, bx * bx + by * by));
		var n = 1 + Std.int(Math.sqrt(dev * 0.75 / tolerance));
		if (n > 1000) n = 1000;
		for (i in 1...n) {
			var t = i / n, u = 1 - t;
			var a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t;
			sink.lineTo(a * x0 + b * x1 + c * x2 + d * x3, a * y0 + b * y1 + c * y2 + d * y3);
		}
		sink.lineTo(x3, y3);
	}
}

// The winding number of lines around a point (isPointInPath)
class Winding implements Sink {
	public static final shared = new Winding();

	public var winding = 0;
	public var onEdge = false;

	var px = 0.0;
	var py = 0.0;
	var sx = 0.0;
	var sy = 0.0;
	var lx = 0.0;
	var ly = 0.0;

	public function new() {}

	public function reset(x:Float, y:Float) {
		px = x;
		py = y;
		winding = 0;
		onEdge = false;
	}

	public function moveTo(x:Float, y:Float) {
		sx = lx = x;
		sy = ly = y;
	}

	public function lineTo(x:Float, y:Float) {
		edge(lx, ly, x, y);
		lx = x;
		ly = y;
	}

	public function close() {
		edge(lx, ly, sx, sy);
		lx = sx;
		ly = sy;
	}

	function edge(x0:Float, y0:Float, x1:Float, y1:Float) {
		// (on the edge itself: inside, as Chromium's)
		var cross = (x1 - x0) * (py - y0) - (y1 - y0) * (px - x0);
		if (Math.abs(cross) < 1e-9 && px >= Math.min(x0, x1) - 1e-9 && px <= Math.max(x0, x1) + 1e-9 && py >= Math.min(y0, y1) - 1e-9
			&& py <= Math.max(y0, y1) + 1e-9)
			onEdge = true;
		if (y0 <= py) {
			if (y1 > py && cross > 0) winding++;
		} else if (y1 <= py && cross < 0) winding--;
	}
}
