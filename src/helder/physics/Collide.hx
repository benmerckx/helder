package helder.physics;

import helder.gfx.shader.Vec3;
import helder.gfx.shader.Mat4;

// The contact tests, each adding its contacts to out: sphere against
// sphere, plane and box; box against plane (its corners under it) and box
// (separating axes among the faces' normals, the corners through the face
// of least overlap: a small core's approximation, edges crossing get one
// contact midway); capsules as spheres at the nearest
// points of their segments (against a plane or a box: its two ends and
// the segment's point nearest the box); and the ray tests of each shape.
// Nothing allocated: the contacts go to a Contacts' reused arrays, the
// vectors are hxmc's struct values (never in an Array, which boxes them).
class Collide {
	static final scratch = new Contacts();

	// a's and b's contacts, added to out as Contact objects
	public static function test(a:Body, b:Body, out:Array<Contact>) {
		scratch.clear();
		collide(a, b, scratch);
		for (i in 0...scratch.length)
			out.push(scratch.contact(i));
	}

	@:allow(helder.physics) static function collide(a:Body, b:Body, out:Contacts) {
		var from = out.length;
		switch [a.shape, b.shape] {
			case [Sphere(ra), Sphere(rb)]: spheres(a, a.position, ra, b, b.position, rb, out);
			case [Plane(n, o), Sphere(r)]: planeSphere(a, n, o, b, b.position, r, out);
			case [Sphere(r), Plane(n, o)]:
				planeSphere(b, n, o, a, a.position, r, out);
				out.flip(from);
			case [Box(h), Sphere(r)]: boxSphere(a, h, b, b.position, r, out);
			case [Sphere(r), Box(h)]:
				boxSphere(b, h, a, a.position, r, out);
				out.flip(from);
			case [Capsule(ra, ha), Sphere(rb)]: spheres(a, nearestOn(a, ha, b.position), ra, b, b.position, rb, out);
			case [Sphere(ra), Capsule(rb, hb)]: spheres(a, a.position, ra, b, nearestOn(b, hb, a.position), rb, out);
			case [Capsule(ra, ha), Capsule(rb, hb)]: capsules(a, ra, ha, b, rb, hb, out);
			case [Plane(n, o), Capsule(r, h)]: planeCapsule(a, n, o, b, r, h, out);
			case [Capsule(r, h), Plane(n, o)]:
				planeCapsule(b, n, o, a, r, h, out);
				out.flip(from);
			case [Box(bh), Capsule(r, h)]: boxCapsule(a, bh, b, r, h, out);
			case [Capsule(r, h), Box(bh)]:
				boxCapsule(b, bh, a, r, h, out);
				out.flip(from);
			case [Plane(n, o), Box(h)]: planeBox(a, n, o, b, h, out);
			case [Box(h), Plane(n, o)]:
				planeBox(b, n, o, a, h, out);
				out.flip(from);
			case [Box(ha), Box(hb)]: boxes(a, ha, b, hb, out);
			case _:
		}
	}

	// (spheres of a and b centred at ca and cb: a sphere's at its position, a capsule's on its segment)
	static function spheres(a:Body, ca:Vec3, ra:Float, b:Body, cb:Vec3, rb:Float, out:Contacts) {
		var d = cb - ca;
		var d2 = dot(d, d), r = ra + rb;
		if (d2 >= r * r) return;
		var l = Math.sqrt(d2);
		var n = l > 1e-12 ? d / l : new Vec3(0, 1, 0);
		out.add(a, b, n, ca + n * (ra - (r - l) / 2), r - l);
	}

	static function planeSphere(plane:Body, n:Vec3, offset:Float, s:Body, c:Vec3, r:Float, out:Contacts) {
		var dist = dot(n, c) - offset;
		if (dist < r) out.add(plane, s, n, c - n * dist, r - dist);
	}

	// a capsule's segment's ends in the world
	static inline function endA(b:Body, h:Float):Vec3
		return b.position + b.orientation.rotate(new Vec3(0, -h, 0));

	static inline function endB(b:Body, h:Float):Vec3
		return b.position + b.orientation.rotate(new Vec3(0, h, 0));

	// the point of a capsule's segment nearest p
	static function nearestOn(b:Body, h:Float, p:Vec3):Vec3 {
		var a = endA(b, h), ab = endB(b, h) - a;
		var len2 = dot(ab, ab);
		var t = len2 > 1e-18 ? clamp(dot(p - a, ab) / len2, 0, 1) : 0;
		return a + ab * t;
	}

	// two capsules: their segments' nearest points (Ericson's closest points of two segments)
	static function capsules(a:Body, ra:Float, ha:Float, b:Body, rb:Float, hb:Float, out:Contacts) {
		var p1 = endA(a, ha), q1 = endB(a, ha), p2 = endA(b, hb), q2 = endB(b, hb);
		var d1 = q1 - p1, d2 = q2 - p2, r = p1 - p2;
		var aa = dot(d1, d1), ee = dot(d2, d2), f = dot(d2, r);
		var s = 0.0, t = 0.0;
		if (aa <= 1e-18 && ee <= 1e-18) {} else if (aa <= 1e-18) t = clamp(f / ee, 0, 1) else {
			var c = dot(d1, r);
			if (ee <= 1e-18) s = clamp(-c / aa, 0, 1) else {
				var bb = dot(d1, d2), den = aa * ee - bb * bb;
				s = den > 1e-18 ? clamp((bb * f - c * ee) / den, 0, 1) : 0;
				t = (bb * s + f) / ee;
				if (t < 0) {
					t = 0;
					s = clamp(-c / aa, 0, 1);
				} else if (t > 1) {
					t = 1;
					s = clamp((bb - c) / aa, 0, 1);
				}
			}
		}
		spheres(a, p1 + d1 * s, ra, b, p2 + d2 * t, rb, out);
	}

	// a capsule on a plane: its ends' spheres (lying down: two contacts)
	static function planeCapsule(plane:Body, n:Vec3, offset:Float, c:Body, r:Float, h:Float, out:Contacts) {
		planeSphere(plane, n, offset, c, endA(c, h), r, out);
		planeSphere(plane, n, offset, c, endB(c, h), r, out);
	}

	// a capsule against a box: its ends' spheres, and the sphere at the
	// segment's point nearest the box (found by projecting back and forth)
	// where it is not an end
	static function boxCapsule(box:Body, bh:Vec3, c:Body, r:Float, h:Float, out:Contacts) {
		boxSphere(box, bh, c, endA(c, h), r, out);
		boxSphere(box, bh, c, endB(c, h), r, out);
		var inv = box.orientation.conjugate();
		var p = c.position;
		for (_ in 0...4) {
			var l = inv.rotate(p - box.position);
			var q = box.position + box.orientation.rotate(new Vec3(clamp(l.x, -bh.x, bh.x), clamp(l.y, -bh.y, bh.y), clamp(l.z, -bh.z, bh.z)));
			p = nearestOn(c, h, q);
		}
		var a = endA(c, h), b = endB(c, h);
		var da = p - a, db = p - b, m = 0.05 * h;
		if (dot(da, da) > m * m && dot(db, db) > m * m) boxSphere(box, bh, c, p, r, out);
	}

	static function boxSphere(box:Body, h:Vec3, s:Body, c:Vec3, r:Float, out:Contacts) {
		var inv = box.orientation.conjugate();
		var p = inv.rotate(c - box.position);
		var q = new Vec3(clamp(p.x, -h.x, h.x), clamp(p.y, -h.y, h.y), clamp(p.z, -h.z, h.z));
		var d = p - q;
		var d2 = dot(d, d);
		if (d2 > 1e-18) {
			if (d2 >= r * r) return;
			var l = Math.sqrt(d2);
			out.add(box, s, box.orientation.rotate(d / l), box.position + box.orientation.rotate(q), r - l);
			return;
		}
		// (the centre inside the box: out through the nearest face)
		var dx = h.x - Math.abs(p.x), dy = h.y - Math.abs(p.y), dz = h.z - Math.abs(p.z);
		var n = dx <= dy && dx <= dz ? new Vec3(p.x < 0 ? -1 : 1, 0, 0) : dy <= dz ? new Vec3(0, p.y < 0 ? -1 : 1, 0) : new Vec3(0, 0, p.z < 0 ? -1 : 1);
		out.add(box, s, box.orientation.rotate(n), c, Math.min(dx, Math.min(dy, dz)) + r);
	}

	// a box's corner k (0 to 7) in the world
	static inline function corner(b:Body, h:Vec3, k:Int):Vec3
		return b.position + b.orientation.rotate(new Vec3((k & 1) == 0 ? -h.x : h.x, (k & 2) == 0 ? -h.y : h.y, (k & 4) == 0 ? -h.z : h.z));

	static function planeBox(plane:Body, n:Vec3, offset:Float, box:Body, h:Vec3, out:Contacts) {
		for (k in 0...8) {
			var c = corner(box, h, k);
			var dist = dot(n, c) - offset;
			if (dist < 0) out.add(plane, box, n, c, -dist);
		}
	}

	// two boxes: separating axes among their faces' normals (none: no
	// contact; edge against edge axes are not tried), the one of least
	// overlap the contact normal; the contacts are the other box's corners
	// through that face (within the face, 2% of slack: boxes of one size
	// stacked touch at their corners), or, where no corner is through it
	// (edges crossing), one contact between the two
	static function boxes(a:Body, ha:Vec3, b:Body, hb:Vec3, out:Contacts) {
		var ma = a.orientation.toMat4(), mb = b.orientation.toMat4();
		var d = b.position - a.position;
		var best = 1e30, bestAxis = -1;
		for (k in 0...6) {
			var l = k < 3 ? axis(ma, k) : axis(mb, k - 3);
			var ra = 0.0, rb = 0.0;
			for (i in 0...3) {
				ra += at(ha, i) * Math.abs(dot(axis(ma, i), l));
				rb += at(hb, i) * Math.abs(dot(axis(mb, i), l));
			}
			var overlap = ra + rb - Math.abs(dot(d, l));
			if (overlap <= 0) return;
			// (a's faces first on a tie, then by order: the same choice everywhere)
			if (overlap < best - 1e-9) {
				best = overlap;
				bestAxis = k;
			}
		}
		var l = bestAxis < 3 ? axis(ma, bestAxis) : axis(mb, bestAxis - 3);
		// (the normal from a to b)
		var n = dot(d, l) < 0 ? l * -1 : l;
		// the faces across n (each box's axis nearest it) and how far each
		// box reaches along n
		var ka = 0, kb = 0, ra = 0.0, rb = 0.0;
		for (i in 0...3) {
			if (Math.abs(dot(axis(ma, i), n)) > Math.abs(dot(axis(ma, ka), n))) ka = i;
			if (Math.abs(dot(axis(mb, i), n)) > Math.abs(dot(axis(mb, kb), n))) kb = i;
			ra += at(ha, i) * Math.abs(dot(axis(ma, i), n));
			rb += at(hb, i) * Math.abs(dot(axis(mb, i), n));
		}
		var planeA = dot(a.position, n) + ra, planeB = dot(b.position, n) - rb;
		var tolA = 0.02 * Math.min(ha.x, Math.min(ha.y, ha.z)), tolB = 0.02 * Math.min(hb.x, Math.min(hb.y, hb.z));
		var count = out.length;
		// a's corners past b's face, within it; b's past a's (the corners of
		// where the two faces overlap, those of a box face to face once)
		for (k in 0...8) {
			var c = corner(a, ha, k);
			var depth = dot(c, n) - planeB;
			if (depth > 0 && inFace(c - b.position, mb, hb, kb, tolB)) out.add(a, b, n, c, depth);
		}
		var mine = out.length;
		for (k in 0...8) {
			var c = corner(b, hb, k);
			var depth = planeA - dot(c, n);
			if (depth <= 0 || !inFace(c - a.position, ma, ha, ka, tolA)) continue;
			var seen = false;
			for (m in count...mine) {
				var e = out.point(m) - c;
				if (dot(e, e) < 1e-8) seen = true;
			}
			if (!seen) out.add(a, b, n, c, depth);
		}
		if (out.length == count) {
			// (no corner through: edges crossing; a contact midway)
			out.add(a, b, n, a.position + d * 0.5, best);
		}
	}

	// whether r (from a box's centre) lies within its face across axis k
	// (its axes m's columns, half extents e; slack tol)
	static function inFace(r:Vec3, m:Mat4, e:Vec3, k:Int, tol:Float):Bool {
		for (i in 0...3)
			if (i != k && Math.abs(dot(r, axis(m, i))) > at(e, i) + tol) return false;
		return true;
	}

	// a turned box's axis i: its rotation's column
	static inline function axis(m:Mat4, i:Int):Vec3
		return i == 0 ? new Vec3(m.c0.x, m.c0.y, m.c0.z) : i == 1 ? new Vec3(m.c1.x, m.c1.y, m.c1.z) : new Vec3(m.c2.x, m.c2.y, m.c2.z);

	static inline function at(v:Vec3, i:Int):Float
		return i == 0 ? v.x : i == 1 ? v.y : v.z;

	static inline function clamp(x:Float, lo:Float, hi:Float):Float
		return x < lo ? lo : x > hi ? hi : x;

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;

	// the distance along unit d from o to the body's shape, -1 for a miss
	public static function ray(b:Body, o:Vec3, d:Vec3):Float {
		return switch b.shape {
			case Sphere(r):
				var m = o - b.position;
				var bq = dot(m, d), cq = dot(m, m) - r * r;
				if (cq > 0 && bq > 0) -1 else {
					var disc = bq * bq - cq;
					if (disc < 0) -1 else Math.max(-bq - Math.sqrt(disc), 0);
				}
			case Plane(n, offset):
				var den = dot(n, d);
				if (Math.abs(den) < 1e-12) -1 else {
					var t = (offset - dot(n, o)) / den;
					t >= 0 ? t : -1;
				}
			case Box(h):
				// (in the box's frame)
				var inv = b.orientation.conjugate();
				slab(h, inv.rotate(o - b.position), inv.rotate(d));
			case Capsule(r, h):
				// (in the capsule's frame: its side, a cylinder along y, then its ends' spheres)
				var inv = b.orientation.conjugate();
				var lo = inv.rotate(o - b.position), ld = inv.rotate(d);
				var best = -1.0;
				var qa = ld.x * ld.x + ld.z * ld.z, qb = lo.x * ld.x + lo.z * ld.z, qc = lo.x * lo.x + lo.z * lo.z - r * r;
				if (qc <= 0 && Math.abs(lo.y) <= h) best = 0 else if (qa > 1e-18) {
					var disc = qb * qb - qa * qc;
					if (disc >= 0) {
						var t = (-qb - Math.sqrt(disc)) / qa;
						if (t >= 0 && Math.abs(lo.y + ld.y * t) <= h) best = t;
					}
				}
				if (best < 0)
					for (e in 0...2) {
						var m = lo - new Vec3(0, e == 0 ? -h : h, 0);
						var bq = dot(m, ld), cq = dot(m, m) - r * r;
						if (cq > 0 && bq > 0) continue;
						var disc = bq * bq - cq;
						if (disc < 0) continue;
						var t = Math.max(-bq - Math.sqrt(disc), 0);
						if (best < 0 || t < best) best = t;
					}
				best;
		}
	}

	// the distance along d from o to the box of half extents h about the
	// origin, 0 from inside, -1 for a miss (Aabb.ray's slab test, without
	// making an Aabb)
	static function slab(h:Vec3, o:Vec3, d:Vec3):Float {
		var t0 = 0.0, t1 = Math.POSITIVE_INFINITY;
		for (k in 0...3) {
			var ok = at(o, k), dk = at(d, k), hi = at(h, k), lo = hi * -1;
			if (dk == 0) {
				if (ok < lo || ok > hi) return -1;
				continue;
			}
			var a = (lo - ok) / dk, b = (hi - ok) / dk;
			if (a > b) {
				var t = a;
				a = b;
				b = t;
			}
			if (a > t0) t0 = a;
			if (b < t1) t1 = b;
			if (t0 > t1) return -1;
		}
		return t0;
	}
}
