import Course.World;
import helder.gfx.Device;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.render.Material;
import helder.scene.render.Mesh;
import helder.scene.render.Shapes;

// The meshes the course is drawn with, made once in code (no files), flat
// shaded and unit sized: a node's scale sizes each, so every piece of one
// kind is the same primitive (drawn instanced). The island's colours are
// the materials' (theme: an island's grass, rock and rails), the pieces'
// own fixed: bumpers, portals, switches and gates glow (emissive: the
// <Scene>'s bloom catches them).
class Kit {
	public final device:Device;
	// the island's
	public final grassMat:Material;
	public final grassDarkMat:Material;
	public final rockMat:Material;
	public final rockDarkMat:Material;
	public final railMat:Material;
	public final accentMat:Material;
	public final grass:Mesh;
	public final grassDark:Mesh;
	public final rock:Mesh;
	public final rockDark:Mesh;
	public final rail:Mesh;
	public final rockBox:Mesh;
	public final accentBox:Mesh;
	public final accentCylinder:Mesh;
	// the pieces'
	public final post:Mesh;
	public final bumper:Mesh;
	public final bumperCap:Mesh;
	public final bumperMat:Material;
	public final mover:Mesh;
	public final spinner:Mesh;
	public final hub:Mesh;
	public final liftTop:Mesh;
	public final piston:Mesh;
	public final boost:Mesh;
	public final chevron:Mesh;
	public final chevronMat:Material;
	public final sand:Mesh;
	public final ice:Mesh;
	public final water:Mesh;
	public final waterMat:Material;
	public final ripple:Mesh;
	public final rippleMat:Material;
	public final portal:Mesh;
	public final portalRing:Mesh;
	public final plates:Array<Mesh>;
	public final plateLit:Array<Mesh>;
	public final gates:Array<Mesh>;
	public final pane:Mesh;
	public final arrow:Mesh;
	public final crumble:Mesh;
	public final crack:Mesh;
	public final lantern:Mesh;
	// the ball, the cup and the flag, the aim
	public final ball:Mesh;
	public final hole:Mesh;
	public final rim:Mesh;
	public final pole:Mesh;
	public final flag:Mesh;
	public final flagMat:Material;
	public final tee:Mesh;
	public final dot:Mesh;
	public final dotMaterial:Material;
	public final ring:Mesh;
	public final ringMaterial:Material;
	// the scenery
	public final cloud:Mesh;
	public final leaves:Mesh;
	public final leavesMat:Material;
	public final trunk:Mesh;
	public final wing:Mesh;
	public final stone:Mesh;
	// particles: soft puffs, confetti, glowing motes (InstancedMesh's)
	public final puff:Mesh;
	public final confetti:Mesh;
	public final mote:Mesh;

	// the switches' and gates' colours, by group
	public static final GROUPS = [0xffc857, 0x5ad1ff, 0xff7bd5];

	public static function rgb(hex:Int, a = 1.0):Vec4 {
		// (sRGB to linear, roughly: the renderer's colours are linear)
		inline function lin(c:Int):Float
			return Math.pow(c / 255, 2.2);
		return new Vec4(lin((hex >> 16) & 255), lin((hex >> 8) & 255), lin(hex & 255), a);
	}

	public static function rgb3(hex:Int, k = 1.0):Vec3 {
		var c = rgb(hex);
		return new Vec3(c.x * k, c.y * k, c.z * k);
	}

	static function mat(hex:Int, roughness = 0.85, a = 1.0, glow = 0.0):Material {
		var m = new Material("golf", rgb(hex, a), 0, roughness, glow > 0 ? rgb3(hex, glow) : null);
		if (a < 1) m.blend = true;
		return m;
	}

	public function new(device:Device) {
		this.device = device;
		grassMat = mat(0x74d27c);
		grassDarkMat = mat(0x66c470);
		rockMat = mat(0xf2d4b0);
		rockDarkMat = mat(0xd9b8e8);
		railMat = mat(0xfff6e8, 0.55);
		accentMat = mat(0xff6b6b, 0.5);
		grass = box(grassMat);
		grassDark = box(grassDarkMat);
		rock = frustum(rockMat, 8);
		rockDark = frustum(rockDarkMat, 8);
		rail = box(railMat);
		rockBox = box(rockDarkMat);
		accentBox = box(accentMat);
		accentCylinder = cylinder(accentMat, 16, false);
		post = cylinder(mat(0xfff6e8, 0.5), 12, false);
		bumperMat = mat(0xff5d73, 0.35, 1, 0.25);
		bumper = cylinder(bumperMat, 16, false);
		bumperCap = cylinder(mat(0xffffff, 0.3), 16, false);
		mover = box(mat(0x7ec8f8, 0.45));
		spinner = box(mat(0xffd166, 0.4));
		hub = cylinder(mat(0x6c5b7b, 0.4), 12, false);
		var liftMat = mat(0xc9d6df, 0.3);
		liftMat.metallic = 0.6;
		liftTop = box(liftMat);
		piston = cylinder(liftMat, 12, false);
		boost = box(mat(0xff8f3f, 0.4, 1, 0.35));
		chevronMat = mat(0xfff0c0, 0.4, 1, 1.4);
		chevron = arrowHead(chevronMat);
		sand = box(mat(0xf3d9a4, 1));
		var iceMat = mat(0xd8f3ff, 0.08, 0.92);
		iceMat.clearcoat = 1;
		ice = box(iceMat);
		waterMat = mat(0x3bb3e0, 0.06, 0.82);
		waterMat.clearcoat = 1;
		waterMat.castShadows = false;
		water = box(waterMat);
		rippleMat = mat(0xffffff, 0.3, 0.5);
		rippleMat.castShadows = false;
		ripple = cylinder(rippleMat, 24, true);
		portal = cylinder(mat(0x8a5cff, 0.2, 1, 1.6), 24, false);
		portalRing = cylinder(mat(0xd9c6ff, 0.2, 1, 2.2), 24, true);
		plates = [for (c in GROUPS) cylinder(mat(c, 0.4, 1, 0.15), 20, false)];
		plateLit = [for (c in GROUPS) cylinder(mat(c, 0.3, 1, 1.6), 20, false)];
		gates = [for (c in GROUPS) box(mat(c, 0.35, 1, 0.45))];
		var paneMat = mat(0x9ee7ff, 0.1, 0.35, 0.6);
		paneMat.castShadows = false;
		paneMat.doubleSided = true;
		pane = box(paneMat);
		arrow = arrowHead(mat(0x9ee7ff, 0.3, 1, 1.2));
		crumble = box(mat(0xd2c46a, 0.9));
		crack = box(mat(0x6b5a3a, 1));
		lantern = icosphere(mat(0xffd27a, 0.3, 1, 3.0));
		ball = icosphere(mat(0xffffff, 0.35, 1, 0.08));
		hole = cylinder(mat(0x1d1f30, 1), 20, false);
		rim = cylinder(mat(0xffffff, 0.6), 20, false);
		pole = cylinder(mat(0xfafafa, 0.4), 6, false);
		flagMat = mat(0xff6b6b, 0.7);
		flag = pennant(flagMat);
		tee = cylinder(mat(0xfff0a8, 0.7), 20, false);
		dotMaterial = mat(0xffffff, 0.5, 1, 0.4);
		dot = Shapes.sphere(device, dotMaterial, 0.5, 8, 4);
		ringMaterial = mat(0xfff3b0, 0.6, 0.7, 0.8);
		ringMaterial.castShadows = false;
		ring = cylinder(ringMaterial, 32, true);
		var cloudMat = mat(0xffffff, 1);
		cloudMat.castShadows = false;
		cloud = icosphere(cloudMat);
		leavesMat = mat(0x6cc070);
		leaves = cone(leavesMat, 7);
		trunk = cylinder(mat(0xc8a07a), 6, false);
		var wingMat = mat(0x3d3a50, 0.8);
		wingMat.castShadows = false;
		wing = pennant(wingMat);
		stone = icosphere(mat(0xbfb6d6, 0.9));
		var puffMat = mat(0xffffff, 1);
		puffMat.castShadows = false;
		puff = icosphere(puffMat);
		var confettiMat = mat(0xffffff, 0.6);
		confettiMat.castShadows = false;
		confettiMat.doubleSided = true;
		confetti = Shapes.box(device, confettiMat, 1, 0.12, 0.6);
		var moteMat = mat(0xffffff, 0.5, 1, 2.5);
		moteMat.castShadows = false;
		mote = Shapes.sphere(device, moteMat, 0.5, 6, 4);
	}

	// the island's colours on the materials
	public function theme(w:World) {
		grassMat.baseColor = rgb(w.grass);
		grassDarkMat.baseColor = rgb(w.grassDark);
		rockMat.baseColor = rgb(w.rock);
		rockDarkMat.baseColor = rgb(w.rockDark);
		railMat.baseColor = rgb(w.rail);
		accentMat.baseColor = rgb(w.accent);
		flagMat.baseColor = rgb(w.accent);
		flagMat.emissive = rgb3(w.accent, w.night ? 0.5 : 0.08);
		leavesMat.baseColor = rgb(w.grassDark);
		// (the night's water darker, its shine the moon's)
		waterMat.baseColor = w.night ? rgb(0x2a6fb0, 0.85) : rgb(0x3bb3e0, 0.8);
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
	// circle at y = 0, narrowing to a third at y = -1 (counter-clockwise from above: outward),
	// its sides broken into two bands for a rockier edge
	function frustum(m:Material, n:Int):Mesh {
		var p = [];
		for (i in 0...n) {
			var a0 = 2 * Math.PI * i / n, a1 = 2 * Math.PI * (i + 1) / n;
			var am = (a0 + a1) / 2;
			var t0 = new Vec3(Math.cos(a0) * 0.5, 0, Math.sin(a0) * 0.5), t1 = new Vec3(Math.cos(a1) * 0.5, 0, Math.sin(a1) * 0.5);
			// (a ledge part way down, its points pushed out and in by turns)
			var k = i % 2 == 0 ? 0.46 : 0.4;
			var m0 = new Vec3(Math.cos(a0) * 0.43, -0.45, Math.sin(a0) * 0.43), m1 = new Vec3(Math.cos(a1) * 0.43, -0.45, Math.sin(a1) * 0.43);
			var mm = new Vec3(Math.cos(am) * k, -0.4, Math.sin(am) * k);
			var b0 = new Vec3(t0.x * 0.3, -1, t0.z * 0.3), b1 = new Vec3(t1.x * 0.3, -1, t1.z * 0.3);
			tri(p, t0, t1, mm);
			tri(p, t0, mm, m0);
			tri(p, t1, m1, mm);
			tri(p, m0, mm, m1);
			tri(p, m0, m1, b1);
			tri(p, m0, b1, b0);
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

	// a pennant: a triangle from the pole (x = 0) out to x = 1, y from 0 to 1 (a wing too)
	function pennant(m:Material):Mesh {
		m.doubleSided = true;
		var p = [];
		tri(p, new Vec3(0, 0, 0), new Vec3(1, 0.5, 0), new Vec3(0, 1, 0));
		return made(p, m);
	}

	// a chevron lying flat, pointing to -z: a unit wide, half a unit deep, a tenth high
	function arrowHead(m:Material):Mesh {
		var p = [];
		var pts = [new Vec3(-0.5, 0, 0.25), new Vec3(0, 0, -0.25), new Vec3(0.5, 0, 0.25), new Vec3(0.5, 0, 0.5), new Vec3(0, 0, 0), new Vec3(-0.5, 0, 0.5)];
		// (its outline: a band of quads up to y = 0.1, its top)
		for (i in 0...pts.length) {
			var a = pts[i], b = pts[(i + 1) % pts.length];
			var at = new Vec3(a.x, 0.1, a.z), bt = new Vec3(b.x, 0.1, b.z);
			tri(p, a, at, bt);
			tri(p, a, bt, b);
		}
		inline function top(v:Vec3)
			return new Vec3(v.x, 0.1, v.z);
		tri(p, top(pts[0]), top(pts[5]), top(pts[4]));
		tri(p, top(pts[0]), top(pts[4]), top(pts[1]));
		tri(p, top(pts[1]), top(pts[4]), top(pts[3]));
		tri(p, top(pts[1]), top(pts[3]), top(pts[2]));
		m.doubleSided = true;
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
