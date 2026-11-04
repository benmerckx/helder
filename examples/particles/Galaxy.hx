// title: GPU particles
// summary: A million particles moved by the GPU (helder.scene.render.GpuParticles): a spiral galaxy flung from its core by a turning emitter, its arms young and blue, a dusty disc and a glowing core; drag to turn around it, tap the disc for a supernova
// tags: 3d, particles, performance, touch
// demo: canvas 640x480
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.os.*;
import helder.scene.*;
import helder.scene.debug.FrameStats;
import helder.scene.debug.Overlay;
import helder.scene.render.*;

// GpuParticles writes a particle once, when it is emitted, and its vertex
// shader moves it from then on (its start, velocity slowed by drag,
// gravity), so the CPU's work a frame is only the particles born in it,
// about 3,300 here (a million alive, five seconds each on average), and
// the ring's new run uploaded: one instanced draw of a million quads. On a
// GPU too slow for them (under 30 fps: a software renderer's) fewer are
// born and drawn (adapt), the overlay saying how many.
//
// The galaxy is a lawn sprinkler's: three arms thrown out of the core
// along directions that turn with time, slowing (drag) as they go, so each
// arm is a spiral of particles born at different moments; young ones hot
// and blue-white, older ones violet and dimmer, a disc of dust reddish and
// slow, the core bright. A drag turns the camera; a tap on the disc sets
// off a supernova there: 20,000 streaks at once.
//
//   bun run helder examples/particles/Galaxy.hx   (--target web: in a page)
class Galaxy {
	public static inline var CAPACITY = 1000000;
	static inline var LIFE = 5.0;

	final device:Device;
	public final world = new World("galaxy");
	public final renderer:Renderer;
	public final fx:GpuParticles;
	public final camera:Camera;
	final eye:Node;
	public var yaw = 0.6;
	public var pitch = 0.55;
	public var distance = 34.0;
	// particles owed by the emission rate (a fraction carried to the next frame)
	var owed = 0.0;
	// how many are kept alive: a million, fewer on a GPU that cannot draw
	// them at 30 fps (adapt: the rate lowered, and the slots drawn with it)
	public var target = 250000;
	var seed = 99;
	final ray = new Camera.CameraRay();

	public function new(device:Device) {
		this.device = device;
		fx = new GpuParticles(device, CAPACITY);
		fx.drag = 0.25;
		renderer = new Renderer(device).use(fx);
		renderer.clearColor = new Color(0.004, 0.005, 0.012);
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.9, 0.1, 400));
	}

	inline function rand():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	// a frame of dt seconds: the clock moved, its share of a million particles born
	public function update(dt:Float) {
		fx.advance(dt);
		var t = fx.time;
		owed += Math.min(dt, 0.1) * target / LIFE;
		// (the newest slots that can be alive: the longest life's worth, and a nova's)
		fx.live = Std.int(Math.min(CAPACITY, target * 1.4 + 20000));
		var n = Std.int(owed);
		owed -= n;
		var turn = t * 0.5;
		for (i in 0...n) {
			var k = rand();
			if (k < 0.72) {
				// (an arm: out of the core along its turning direction, a little spread)
				var arm = Std.int(rand() * 3), a = turn + arm * Math.PI * 2 / 3 + (rand() - 0.5) * (rand() - 0.5) * 0.9;
				var r0 = 0.3 + rand() * 0.8, sp = 4.5 + rand() * 1.5, tilt = (rand() - 0.5) * 0.12, side = 0.15 + (rand() - 0.5) * 0.25;
				var ca = Math.cos(a), sa = Math.sin(a);
				var young = rand();
				fx.emit(ca * r0, tilt * r0, sa * r0, ca * sp - sa * sp * side, tilt * 0.6, sa * sp + ca * sp * side, 0.3 + young * 0.6, 0.4 + young * 0.4,
					1.6, 0.9, 0.06 + rand() * 0.05, 0.035, LIFE * (0.6 + rand() * 0.8), 0, 0.6 + young * 0.4);
			} else if (k < 0.94) {
				// (dust: anywhere on the disc, slow, reddish and faint)
				var a = rand() * Math.PI * 2, r = 1 + Math.pow(rand(), 0.8) * 13, sp = 0.15 + rand() * 0.3;
				var ca = Math.cos(a), sa = Math.sin(a);
				fx.emit(ca * r, (rand() - 0.5) * 0.4, sa * r, -sa * sp, 0, ca * sp, 1.2, 0.5, 0.3, 0.12, 0.04, 0.06, LIFE * (0.6 + rand() * 0.8));
			} else {
				// (the core: a bright, warm, slow swarm)
				var a = rand() * Math.PI * 2, r = Math.pow(rand(), 2) * 1.6, sp = 0.2 + rand() * 0.5;
				var ca = Math.cos(a), sa = Math.sin(a);
				fx.emit(ca * r, (rand() - 0.5) * r * 0.5, sa * r, -sa * sp, (rand() - 0.5) * 0.2, ca * sp, 2.4, 1.7, 1.0, 0.6, 0.06, 0.12,
					LIFE * (0.4 + rand() * 0.6), 0, 0.5);
			}
		}
		// (the camera about the core, turning slowly by itself)
		yaw += dt * 0.04;
		var cp = Math.cos(pitch);
		eye.position = new Vec3(Math.cos(yaw) * cp * distance, Math.sin(pitch) * distance, Math.sin(yaw) * cp * distance);
		eye.lookAt(new Vec3(0, 0, 0));
	}

	// every second: fewer particles while the median frame is over 34 ms,
	// more (from a quarter million, up to the million) while it is under 20
	public function adapt(stats:FrameStats) {
		if (stats.count < 1) return;
		var p50 = stats.percentile(0.5);
		if (p50 > 0.034 && target > 25000) target = Std.int(Math.max(25000, target * 0.6));
		else if (p50 < 0.02 && target < CAPACITY) target = Std.int(Math.min(CAPACITY, target * 1.3));
	}

	// a supernova where the view's point (x, y: -1 to 1) meets the disc
	public function nova(x:Float, y:Float, aspect:Float) {
		camera.rayInto(x, y, aspect, ray);
		if (Math.abs(ray.dir.y) < 1e-4) return;
		var d = -ray.origin.y / ray.dir.y;
		if (d < 0) return;
		var p = ray.origin + ray.dir * d;
		for (_ in 0...20000) {
			// (a direction on the sphere, a speed: a shell and its slower inside)
			var u = rand() * 2 - 1, a = rand() * Math.PI * 2, s = Math.sqrt(1 - u * u), sp = 0.8 + Math.pow(rand(), 0.5) * 4;
			var hot = rand();
			fx.emit(p.x, p.y, p.z, Math.cos(a) * s * sp, u * sp * 0.6, Math.sin(a) * s * sp, 1.4 + hot, 0.8 + hot * 0.6, 0.5 + hot * 1.4, 0.7, 0.035, 0.015,
				1.5 + rand() * 2.5, 0.04, 1);
		}
	}

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);

	static function main() {
		var begun = Sys.time(), firstFrame = -1.0, printed = 0.0;
		var window = new Window("GPU particles", 640, 480);
		var device = Device.create(window.surface);
		var galaxy = new Galaxy(device);
		var overlay = new Overlay(device), stats = new FrameStats(120), recent = new FrameStats(30);
		overlay.detail = true;
		// (a press: a drag turns the camera, a press let go where it began a nova)
		var downX = 0, downY = 0, lastX = 0, lastY = 0, pressed = false, moved = false;
		var last = Sys.time(), frames = 0, adapted = last;
		App.run(() -> {
			var now = Sys.time();
			overlay.scale = window.scale;
			if (now - adapted > 1) {
				galaxy.adapt(recent);
				recent.clear();
				adapted = now;
			}
			galaxy.update(Math.min(now - last, 0.1));
			var born = galaxy.fx.pending;
			var enc = device.beginFrame();
			if (enc == null) return;
			galaxy.draw(enc);
			stats.from(galaxy.renderer);
			stats.draws = 1;
			stats.instanced = galaxy.fx.live;
			overlay.lines.resize(0);
			overlay.lines.push('PARTICLES ${galaxy.target}' + (galaxy.target < Galaxy.CAPACITY ? ' (FEWER: A SLOW GPU)' : ''));
			overlay.lines.push('BORN THIS FRAME ${born}');
			overlay.draw(enc, stats);
			var cpu = Sys.time() - now;
			device.endFrame();
			if (++frames > 3) {
				stats.add(now - last, cpu);
				recent.add(now - last, cpu);
			}
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
				pressed = true;
				moved = false;
				downX = lastX = e.x;
				downY = lastY = e.y;
			case PointerMove if (pressed):
				if (Math.abs(e.x - downX) + Math.abs(e.y - downY) > 6 * window.scale) moved = true;
				galaxy.yaw += (e.x - lastX) * 0.006 / window.scale;
				galaxy.pitch = Math.max(0.05, Math.min(1.45, galaxy.pitch + (e.y - lastY) * 0.006 / window.scale));
				lastX = e.x;
				lastY = e.y;
			case PointerUp:
				if (pressed && !moved) galaxy.nova(e.x / device.width * 2 - 1, 1 - e.y / device.height * 2, device.width / device.height);
				pressed = false;
			case PointerCancel: pressed = false;
			case Scroll: galaxy.distance = Math.max(8, Math.min(90, galaxy.distance * Math.pow(1.0015, e.deltaY)));
			case _:
		});
	}
}
