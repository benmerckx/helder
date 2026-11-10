import haxe.io.Bytes;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.ShaderMath.*;
import Sdf;

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

	// a tube through points (Catmull-Rom between them), its radius from
	// r0 to r1; uv: x around, y along (0 to 1)
	public function tube(points:Array<Vec3>, r0:Float, r1:Float, steps = 8, sides = 7, rough = 0.0) {
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
				var q = path[k] + n * r;
				// (knots and gnarls: the radius swollen by noise where it is rough)
				var knob = rough > 0 ? 1 + rough * (noise3(q.x * 2.7, q.y * 2.7, q.z * 2.7) - 0.4) * 1.6 : 1;
				vertex(path[k] + n * (r * knob), n, s / sides, v);
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

	// the surface of a signed distance field in a box, sampled every cell
	// (surface nets: a vertex a cell the surface crosses, a quad an edge it
	// crosses), its normals from the field's gradient; uv: x how open it is
	// (the field probed along the normal: crevices dark), y the moss's
	// share (from moss, given the point and its normal); top: how far below
	// the nearest of tops (where moss hangs from) it is
	public function field(f:Field, x0:Float, y0:Float, z0:Float, x1:Float, y1:Float, z1:Float, cell:Float, ?tops:Array<Float>,
			?moss:(x:Float, y:Float, z:Float, nx:Float, ny:Float, nz:Float) -> Float) {
		var nx = Std.int(Math.ceil((x1 - x0) / cell)) + 1, ny = Std.int(Math.ceil((y1 - y0) / cell)) + 1, nz = Std.int(Math.ceil((z1 - z0) / cell)) + 1;
		var v = new haxe.ds.Vector<Float>(nx * ny * nz);
		for (k in 0...nz)
			for (j in 0...ny)
				for (i in 0...nx)
					v[i + nx * (j + ny * k)] = f(x0 + i * cell, y0 + j * cell, z0 + k * cell);
		var cx = nx - 1, cy = ny - 1, cz = nz - 1;
		var ids = new haxe.ds.Vector<Int>(cx * cy * cz);
		var corner = [for (c in 0...8) (c & 1) + nx * (((c >> 1) & 1) + ny * ((c >> 2) & 1))];
		var edges = [0, 1, 2, 3, 4, 5, 6, 7, 0, 2, 1, 3, 4, 6, 5, 7, 0, 4, 1, 5, 2, 6, 3, 7];
		var h = cell * 0.5;
		for (k in 0...cz)
			for (j in 0...cy)
				for (i in 0...cx) {
					var at = i + nx * (j + ny * k), id = i + cx * (j + cy * k);
					var mask = 0;
					for (c in 0...8)
						if (v[at + corner[c]] < 0) mask |= 1 << c;
					if (mask == 0 || mask == 255) {
						ids[id] = -1;
						continue;
					}
					var sx = 0.0, sy = 0.0, sz = 0.0, n = 0;
					for (e in 0...12) {
						var a = edges[e * 2], b = edges[e * 2 + 1];
						if (((mask >> a) & 1) == ((mask >> b) & 1)) continue;
						var va = v[at + corner[a]], vb = v[at + corner[b]];
						var t = va / (va - vb);
						sx += (a & 1) + ((b & 1) - (a & 1)) * t;
						sy += ((a >> 1) & 1) + (((b >> 1) & 1) - ((a >> 1) & 1)) * t;
						sz += ((a >> 2) & 1) + (((b >> 2) & 1) - ((a >> 2) & 1)) * t;
						n++;
					}
					var px = x0 + (i + sx / n) * cell, py = y0 + (j + sy / n) * cell, pz = z0 + (k + sz / n) * cell;
					var gx = f(px + h, py, pz) - f(px - h, py, pz), gy = f(px, py + h, pz) - f(px, py - h, pz), gz = f(px, py, pz + h) - f(px, py, pz - h);
					var len = Math.sqrt(gx * gx + gy * gy + gz * gz);
					if (len > 0) {
						gx /= len;
						gy /= len;
						gz /= len;
					} else gy = 1;
					var shut = 0.0;
					for (s in [2.0, 5.0, 11.0]) {
						var d = s * cell;
						shut += Math.max(d - f(px + gx * d, py + gy * d, pz + gz * d), 0) / d;
					}
					var open = Math.max(0, 1 - shut * 0.4);
					top = 99;
					if (tops != null)
						for (t in tops)
							if (t - py > -0.15) top = Math.min(top, t - py);
					ids[id] = vertex(new Vec3(px, py, pz), new Vec3(gx, gy, gz), open, moss == null ? 0 : moss(px, py, pz, gx, gy, gz));
				}
		inline function cellId(i:Int, j:Int, k:Int)
			return ids[i + cx * (j + cy * k)];
		for (k in 0...nz)
			for (j in 0...ny)
				for (i in 0...nx) {
					var at = i + nx * (j + ny * k);
					var inside = v[at] < 0;
					if (i < cx && j > 0 && k > 0 && j < cy && k < cz && (v[at + 1] < 0) != inside) {
						var a = cellId(i, j - 1, k - 1), b = cellId(i, j, k - 1), c = cellId(i, j, k), d = cellId(i, j - 1, k);
						if (a >= 0 && b >= 0 && c >= 0 && d >= 0) {
							tri(a, b, c);
							tri(a, c, d);
						}
					}
					if (j < cy && i > 0 && k > 0 && i < cx && k < cz && (v[at + nx] < 0) != inside) {
						var a = cellId(i - 1, j, k - 1), b = cellId(i, j, k - 1), c = cellId(i, j, k), d = cellId(i - 1, j, k);
						if (a >= 0 && b >= 0 && c >= 0 && d >= 0) {
							tri(a, b, c);
							tri(a, c, d);
						}
					}
					if (k < cz && i > 0 && j > 0 && i < cx && j < cy && (v[at + nx * ny] < 0) != inside) {
						var a = cellId(i - 1, j - 1, k), b = cellId(i, j - 1, k), c = cellId(i, j, k), d = cellId(i - 1, j, k);
						if (a >= 0 && b >= 0 && c >= 0 && d >= 0) {
							tri(a, b, c);
							tri(a, c, d);
						}
					}
				}
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
