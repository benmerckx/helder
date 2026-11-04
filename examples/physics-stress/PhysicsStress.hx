// title: Physics stress
// summary: A thousand crates rained into a walled pit by helder.physics at a fixed step, piling up and going to sleep, then stirred by a kinematic paddle that wakes them as it sweeps; all drawn in one instanced draw with shadows, the body count and the step's time shown; tap for a hundred more, the button turns the paddle on and off
// tags: 3d, physics, instancing, performance
// demo: canvas 640x480
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.physics.*;
import helder.scene.*;
import helder.scene.debug.FrameStats;
import helder.scene.debug.Overlay;
import helder.scene.math.Aabb;
import helder.scene.math.Quat;
import helder.scene.render.*;

// A thousand boxes (a 10 x 10 x 10 lattice, a little turned) dropped onto
// a walled floor, piling up, stepped at 60 Hz (Stages, FixedStep); the bodies have no nodes: after
// each step their positions and orientations go into one InstancedMesh
// (setTransform), one draw for all of them, casting shadows. After four
// seconds a kinematic paddle (Body.kinematic: moved by the angular
// velocity it is given, pushing, never pushed) sweeps round the floor,
// waking the sleeping towers it touches. The overlay shows the bodies,
// how many are awake, the contacts, and the step's p50 and p99.
//
//   bun run helder examples/physics-stress/PhysicsStress.hx   (--target web: in a page)
class PhysicsStress {
	static inline var MAX = 3000;
	static inline var HALF = 0.25;

	public final physics = new PhysicsWorld();
	public final world = new World("physics-stress");
	public final renderer:Renderer;
	final camera:Camera;
	final crates:InstancedMesh;
	final boxes:Array<Body> = [];
	final paddle:Body;
	final paddleNode:Node;
	public final steps = new FrameStats(120);
	public var sweeping = false;
	var time = 0.0;
	var seed = 3;

	public function new(device:Device) {
		renderer = new Renderer(device).use(new Shadows(device, 2048));
		renderer.clearColor = new Color(0.55, 0.62, 0.72);
		physics.iterations = 10;
		var ground = new Material("ground", new Vec4(0.45, 0.48, 0.52, 1), 0, 0.85);
		var floor = world.node("floor");
		MeshRenderer.attach(floor, Shapes.box(device, ground, 16, 0.2, 16));
		floor.position = new Vec3(0, -0.1, 0);
		physics.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		var wall = new Material("wall", new Vec4(0.3, 0.38, 0.5, 1), 0, 0.6);
		for (w in [[7.8, 0, 0.2, 8], [-7.8, 0, 0.2, 8], [0, 7.8, 8, 0.2], [0, -7.8, 8, 0.2]]) {
			var n = world.node("wall"), half = new Vec3(w[2], 0.6, w[3]);
			n.position = new Vec3(w[0], 0.6, w[1]);
			MeshRenderer.attach(n, Shapes.box(device, wall, half.x * 2, half.y * 2, half.z * 2));
			physics.add(new Body(Box(half), n.position, 0));
		}
		var crate = new Material("crate", new Vec4(1, 1, 1, 1), 0, 0.55);
		crates = new InstancedMesh(Shapes.box(device, crate, HALF * 2, HALF * 2, HALF * 2), MAX, 0);
		crates.bounds = new Aabb(new Vec3(-8, 0, -8), new Vec3(8, 14, 8));
		InstancedMesh.attach(world.node("crates"), crates);
		// (the paddle: a long bar about the centre, kinematic)
		paddleNode = world.node("paddle");
		MeshRenderer.attach(paddleNode, Shapes.box(device, new Material("paddle", new Vec4(0.95, 0.35, 0.15, 1), 0.2, 0.4), 13, 0.8, 0.4));
		paddle = physics.add(Body.kinematic(Box(new Vec3(6.5, 0.4, 0.2)), new Vec3(0, 0.4, 0)), paddleNode);
		var sun = world.node("sun");
		Light.attach(sun, Light.directional(new Vec3(1, 0.96, 0.9), 2.8));
		sun.rotation = Quat.fromEuler(-0.95, -0.5, 0);
		var eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.8, 0.1, 200));
		eye.position = new Vec3(0, 15, 19);
		eye.lookAt(new Vec3(0, 1.5, 0));
		for (x in 0...10)
			for (z in 0...10)
				for (y in 0...10)
					add((x - 4.5) * 1.3 + (rand() - 0.5) * 0.3, 1 + y * 0.9 + rand() * 0.3, (z - 4.5) * 1.3 + (rand() - 0.5) * 0.3, rand() * 3);
	}

	inline function rand():Float {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff;
		return seed / 0x7fffffff;
	}

	// a crate at x, y, z, turned by yaw about y, of a colour of its own
	function add(x:Float, y:Float, z:Float, yaw:Float) {
		if (boxes.length == MAX) return;
		var b = new Body(Box(new Vec3(HALF, HALF, HALF)), new Vec3(x, y, z));
		b.orientation = Quat.axisAngle(new Vec3(0, 1, 0), yaw);
		b.friction = 0.6;
		b.restitution = 0.1;
		physics.add(b);
		var i = boxes.length;
		boxes.push(b);
		crates.count = boxes.length;
		var k = rand(), g = 0.75 + rand() * 0.25;
		// (crates' woods, a few painted)
		if (k < 0.12) crates.setColor(i, 0.2 * g, 0.5 * g, 0.9 * g) else if (k < 0.2) crates.setColor(i, 0.95 * g, 0.75 * g, 0.2 * g)
		else crates.setColor(i, 0.78 * g, 0.55 * g, 0.32 * g);
	}

	// a hundred more, dropped from above in a heap
	public function drop() {
		for (k in 0...100)
			add((rand() - 0.5) * 9, 9 + k * 0.08, (rand() - 0.5) * 9, rand() * 3);
	}

	public function toggle() {
		sweeping = !sweeping;
		paddle.angular = new Vec3(0, sweeping ? 0.5 : 0, 0);
	}

	// one fixed step, timed
	public function step(dt:Float) {
		time += dt;
		if (time >= 4 && time - dt < 4 && !sweeping) toggle();
		var t0 = Sys.time();
		physics.step(dt);
		steps.add(Sys.time() - t0);
	}

	// the bodies into the set (after the steps of a frame)
	public function sync() {
		for (i in 0...boxes.length) {
			var b = boxes[i], p = b.position, q = b.orientation;
			crates.setTransform(i, p.x, p.y, p.z, q.x, q.y, q.z, q.w);
		}
	}

	public function awake():Int {
		var n = 0;
		for (b in boxes)
			if (!b.sleeping) n++;
		return n;
	}

	public function bodies():Int
		return boxes.length;

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);

	static function main() {
		var begun = Sys.time(), firstFrame = -1.0, printed = 0.0;
		var window = new Window("Physics stress", 640, 480);
		var device = Device.create(window.surface);
		var demo = new PhysicsStress(device);
		var overlay = new Overlay(device), stats = new FrameStats(120);
		overlay.detail = true;
		var label = "PADDLE";
		// (the button: top right, in points)
		function button(w:Float):{x:Float, y:Float, w:Float, h:Float}
			return {x: w - 132, y: 12, w: 120, h: 34};
		overlay.extra = o -> {
			var b = button(device.width / window.scale);
			o.rect(b.x, b.y, b.w, b.h, demo.sweeping ? 0xF0E05A26 : 0xC0202430, 6);
			o.text(label, b.x + (b.w - Overlay.measure(label)) / 2, b.y + 12, 0xFFF0F4F8);
		};
		var stages = new Stages(new FixedStep(1 / 60)), last = Sys.time(), frames = 0;
		stages.on(FixedUpdate, dt -> demo.step(dt));
		App.run(() -> {
			var now = Sys.time();
			overlay.scale = window.scale;
			stages.frame(Math.min(now - last, 0.1));
			demo.sync();
			var enc = device.beginFrame();
			if (enc == null) return;
			demo.draw(enc);
			stats.from(demo.renderer);
			var s = demo.steps;
			overlay.lines.resize(0);
			overlay.lines.push('BODIES ${demo.bodies()} AWAKE ${demo.awake()} CONTACTS ${demo.physics.contacts}');
			overlay.lines.push('STEP P50 ${ms(s.percentile(0.5))} P99 ${ms(s.percentile(0.99))} MS');
			overlay.lines.push('TAP: 100 MORE');
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
			case KeyDown if (e.key == 0x20): demo.toggle();
			case PointerDown:
				var b = button(device.width / window.scale), x = e.x / window.scale, y = e.y / window.scale;
				if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h) demo.toggle() else demo.drop();
			case _:
		});
	}

	static function ms(s:Float):String {
		var t = Math.round(s * 10000);
		return Std.int(t / 10) + "." + (t % 10);
	}
}
