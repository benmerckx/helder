package helder.scene.render;

import haxe.io.Bytes;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Texture2D;
import helder.gfx.shader.Vec2;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.render.PbrShader;
import helder.test.Test;
import helder.scene.render.PbrShader.materialOf;
import helder.scene.render.PbrShader.shadeAt;
import helder.scene.render.PbrShader.uvOf;
import helder.scene.render.PbrShader.fogAmount;
import helder.scene.render.PbrShader.instanceNormal;

// The standard shader's material options run on the CPU (shadeAt
// as the GPU runs it, its textures white): Material.ground's sunset with
// the sphere under it and the sky it no longer reflects below its
// horizon, Material.air towards the limb, Material.crystal's Fresnel and
// see-through middle, a node's tint (MeshRenderer.tint), a double-sided
// face seen from behind; glTF's uv transform, clear coat and transmission;
// an instance's normal (instanceNormal) as the object's normalMatrix turns it.
// The renderer drawing them: the 3d lane's "crystal", "khrtransform" and
// "khrclearcoat" frames (tests/3d/Scenes.hx).
function tests() {
	describe("Material options in PbrShader", () -> {
		final white = new Texture2D(1, 1, Bytes.ofHex("ffffffff"));
		// a frame lit by a sun along l (no shadows, no environment), the eye at eye
		function frame(l:Vec3, eye:Vec3, ?fog:Fog):PbrFrame {
			var zero = new Vec4(0, 0, 0, 0);
			return {
				viewProj: Mat4.identity(), eye: new Vec4(eye.x, eye.y, eye.z, 1), lightDir: new Vec4(l.x, l.y, l.z, 0), lightColor: new Vec4(3, 3, 3, 0),
				sky: new Vec4(0.1, 0.1, 0.1, 0), ground: new Vec4(0.1, 0.1, 0.1, 0), exposure: new Vec4(1, 1, 0, 0), lightViewProj: Mat4.identity(),
				shadow: zero, point0: zero, point1: zero, point2: zero, point3: zero, pointColor0: zero, pointColor1: zero, pointColor2: zero,
				pointColor3: zero, spot0: new Vec4(0, 0, 0, -2), spot1: new Vec4(0, 0, 0, -2), spot2: new Vec4(0, 0, 0, -2), spot3: new Vec4(0, 0, 0, -2),
				lightViewProjFar: Mat4.identity(), shadowFar: zero, environment: zero, rim: zero, fog: Fog.colorOf(fog), fogShape: Fog.shapeOf(fog), shadowSoft: zero
			};
		}
		function material(m:Material):PbrMaterial
			return materialOf(m);
		// the colour at the origin, its normal n, the node's up, tinted
		function shade(m:Material, n:Vec3, up:Vec3, l:Vec3, eye:Vec3, ?tint:Vec3, ?fog:Fog):Vec4
			return shadeAt(n, new Vec3(0, 0, 0), new Vec2(0, 0), up, tint ?? new Vec3(1, 1, 1), frame(l, eye, fog), material(m), white, white, white,
				white, white, white, white);
		function sum(c:Vec4):Float
			return c.x + c.y + c.z;

		// (the sun overhead, the eye up and in front)
		function sunny()
			return new Vec3(0, 1, 0);
		function above()
			return new Vec3(0, 3, 4);

		test("ground: the sun sets on it with the sphere's side under it", () -> {
			var m = new Material("wall", new Vec4(0.5, 0.5, 0.5, 1), 0, 0.6);
			// (a wall facing the sun, its node's up turned from the sun: the night side)
			var lit = shade(m, sunny(), new Vec3(0, 1, 0), sunny(), above()), night = shade(m, sunny(), new Vec3(0, -1, 0), sunny(), above());
			approx(sum(lit), sum(night), 1e-6, "without ground its up does not matter");
			m.ground = 1;
			var day = shade(m, sunny(), new Vec3(0, 1, 0), sunny(), above()), dark = shade(m, sunny(), new Vec3(0, -1, 0), sunny(), above());
			approx(sum(day), sum(lit), 1e-6, "on the day side as before");
			assert(sum(dark) < sum(lit) * 0.25, 'on the night side its sun gone: ${sum(dark)} against ${sum(lit)}');
			// (at the terminator: between)
			var dusk = shade(m, sunny(), new Vec3(0.9976, 0.0698, 0), sunny(), above());
			assert(sum(dusk) > sum(dark) && sum(dusk) < sum(day), "faded across the terminator");
		});

		test("fog: the surface towards its colour by the distance past its start", () -> {
			var m = new Material("wall", new Vec4(0.5, 0.5, 0.5, 1), 0, 0.6), n = new Vec3(0, 0, 1), eye = new Vec3(0, 0, 10);
			var fog = new Fog(new Vec3(1, 0, 0), 0.1);
			var clear = shade(m, n, sunny(), sunny(), eye), misty = shade(m, n, sunny(), sunny(), eye, null, fog);
			var k = 1 - Math.exp(-1);
			approx(misty.x, clear.x + (1 - clear.x) * k, 1e-6, "red: 1 - e^(-density * distance) of it");
			approx(misty.y, clear.y * (1 - k), 1e-6, "green: what is left of the surface's");
			fog.max = 0.5;
			approx(shade(m, n, sunny(), sunny(), eye, null, fog).y, clear.y * 0.5, 1e-6, "at most max");
			fog.max = 1;
			fog.start = 10;
			approx(sum(shade(m, n, sunny(), sunny(), eye, null, fog)), sum(clear), 1e-6, "none before its start");
			fog.start = 0;
			m.fog = false;
			approx(sum(shade(m, n, sunny(), sunny(), eye, null, fog)), sum(clear), 1e-6, "a material without it");
			m.fog = true;
			m.blend = true;
			m.blending = Additive;
			approx(shade(m, n, sunny(), sunny(), eye, null, fog).x, clear.x * (1 - k), 1e-6, "light added fades, not reddened");
		});

		test("fog: thinner upwards, its height falloff summed along the view", () -> {
			var fog = new Fog(new Vec3(1, 1, 1), 0.1);
			fog.falloff = 1;
			// (straight down 10 m from y 10: the density 0.1 e^(-y) summed is 0.1 (1 - e^(-10)))
			var down = fogAmount(Fog.colorOf(fog), Fog.shapeOf(fog), new Vec3(0, 10, 0), new Vec3(0, 0, 0));
			approx(down, 1 - Math.exp(-0.1 * (1 - Math.exp(-10))), 1e-6, "looking down");
			var up = fogAmount(Fog.colorOf(fog), Fog.shapeOf(fog), new Vec3(0, 0, 0), new Vec3(0, 10, 0));
			approx(up, down, 1e-6, "the same up as down");
			// (level at its height: the density as it is)
			var level = fogAmount(Fog.colorOf(fog), Fog.shapeOf(fog), new Vec3(0, 0, 0), new Vec3(10, 0, 0));
			approx(level, 1 - Math.exp(-1), 1e-6, "level, at its height");
			var high = fogAmount(Fog.colorOf(fog), Fog.shapeOf(fog), new Vec3(0, 5, 0), new Vec3(10, 5, 0));
			approx(high, 1 - Math.exp(-Math.exp(-5)), 1e-6, "level, 5 m above it");
		});

		test("air: towards the limb, its colour", () -> {
			var m = new Material("wall", new Vec4(0.05, 0.05, 0.05, 1), 0, 0.9);
			m.ground = 1;
			m.air = new Vec4(0, 0, 2, 0.8);
			var facing = shade(m, new Vec3(0, 0, 1), new Vec3(0, 0, 1), new Vec3(0, 0, 1), new Vec3(0, 0, 5));
			var limb = shade(m, new Vec3(0, 0, 1), new Vec3(0, 1, 0), new Vec3(0, 1, 0), new Vec3(0, 0, 5));
			assert(limb.z - limb.x > facing.z - facing.x + 0.2, 'bluer at the limb: $limb against $facing');
		});

		test("crystal: polished, its edges opaque and bright, its middle see-through", () -> {
			var m = new Material("crystal", new Vec4(0.1, 0.3, 1, 0.6), 0, 0.8, new Vec3(0, 0.2, 1));
			m.crystal = 1;
			var n = new Vec3(0, 0, 1);
			var facing = shade(m, n, sunny(), sunny(), new Vec3(0, 0, 5)), grazing = shade(m, n, sunny(), sunny(), new Vec3(0, 5, 0.3));
			approx(facing.w, 0.6, 0.05, "seen through where it faces the eye");
			assert(grazing.w > 0.85, 'opaque at its edge: ${grazing.w}');
			assert(facing.z > facing.x * 3, 'lit from inside in its colour: $facing');
			var plain = new Material("plain", new Vec4(0.1, 0.3, 1, 0.6), 0, 0.8, new Vec3(0, 0.2, 1));
			// (a highlight from the sun: sharp on the crystal, broad on the rough plain one)
			var l = new Vec3(0, 0.6, 0.8), mirror = new Vec3(0, -3, 4);
			assert(sum(shade(m, n, sunny(), l, mirror)) > sum(shade(plain, n, sunny(), l, mirror)) * 2, "a sharper, brighter highlight");
		});

		test("a node's tint times the base colour", () -> {
			var m = new Material("wall", new Vec4(0.5, 0.5, 0.5, 1), 0, 1);
			var plain = shade(m, sunny(), sunny(), sunny(), above()), red = shade(m, sunny(), sunny(), sunny(), above(), new Vec3(1.5, 0.5, 0.5));
			assert(red.x > plain.x && red.y < plain.y, 'tinted: $red against $plain');
		});

		test("uv transform: KHR_texture_transform's offset, rotation and scale", () -> {
			var m = new Material("t");
			m.uvOffset = new Vec2(0.5, 0.25);
			m.uvRotation = Math.PI / 2;
			m.uvScale = new Vec2(2, 3);
			// (glTF's: translation * rotation * scale; u' = cos sx u + sin sy v + ox, v' = -sin sx u + cos sy v + oy)
			var uv = uvOf(material(m), new Vec2(1, 1));
			approx(uv.x, 3.5, 1e-6);
			approx(uv.y, -1.75, 1e-6);
		});

		test("clear coat: a sharp reflection over a rough base", () -> {
			var m = new Material("paint", new Vec4(0.6, 0.1, 0.1, 1), 0, 0.9);
			var n = new Vec3(0, 0, 1), l = new Vec3(0, 0.6, 0.8), mirror = new Vec3(0, -3, 4);
			var bare = shade(m, n, sunny(), l, mirror);
			m.clearcoat = 1;
			m.clearcoatRoughness = 0.05;
			assert(sum(shade(m, n, sunny(), l, mirror)) > sum(bare) * 2, "the coat's highlight");
		});

		test("transmission: the diffuse light let through, alpha the share not", () -> {
			var m = new Material("glass", new Vec4(0.9, 0.9, 0.2, 1), 0, 0.1);
			var solid = shade(m, sunny(), sunny(), sunny(), above());
			m.transmission = 1;
			var glass = shade(m, sunny(), sunny(), sunny(), above());
			approx(glass.w, 0, 1e-6, "see-through");
			assert(sum(glass) < sum(solid), "its diffuse light gone");
		});

		test("double-sided: a face seen from behind lit as its front turned to the eye", () -> {
			var m = new Material("pane", new Vec4(0.5, 0.5, 0.5, 1), 0, 0.7, null, true);
			// (its normal away from the eye and the sun; seen from the sun's side)
			var behind = shade(m, new Vec3(0, -1, 0), sunny(), sunny(), above()), front = shade(m, sunny(), sunny(), sunny(), above());
			approx(sum(behind), sum(front), 1e-6);
			m.doubleSided = false;
			assert(sum(shade(m, new Vec3(0, -1, 0), sunny(), sunny(), above())) < sum(front) * 0.3, "single-sided: its own normal's");
		});
		test("instanced: a normal turned by the instance matrix's inverse transpose, as the object's normalMatrix (uneven and mirrored scales)", () -> {
			for (scale in [new Vec3(0.3, 1.4, 0.7), new Vec3(2, 0.25, 1), new Vec3(-1, 0.5, 2)]) {
				var turn = helder.scene.math.Quat.axisAngle(new Vec3(0.48, 0.8, 0.36), 0.9);
				var m = helder.scene.math.MathTools.compose(new Vec3(1, 2, 3), turn, scale);
				var nm = helder.scene.math.MathTools.normalMatrix(m);
				for (n in [new Vec3(0, 1, 0), new Vec3(0.6, 0, 0.8), new Vec3(-0.48, 0.6, 0.64)]) {
					var a = instanceNormal(m.c0.xyz, m.c1.xyz, m.c2.xyz, n), b = nm * new Vec4(n.x, n.y, n.z, 0);
					var la = Math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z), lb = Math.sqrt(b.x * b.x + b.y * b.y + b.z * b.z);
					approx(a.x / la, b.x / lb, 1e-9);
					approx(a.y / la, b.y / lb, 1e-9);
					approx(a.z / la, b.z / lb, 1e-9);
				}
			}
		});
	});
}
