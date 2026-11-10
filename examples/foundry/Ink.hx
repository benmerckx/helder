import Model;
import helder.text.FontEncoder.FontPoint;

// What a pen line leaves: the line through its knots (a centripetal
// Catmull-Rom spline, so it never loops between close knots; split at
// corners), swept by the pen's ellipse (the envelope's exact points: the
// ellipse's point whose normal is the line's), capped round (the
// ellipse's half) or flat, then fitted with TrueType's quadratics within
// a font unit and a bit. Overlapping lines stay overlapping contours, as a
// font may have them (filled by the non-zero rule). The board, the grid,
// the preview and the exported font all draw these same contours.
typedef Shape = {contours:Array<Array<FontPoint>>, advance:Float, dx:Float, x0:Float, y0:Float, x1:Float, y1:Float};

private typedef Sample = {x:Float, y:Float, tx:Float, ty:Float, ?brk:Bool};

class Ink {
	static inline var TOLERANCE = 1.2;
	static inline var SPAN = 48;
	static inline var ROUND = 1.12;

	// a glyph's lines in its own space, its parts' moved there
	public static function lines(face:Face, char:String, depth = 0):Array<Line> {
		if (depth > 4) return [];
		var g = Model.glyph(face, char);
		var out = g == null ? [] : g.lines.copy();
		var base:Null<Box> = null;
		for (p in Charset.parts(face, char)) {
			var src = lines(face, p.of, depth + 1);
			if (src.length == 0) continue;
			var moved = move(src, p, face, base);
			if (base == null) base = box(moved);
			for (l in moved)
				out.push(l);
		}
		return out;
	}

	static function move(src:Array<Line>, p:Part, face:Face, base:Null<Box>):Array<Line> {
		var b = box(src), m = face.metrics, hv = vertical(face.pen);
		var band = Charset.tall(p.of) ? m.capHeight : m.xHeight;
		var a = 1.0, bb = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0;
		switch p.how {
			case Flip:
				a = -1;
				e = b.x0 + b.x1;
			case Half:
				a = -1;
				d = -1;
				e = b.x0 + b.x1;
				f = band;
			case Flop:
				d = -1;
				f = band;
			case Grow:
				var top = b.y1 > m.xHeight + 60 ? m.ascender : m.xHeight;
				var k = (m.capHeight - 2 * hv) / (top - 2 * hv);
				a = d = k;
				e = b.x0 - b.x0 * k;
				f = hv - hv * k;
			case Mark if (base != null):
				e = (base.x0 + base.x1) / 2 - (b.x0 + b.x1) / 2;
				if (b.y0 > m.xHeight - 50) f = Math.max(0, base.y1 - (m.xHeight - hv));
			case Dotless:
				src = src.filter(l -> Lambda.exists(l.knots, k -> k.y < m.xHeight));
			case Top:
				f = m.xHeight - hv - b.y1;
			case Beside:
				e = b.x1 - b.x0 + face.pen.width * 1.6;
			case _:
		}
		e += p.dx ?? 0;
		f += p.dy ?? 0;
		return [for (l in src) {knots: [for (k in l.knots) {x: a * k.x + c * k.y + e, y: bb * k.x + d * k.y + f, corner: k.corner}], closed: l.closed}];
	}

	// a glyph's contours placed for the font: its ink after its left
	// spacing, its advance after its right
	public static function shape(face:Face, char:String):Shape {
		// (a face never changes: its shapes are kept until the next one; a
		// glyph whose lines, pen and spacing are the same as the last face's keeps its shape too)
		var hit = shapes.get(char);
		if (hit != null && hit.face == face) return hit.shape;
		var lines = lines(face, char), g = Model.glyph(face, char);
		var key = haxe.Json.stringify({l: lines, p: face.pen, s: face.metrics.spacing, a: g?.left, b: g?.right});
		if (hit != null && hit.key == key) {
			shapes.set(char, {face: face, key: key, shape: hit.shape});
			return hit.shape;
		}
		var s = make(face, char, lines);
		shapes.set(char, {face: face, key: key, shape: s});
		return s;
	}

	static final shapes = new Map<String, {face:Face, key:String, shape:Shape}>();

	static function make(face:Face, char:String, lines:Array<Line>):Shape {
		var contours = contours(lines, face.pen);
		var x0 = Math.POSITIVE_INFINITY, y0 = Math.POSITIVE_INFINITY, x1 = Math.NEGATIVE_INFINITY, y1 = Math.NEGATIVE_INFINITY;
		for (c in contours)
			for (p in c) {
				if (p.x < x0) x0 = p.x;
				if (p.x > x1) x1 = p.x;
				if (p.y < y0) y0 = p.y;
				if (p.y > y1) y1 = p.y;
			}
		var g = Model.glyph(face, char), s = face.metrics.spacing;
		var left = s + (g?.left ?? 0), right = s + (g?.right ?? 0);
		if (contours.length == 0) return {contours: [], advance: 0, dx: 0, x0: 0, y0: 0, x1: 0, y1: 0};
		var dx = left - x0;
		return {
			contours: [for (c in contours) [for (p in c) {x: p.x + dx, y: p.y, on: p.on}]],
			advance: Math.max(0, x1 - x0 + left + right),
			dx: dx,
			x0: x0 + dx,
			y0: y0,
			x1: x1 + dx,
			y1: y1
		};
	}

	// the contours of lines drawn with pen
	public static function contours(lines:Array<Line>, pen:Pen):Array<Array<FontPoint>> {
		var out = [];
		var nib = new Nib(pen);
		for (l in lines)
			for (piece in pieces(l))
				for (c in sweep(piece.knots, piece.closed, pen.cap, nib))
					out.push(fit(c));
		return out;
	}

	// the pen's vertical half extent: how far ink reaches above a horizontal line's knots
	public static function vertical(pen:Pen):Float
		return new Nib(pen).extent(0, 1);

	public static function horizontal(pen:Pen):Float
		return new Nib(pen).extent(1, 0);

	// the path a line's centre takes, as points (each piece's)
	public static function centre(l:Line):Array<Array<{x:Float, y:Float}>>
		return [for (p in pieces(l)) p.knots.length < 2 ? [p.knots[0]] : [for (s in spline(p.knots, p.closed)) {x: s.x, y: s.y}]];

	// a line split at its corners: open pieces, or one closed loop
	static function pieces(l:Line):Array<{knots:Array<Knot>, closed:Bool}> {
		var ks = l.knots, n = ks.length;
		if (n == 0) return [];
		var closed = l.closed == true && n > 2;
		var corners = [for (i in 0...n) if (ks[i].corner == true && (closed || i > 0 && i < n - 1)) i];
		if (closed && corners.length == 0) return [{knots: ks, closed: true}];
		// (a loop with corners: opened at its first, its last piece back to it)
		if (closed) ks = [for (i in 0...n + 1) ks[(corners[0] + i) % n]];
		var out = [], from = 0;
		for (i in 1...ks.length)
			if (i == ks.length - 1 || ks[i].corner == true) {
				out.push({knots: ks.slice(from, i + 1), closed: false});
				from = i;
			}
		if (out.length == 0) out.push({knots: ks, closed: false});
		return out;
	}

	// a piece's outline before fitting: points with their tangents
	static function sweep(ks:Array<Knot>, closed:Bool, cap:Cap, nib:Nib):Array<Array<Sample>> {
		if (ks.length == 1 || ks.length == 2 && ks[0].x == ks[1].x && ks[0].y == ks[1].y) return [orient(dot(ks[0], nib), false)];
		var line = spline(ks, closed);
		var left = [], right = [];
		for (s in line) {
			var q = nib.support(-s.ty, s.tx);
			left.push({x: s.x + q.x, y: s.y + q.y, tx: s.tx, ty: s.ty});
			right.push({x: s.x - q.x, y: s.y - q.y, tx: -s.tx, ty: -s.ty});
		}
		if (closed) {
			right.reverse();
			var a = orient(left, false), b = orient(right, false);
			// (the outer loop clockwise, the inner one against it)
			return Math.abs(area(left)) >= Math.abs(area(right)) ? [a, orient(b, true)] : [orient(a, true), b];
		}
		var out = left.copy(), first = line[0], last = line[line.length - 1];
		if (cap == Flat) {
			out[out.length - 1].brk = true;
			right[right.length - 1].brk = true;
		} else
			for (p in round(last, 1, nib))
				out.push(p);
		right.reverse();
		for (p in right)
			out.push(p);
		if (cap == Flat) {
			out[out.length - 1].brk = true;
			out[0].brk = true;
		} else
			for (p in round(first, -1, nib))
				out.push(p);
		return [orient(out, false)];
	}

	// an end's half of the pen: from the left side round to the right (forward: the end, else the start)
	static function round(s:Sample, forward:Int, nib:Nib):Array<Sample> {
		var out = [], steps = 10;
		var tx = s.tx * forward, ty = s.ty * forward;
		for (i in 1...steps) {
			// (the normal turns from the travel's left, through the travel, to its right)
			var phi = Math.PI / 2 - Math.PI * i / steps;
			var dx = Math.cos(phi) * tx - Math.sin(phi) * ty, dy = Math.cos(phi) * ty + Math.sin(phi) * tx;
			var q = nib.support(dx, dy);
			out.push({x: s.x + q.x, y: s.y + q.y, tx: dy, ty: -dx});
		}
		return out;
	}

	static function dot(k:Knot, nib:Nib):Array<Sample> {
		var out = [], steps = 24;
		for (i in 0...steps) {
			var phi = Math.PI * 2 * i / steps, dx = Math.cos(phi), dy = Math.sin(phi);
			var q = nib.support(dx, dy);
			out.push({x: k.x + q.x, y: k.y + q.y, tx: -dy, ty: dx});
		}
		return out;
	}

	// points along the spline through ks, every few units, with unit tangents
	static function spline(ks:Array<Knot>, closed:Bool):Array<Sample> {
		var n = ks.length, out:Array<Sample> = [];
		var segments = closed ? n : n - 1;
		inline function at(i:Int):{x:Float, y:Float}
			return closed ? ks[(i + n) % n] : i < 0 ? {x: 2 * ks[0].x - ks[1].x, y: 2 * ks[0].y - ks[1].y} : i >= n ? {
				x: 2 * ks[n - 1].x - ks[n - 2].x,
				y: 2 * ks[n - 1].y - ks[n - 2].y
			} : ks[i];
		for (i in 0...segments) {
			var p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
			var d1 = dist(p0, p1), d2 = dist(p1, p2), d3 = dist(p2, p3);
			if (d2 < 1e-6) continue;
			var s1 = Math.sqrt(d1), s2 = Math.sqrt(d2), s3 = Math.sqrt(d3);
			var b1x, b1y, b2x, b2y;
			if (d1 < 1e-6) {
				b1x = p1.x + (p2.x - p1.x) / 3;
				b1y = p1.y + (p2.y - p1.y) / 3;
			} else {
				var k = 3 * s1 * (s1 + s2), w = 2 * d1 + 3 * s1 * s2 + d2;
				b1x = (d1 * p2.x - d2 * p0.x + w * p1.x) / k;
				b1y = (d1 * p2.y - d2 * p0.y + w * p1.y) / k;
			}
			if (d3 < 1e-6) {
				b2x = p2.x - (p2.x - p1.x) / 3;
				b2y = p2.y - (p2.y - p1.y) / 3;
			} else {
				var k = 3 * s3 * (s3 + s2), w = 2 * d3 + 3 * s3 * s2 + d2;
				b2x = (d3 * p1.x - d2 * p3.x + w * p2.x) / k;
				b2y = (d3 * p1.y - d2 * p3.y + w * p2.y) / k;
			}
			// (Catmull-Rom's handles run short on a round shape: an eight-knot
			// ring comes out square-ish; a loop's lengthened toward a circle's)
			var round = closed ? ROUND : 1.0;
			b1x = p1.x + (b1x - p1.x) * round;
			b1y = p1.y + (b1y - p1.y) * round;
			b2x = p2.x + (b2x - p2.x) * round;
			b2y = p2.y + (b2y - p2.y) * round;
			var steps = Std.int(Math.max(3, Math.min(80, Math.ceil(d2 / 9))));
			for (j in (out.length == 0 ? 0 : 1)...steps + 1) {
				var t = j / steps, u = 1 - t;
				var x = u * u * u * p1.x + 3 * u * u * t * b1x + 3 * u * t * t * b2x + t * t * t * p2.x;
				var y = u * u * u * p1.y + 3 * u * u * t * b1y + 3 * u * t * t * b2y + t * t * t * p2.y;
				var dx = 3 * u * u * (b1x - p1.x) + 6 * u * t * (b2x - b1x) + 3 * t * t * (p2.x - b2x);
				var dy = 3 * u * u * (b1y - p1.y) + 6 * u * t * (b2y - b1y) + 3 * t * t * (p2.y - b2y);
				var len = Math.sqrt(dx * dx + dy * dy);
				if (len < 1e-9) {
					dx = p2.x - p1.x;
					dy = p2.y - p1.y;
					len = Math.sqrt(dx * dx + dy * dy);
				}
				out.push({x: x, y: y, tx: dx / len, ty: dy / len});
			}
		}
		// (a loop's last point is its first)
		if (closed && out.length > 1) out.pop();
		if (out.length == 1) out.push({x: out[0].x + out[0].tx * 0.01, y: out[0].y + out[0].ty * 0.01, tx: out[0].tx, ty: out[0].ty});
		return out;
	}

	// points turned to run clockwise (y up: outer contours), or against it
	static function orient(pts:Array<Sample>, counter:Bool):Array<Sample> {
		if ((area(pts) > 0) == counter) return pts;
		var out = [for (i in 0...pts.length) pts[pts.length - 1 - i]];
		return [for (p in out) {x: p.x, y: p.y, tx: -p.tx, ty: -p.ty, brk: p.brk}];
	}

	static function area(pts:Array<Sample>):Float {
		var a = 0.0;
		for (i in 0...pts.length) {
			var p = pts[i], q = pts[(i + 1) % pts.length];
			a += p.x * q.y - q.x * p.y;
		}
		return a / 2;
	}

	// a closed run of points as quadratics: from each point, the farthest
	// one a single curve (its control where the two tangents meet) or a
	// line stays within the tolerance of every point between
	static function fit(pts:Array<Sample>):Array<FontPoint> {
		var n = pts.length, start = 0;
		for (i in 0...n)
			if (pts[i].brk == true) {
				start = i;
				break;
			}
		var out:Array<FontPoint> = [{x: pts[start].x, y: pts[start].y, on: true}];
		var i = start, done = 0;
		while (done < n) {
			var best = 1, control:Null<{x:Float, y:Float}> = null;
			var span = 2;
			while (span <= SPAN && span <= n - done) {
				if (pts[(i + span - 1) % n].brk == true) break;
				var j = (i + span) % n;
				if (straight(pts, i, span)) {
					best = span;
					control = null;
				} else {
					var c = meet(pts[i], pts[j]);
					if (c == null || !fits(pts, i, span, c)) break;
					best = span;
					control = c;
				}
				span++;
			}
			var j = (i + best) % n;
			if (control != null) out.push({x: control.x, y: control.y, on: false});
			done += best;
			if (done < n) out.push({x: pts[j].x, y: pts[j].y, on: true});
			i = j;
		}
		return out;
	}

	static function straight(pts:Array<Sample>, i:Int, span:Int):Bool {
		var n = pts.length, a = pts[i], b = pts[(i + span) % n];
		var dx = b.x - a.x, dy = b.y - a.y, len = Math.sqrt(dx * dx + dy * dy);
		if (len < 1e-9) return false;
		for (k in 1...span) {
			var p = pts[(i + k) % n];
			if (Math.abs((p.x - a.x) * dy - (p.y - a.y) * dx) / len > TOLERANCE * 0.7) return false;
		}
		// (and the ends' tangents along it: a line's, not a curve's chord)
		var ca = (a.tx * dx + a.ty * dy) / len, cb = (b.tx * dx + b.ty * dy) / len;
		return ca > 0.999 && cb > 0.999 || span <= 2;
	}

	// where the tangents at a and b meet, ahead of a and behind b
	static function meet(a:Sample, b:Sample):Null<{x:Float, y:Float}> {
		var den = a.tx * b.ty - a.ty * b.tx;
		if (Math.abs(den) < 1e-6) return null;
		var wx = b.x - a.x, wy = b.y - a.y;
		var t = (wx * b.ty - wy * b.tx) / den, s = (wx * a.ty - wy * a.tx) / den;
		var chord = Math.sqrt(wx * wx + wy * wy);
		if (t <= 0 || s <= 0 || t > chord * 1.5 || s > chord * 1.5) return null;
		return {x: a.x + a.tx * t, y: a.y + a.ty * t};
	}

	static function fits(pts:Array<Sample>, i:Int, span:Int, c:{x:Float, y:Float}):Bool {
		var n = pts.length, a = pts[i], b = pts[(i + span) % n];
		// (each point's parameter guessed from the distance along, then refined)
		var lens = [0.0], total = 0.0;
		for (k in 1...span + 1) {
			var p = pts[(i + k - 1) % n], q = pts[(i + k) % n];
			total += Math.sqrt((q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y));
			lens.push(total);
		}
		if (total < 1e-9) return false;
		for (k in 1...span) {
			var p = pts[(i + k) % n], t = lens[k] / total;
			for (_ in 0...4) {
				var u = 1 - t;
				var qx = u * u * a.x + 2 * u * t * c.x + t * t * b.x, qy = u * u * a.y + 2 * u * t * c.y + t * t * b.y;
				var dx = 2 * u * (c.x - a.x) + 2 * t * (b.x - c.x), dy = 2 * u * (c.y - a.y) + 2 * t * (b.y - c.y);
				var ddx = 2 * (b.x - 2 * c.x + a.x), ddy = 2 * (b.y - 2 * c.y + a.y);
				var f = (qx - p.x) * dx + (qy - p.y) * dy, fd = dx * dx + dy * dy + (qx - p.x) * ddx + (qy - p.y) * ddy;
				if (Math.abs(fd) < 1e-9) break;
				t -= f / fd;
				if (t < 0) t = 0;
				if (t > 1) t = 1;
			}
			var u = 1 - t;
			var qx = u * u * a.x + 2 * u * t * c.x + t * t * b.x, qy = u * u * a.y + 2 * u * t * c.y + t * t * b.y;
			if ((qx - p.x) * (qx - p.x) + (qy - p.y) * (qy - p.y) > TOLERANCE * TOLERANCE) return false;
		}
		return true;
	}

	public static function box(lines:Array<Line>):Box {
		var b:Box = {x0: Math.POSITIVE_INFINITY, y0: Math.POSITIVE_INFINITY, x1: Math.NEGATIVE_INFINITY, y1: Math.NEGATIVE_INFINITY};
		for (l in lines)
			for (k in l.knots) {
				if (k.x < b.x0) b.x0 = k.x;
				if (k.x > b.x1) b.x1 = k.x;
				if (k.y < b.y0) b.y0 = k.y;
				if (k.y > b.y1) b.y1 = k.y;
			}
		if (b.x0 > b.x1) return {x0: 0, y0: 0, x1: 0, y1: 0};
		return b;
	}

	static inline function dist(a:{x:Float, y:Float}, b:{x:Float, y:Float}):Float
		return Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

typedef Box = {x0:Float, y0:Float, x1:Float, y1:Float};

// the pen's ellipse: half its width along its edge's angle, less across
private class Nib {
	final ux:Float;
	final uy:Float;
	final a2:Float;
	final b2:Float;

	public function new(pen:Pen) {
		var r = pen.angle * Math.PI / 180, half = pen.width / 2;
		var across = half * Math.max(0.06, 1 - pen.contrast * 0.94);
		ux = Math.cos(r);
		uy = Math.sin(r);
		a2 = half * half;
		b2 = across * across;
	}

	// the ellipse's point whose outward normal is (dx, dy)
	public function support(dx:Float, dy:Float):{x:Float, y:Float} {
		var du = dx * ux + dy * uy, dv = -dx * uy + dy * ux;
		var h = Math.sqrt(a2 * du * du + b2 * dv * dv);
		if (h < 1e-9) return {x: 0, y: 0};
		var pu = a2 * du / h, pv = b2 * dv / h;
		return {x: pu * ux - pv * uy, y: pu * uy + pv * ux};
	}

	// how far the ellipse reaches along (dx, dy)
	public function extent(dx:Float, dy:Float):Float {
		var du = dx * ux + dy * uy, dv = -dx * uy + dy * ux;
		return Math.sqrt(a2 * du * du + b2 * dv * dv);
	}
}
