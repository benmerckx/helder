import helder.gfx.Device;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.render.Material;
import helder.scene.render.Mesh;
import helder.scene.render.Shapes;

// The meshes the course is drawn with, made once in code (no files), flat
// shaded and unit sized: a node's scale sizes each, so every piece of one
// kind is the same primitive (drawn instanced). Pastel colours, a matte
// finish.
class Kit {
	public final device:Device;
	public final grass:Mesh;
	public final grassDark:Mesh;
	public final rock:Mesh;
	public final rockDark:Mesh;
	public final rail:Mesh;
	public final post:Mesh;
	public final mover:Mesh;
	public final ball:Mesh;
	public final hole:Mesh;
	public final rim:Mesh;
	public final pole:Mesh;
	public final flag:Mesh;
	public final tee:Mesh;
	public final dot:Mesh;
	public final dotMaterial:Material;
	public final shadow:Mesh;
	public final trail:Mesh;
	public final trailMaterial:Material;
	public final ring:Mesh;
	public final ringMaterial:Material;
	public final confetti:Array<Mesh>;
	public final cloud:Mesh;
	public final leaves:Mesh;
	public final trunk:Mesh;

	public static function rgb(hex:Int, a = 1.0):Vec4 {
		// (sRGB to linear, roughly: the renderer's colours are linear)
		inline function lin(c:Int):Float
			return Math.pow(c / 255, 2.2);
		return new Vec4(lin((hex >> 16) & 255), lin((hex >> 8) & 255), lin(hex & 255), a);
	}

	static function mat(hex:Int, roughness = 0.85, a = 1.0):Material {
		var m = new Material("golf", rgb(hex, a), 0, roughness);
		if (a < 1) m.blend = true;
		return m;
	}

	public function new(device:Device) {
		this.device = device;
		grass = box(mat(0x74d27c));
		grassDark = box(mat(0x66c470));
		rock = frustum(mat(0xf2d4b0), 8);
		rockDark = frustum(mat(0xd9b8e8), 8);
		rail = box(mat(0xfff6e8, 0.6));
		post = cylinder(mat(0xff8a80, 0.5), 10, false);
		mover = box(mat(0x7ec8f8, 0.5));
		ball = icosphere(mat(0xffffff, 0.4));
		hole = cylinder(mat(0x2b2d42, 1), 16, false);
		rim = cylinder(mat(0xffffff, 0.7), 16, false);
		pole = cylinder(mat(0xfafafa, 0.5), 6, false);
		flag = prism(mat(0xff6b6b, 0.7));
		tee = cylinder(mat(0xfff0a8, 0.7), 20, false);
		dotMaterial = mat(0xffffff, 0.5);
		dot = Shapes.sphere(device, dotMaterial, 0.5, 8, 4);
		shadow = cylinder(mat(0x000000, 1, 0.22), 16, false);
		trailMaterial = mat(0xffffff, 0.6, 0.45);
		trail = Shapes.sphere(device, trailMaterial, 0.5, 8, 4);
		ringMaterial = mat(0xfff3b0, 0.6, 0.7);
		ring = cylinder(ringMaterial, 24, true);
		confetti = [for (c in [0xff8a80, 0xffd166, 0x7ec8f8, 0xb39ddb, 0x8fd694]) box(mat(c, 0.6))];
		cloud = icosphere(mat(0xffffff, 1));
		leaves = cone(mat(0x6cc070), 7);
		trunk = cylinder(mat(0xc8a07a), 6, false);
	}

	function box(m:Material):Mesh
		return Shapes.box(device, m, 1, 1, 1);

	// (triangles of their own vertices: flat shaded, normals from the faces)
	function made(p:Array<Float>, m:Material):Mesh {
		var mesh = new Mesh();
		mesh.add(device, p, null, null, null, m);
		return mesh;
	}

	static function tri(p:Array<Float>, a:Vec3, b:Vec3, c:Vec3) {
		for (v in [a, b, c]) {
			p.push(v.x);
			p.push(v.y);
			p.push(v.z);
		}
	}

	// an island's underside: an n-sided cone cut off, its top the unit square's
	// circle at y = 0, narrowing to a third at y = -1 (counter-clockwise from above: outward)
	function frustum(m:Material, n:Int):Mesh {
		var p = [];
		for (i in 0...n) {
			var a0 = 2 * Math.PI * i / n, a1 = 2 * Math.PI * (i + 1) / n;
			var t0 = new Vec3(Math.cos(a0) * 0.5, 0, Math.sin(a0) * 0.5), t1 = new Vec3(Math.cos(a1) * 0.5, 0, Math.sin(a1) * 0.5);
			var b0 = new Vec3(t0.x * 0.35, -1, t0.z * 0.35), b1 = new Vec3(t1.x * 0.35, -1, t1.z * 0.35);
			tri(p, t0, t1, b1);
			tri(p, t0, b1, b0);
			tri(p, new Vec3(0, -1.05, 0), b0, b1);
		}
		return made(p, m);
	}

	// a unit cylinder (radius 0.5, y from 0 to 1), n sides; open: no caps (a ring)
	function cylinder(m:Material, n:Int, open:Bool):Mesh {
		var p = [];
		for (i in 0...n) {
			var a0 = 2 * Math.PI * i / n, a1 = 2 * Math.PI * (i + 1) / n;
			var b0 = new Vec3(Math.cos(a0) * 0.5, 0, -Math.sin(a0) * 0.5), b1 = new Vec3(Math.cos(a1) * 0.5, 0, -Math.sin(a1) * 0.5);
			var t0 = new Vec3(b0.x, 1, b0.z), t1 = new Vec3(b1.x, 1, b1.z);
			tri(p, b0, b1, t1);
			tri(p, b0, t1, t0);
			if (!open) {
				tri(p, new Vec3(0, 1, 0), t0, t1);
				tri(p, new Vec3(0, 0, 0), b1, b0);
			}
		}
		if (open) m.doubleSided = true;
		return made(p, m);
	}

	// a unit cone (radius 0.5 at y = 0, its tip at y = 1)
	function cone(m:Material, n:Int):Mesh {
		var p = [];
		for (i in 0...n) {
			var a0 = 2 * Math.PI * i / n, a1 = 2 * Math.PI * (i + 1) / n;
			var b0 = new Vec3(Math.cos(a0) * 0.5, 0, -Math.sin(a0) * 0.5), b1 = new Vec3(Math.cos(a1) * 0.5, 0, -Math.sin(a1) * 0.5);
			tri(p, b0, b1, new Vec3(0, 1, 0));
			tri(p, new Vec3(0, 0, 0), b1, b0);
		}
		return made(p, m);
	}

	// a pennant: a thin triangular prism from the pole (x = 0) out to x = 1, y from 0 to 1
	function prism(m:Material):Mesh {
		m.doubleSided = true;
		var p = [];
		tri(p, new Vec3(0, 0, 0), new Vec3(1, 0.5, 0), new Vec3(0, 1, 0));
		return made(p, m);
	}

	// a low-poly ball: an icosahedron split once (80 faces), radius 0.5, flat shaded
	function icosphere(m:Material):Mesh {
		var t = (1 + Math.sqrt(5)) / 2;
		var v = [
			new Vec3(-1, t, 0), new Vec3(1, t, 0), new Vec3(-1, -t, 0), new Vec3(1, -t, 0), new Vec3(0, -1, t), new Vec3(0, 1, t), new Vec3(0, -1, -t),
			new Vec3(0, 1, -t), new Vec3(t, 0, -1), new Vec3(t, 0, 1), new Vec3(-t, 0, -1), new Vec3(-t, 0, 1)
		];
		var f = [
			0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5,
			2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1
		];
		inline function unit(a:Vec3):Vec3 {
			var l = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
			return new Vec3(a.x / l * 0.5, a.y / l * 0.5, a.z / l * 0.5);
		}
		var p = [];
		var i = 0;
		while (i < f.length) {
			var a = unit(v[f[i]]), b = unit(v[f[i + 1]]), c = unit(v[f[i + 2]]);
			var ab = unit(a + b), bc = unit(b + c), ca = unit(c + a);
			tri(p, a, ab, ca);
			tri(p, b, bc, ab);
			tri(p, c, ca, bc);
			tri(p, ab, bc, ca);
			i += 3;
		}
		return made(p, m);
	}
}
