package hxmc.physics;

import hxmc.gfx.shader.Vec3;
import hxmc.scene.math.Aabb;

// The contact tests, each adding its contacts to out: sphere against
// sphere, plane and box; box against plane (its corners under it) and box
// (the corners of each inside the other: a small core's approximation,
// edge-on-edge crossings are missed); and the ray tests of each shape.
class Collide {
	public static function test(a:Body, b:Body, out:Array<Contact>) {
		var from = out.length;
		switch [a.shape, b.shape] {
			case [Sphere(ra), Sphere(rb)]: spheres(a, ra, b, rb, out);
			case [Plane(n, o), Sphere(r)]: planeSphere(a, n, o, b, r, out);
			case [Sphere(r), Plane(n, o)]:
				planeSphere(b, n, o, a, r, out);
				flip(out, from);
			case [Box(h), Sphere(r)]: boxSphere(a, h, b, r, out);
			case [Sphere(r), Box(h)]:
				boxSphere(b, h, a, r, out);
				flip(out, from);
			case [Plane(n, o), Box(h)]: planeBox(a, n, o, b, h, out);
			case [Box(h), Plane(n, o)]:
				planeBox(b, n, o, a, h, out);
				flip(out, from);
			case [Box(ha), Box(hb)]:
				cornersIn(a, ha, b, hb, out);
				var mid = out.length;
				cornersIn(b, hb, a, ha, out);
				flip(out, mid);
			case _:
		}
	}

	// the contacts from index from on, turned around (a and b swapped)
	static function flip(out:Array<Contact>, from:Int) {
		for (k in from...out.length) {
			var c = out[k];
			out[k] = new Contact(c.b, c.a, c.normal * -1, c.point, c.depth);
		}
	}

	static function spheres(a:Body, ra:Float, b:Body, rb:Float, out:Array<Contact>) {
		var d = b.position - a.position;
		var d2 = dot(d, d), r = ra + rb;
		if (d2 >= r * r) return;
		var l = Math.sqrt(d2);
		var n = l > 1e-12 ? d / l : new Vec3(0, 1, 0);
		out.push(new Contact(a, b, n, a.position + n * (ra - (r - l) / 2), r - l));
	}

	static function planeSphere(plane:Body, n:Vec3, offset:Float, s:Body, r:Float, out:Array<Contact>) {
		var dist = dot(n, s.position) - offset;
		if (dist < r) out.push(new Contact(plane, s, n, s.position - n * dist, r - dist));
	}

	static function boxSphere(box:Body, h:Vec3, s:Body, r:Float, out:Array<Contact>) {
		var inv = box.orientation.conjugate();
		var p = inv.rotate(s.position - box.position);
		var q = new Vec3(clamp(p.x, -h.x, h.x), clamp(p.y, -h.y, h.y), clamp(p.z, -h.z, h.z));
		var d = p - q;
		var d2 = dot(d, d);
		if (d2 > 1e-18) {
			if (d2 >= r * r) return;
			var l = Math.sqrt(d2);
			out.push(new Contact(box, s, box.orientation.rotate(d / l), box.position + box.orientation.rotate(q), r - l));
			return;
		}
		// (the centre inside the box: out through the nearest face)
		var dx = h.x - Math.abs(p.x), dy = h.y - Math.abs(p.y), dz = h.z - Math.abs(p.z);
		var n = dx <= dy && dx <= dz ? new Vec3(p.x < 0 ? -1 : 1, 0, 0) : dy <= dz ? new Vec3(0, p.y < 0 ? -1 : 1, 0) : new Vec3(0, 0, p.z < 0 ? -1 : 1);
		out.push(new Contact(box, s, box.orientation.rotate(n), s.position, Math.min(dx, Math.min(dy, dz)) + r));
	}

	static function corners(b:Body, h:Vec3):Array<Vec3>
		return [
			for (k in 0...8)
				b.position + b.orientation.rotate(new Vec3((k & 1) == 0 ? -h.x : h.x, (k & 2) == 0 ? -h.y : h.y, (k & 4) == 0 ? -h.z : h.z))
		];

	static function planeBox(plane:Body, n:Vec3, offset:Float, box:Body, h:Vec3, out:Array<Contact>) {
		for (c in corners(box, h)) {
			var dist = dot(n, c) - offset;
			if (dist < 0) out.push(new Contact(plane, box, n, c, -dist));
		}
	}

	// the corners of box a inside box b: contacts pushing each out through b's nearest face
	static function cornersIn(a:Body, ha:Vec3, b:Body, hb:Vec3, out:Array<Contact>) {
		var inv = b.orientation.conjugate();
		for (c in corners(a, ha)) {
			var p = inv.rotate(c - b.position);
			var dx = hb.x - Math.abs(p.x), dy = hb.y - Math.abs(p.y), dz = hb.z - Math.abs(p.z);
			if (dx <= 0 || dy <= 0 || dz <= 0) continue;
			// (the face it is nearest; the normal from b to a there, so from a to b its opposite)
			var n = dx <= dy && dx <= dz ? new Vec3(p.x < 0 ? -1 : 1, 0, 0) : dy <= dz ? new Vec3(0, p.y < 0 ? -1 : 1, 0) : new Vec3(0, 0, p.z < 0 ? -1 : 1);
			out.push(new Contact(a, b, b.orientation.rotate(n) * -1, c, Math.min(dx, Math.min(dy, dz))));
		}
	}

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
				new Aabb(h * -1, h).ray(inv.rotate(o - b.position), inv.rotate(d));
		}
	}
}
