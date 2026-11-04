// title: Planet
// summary: A planet under a physically based atmosphere (Rayleigh, Mie and ozone, marched through its shell against a transmittance LUT): its day side's blue limb, the night side's city lights, a sunrise's reds along the terminator, a moon and stars; drag to orbit, pinch or scroll to zoom, and presets for Earth, Mars, a toxic world and an ice world
// tags: 3d, shaders, pbr, touch
// demo: canvas 640x480
import Atmosphere;
import haxe.io.Bytes;
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.image.Image;
import helder.os.*;
import helder.scene.*;
import helder.scene.debug.FrameStats;
import helder.scene.debug.Overlay;
import helder.scene.math.Quat;
import helder.scene.render.*;

// The atmosphere is the example's own code (Atmosphere, AtmosphereShader:
// Expansion's, after Maxime Heckel and Hillaire), drawn at the renderer's
// AfterOpaque injection point over the planet that helder.scene's
// standard material draws: a texture of its surface made here from
// noise (oceans, land, ice caps by preset) and an emissive one of its
// cities, emitted on the night side only (Material.emissiveNight). The
// planet turns, the moon orbits, the stars are GpuParticles that never
// die. A drag orbits the camera, a pinch or the wheel zooms; SUNRISE
// puts the sun just behind the limb, seen from the night side.
//
//   bun run helder examples/planet/Planet.hx   (--target web: in a page)
class Planet {
	static final NAMES = ["EARTH", "MARS", "TOXIC", "ICE", "SUNRISE", "STATS"];
	static final PRESETS = [Atmosphere.EARTH, Atmosphere.MARS, Atmosphere.TOXIC, Atmosphere.ICE];

	final device:Device;
	final world = new World("planet");
	public final renderer:Renderer;
	final air:Atmosphere;
	final camera:Camera;
	final eye:Node;
	final globe:Node;
	final moon:Node;
	final surface:Material;
	final textures:Array<Null<{color:Texture, lights:Texture, mean:Vec3}>> = [null, null, null, null];
	// towards the sun
	final toSun = new Vec3(0.82, 0.22, 0.53);
	public var preset = 0;
	public var showStats = false;
	public var yaw = 0.3;
	public var pitch = 0.25;
	public var distance = 3.4;
	var time = 0.0;

	public function new(device:Device) {
		this.device = device;
		renderer = new Renderer(device);
		renderer.clearColor = new Color(0, 0, 0.002);
		renderer.sky = new Vec3(0.012, 0.012, 0.016);
		renderer.ground = new Vec3(0.006, 0.006, 0.008);
		renderer.sunColor = new Vec3(1.25, 1.2, 1.12);
		// (stars first: the air drawn over them)
		var stars = new GpuParticles(device, 3000);
		renderer.use(stars);
		var seed = 17;
		function rand():Float {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return seed / 0x7fffffff;
		}
		for (_ in 0...3000) {
			var u = rand() * 2 - 1, a = rand() * Math.PI * 2, s = Math.sqrt(1 - u * u), b = 0.3 + Math.pow(rand(), 4) * 2.5, warm = rand() * 0.3;
			stars.emit(Math.cos(a) * s * 150, u * 150, Math.sin(a) * s * 150, 0, 0, 0, b * (1 + warm), b, b * (1.2 - warm), 1, 0.18, 0.18, 1e7);
		}
		air = new Atmosphere(renderer, 8);
		surface = new Material("surface", new Vec4(1, 1, 1, 1), 0, 0.75, new Vec3(1.6, 1.3, 0.8));
		surface.emissiveNight = 1;
		globe = world.node("globe");
		MeshRenderer.attach(globe, Shapes.sphere(device, surface, 1, 96, 48));
		moon = world.node("moon");
		var moonMaterial = new Material("moon", new Vec4(1, 1, 1, 1), 0, 0.9);
		moonMaterial.baseColorTexture = rock(device);
		MeshRenderer.attach(moon, Shapes.sphere(device, moonMaterial, 0.22, 48, 24));
		// (the sun: a light along toSun and a disc far away, emissive)
		var sun = world.node("sun");
		sun.position = toSun * 90;
		sun.lookAt(new Vec3(0, 0, 0));
		Light.attach(sun, Light.directional(new Vec3(1, 0.97, 0.92), 1));
		var disc = world.node("disc");
		disc.position = toSun * 120;
		MeshRenderer.attach(disc, Shapes.sphere(device, new Material("disc", new Vec4(0, 0, 0, 1), 0, 1, new Vec3(40, 36, 30)), 1.6, 24, 12));
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.75, 0.02, 400));
		setPreset(0);
	}

	public function setPreset(k:Int) {
		preset = k;
		if (textures[k] == null) textures[k] = paint(device, k);
		var t = textures[k];
		surface.baseColorTexture = t.color;
		surface.emissiveTexture = t.lights;
	}

	// the camera just past the night side's edge, the sun behind the limb
	public function sunrise() {
		// (opposite the sun, turned 27 degrees about the up: the sun just past the limb)
		var a = Math.atan2(-toSun.z, -toSun.x) + 0.47;
		yaw = a;
		pitch = -Math.asin(toSun.y) + 0.05;
		distance = 2.4;
	}

	public function update(dt:Float) {
		time += dt;
		globe.rotation = Quat.axisAngle(new Vec3(0.196, 0.981, 0), time * 0.05);
		var m = time * 0.08 + 1.2;
		moon.position = new Vec3(Math.cos(m) * 2.6, Math.sin(m) * 0.35, Math.sin(m) * 2.6);
		moon.rotation = Quat.axisAngle(new Vec3(0, 1, 0), -m);
		var cp = Math.cos(pitch);
		eye.position = new Vec3(Math.cos(yaw) * cp * distance, Math.sin(pitch) * distance, Math.sin(yaw) * cp * distance);
		eye.lookAt(new Vec3(0, 0, 0));
		air.clear();
		air.add(new Vec3(0, 0, 0), 1, PRESETS[preset], textures[preset].mean);
	}

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);

	// --- the surfaces, painted from noise: equirectangular, as Shapes.sphere's uvs

	static inline var TW = 512;
	static inline var TH = 256;

	static function paint(device:Device, kind:Int):{color:Texture, lights:Texture, mean:Vec3} {
		var color = Bytes.alloc(TW * TH * 4), lights = Bytes.alloc(TW * TH * 4);
		var sr = 0.0, sg = 0.0, sb = 0.0;
		for (j in 0...TH) {
			var lat = Math.PI * (j + 0.5) / TH, y = Math.cos(lat), r = Math.sin(lat);
			for (i in 0...TW) {
				var lon = 2 * Math.PI * (i + 0.5) / TW;
				// (the point on the sphere, as Shapes.sphere puts uv's)
				var x = r * Math.cos(lon), z = -r * Math.sin(lon);
				var h = fbm(x * 1.6 + kind * 7.1, y * 1.6, z * 1.6, 7);
				var d = fbm(x * 5 + 3, y * 5, z * 5, 4);
				var polar = Math.abs(y);
				var c:Array<Float>, glow = 0.0;
				switch kind {
					case 0:
						// (Earth: oceans, greens to browns, deserts, ice at the poles)
						if (h < 0.52) {
							var deep = Math.min(1, (0.52 - h) * 6);
							c = [0.02 + 0.04 * (1 - deep), 0.07 + 0.1 * (1 - deep), 0.2 + 0.12 * (1 - deep)];
						} else {
							var dry = smooth(0.45, 0.7, d + (0.5 - polar) * 0.3);
							c = [0.05 + 0.3 * dry, 0.11 + 0.14 * dry, 0.03 + 0.08 * dry];
							// (cities: speckles near the coasts, away from the poles and deserts)
							var coast = 1 - Math.min(1, (h - 0.52) * 8), dots = fbm(x * 90, y * 90, z * 90, 2);
							glow = dots > 0.62 && polar < 0.75 ? (dots - 0.62) * 6 * (0.3 + coast) * (1 - dry * 0.8) : 0;
						}
						if (polar > 0.82 + (d - 0.5) * 0.15) c = [0.85, 0.88, 0.92];
					case 1:
						// (Mars: rusts, dark plains, small caps; no lights)
						var t = smooth(0.35, 0.65, h);
						c = [0.22 + 0.3 * t + 0.08 * d, 0.09 + 0.1 * t, 0.05 + 0.04 * t];
						if (polar > 0.9 + (d - 0.5) * 0.1) c = [0.85, 0.8, 0.78];
					case 2:
						// (toxic: green-teal seas, yellow crusts, glowing pools at night)
						if (h < 0.5) {
							c = [0.05, 0.22 + 0.1 * d, 0.16];
							glow = d > 0.62 ? (d - 0.62) * 4 : 0;
						} else
							c = [0.34 + 0.18 * d, 0.32 + 0.12 * d, 0.07];
					case _:
						// (ice: white and pale blue, dark cracks, a faint cyan in them)
						var crack = Math.abs(fbm(x * 6, y * 6, z * 6, 3) - 0.5);
						c = [0.6 + 0.2 * h, 0.7 + 0.15 * h, 0.82];
						if (crack < 0.02) {
							c = [0.25, 0.35, 0.45];
							glow = 0.25;
						}
				}
				var o = 4 * (j * TW + i);
				for (k in 0...3)
					color.set(o + k, Std.int(Math.pow(Math.min(1, c[k]), 1 / 2.2) * 255));
				color.set(o + 3, 255);
				var g = Math.pow(Math.min(1, glow), 1 / 2.2) * 255;
				var gc = kind == 2 ? [0.3, 1.0, 0.5] : kind == 3 ? [0.4, 0.9, 1.0] : [1.0, 0.8, 0.5];
				for (k in 0...3)
					lights.set(o + k, Std.int(g * gc[k]));
				lights.set(o + 3, 255);
				sr += c[0];
				sg += c[1];
				sb += c[2];
			}
		}
		var n = TW * TH;
		return {
			color: ImageTexture.create(device, new Image(TW, TH, color), {mips: true}),
			lights: ImageTexture.create(device, new Image(TW, TH, lights), {mips: true}),
			mean: new Vec3(sr / n, sg / n, sb / n)
		};
	}

	// the moon's grey, cratered by noise
	static function rock(device:Device):Texture {
		var px = Bytes.alloc(256 * 128 * 4);
		for (j in 0...128) {
			var lat = Math.PI * (j + 0.5) / 128, y = Math.cos(lat), r = Math.sin(lat);
			for (i in 0...256) {
				var lon = 2 * Math.PI * (i + 0.5) / 256, x = r * Math.cos(lon), z = -r * Math.sin(lon);
				var v = 0.35 + 0.4 * fbm(x * 3 + 9, y * 3, z * 3, 5) - 0.15 * smooth(0.55, 0.6, fbm(x * 8, y * 8, z * 8, 2));
				var o = 4 * (j * 256 + i), b = Std.int(Math.pow(Math.max(0, Math.min(1, v)), 1 / 2.2) * 255);
				px.set(o, b);
				px.set(o + 1, b);
				px.set(o + 2, b);
				px.set(o + 3, 255);
			}
		}
		return ImageTexture.create(device, new Image(256, 128, px), {mips: true});
	}

	static inline function smooth(a:Float, b:Float, x:Float):Float {
		var t = Math.max(0, Math.min(1, (x - a) / (b - a)));
		return t * t * (3 - 2 * t);
	}

	// value noise in 3D: octaves of it, 0 to 1
	static function fbm(x:Float, y:Float, z:Float, octaves:Int):Float {
		var s = 0.0, a = 0.5, total = 0.0;
		for (_ in 0...octaves) {
			s += a * noise(x, y, z);
			total += a;
			x *= 2.03;
			y *= 2.03;
			z *= 2.03;
			a *= 0.5;
		}
		return s / total;
	}

	static function noise(x:Float, y:Float, z:Float):Float {
		var ix = Math.floor(x), iy = Math.floor(y), iz = Math.floor(z);
		var fx = x - ix, fy = y - iy, fz = z - iz;
		var ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy), uz = fz * fz * (3 - 2 * fz);
		inline function h(i:Int, j:Int, k:Int):Float {
			var n = (i * 73856093) ^ (j * 19349663) ^ (k * 83492791);
			n = (n ^ (n >>> 13)) * 1274126177;
			return ((n ^ (n >>> 16)) & 0xffff) / 65535;
		}
		inline function lerp(a:Float, b:Float, t:Float):Float
			return a + (b - a) * t;
		return lerp(lerp(lerp(h(ix, iy, iz), h(ix + 1, iy, iz), ux), lerp(h(ix, iy + 1, iz), h(ix + 1, iy + 1, iz), ux), uy),
			lerp(lerp(h(ix, iy, iz + 1), h(ix + 1, iy, iz + 1), ux), lerp(h(ix, iy + 1, iz + 1), h(ix + 1, iy + 1, iz + 1), ux), uy), uz);
	}

	// --- the buttons along the bottom, in points

	static function slot(k:Int, w:Float, h:Float):{x:Float, y:Float, w:Float, h:Float} {
		var bw = (w - 24 - 5 * 6) / 6;
		return {x: 12 + k * (bw + 6), y: h - 44, w: bw, h: 32};
	}

	public function controls(o:Overlay, w:Float, h:Float) {
		for (k in 0...NAMES.length) {
			var b = slot(k, w, h), on = k < 4 ? k == preset : k == 5 && showStats;
			o.rect(b.x, b.y, b.w, b.h, on ? 0xF03D7BF0 : 0xA0202430, 6);
			o.text(NAMES[k], b.x + (b.w - Overlay.measure(NAMES[k])) / 2, b.y + 11, 0xFFF0F4F8);
		}
	}

	// a press at x, y (points) on a button: true
	public function press(x:Float, y:Float, w:Float, h:Float):Bool {
		for (k in 0...NAMES.length) {
			var b = slot(k, w, h);
			if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) {
				if (k < 4) setPreset(k) else if (k == 4) sunrise() else showStats = !showStats;
				return true;
			}
		}
		return false;
	}

	static function main() {
		var begun = Sys.time(), firstFrame = -1.0, printed = 0.0;
		var window = new Window("Planet", 640, 480);
		var device = Device.create(window.surface);
		var planet = new Planet(device);
		var overlay = new Overlay(device), stats = new FrameStats(120);
		overlay.extra = o -> planet.controls(o, device.width / window.scale, device.height / window.scale);
		// (fingers down: one drags the orbit, two pinch the distance)
		var fingers = new Map<Int, {x:Float, y:Float}>(), spread = 0.0;
		function pinch():Float {
			var ps = [for (p in fingers) p];
			if (ps.length < 2) return 0;
			var dx = ps[0].x - ps[1].x, dy = ps[0].y - ps[1].y;
			return Math.sqrt(dx * dx + dy * dy);
		}
		var last = Sys.time(), frames = 0;
		App.run(() -> {
			var now = Sys.time();
			overlay.scale = window.scale;
			overlay.detail = planet.showStats;
			planet.update(Math.min(now - last, 0.1));
			var enc = device.beginFrame();
			if (enc == null) return;
			planet.draw(enc);
			stats.from(planet.renderer);
			overlay.panel = planet.showStats;
			overlay.draw(enc, stats);
			var cpu = Sys.time() - now;
			device.endFrame();
			if (++frames > 3) stats.add(now - last, cpu);
			// (the site's numbers: site/numbers.mjs reads the last stats line)
			if (firstFrame < 0) firstFrame = Sys.time() - begun;
			if (now - printed > 0.5 && stats.count > 10) {
				printed = now;
				Sys.println(stats.report(firstFrame, 0, device.textureBytes));
			}
			last = now;
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case PointerDown:
				var s = window.scale;
				if (planet.press(e.x / s, e.y / s, device.width / s, device.height / s)) return;
				fingers.set(e.pointer.id, {x: e.x, y: e.y});
				spread = pinch();
			case PointerMove if (fingers.exists(e.pointer.id)):
				var p = fingers.get(e.pointer.id), s = window.scale;
				if (Lambda.count(fingers) == 1) {
					planet.yaw += (e.x - p.x) * 0.006 / s;
					planet.pitch = Math.max(-1.4, Math.min(1.4, planet.pitch + (e.y - p.y) * 0.006 / s));
				}
				fingers.set(e.pointer.id, {x: e.x, y: e.y});
				var now = pinch();
				if (spread > 0 && now > 0) planet.distance = Math.max(1.25, Math.min(12, planet.distance * spread / now));
				spread = now;
			case PointerUp | PointerCancel:
				fingers.remove(e.pointer.id);
				spread = pinch();
			case Scroll: planet.distance = Math.max(1.25, Math.min(12, planet.distance * Math.pow(1.0015, e.deltaY)));
			case _:
		});
	}
}
