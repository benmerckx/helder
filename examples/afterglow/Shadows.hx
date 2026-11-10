// A point light's sight in 2D: what it sees past a set of segments (x0,
// y0, x1, y1, ...): whether a point is in its light, and the polygon it
// lights, cast to every endpoint (and just either side of it) and, between
// them, around its reach (so the polygon ends at the reach's circle, not
// at walls far beyond it).
class Shadows {
	static inline var AROUND = 72;

	public final segments:Array<Float> = [];

	public function new() {}

	public function clear()
		segments.resize(0);

	public function add(x0:Float, y0:Float, x1:Float, y1:Float) {
		segments.push(x0);
		segments.push(y0);
		segments.push(x1);
		segments.push(y1);
	}

	// a box's four sides
	public function box(x:Float, y:Float, w:Float, h:Float) {
		add(x, y, x + w, y);
		add(x + w, y, x + w, y + h);
		add(x + w, y + h, x, y + h);
		add(x, y + h, x, y);
	}

	// nothing between (lx, ly) and (x, y)
	public function sees(lx:Float, ly:Float, x:Float, y:Float):Bool {
		var s = segments, k = 0;
		while (k < s.length) {
			if (cross(lx, ly, x, y, s[k], s[k + 1], s[k + 2], s[k + 3])) return false;
			k += 4;
		}
		return true;
	}

	// the lit polygon about (lx, ly), out to reach: x, y pairs in turn
	public function polygon(lx:Float, ly:Float, reach:Float):Array<Float> {
		var s = segments, angles:Array<Float> = [];
		var near:Array<Float> = [], k = 0;
		while (k < s.length) {
			if (close(lx, ly, s[k], s[k + 1], s[k + 2], s[k + 3], reach)) for (n in 0...4)
				near.push(s[k + n]);
			k += 4;
		}
		k = 0;
		while (k < near.length) {
			for (e in [0, 2]) {
				var dx = near[k + e] - lx, dy = near[k + e + 1] - ly;
				if (dx * dx + dy * dy > reach * reach * 1.2) continue;
				var a = Math.atan2(dy, dx);
				angles.push(a - 0.0004);
				angles.push(a);
				angles.push(a + 0.0004);
			}
			k += 4;
		}
		for (n in 0...AROUND)
			angles.push(-Math.PI + n * Math.PI * 2 / AROUND);
		angles.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var out:Array<Float> = [], last = -10.0;
		for (a in angles) {
			if (a - last < 0.00005) continue;
			last = a;
			var dx = Math.cos(a), dy = Math.sin(a), t = reach;
			k = 0;
			while (k < near.length) {
				var h = hit(lx, ly, dx, dy, near[k], near[k + 1], near[k + 2], near[k + 3]);
				if (h >= 0 && h < t) t = h;
				k += 4;
			}
			out.push(lx + dx * t);
			out.push(ly + dy * t);
		}
		return out;
	}

	// how far along (dx, dy) from (x, y) the ray meets the segment; -1: never
	static function hit(x:Float, y:Float, dx:Float, dy:Float, ax:Float, ay:Float, bx:Float, by:Float):Float {
		var ex = bx - ax, ey = by - ay;
		var d = dx * ey - dy * ex;
		if (Math.abs(d) < 1e-9) return -1;
		var px = ax - x, py = ay - y;
		var t = (px * ey - py * ex) / d, u = (px * dy - py * dx) / d;
		return t >= 0 && u >= 0 && u <= 1 ? t : -1;
	}

	// whether two segments cross (touching ends do not count)
	static function cross(ax:Float, ay:Float, bx:Float, by:Float, cx:Float, cy:Float, dx:Float, dy:Float):Bool {
		var rx = bx - ax, ry = by - ay, sx = dx - cx, sy = dy - cy;
		var d = rx * sy - ry * sx;
		if (Math.abs(d) < 1e-9) return false;
		var qx = cx - ax, qy = cy - ay;
		var t = (qx * sy - qy * sx) / d, u = (qx * ry - qy * rx) / d;
		return t > 1e-6 && t < 1 - 1e-6 && u >= 0 && u <= 1;
	}

	// a segment within reach of (x, y)
	static function close(x:Float, y:Float, ax:Float, ay:Float, bx:Float, by:Float, reach:Float):Bool {
		var ex = bx - ax, ey = by - ay, l = ex * ex + ey * ey;
		var t = l > 0 ? Math.max(0, Math.min(1, ((x - ax) * ex + (y - ay) * ey) / l)) : 0;
		var px = ax + ex * t - x, py = ay + ey * t - y;
		return px * px + py * py <= reach * reach;
	}
}
