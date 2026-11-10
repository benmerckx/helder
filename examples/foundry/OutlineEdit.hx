import Model;

// Edits of an outline, each a new outline: points moved (a point on the
// curve takes its handles along; a handle of a smooth point turns the one
// across from it to stay in line), a point made smooth or a corner, a
// point put on a curve (split there, the curve unchanged), points taken
// out (the curves either side made one). Points are a contour's index and
// a point's in it, as stored.
class OutlineEdit {
	// the point nearest (x, y) within r: on the curve before handles
	public static function pointAt(outline:Array<Array<OPoint>>, x:Float, y:Float, r:Float):Null<{c:Int, p:Int}> {
		var best:Null<{c:Int, p:Int}> = null, most = r;
		for (pass in 0...2)
			for (c in 0...outline.length)
				for (p in 0...outline[c].length) {
					var q = outline[c][p];
					if ((q.off == true) != (pass == 1)) continue;
					var d = Math.sqrt((q.x - x) * (q.x - x) + (q.y - y) * (q.y - y));
					if (d < most) {
						most = d;
						best = {c: c, p: p};
					}
				}
		return best;
	}

	// the curve or line nearest (x, y) within r: its contour, the index its on point starts at, where on it
	public static function segmentAt(outline:Array<Array<OPoint>>, x:Float, y:Float, r:Float):Null<{c:Int, at:Int, t:Float}> {
		var best:Null<{c:Int, at:Int, t:Float}> = null, most = r;
		for (c in 0...outline.length) {
			var pts = outline[c], n = pts.length;
			for (i in 0...n) {
				if (pts[i].off == true) continue;
				var a = pts[i], h1 = pts[(i + 1) % n];
				var cubic = h1.off == true, h2 = pts[(i + 2) % n], b = cubic ? pts[(i + 3) % n] : h1;
				for (k in 0...33) {
					var t = k / 32, px, py;
					if (cubic) {
						var u = 1 - t;
						px = u * u * u * a.x + 3 * u * u * t * h1.x + 3 * u * t * t * h2.x + t * t * t * b.x;
						py = u * u * u * a.y + 3 * u * u * t * h1.y + 3 * u * t * t * h2.y + t * t * t * b.y;
					} else {
						px = a.x + (b.x - a.x) * t;
						py = a.y + (b.y - a.y) * t;
					}
					var d = Math.sqrt((px - x) * (px - x) + (py - y) * (py - y));
					if (d < most) {
						most = d;
						best = {c: c, at: i, t: t};
					}
				}
			}
		}
		return best;
	}

	// the points chosen moved by (dx, dy), from the outline as it was when the drag began
	public static function moved(outline:Array<Array<OPoint>>, chosen:Array<{c:Int, p:Int}>, dx:Float, dy:Float):Array<Array<OPoint>> {
		var out = [for (c in outline) [for (q in c) {x: q.x, y: q.y, off: q.off, smooth: q.smooth}]];
		inline function picked(c:Int, p:Int):Bool
			return Lambda.exists(chosen, s -> s.c == c && s.p == p);
		for (c in 0...outline.length) {
			var pts = outline[c], n = pts.length, moving = [for (_ in 0...n) false];
			for (p in 0...n)
				if (picked(c, p)) {
					moving[p] = true;
					// (a point on the curve takes its handles along)
					if (pts[p].off != true)
						for (side in [-1, 1]) {
							var h = (p + side + n) % n;
							if (pts[h].off == true) moving[h] = true;
						}
				}
			for (p in 0...n)
				if (moving[p]) {
					out[c][p].x = pts[p].x + dx;
					out[c][p].y = pts[p].y + dy;
				}
			// (a handle moved alone: the one across its smooth point turned to stay in line)
			for (p in 0...n) {
				if (!moving[p] || pts[p].off != true) continue;
				for (side in [-1, 1]) {
					var anchor = (p + side + n) % n, across = (anchor + side + n) % n;
					if (pts[anchor].off == true || pts[anchor].smooth != true || moving[anchor] || pts[across].off != true || moving[across]) continue;
					var ax = out[c][anchor].x, ay = out[c][anchor].y;
					var vx = ax - out[c][p].x, vy = ay - out[c][p].y, len = Math.sqrt(vx * vx + vy * vy);
					var keep = Math.sqrt(Math.pow(pts[across].x - ax, 2) + Math.pow(pts[across].y - ay, 2));
					if (len < 1e-6) continue;
					out[c][across].x = ax + vx / len * keep;
					out[c][across].y = ay + vy / len * keep;
				}
			}
		}
		return out;
	}

	// a point on the curve made smooth (its handles put in line) or a corner
	public static function toggled(outline:Array<Array<OPoint>>, c:Int, p:Int):Array<Array<OPoint>> {
		var out = [for (k in outline) k.copy()], pts = out[c], n = pts.length, q = pts[p];
		if (q.off == true) return outline;
		var smooth = q.smooth != true;
		pts[p] = {x: q.x, y: q.y, smooth: smooth};
		var a = pts[(p - 1 + n) % n], b = pts[(p + 1) % n];
		if (smooth && (a.off == true || b.off == true)) {
			var dx = b.x - a.x, dy = b.y - a.y, len = Math.sqrt(dx * dx + dy * dy);
			if (len > 1e-6) {
				dx /= len;
				dy /= len;
				if (a.off == true) {
					var la = Math.sqrt(Math.pow(a.x - q.x, 2) + Math.pow(a.y - q.y, 2));
					pts[(p - 1 + n) % n] = {x: q.x - dx * la, y: q.y - dy * la, off: true};
				}
				if (b.off == true) {
					var lb = Math.sqrt(Math.pow(b.x - q.x, 2) + Math.pow(b.y - q.y, 2));
					pts[(p + 1) % n] = {x: q.x + dx * lb, y: q.y + dy * lb, off: true};
				}
			}
		}
		return out;
	}

	// a point put on a curve (or a line) at t, its shape unchanged
	public static function inserted(outline:Array<Array<OPoint>>, c:Int, at:Int, t:Float):Array<Array<OPoint>> {
		var out = [for (k in outline) k.copy()], pts = out[c], n = pts.length;
		var a = pts[at], h1 = pts[(at + 1) % n];
		if (h1.off != true) {
			pts.insert(at + 1, {x: a.x + (h1.x - a.x) * t, y: a.y + (h1.y - a.y) * t});
			return out;
		}
		var h2 = pts[(at + 2) % n], b = pts[(at + 3) % n];
		var l = Ink.sub(a.x, a.y, h1.x, h1.y, h2.x, h2.y, b.x, b.y, 0, t), r = Ink.sub(a.x, a.y, h1.x, h1.y, h2.x, h2.y, b.x, b.y, t, 1);
		var made:Array<OPoint> = [
			{x: l[2], y: l[3], off: true},
			{x: l[4], y: l[5], off: true},
			{x: l[6], y: l[7], smooth: true},
			{x: r[2], y: r[3], off: true},
			{x: r[4], y: r[5], off: true}
		];
		// (the curve's two handles replaced by the five around the new point)
		var i1 = (at + 1) % n, i2 = (at + 2) % n;
		var keep = [for (i in 0...n) if (i != i1 && i != i2) pts[i]];
		var pos = keep.indexOf(a) + 1;
		for (k in 0...made.length)
			keep.insert(pos + k, made[k]);
		out[c] = keep;
		return out;
	}

	// the points chosen taken out: a point on the curve and its handles (the
	// curves either side made one, keeping their outer handles), a handle
	// (its curve made a line); a contour left with fewer than two points goes
	public static function removed(outline:Array<Array<OPoint>>, chosen:Array<{c:Int, p:Int}>):Array<Array<OPoint>> {
		var out = [];
		for (c in 0...outline.length) {
			var pts = outline[c];
			var gone = [for (s in chosen) if (s.c == c) s.p];
			if (gone.length == 0) {
				out.push(pts);
				continue;
			}
			// (as segments: an on point, then its curve's handles, if any)
			var segs = segments(pts), kept:Array<Segment> = [];
			for (s in segs) {
				if (gone.indexOf(s.i) >= 0) {
					// (merged into the one before: its first handle kept, this one's last taken over)
					var prev = kept.length > 0 ? kept[kept.length - 1] : null;
					if (prev != null) {
						if (prev.h1 != null || s.h2 != null) {
							prev.h1 = prev.h1 ?? {x: prev.a.x, y: prev.a.y, off: true};
							prev.h2 = s.h2;
						}
					}
					continue;
				}
				var seg:Segment = {i: s.i, a: s.a, h1: s.h1, h2: s.h2, h1i: s.h1i, h2i: s.h2i};
				if (s.h1i >= 0 && gone.indexOf(s.h1i) >= 0 || s.h2i >= 0 && gone.indexOf(s.h2i) >= 0) seg.h1 = seg.h2 = null;
				kept.push(seg);
			}
			// (the first segment removed: the last one carries on into what follows)
			if (kept.length > 0 && gone.indexOf(segs[0].i) >= 0 && kept[kept.length - 1].h2 == null && segs[0].h2 != null) {
				var last = kept[kept.length - 1];
				last.h1 = last.h1 ?? {x: last.a.x, y: last.a.y, off: true};
				last.h2 = segs[0].h2;
			}
			if (kept.length < 2) continue;
			var made:Array<OPoint> = [];
			for (s in kept) {
				made.push(s.a);
				if (s.h1 != null) {
					made.push(s.h1);
					made.push(s.h2 ?? s.h1);
				}
			}
			out.push(made);
		}
		return out;
	}

	// a contour's segments from each point on it: its handles' points and indices (-1: a line)
	static function segments(pts:Array<OPoint>):Array<Segment> {
		var n = pts.length, out:Array<Segment> = [];
		for (i in 0...n) {
			if (pts[i].off == true) continue;
			var j = (i + 1) % n;
			if (pts[j].off == true) out.push({i: i, a: pts[i], h1: pts[j], h2: pts[(i + 2) % n], h1i: j, h2i: (i + 2) % n}) else
				out.push({i: i, a: pts[i], h1: null, h2: null, h1i: -1, h2i: -1});
		}
		return out;
	}
}

private typedef Segment = {i:Int, a:OPoint, h1:Null<OPoint>, h2:Null<OPoint>, h1i:Int, h2i:Int};
