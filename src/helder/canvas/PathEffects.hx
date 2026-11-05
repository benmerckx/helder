package helder.canvas;

// Paths made from paths (Skia's path effects, skia-canvas's Path2D
// methods): corners rounded, a part kept by length (trim), dashes as
// subpaths, a hand-drawn jitter. Each flattens the path (within
// tolerance) to polylines, its subpaths' closedness kept, and returns a
// new path.
class PathEffects {
	// each subpath as points: [x, y, ...], closed or not
	static function polylines(p:Path, tolerance:Float):Array<{pts:Array<Float>, closed:Bool}> {
		var out = [];
		var c = new Collect(out);
		// (flatten closes every subpath: Collect takes the verbs' own closes instead)
		var pts = p.points, pi = 0, cur:Array<Float> = null, lx = 0.0, ly = 0.0;
		for (i in 0...p.verbCount)
			switch p.verbs[i] {
				case Path.MOVE:
					cur = [pts[pi], pts[pi + 1]];
					out.push({pts: cur, closed: false});
					lx = pts[pi];
					ly = pts[pi + 1];
					pi += 2;
				case Path.LINE:
					cur.push(pts[pi]);
					cur.push(pts[pi + 1]);
					lx = pts[pi];
					ly = pts[pi + 1];
					pi += 2;
				case Path.QUAD:
					c.cur = cur;
					Path.Curves.quad(c, lx, ly, pts[pi], pts[pi + 1], pts[pi + 2], pts[pi + 3], tolerance);
					lx = pts[pi + 2];
					ly = pts[pi + 3];
					pi += 4;
				case Path.CUBIC:
					c.cur = cur;
					Path.Curves.cubic(c, lx, ly, pts[pi], pts[pi + 1], pts[pi + 2], pts[pi + 3], pts[pi + 4], pts[pi + 5], tolerance);
					lx = pts[pi + 4];
					ly = pts[pi + 5];
					pi += 6;
				case _:
					if (out.length > 0) out[out.length - 1].closed = true;
			}
		return out;
	}

	// every corner (a turn between two segments) cut back by up to radius and rounded by an arc tangent to both
	public static function round(p:Path, radius:Float, tolerance = 0.1):Path {
		var out = new Path();
		for (sub in polylines(p, tolerance)) {
			var n = Std.int(sub.pts.length / 2);
			if (n < 2) continue;
			var x = sub.pts;
			inline function X(k:Int)
				return x[((k % n + n) % n) * 2];
			inline function Y(k:Int)
				return x[((k % n + n) % n) * 2 + 1];
			if (sub.closed) {
				// (from the middle of the first segment, every corner through arcTo)
				out.moveTo((X(0) + X(1)) / 2, (Y(0) + Y(1)) / 2);
				for (k in 1...n + 1)
					out.arcTo(X(k), Y(k), X(k + 1), Y(k + 1), corner(X(k - 1), Y(k - 1), X(k), Y(k), X(k + 1), Y(k + 1), radius));
				out.lineTo((X(0) + X(1)) / 2, (Y(0) + Y(1)) / 2);
				out.close();
			} else {
				out.moveTo(X(0), Y(0));
				for (k in 1...n - 1)
					out.arcTo(X(k), Y(k), X(k + 1), Y(k + 1), corner(X(k - 1), Y(k - 1), X(k), Y(k), X(k + 1), Y(k + 1), radius));
				out.lineTo(X(n - 1), Y(n - 1));
			}
		}
		return out;
	}

	// (the radius that fits a corner: its segments' halves at most)
	static function corner(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, r:Float):Float {
		var l0 = Math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay)), l1 = Math.sqrt((cx - bx) * (cx - bx) + (cy - by) * (cy - by));
		if (l0 == 0 || l1 == 0) return 0;
		var cos = ((ax - bx) * (cx - bx) + (ay - by) * (cy - by)) / (l0 * l1);
		var half = Math.acos(Math.max(-1, Math.min(1, cos))) / 2;
		var t = Math.tan(half);
		// (the tangent points at r / tan(half) from the corner, within half of each segment)
		var dist = Math.min(r / Math.max(t, 1e-9), Math.min(l0, l1) / 2);
		return dist * t;
	}

	// the part of each subpath between the fractions start and end of its length (inverted: the rest)
	public static function trim(p:Path, start:Float, end:Float, inverted = false, tolerance = 0.1):Path {
		var out = new Path();
		for (sub in polylines(p, tolerance)) {
			var pts = sub.pts.copy();
			if (sub.closed && pts.length >= 4) {
				pts.push(pts[0]);
				pts.push(pts[1]);
			}
			var total = length(pts);
			var a = Math.max(0, Math.min(1, start)) * total, b = Math.max(0, Math.min(1, end)) * total;
			if (a > b) {
				var t = a;
				a = b;
				b = t;
			}
			if (!inverted) piece(pts, a, b, out) else {
				piece(pts, 0, a, out);
				piece(pts, b, total, out);
			}
		}
		return out;
	}

	static function length(pts:Array<Float>):Float {
		var l = 0.0, k = 2;
		while (k < pts.length) {
			l += Math.sqrt(Math.pow(pts[k] - pts[k - 2], 2) + Math.pow(pts[k + 1] - pts[k - 1], 2));
			k += 2;
		}
		return l;
	}

	// the polyline between the lengths a and b along it, an open subpath of out
	static function piece(pts:Array<Float>, a:Float, b:Float, out:Path) {
		if (b <= a) return;
		var at = 0.0, k = 2, started = false;
		while (k < pts.length) {
			var x0 = pts[k - 2], y0 = pts[k - 1], x1 = pts[k], y1 = pts[k + 1];
			var l = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
			if (l > 0 && at + l > a && at < b) {
				var t0 = Math.max(0, (a - at) / l), t1 = Math.min(1, (b - at) / l);
				if (!started) {
					out.moveTo(x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0);
					started = true;
				}
				out.lineTo(x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1);
			}
			at += l;
			k += 2;
		}
	}

	// the dashes along each subpath (on and off lengths from offset) as open subpaths
	public static function dash(p:Path, intervals:Array<Float>, offset = 0.0, tolerance = 0.1):Path {
		var d = intervals.length % 2 == 1 ? intervals.concat(intervals) : intervals;
		var period = 0.0;
		for (v in d)
			period += v;
		var out = new Path();
		if (!(period > 0)) {
			out.addPath(p);
			return out;
		}
		for (sub in polylines(p, tolerance)) {
			var pts = sub.pts.copy();
			if (sub.closed && pts.length >= 4) {
				pts.push(pts[0]);
				pts.push(pts[1]);
			}
			var total = length(pts), at = -(offset % period), k = 0;
			if (at > 0) at -= period;
			while (at < total) {
				var len = d[k % d.length];
				if (k % 2 == 0) piece(pts, Math.max(0, at), Math.min(total, at + len), out);
				at += len;
				k++;
			}
		}
		return out;
	}

	// each subpath resampled every segment units and moved across itself by up to amount, from a seed
	// (the same seed, the same path)
	public static function jitter(p:Path, segment:Float, amount:Float, seed = 0, tolerance = 0.1):Path {
		var out = new Path();
		var state:Int = (seed * 0x9E3779B1) | 1;
		inline function random():Float {
			state ^= state << 13;
			state ^= state >>> 17;
			state ^= state << 5;
			return (state & 0xFFFFFF) / 0x1000000;
		}
		for (sub in polylines(p, tolerance)) {
			var pts = sub.pts.copy();
			if (sub.closed && pts.length >= 4) {
				pts.push(pts[0]);
				pts.push(pts[1]);
			}
			var total = length(pts);
			var steps = Std.int(Math.max(1, Math.ceil(total / Math.max(segment, 1e-6))));
			var first = true;
			for (s in 0...steps + 1) {
				var at = total * s / steps;
				var q = pointAt(pts, at);
				var j = (random() * 2 - 1) * amount;
				var x = q[0] - q[3] * j, y = q[1] + q[2] * j;
				if (first) out.moveTo(x, y) else out.lineTo(x, y);
				first = false;
			}
			if (sub.closed) out.close();
		}
		return out;
	}

	// (the point at a length along a polyline, and the direction there)
	static function pointAt(pts:Array<Float>, l:Float):Array<Float> {
		var at = 0.0, k = 2;
		while (k < pts.length) {
			var x0 = pts[k - 2], y0 = pts[k - 1], x1 = pts[k], y1 = pts[k + 1];
			var len = Math.sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));
			if (len > 0 && (at + len >= l || k + 2 >= pts.length)) {
				var t = Math.min(1, (l - at) / len);
				return [x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, (x1 - x0) / len, (y1 - y0) / len];
			}
			at += len;
			k += 2;
		}
		return [pts[0], pts[1], 1, 0];
	}
}

// (a curve's points into the current polyline)
private class Collect implements Path.Sink {
	public var cur:Array<Float> = null;

	final out:Array<{pts:Array<Float>, closed:Bool}>;

	public function new(out) {
		this.out = out;
	}

	public function moveTo(x:Float, y:Float) {}

	public function lineTo(x:Float, y:Float) {
		cur.push(x);
		cur.push(y);
	}

	public function close() {}
}
