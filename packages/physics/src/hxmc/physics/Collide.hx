package hxmc.physics;

import hxmc.gfx.shader.Vec3;

// The contact tests (a moving sphere against a sphere, a box or a plane)
// and ray tests of each shape.
class Collide {
	public static function test(a:Body, b:Body):Null<Contact> {
		return switch [a.shape, b.shape] {
			case [Sphere(ra), Sphere(rb)]: spheres(a, ra, b, rb);
			case [Sphere(r), Plane(n, o)]: flip(planeSphere(b, n, o, a, r));
			case [Plane(n, o), Sphere(r)]: planeSphere(a, n, o, b, r);
			case [Sphere(r), Box(h)]: flip(boxSphere(b, h, a, r));
			case [Box(h), Sphere(r)]: boxSphere(a, h, b, r);
			case _: null;
		}
	}

	static function flip(c:Null<Contact>):Null<Contact>
		return c == null ? null : new Contact(c.b, c.a, c.normal * -1, c.depth);

	static function spheres(a:Body, ra:Float, b:Body, rb:Float):Null<Contact> {
		var d = b.position - a.position;
		var d2 = d.x * d.x + d.y * d.y + d.z * d.z, r = ra + rb;
		if (d2 >= r * r) return null;
		var l = Math.sqrt(d2);
		return new Contact(a, b, l > 1e-12 ? d / l : new Vec3(0, 1, 0), r - l);
	}

	// (the plane: points p with n.p = offset, n of unit length; a sphere below it is pushed up)
	static function planeSphere(plane:Body, n:Vec3, offset:Float, s:Body, r:Float):Null<Contact> {
		var dist = n.x * s.position.x + n.y * s.position.y + n.z * s.position.z - offset;
		return dist >= r ? null : new Contact(plane, s, n, r - dist);
	}

	static function boxSphere(box:Body, h:Vec3, s:Body, r:Float):Null<Contact> {
		var c = box.position, p = s.position;
		// the box's point nearest the sphere's centre
		var q = new Vec3(clamp(p.x, c.x - h.x, c.x + h.x), clamp(p.y, c.y - h.y, c.y + h.y), clamp(p.z, c.z - h.z, c.z + h.z));
		var d = p - q;
		var d2 = d.x * d.x + d.y * d.y + d.z * d.z;
		if (d2 > 1e-18) {
			if (d2 >= r * r) return null;
			var l = Math.sqrt(d2);
			return new Contact(box, s, d / l, r - l);
		}
		// (the centre inside the box: out through the nearest face)
		var rel = p - c;
		var dx = h.x - Math.abs(rel.x), dy = h.y - Math.abs(rel.y), dz = h.z - Math.abs(rel.z);
		if (dx <= dy && dx <= dz) return new Contact(box, s, new Vec3(rel.x < 0 ? -1 : 1, 0, 0), dx + r);
		if (dy <= dz) return new Contact(box, s, new Vec3(0, rel.y < 0 ? -1 : 1, 0), dy + r);
		return new Contact(box, s, new Vec3(0, 0, rel.z < 0 ? -1 : 1), dz + r);
	}

	static inline function clamp(x:Float, lo:Float, hi:Float):Float
		return x < lo ? lo : x > hi ? hi : x;

	// the distance along unit d from o to the body's shape, -1 for a miss
	public static function ray(b:Body, o:Vec3, d:Vec3):Float {
		return switch b.shape {
			case Sphere(r):
				var m = o - b.position;
				var bq = m.x * d.x + m.y * d.y + m.z * d.z, cq = m.x * m.x + m.y * m.y + m.z * m.z - r * r;
				if (cq > 0 && bq > 0) -1 else {
					var disc = bq * bq - cq;
					if (disc < 0) -1 else Math.max(-bq - Math.sqrt(disc), 0);
				}
			case Plane(n, offset):
				var den = n.x * d.x + n.y * d.y + n.z * d.z;
				if (Math.abs(den) < 1e-12) -1 else {
					var t = (offset - (n.x * o.x + n.y * o.y + n.z * o.z)) / den;
					t >= 0 ? t : -1;
				}
			case Box(h):
				new hxmc.scene.math.Aabb(b.position - h, b.position + h).ray(o, d);
		}
	}
}
