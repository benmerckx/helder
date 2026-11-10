import Model;

// A line drawn by hand made into a few knots: the pointer's path smoothed,
// thinned to the points that shape it (Ramer–Douglas–Peucker), a sharp
// turn kept as a corner, closed when it ends where it began; then snapped
// so that what is meant comes out: ink resting on the baseline and
// reaching the x-height (or capitals, ascenders, descenders), a knot near
// another line's on it (an arch meeting its stem), a stem upright.
class Freehand {
	static inline var THIN = 7.0;
	static inline var TURN = 55.0;
	static inline var GUIDE = 45.0;
	static inline var JOIN = 30.0;

	public static function line(points:Array<{x:Float, y:Float}>, face:Face, others:Array<Line>, straight:Bool):Null<Line> {
		if (points.length == 0) return null;
		var pen = face.pen, length = 0.0;
		for (i in 1...points.length)
			length += dist(points[i - 1], points[i]);
		if (length < Math.max(12, pen.width / 4)) return snap({knots: [{x: points[0].x, y: points[0].y}]}, face, others);
		if (straight) return snap({knots: [{x: points[0].x, y: points[0].y}, {x: points[points.length - 1].x, y: points[points.length - 1].y}]}, face, others);
		var smooth = points;
		for (_ in 0...2)
			smooth = [for (i in 0...smooth.length) i == 0 || i == smooth.length - 1 ? smooth[i] : {
				x: (smooth[i - 1].x + 2 * smooth[i].x + smooth[i + 1].x) / 4,
				y: (smooth[i - 1].y + 2 * smooth[i].y + smooth[i + 1].y) / 4
			}];
		var kept = thin(smooth, THIN);
		var closed = kept.length > 3 && dist(kept[0], kept[kept.length - 1]) < pen.width * 0.9 && length > pen.width * 4;
		if (closed) kept.pop();
		var n = kept.length, knots:Array<Knot> = [];
		for (i in 0...n) {
			var p = kept[i], corner = false;
			if (closed || i > 0 && i < n - 1) {
				var a = kept[(i - 1 + n) % n], b = kept[(i + 1) % n];
				corner = angle(a, p, b) > TURN;
			}
			knots.push({x: p.x, y: p.y, corner: corner});
		}
		return snap({knots: knots, closed: closed}, face, others);
	}

	// a line made to sit on the guides near it (stretched so its lowest
	// knot rests on one and its highest reaches one: a bowl stays round),
	// its ends onto other lines' knots near them, a straight stroke upright
	// and in line with a stem
	public static function snap(l:Line, face:Face, others:Array<Line>):Line {
		var m = face.metrics, hv = Ink.vertical(face.pen), hh = Ink.horizontal(face.pen);
		var targets = [m.descender + hv, hv, m.xHeight - hv, m.capHeight - hv, m.ascender - hv];
		var knots = l.knots.copy(), n = knots.length;
		var lo = Math.POSITIVE_INFINITY, hi = Math.NEGATIVE_INFINITY;
		for (k in knots) {
			if (k.y < lo) lo = k.y;
			if (k.y > hi) hi = k.y;
		}
		var lo2 = near(lo, targets), hi2 = near(hi, targets);
		if (hi - lo < 1) lo2 = hi2 = near(lo, targets);
		if (hi2 <= lo2 && hi - lo >= 1) hi2 = hi;
		knots = [for (k in knots) {
			x: k.x,
			y: hi - lo < 1 ? k.y + lo2 - lo : lo2 + (k.y - lo) * (hi2 - lo2) / (hi - lo),
			corner: k.corner
		}];
		// (an end near another line's knot: on it)
		for (i in (l.closed == true ? [] : [0, n - 1])) {
			var best = JOIN;
			for (o in others)
				for (q in o.knots) {
					var d = dist(knots[i], q);
					if (d < best) {
						best = d;
						knots[i] = {x: q.x, y: q.y, corner: knots[i].corner};
					}
				}
		}
		// (a straight stroke nearly upright or level: made so, in line with a stem)
		if (n == 2) {
			var a = knots[0], b = knots[1];
			if (Math.abs(a.x - b.x) < Math.abs(a.y - b.y) * 0.08) {
				var x = a.x;
				for (o in others)
					for (q in o.knots)
						if (Math.abs(x - q.x) < hh * 0.5) x = q.x;
				knots = [{x: x, y: a.y, corner: a.corner}, {x: x, y: b.y, corner: b.corner}];
			} else if (Math.abs(a.y - b.y) < Math.abs(a.x - b.x) * 0.08) knots[1] = {x: b.x, y: a.y, corner: b.corner};
		}
		return {knots: knots, closed: l.closed};
	}

	// the guide within reach of y, else y
	static function near(y:Float, targets:Array<Float>):Float {
		var best = y, most = GUIDE;
		for (t in targets)
			if (Math.abs(y - t) < most) {
				most = Math.abs(y - t);
				best = t;
			}
		return best;
	}

	// the points that keep the path within tolerance of it
	static function thin(pts:Array<{x:Float, y:Float}>, tolerance:Float):Array<{x:Float, y:Float}> {
		if (pts.length < 3) return pts.copy();
		var keep = [for (_ in pts) false];
		keep[0] = keep[pts.length - 1] = true;
		var stack = [[0, pts.length - 1]];
		while (stack.length > 0) {
			var s = stack.pop(), a = s[0], b = s[1], far = -1, most = tolerance;
			for (i in a + 1...b) {
				var d = toSegment(pts[i], pts[a], pts[b]);
				if (d > most) {
					most = d;
					far = i;
				}
			}
			if (far < 0) continue;
			keep[far] = true;
			stack.push([a, far]);
			stack.push([far, b]);
		}
		return [for (i in 0...pts.length) if (keep[i]) pts[i]];
	}

	// how far a path turns at p, in degrees
	static function angle(a:{x:Float, y:Float}, p:{x:Float, y:Float}, b:{x:Float, y:Float}):Float {
		var ux = p.x - a.x, uy = p.y - a.y, vx = b.x - p.x, vy = b.y - p.y;
		var lu = Math.sqrt(ux * ux + uy * uy), lv = Math.sqrt(vx * vx + vy * vy);
		if (lu < 1e-9 || lv < 1e-9) return 0;
		var c = (ux * vx + uy * vy) / (lu * lv);
		return Math.acos(Math.max(-1, Math.min(1, c))) * 180 / Math.PI;
	}

	static function toSegment(p:{x:Float, y:Float}, a:{x:Float, y:Float}, b:{x:Float, y:Float}):Float {
		var dx = b.x - a.x, dy = b.y - a.y, len = dx * dx + dy * dy;
		var t = len == 0 ? 0 : Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len));
		return dist(p, {x: a.x + t * dx, y: a.y + t * dy});
	}

	static inline function dist(a:{x:Float, y:Float}, b:{x:Float, y:Float}):Float
		return Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}
