import Course.World;
import haxe.io.Bytes;
import helder.gfx.Device;
import helder.gfx.Texture;
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
	// the aim's predicted path: white, a little glow, tinted per instance
	public final pathDot:Mesh;
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
	// the diorama's: the cloud sea's soft puffs (smooth, flattened, lit
	// low: their emissive the island's shade), the contact shadows (a soft
	// disc, a ramp along a wall's foot: see-through, the island's cool
	// shade, never black), the lanterns' halo (added light), the
	// islands' undersides darker toward the bottom (a ramp on the rock)
	public final cloudPuff:Mesh;
	public final cloudSeaMat:Material;
	public final blobMat:Material;
	public final skirtMat:Material;
	public final blob:Mesh;
	public final glowMat:Material;
	public final glow:Mesh;
	public final rockBoxMat:Material;
	// the creatures: a bird's body and its wing (an inner panel and a swept
	// tip, bent; tinted per instance), a moth, the heron (body, neck and
	// head, beak, legs)
	public final birdBody:Mesh;
	public final wingIn:Mesh;
	public final wingTip:Mesh;
	public final moth:Mesh;
	public final heronBody:Mesh;
	public final heronNeck:Mesh;
	public final heronBeak:Mesh;
	public final heronLegs:Mesh;

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
		// (mown in stripes: Turf)
		grassMat.shader = Turf.TurfShader;
		grassDarkMat.shader = Turf.TurfShader;
		rockMat = mat(0xf2d4b0);
		rockDarkMat = mat(0xd9b8e8);
		railMat = mat(0xfff6e8, 0.55);
		accentMat = mat(0xff6b6b, 0.5);
		grass = box(grassMat);
		grassDark = box(grassDarkMat);
		rock = frustum(rockMat, 8);
		rockDark = frustum(rockDarkMat, 8);
		rail = box(railMat);
		rockBoxMat = mat(0xd9b8e8);
		rockBox = box(rockBoxMat);
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
		sand = box(mat(0xe9c47e, 1));
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
		var pathMat = mat(0xffffff, 0.5, 1, 0.12);
		pathMat.castShadows = false;
		pathDot = Shapes.sphere(device, pathMat, 0.5, 8, 4);
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

		// --- the diorama's
		var clamp = device.createSampler({filter: Linear, wrap: Clamp});
		var under = texture(4, 64, (x, y) -> {
			// (white at the top, a cool shade by the bottom: the rock's colour times it)
			var k = y * y;
			return [255 - 110 * k, 255 - 108 * k, 255 - 80 * k, 255];
		});
		for (m in [rockMat, rockDarkMat]) {
			m.baseColorTexture = under;
			m.sampler = clamp;
		}
		cloudSeaMat = mat(0xffffff, 1);
		cloudSeaMat.castShadows = false;
		cloudPuff = ellipsoid(cloudSeaMat, 20, 10);
		var soft = texture(64, 64, (x, y) -> {
			var dx = x * 2 - 1, dy = y * 2 - 1, r = Math.min(1, Math.sqrt(dx * dx + dy * dy));
			var a = Math.exp(-r * r * 3.2) * (1 - r * r);
			return [255, 255, 255, 255 * a];
		});
		blobMat = mat(0x2c3a6e, 1, 0.3);
		blobMat.baseColorTexture = soft;
		blobMat.sampler = clamp;
		blobMat.castShadows = false;
		blob = quad(blobMat, false);
		skirtMat = mat(0x2c3a6e, 1, 0.24);
		skirtMat.baseColorTexture = texture(4, 64, (x, y) -> [255, 255, 255, 255 * (1 - y) * (1 - y)]);
		skirtMat.sampler = clamp;
		skirtMat.castShadows = false;
		var light = texture(64, 64, (x, y) -> {
			var dx = x * 2 - 1, dy = y * 2 - 1, r = Math.min(1, Math.sqrt(dx * dx + dy * dy));
			// (its falloff in alpha: the light added fades by it, and over the
			// sky behind the scene its coverage is as soft as its light)
			var v = Math.pow(1 - r, 2.6) * 0.7 + Math.exp(-r * r * 30) * 0.3;
			return [255, 255, 255, 255 * v];
		});
		glowMat = new Material("glow", rgb(0x000000), 0, 1, rgb3(0xffc98a, 1.4));
		glowMat.emissiveTexture = light;
		glowMat.baseColorTexture = light;
		glowMat.sampler = clamp;
		glowMat.blend = true;
		glowMat.blending = Additive;
		glowMat.castShadows = false;
		glowMat.fog = false;
		glow = quad(glowMat, true);
		var creature = mat(0xffffff, 0.9);
		creature.castShadows = false;
		creature.doubleSided = true;
		birdBody = birdShape(creature);
		var feather = mat(0xffffff, 0.9);
		feather.castShadows = false;
		feather.doubleSided = true;
		wingIn = made([0, 0, -0.16, 0.52, 0.07, -0.13, 0.5, 0.07, 0.1, 0, 0, -0.16, 0.5, 0.07, 0.1, 0, 0, 0.14], feather);
		wingTip = made([0.52, 0.07, -0.13, 1.0, -0.05, 0.12, 0.5, 0.07, 0.1], feather);
		var mothMat = mat(0xfff0c8, 0.6, 1, 1.6);
		mothMat.castShadows = false;
		mothMat.doubleSided = true;
		moth = made([0, 0, 0, -0.5, 0.1, -0.35, -0.42, -0.05, 0.3, 0, 0, 0, 0.5, 0.1, -0.35, 0.42, -0.05, 0.3], mothMat);
		heronBody = heronShape(mat(0x7f8fb8, 0.85), 0);
		heronNeck = heronShape(mat(0xd8dcef, 0.85), 1);
		heronBeak = heronShape(mat(0xf2b13c, 0.6), 2);
		heronLegs = heronShape(mat(0x2b2d4a, 0.8), 3);
	}

	// a texture of width by height texels from f(u, v) (0..1 across): its rgba 0..255 (sRGB)
	function texture(width:Int, height:Int, f:(Float, Float) -> Array<Float>):Texture {
		var b = Bytes.alloc(width * height * 4);
		for (y in 0...height)
			for (x in 0...width) {
				var c = f((x + 0.5) / width, (y + 0.5) / height), o = (y * width + x) * 4;
				for (k in 0...4)
					b.set(o + k, Std.int(Math.max(0, Math.min(255, c[k]))));
			}
		return device.createTexture({width: width, height: height, data: b});
	}

	// a unit square (-0.5..0.5), lying on xz facing up, or standing in xy facing +z; uv 0..1 across
	function quad(m:Material, standing:Bool):Mesh {
		var p = standing ? [-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0] : [-0.5, 0, 0.5, 0.5, 0, 0.5, 0.5, 0, -0.5, -0.5, 0, -0.5];
		var n = standing ? [0.0, 0, 1] : [0.0, 1, 0];
		var mesh = new Mesh();
		mesh.add(device, p, n.concat(n).concat(n).concat(n), [0, 1, 1, 1, 1, 0, 0, 0], [0, 1, 2, 0, 2, 3], m);
		return mesh;
	}

	// a smooth ball of radius 0.5 squashed to a cloud's puff: its top rounded, its bottom flat
	function ellipsoid(m:Material, segments:Int, rings:Int):Mesh {
		var p = [], idx = [];
		for (r in 0...rings + 1) {
			var a = Math.PI * r / rings, y = Math.cos(a) * 0.5, s = Math.sin(a) * 0.5;
			for (k in 0...segments + 1) {
				var b = 2 * Math.PI * (k % segments) / segments;
				p.push(Math.cos(b) * s);
				p.push(y > 0 ? y * 0.62 : y * 0.22);
				p.push(-Math.sin(b) * s);
			}
		}
		for (r in 0...rings)
			for (k in 0...segments) {
				var a = r * (segments + 1) + k, b = a + segments + 1;
				for (i in [a, b, a + 1, a + 1, b, b + 1])
					idx.push(i);
			}
		var mesh = new Mesh();
		mesh.add(device, p, null, null, idx, m);
		return mesh;
	}

	// a bird's body, a unit long, its beak toward -z: a diamond with a forked tail
	function birdShape(m:Material):Mesh {
		var p = [];
		var nose = new Vec3(0, 0.04, -0.5), top = new Vec3(0, 0.17, -0.12), belly = new Vec3(0, -0.14, -0.06);
		var l = new Vec3(-0.15, 0.02, -0.1), r = new Vec3(0.15, 0.02, -0.1), tail = new Vec3(0, 0.03, 0.28);
		var tl = new Vec3(-0.13, 0.04, 0.55), tr = new Vec3(0.13, 0.04, 0.55), notch = new Vec3(0, 0.03, 0.42);
		tri(p, nose, l, top);
		tri(p, nose, top, r);
		tri(p, nose, belly, l);
		tri(p, nose, r, belly);
		tri(p, top, l, tail);
		tri(p, top, tail, r);
		tri(p, belly, tail, l);
		tri(p, belly, r, tail);
		tri(p, tail, tl, notch);
		tri(p, tail, notch, tr);
		return made(p, m);
	}

	// the heron's parts, about a metre tall at scale 1, facing -z: 0 the
	// body and tail, 1 the neck and head (turning about the neck's foot,
	// its origin: the node's), 2 the beak (on the neck's node), 3 the legs
	function heronShape(m:Material, part:Int):Mesh {
		m.castShadows = false;
		m.doubleSided = true;
		var p = [];
		inline function v(x:Float, y:Float, z:Float)
			return new Vec3(x, y, z);
		switch part {
			case 0:
				var front = v(0, 0.62, -0.2), back = v(0, 0.66, 0.28), top = v(0, 0.78, 0.02), bottom = v(0, 0.52, 0.0);
				var l = v(-0.11, 0.66, 0.02), r = v(0.11, 0.66, 0.02), tail = v(0, 0.58, 0.42);
				tri(p, front, l, top);
				tri(p, front, top, r);
				tri(p, front, bottom, l);
				tri(p, front, r, bottom);
				tri(p, top, l, back);
				tri(p, top, back, r);
				tri(p, bottom, back, l);
				tri(p, bottom, r, back);
				tri(p, back, l, tail);
				tri(p, back, tail, r);
			case 1:
				// (an S: up and forward from the shoulders to the head, four-sided)
				var pts = [v(0, 0, 0), v(0, 0.14, -0.05), v(0, 0.26, 0.01), v(0, 0.36, -0.04)];
				var w = [0.06, 0.035, 0.03, 0.04];
				for (i in 0...pts.length - 1) {
					var a = pts[i], b = pts[i + 1], wa = w[i], wb = w[i + 1];
					var ring0 = [v(a.x - wa, a.y, a.z), v(a.x, a.y, a.z - wa), v(a.x + wa, a.y, a.z), v(a.x, a.y, a.z + wa)];
					var ring1 = [v(b.x - wb, b.y, b.z), v(b.x, b.y, b.z - wb), v(b.x + wb, b.y, b.z), v(b.x, b.y, b.z + wb)];
					for (k in 0...4) {
						var k1 = (k + 1) % 4;
						tri(p, ring0[k], ring1[k], ring0[k1]);
						tri(p, ring0[k1], ring1[k], ring1[k1]);
					}
				}
				// (the head, a crest behind it)
				tri(p, v(-0.04, 0.36, -0.02), v(0, 0.42, -0.04), v(0, 0.37, -0.11));
				tri(p, v(0.04, 0.36, -0.02), v(0, 0.37, -0.11), v(0, 0.42, -0.04));
				tri(p, v(-0.04, 0.36, -0.02), v(0.04, 0.36, -0.02), v(0, 0.42, -0.04));
				tri(p, v(0, 0.42, -0.04), v(-0.01, 0.39, 0.07), v(0.01, 0.4, 0.07));
			case 2:
				tri(p, v(-0.015, 0.39, -0.08), v(0, 0.375, -0.24), v(0.015, 0.39, -0.08));
				tri(p, v(-0.015, 0.39, -0.08), v(0.015, 0.39, -0.08), v(0, 0.365, -0.09));
			case _:
				for (s in [-1.0, 1.0]) {
					var x = s * 0.04;
					tri(p, v(x - 0.012, 0.56, 0.02), v(x, 0, 0), v(x + 0.012, 0.56, 0.02));
					tri(p, v(x, 0, 0), v(x, 0.005, -0.08), v(x + 0.004, 0.006, 0));
				}
		}
		return made(p, m);
	}


	// the island's colours on the materials
	public function theme(w:World) {
		grassMat.baseColor = rgb(w.grass);
		grassDarkMat.baseColor = rgb(w.grassDark);
		rockMat.baseColor = rgb(w.rock);
		rockDarkMat.baseColor = rgb(w.rockDark);
		rockBoxMat.baseColor = rgb(w.rockDark);
		// (the diorama's: the cloud sea lit low, its shade the island's; the contact shadows in the island's cool shade)
		// (lit from above: the sun's side the cloud's colour, the rest falling into the island's shade, never dark)
		var lit = rgb(w.cloud), shade = rgb(w.cloudShade), k = w.night ? 0.5 : 0.72;
		cloudSeaMat.baseColor = new Vec4(lit.x * 0.75, lit.y * 0.75, lit.z * 0.75, 1);
		cloudSeaMat.emissive = new Vec3(shade.x * k, shade.y * k, shade.z * k);
		var sh = rgb(w.shade);
		blobMat.baseColor = new Vec4(sh.x, sh.y, sh.z, w.night ? 0.42 : 0.32);
		skirtMat.baseColor = new Vec4(sh.x, sh.y, sh.z, w.night ? 0.32 : 0.26);
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
	function made(p:Array<Float>, m:Material, ?uvs:Array<Float>):Mesh {
		var mesh = new Mesh();
		mesh.add(device, p, null, uvs, null, m);
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
		// (v down its height: the darker ramp toward the bottom)
		return made(p, m, [for (i in 0...Std.int(p.length / 3)) for (k in 0...2) k == 0 ? 0.5 : Math.min(1, -p[i * 3 + 1])]);
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
