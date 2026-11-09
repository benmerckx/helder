import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.ShaderMath.*;

// Meshes made in code for PaintShader: 16 floats a vertex (position,
// normal, uv, kind, anchor), 32-bit indices. What a shape is painted as
// (kind, its solid's top for the moss, a seed, a kind's own value) and
// what it hangs from (anchor, sway) are set before adding it.
class Builder {
	public static inline var FLOATS = 16;

	public var kind = 0;
	public var top = 0.0;
	public var seed = 0.0;
	public var extra = 0.0;
	public var anchor = new Vec3(0, 0, 0);
	public var sway = 0.0;

	final data:Array<Float> = [];
	final indices:Array<Int> = [];

	public function new() {}

	public var vertices(get, never):Int;

	inline function get_vertices()
		return Std.int(data.length / FLOATS);

	public function vertex(p:Vec3, n:Vec3, u:Float, v:Float):Int {
		var at = vertices;
		for (f in [p.x, p.y, p.z, n.x, n.y, n.z, u, v, kind, top, seed, extra, anchor.x, anchor.y, anchor.z, sway])
			data.push(f);
		return at;
	}

	public function tri(a:Int, b:Int, c:Int) {
		indices.push(a);
		indices.push(b);
		indices.push(c);
	}

	public function quad(a:Vec3, b:Vec3, c:Vec3, d:Vec3, n:Vec3, u0 = 0.0, v0 = 0.0, u1 = 1.0, v1 = 1.0) {
		var i = vertex(a, n, u0, v0), j = vertex(b, n, u1, v0), k = vertex(c, n, u1, v1), l = vertex(d, n, u0, v1);
		tri(i, j, k);
		tri(i, k, l);
	}

	// a box about c, size s, turned yaw about y; its top for the moss
	public function box(c:Vec3, s:Vec3, yaw = 0.0) {
		var co = Math.cos(yaw), si = Math.sin(yaw);
		var cx = c.x, cy = c.y, cz = c.z, hx = s.x / 2, hy = s.y / 2, hz = s.z / 2;
		function at(x:Float, y:Float, z:Float):Vec3 {
			var px = x * hx, pz = z * hz;
			return new Vec3(cx + px * co + pz * si, cy + y * hy, cz - px * si + pz * co);
		}
		function dir(x:Float, y:Float, z:Float):Vec3
			return new Vec3(x * co + z * si, y, -x * si + z * co);
		top = cy + hy;
		quad(at(-1, -1, 1), at(1, -1, 1), at(1, 1, 1), at(-1, 1, 1), dir(0, 0, 1));
		quad(at(1, -1, -1), at(-1, -1, -1), at(-1, 1, -1), at(1, 1, -1), dir(0, 0, -1));
		quad(at(1, -1, 1), at(1, -1, -1), at(1, 1, -1), at(1, 1, 1), dir(1, 0, 0));
		quad(at(-1, -1, -1), at(-1, -1, 1), at(-1, 1, 1), at(-1, 1, -1), dir(-1, 0, 0));
		quad(at(-1, 1, 1), at(1, 1, 1), at(1, 1, -1), at(-1, 1, -1), dir(0, 1, 0));
		quad(at(-1, -1, -1), at(1, -1, -1), at(1, -1, 1), at(-1, -1, 1), dir(0, -1, 0));
	}

	public function boxes(x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float)
		box(new Vec3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), new Vec3(x1 - x0, y1 - y0, z1 - z0));

	// a wall from x0 to x1 between z0 (back) and z1 (front), from y0 up to
	// top, with arched openings of radius r springing at spring, their
	// piers pier wide; a deck over it
	public function arcade(x0:Float, x1:Float, z0:Float, z1:Float, y0:Float, spring:Float, r:Float, pier:Float, top:Float, deck = 0.35) {
		var bay = 2 * r + pier;
		var count = Std.int(Math.max(1, Math.floor((x1 - x0 - pier) / bay)));
		var start = x0 + (x1 - x0 - count * bay - pier) / 2;
		var crown = top + deck;
		this.top = crown;
		// (piers: the ends' and between the openings)
		var x = x0;
		for (k in 0...count + 1) {
			var e = start + k * bay + pier;
			boxes(x, y0, z0, e, top, z1);
			this.top = crown;
			x = e + 2 * r;
		}
		if (x < x1) {
			boxes(x - 2 * r - pier + pier, y0, z0, x1, top, z1);
		}
		for (k in 0...count) {
			var cx = start + k * bay + pier + r;
			this.top = crown;
			spandrel(cx, r, spring, top, z1, 1);
			spandrel(cx, r, spring, top, z0, -1);
			intrados(cx, r, spring, z0, z1);
		}
		boxes(x0 - 0.15, top, z0 - 0.15, x1 + 0.15, crown, z1 + 0.15);
		this.top = crown;
	}

	function arc(cx:Float, r:Float, spring:Float, th:Float):Vec3
		return new Vec3(cx + r * Math.cos(th), spring + r * Math.sin(th), 0);

	function outer(cx:Float, r:Float, spring:Float, top:Float, th:Float):Vec3 {
		var q = Math.PI / 4;
		if (th <= q) return new Vec3(cx + r, spring + (top - spring) * th / q, 0);
		if (th >= 3 * q) return new Vec3(cx - r, top - (top - spring) * (th - 3 * q) / q, 0);
		return new Vec3(cx + r - 2 * r * (th - q) / (2 * q), top, 0);
	}

	function spandrel(cx:Float, r:Float, spring:Float, top:Float, z:Float, facing:Float) {
		var n = 16;
		for (k in 0...n) {
			var a = Math.PI * k / n, b = Math.PI * (k + 1) / n;
			var p0 = arc(cx, r, spring, a), p1 = arc(cx, r, spring, b), q0 = outer(cx, r, spring, top, a), q1 = outer(cx, r, spring, top, b);
			quad(new Vec3(p0.x, p0.y, z), new Vec3(q0.x, q0.y, z), new Vec3(q1.x, q1.y, z), new Vec3(p1.x, p1.y, z), new Vec3(0, 0, facing));
		}
	}

	function intrados(cx:Float, r:Float, spring:Float, z0:Float, z1:Float) {
		var n = 16;
		for (k in 0...n) {
			var a = Math.PI * k / n, b = Math.PI * (k + 1) / n;
			var p0 = arc(cx, r, spring, a), p1 = arc(cx, r, spring, b);
			var m = (a + b) / 2;
			quad(new Vec3(p0.x, p0.y, z0), new Vec3(p1.x, p1.y, z0), new Vec3(p1.x, p1.y, z1), new Vec3(p0.x, p0.y, z1),
				new Vec3(-Math.cos(m), -Math.sin(m), 0));
		}
	}

	// a tube through points (Catmull-Rom between them), its radius from
	// r0 to r1; uv: x around, y along (0 to 1)
	public function tube(points:Array<Vec3>, r0:Float, r1:Float, steps = 8, sides = 7) {
		var path:Array<Vec3> = [];
		for (k in 0...points.length - 1) {
			var p0 = points[k == 0 ? 0 : k - 1], p1 = points[k], p2 = points[k + 1], p3 = points[k + 2 < points.length ? k + 2 : k + 1];
			for (s in 0...steps) {
				var t = s / steps, t2 = t * t, t3 = t2 * t;
				path.push(p0 * (-0.5 * t3 + t2 - 0.5 * t) + p1 * (1.5 * t3 - 2.5 * t2 + 1) + p2 * (-1.5 * t3 + 2 * t2 + 0.5 * t) + p3 * (0.5 * t3 - 0.5 * t2));
			}
		}
		path.push(points[points.length - 1]);
		var up = new Vec3(0, 1, 0);
		var rows:Array<Int> = [];
		for (k in 0...path.length) {
			var t = normalize(path[k + 1 < path.length ? k + 1 : k] - path[k > 0 ? k - 1 : k]);
			if (Math.abs(dot(t, up)) > 0.95) up = new Vec3(1, 0, 0);
			var side = normalize(cross(t, up));
			up = normalize(cross(side, t));
			var v = k / (path.length - 1), r = r0 + (r1 - r0) * v;
			rows.push(vertices);
			for (s in 0...sides + 1) {
				var a = 2 * Math.PI * s / sides;
				var n = side * Math.cos(a) + up * Math.sin(a);
				vertex(path[k] + n * r, n, s / sides, v);
			}
		}
		for (k in 0...rows.length - 1)
			for (s in 0...sides) {
				var a = rows[k] + s, b = rows[k + 1] + s;
				tri(a, b, b + 1);
				tri(a, b + 1, a + 1);
			}
	}

	// a solid of revolution about the axis at c: profile's (radius, height)
	// pairs; uv: x the radius's share of the largest (or around), y along the profile
	public function lathe(c:Vec3, profile:Array<Float>, sides = 12, around = false) {
		var n = Std.int(profile.length / 2), rows:Array<Int> = [];
		var rmax = 0.0;
		for (k in 0...n)
			rmax = Math.max(rmax, profile[k * 2]);
		for (k in 0...n) {
			var r = profile[k * 2], y = profile[k * 2 + 1];
			var k0 = k > 0 ? k - 1 : k, k1 = k < n - 1 ? k + 1 : k;
			var dr = profile[k1 * 2] - profile[k0 * 2], dy = profile[k1 * 2 + 1] - profile[k0 * 2 + 1];
			rows.push(vertices);
			for (s in 0...sides + 1) {
				var a = 2 * Math.PI * s / sides, ca = Math.cos(a), sa = Math.sin(a);
				var len = Math.sqrt(dr * dr + dy * dy);
				var nr = len > 0 ? dy / len : 0, ny = len > 0 ? -dr / len : 1;
				vertex(new Vec3(c.x + r * ca, c.y + y, c.z + r * sa), new Vec3(nr * ca, ny, nr * sa), around ? s / sides : r / rmax, k / (n - 1));
			}
		}
		for (k in 0...n - 1)
			for (s in 0...sides) {
				var a = rows[k] + s, b = rows[k + 1] + s;
				tri(a, b, b + 1);
				tri(a, b + 1, a + 1);
			}
	}

	// a flat disc facing up at c (uv: the square about it), a notch cut from it
	public function pad(c:Vec3, r:Float, notch:Float, sides = 12) {
		var mid = vertex(c, new Vec3(0, 1, 0), 0.5, 0.5);
		var first = vertices;
		for (s in 0...sides + 1) {
			var a = notch + 0.35 + (2 * Math.PI - 0.7) * s / sides;
			vertex(new Vec3(c.x + r * Math.cos(a), c.y, c.z + r * Math.sin(a)), new Vec3(0, 1, 0), 0.5 + 0.5 * Math.cos(a), 0.5 + 0.5 * Math.sin(a));
		}
		for (s in 0...sides)
			tri(mid, first + s, first + s + 1);
	}

	public function vertexBytes():Bytes {
		var b = Bytes.alloc(data.length * 4);
		for (k in 0...data.length)
			b.setFloat(k * 4, data[k]);
		return b;
	}

	public function indexBytes():Bytes {
		var b = Bytes.alloc(indices.length * 4);
		for (k in 0...indices.length)
			b.setInt32(k * 4, indices[k]);
		return b;
	}

	public var count(get, never):Int;

	inline function get_count()
		return indices.length;
}
