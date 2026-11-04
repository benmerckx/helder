// title: Instancing stress
// summary: An asteroid belt of spinning rocks, each moved, turned and coloured every frame: up to 20,000 nodes drawn one by one or batched by the renderer, or 200,000 instances of one InstancedMesh from flat arrays; a slider for how many, a stats overlay of fps, frame time p50/p99, draws and CPU time
// tags: 3d, instancing, performance
// demo: canvas 640x480
import helder.gfx.*;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.os.*;
import helder.scene.*;
import helder.scene.debug.FrameStats;
import helder.scene.debug.Overlay;
import helder.scene.math.Quat;
import helder.scene.render.*;

// Three ways to draw many copies of one mesh, the same rocks in each:
//
//   SEPARATE   a Node a rock (MeshRenderer), renderer.instancing off: a
//              draw call each, its matrices in a uniform block
//   BATCHED    the same nodes, renderer.instancing on: the renderer finds
//              the runs of one primitive and draws each run instanced,
//              writing the nodes' matrices into its instance buffer
//   INSTANCED  no nodes: one InstancedMesh, the rocks' transforms and
//              colours written into its flat data, one instanced draw
//
// Every rock orbits (Kepler's: slower farther out) and spins about its
// own axis each frame, on the CPU, so CPU ms is the frame's work: the
// update and the renderer's extraction and recording. The slider sets how
// many (logarithmic; nodes up to 20,000, instances up to 200,000); the
// buttons the mode (it starts at 100,000 instances, halved down to
// 10,000 while the median frame is over 50 ms: a software GPU); the overlay (helder.scene.debug.Overlay, detail on)
// shows fps, the frame time's p50 and p99, the CPU's, draws and instances.
//
//   bun run helder examples/instancing/Instancing.hx   (--target web: in a page)
class Instancing {
	static inline var MAX_NODES = 20000;
	static inline var MAX_INSTANCES = 200000;
	static final MODES = ["SEPARATE", "BATCHED", "INSTANCED"];

	final device:Device;
	final world = new World("instancing");
	final renderer:Renderer;
	final camera:Camera;
	final eye:Node;
	final rock:Mesh;
	final set:InstancedMesh;
	final nodes:Array<Node> = [];
	// each rock's orbit (radius, angle at 0, speed, height) and spin (axis, speed)
	final radius:Array<Float> = [];
	final phase:Array<Float> = [];
	final speed:Array<Float> = [];
	final height:Array<Float> = [];
	final ax:Array<Float> = [];
	final ay:Array<Float> = [];
	final az:Array<Float> = [];
	final spin:Array<Float> = [];
	final size:Array<Float> = [];
	final tints:Array<Vec3> = [];

	public var mode = 2;
	public var count = 100000;
	var shownNodes = 0;

	public function new(device:Device) {
		this.device = device;
		renderer = new Renderer(device);
		renderer.clearColor = new Color(0.01, 0.012, 0.03);
		renderer.sky = new Vec3(0.08, 0.09, 0.14);
		renderer.ground = new Vec3(0.03, 0.025, 0.02);
		renderer.sunColor = new Vec3(3.2, 3.0, 2.7);
		rock = Shapes.box(device, new Material("rock", new Vec4(1, 1, 1, 1), 0, 0.7), 1, 1, 1);
		// (a fixed seed: the same belt every run)
		var seed = 12345;
		function rand():Float {
			seed = (seed * 1103515245 + 12345) & 0x7fffffff;
			return seed / 0x7fffffff;
		}
		for (i in 0...MAX_INSTANCES) {
			var r = 16 + Math.pow(rand(), 0.8) * 70;
			radius.push(r);
			phase.push(rand() * Math.PI * 2);
			speed.push(0.6 / Math.pow(r / 16, 1.5));
			height.push((rand() - 0.5) * (1 + r * 0.05) * (rand() + 0.2));
			var x = rand() - 0.5, y = rand() - 0.5, z = rand() - 0.5, l = Math.sqrt(x * x + y * y + z * z) + 1e-6;
			ax.push(x / l);
			ay.push(y / l);
			az.push(z / l);
			spin.push(0.5 + rand() * 2.5);
			size.push(0.12 + Math.pow(rand(), 3) * 0.6);
			// (greys and rusts, a few icy blues)
			var k = rand(), g = 0.35 + rand() * 0.4;
			tints.push(k < 0.15 ? new Vec3(g * 0.7, g * 0.85, g * 1.2) : k < 0.55 ? new Vec3(g * 1.15, g * 0.8, g * 0.55) : new Vec3(g, g * 0.95, g * 0.9));
		}
		set = new InstancedMesh(rock, MAX_INSTANCES, count);
		for (i in 0...MAX_INSTANCES)
			set.setColor(i, tints[i].x, tints[i].y, tints[i].z);
		InstancedMesh.attach(world.node("belt"), set);
		// (a planet in the middle)
		var planet = world.node("planet");
		MeshRenderer.attach(planet, Shapes.sphere(device, new Material("planet", new Vec4(0.75, 0.55, 0.35, 1), 0, 0.6), 9, 48, 24));
		var sun = world.node("sun");
		Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.88), 3.2));
		sun.rotation = Quat.fromEuler(-0.5, -0.9, 0);
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(0.9, 0.5, 400));
		setMode(mode);
	}

	public function setMode(m:Int) {
		mode = m;
		renderer.instancing = m == 1;
		var max = m == 2 ? MAX_INSTANCES : MAX_NODES;
		if (count > max) count = max;
		if (m != 2 && count > 10000) count = 10000;
		apply();
	}

	public function setCount(n:Int) {
		count = n;
		apply();
	}

	// the nodes (made when first needed) or the set's count, for the mode
	function apply() {
		var nodesWanted = mode == 2 ? 0 : count;
		while (nodes.length < nodesWanted) {
			var n = world.node("rock");
			MeshRenderer.attach(n, rock);
			MeshRenderer.tint(n, tints[nodes.length]);
			nodes.push(n);
		}
		for (i in nodesWanted...shownNodes)
			nodes[i].visible = false;
		for (i in shownNodes...nodesWanted)
			nodes[i].visible = true;
		shownNodes = nodesWanted;
		set.count = mode == 2 ? count : 0;
	}

	public function update(t:Float) {
		// (the camera drifting about the belt)
		var a = t * 0.05;
		eye.position = new Vec3(Math.cos(a) * 105, 34 + Math.sin(t * 0.13) * 10, Math.sin(a) * 105);
		eye.lookAt(new Vec3(0, 0, 0));
		var n = mode == 2 ? count : shownNodes;
		for (i in 0...n) {
			var o = phase[i] + t * speed[i], r = radius[i];
			var x = Math.cos(o) * r, z = Math.sin(o) * r, y = height[i];
			var h = t * spin[i] * 0.5, s = Math.sin(h), c = Math.cos(h);
			if (mode == 2) set.setTransform(i, x, y, z, ax[i] * s, ay[i] * s, az[i] * s, c, size[i]);
			else {
				var node = nodes[i];
				node.position = new Vec3(x, y, z);
				node.rotation = new Quat(ax[i] * s, ay[i] * s, az[i] * s, c);
				node.scale = new Vec3(size[i], size[i], size[i]);
			}
		}
	}

	public function draw(enc:Encoder)
		renderer.draw(enc, world, camera);

	// --- the controls: three buttons and a slider along the bottom, in points

	static inline var BAR = 44.0;

	// the slider's track: from x0, w wide, at y (points)
	static function track(w:Float, h:Float):{x:Float, y:Float, w:Float}
		return {x: 16, y: h - BAR - 26, w: w - 32};

	// a count from a share of the track (logarithmic, from 100)
	function countAt(share:Float):Int {
		var max = mode == 2 ? MAX_INSTANCES : MAX_NODES;
		share = Math.max(0, Math.min(1, share));
		return Std.int(Math.round(100 * Math.pow(max / 100, share) / 100) * 100);
	}

	function shareOf(n:Int):Float {
		var max = mode == 2 ? MAX_INSTANCES : MAX_NODES;
		return Math.log(n / 100) / Math.log(max / 100);
	}

	public function controls(o:Overlay, w:Float, h:Float) {
		var bw = (w - 32 - 16) / 3;
		for (k in 0...3) {
			var x = 16 + k * (bw + 8), y = h - BAR;
			o.rect(x, y, bw, 32, k == mode ? 0xF03D7BF0 : 0xC0202430, 6);
			o.text(MODES[k], x + (bw - Overlay.measure(MODES[k])) / 2, y + 11, 0xFFF0F4F8);
		}
		var tr = track(w, h), s = shareOf(count);
		o.rect(tr.x, tr.y - 3, tr.w, 6, 0xA0303644, 3);
		o.rect(tr.x, tr.y - 3, tr.w * s, 6, 0xFF3D7BF0, 3);
		o.rect(tr.x + tr.w * s - 9, tr.y - 9, 18, 18, 0xFFF0F4F8, 9);
		var label = 'N ${count}' + (mode == 2 ? ' INSTANCES' : ' NODES');
		o.text(label, tr.x, tr.y - 26, 0xFFF0F4F8);
	}

	var dragging = false;
	// whether the controls were used (the count then the viewer's)
	public var touched = false;

	// a press or drag at x, y (points): a button pressed, the slider moved; true: taken
	public function press(x:Float, y:Float, w:Float, h:Float, down:Bool):Bool {
		var tr = track(w, h);
		if (down) touched = true;
		if (down && y >= h - BAR && y <= h - BAR + 32) {
			var bw = (w - 32 - 16) / 3, k = Std.int((x - 16) / (bw + 8));
			if (k >= 0 && k < 3 && k != mode) setMode(k);
			return true;
		}
		if (down && Math.abs(y - tr.y) < 22) dragging = true;
		if (dragging) {
			var n = countAt((x - tr.x) / tr.w);
			if (n != count) setCount(n);
			return true;
		}
		return false;
	}

	public function release()
		dragging = false;

	static function main() {
		var begun = Sys.time(), firstFrame = -1.0, printed = 0.0;
		var window = new Window("Instancing stress", 640, 480);
		var device = Device.create(window.surface);
		var demo = new Instancing(device);
		var overlay = new Overlay(device), stats = new FrameStats(120);
		overlay.detail = true;
		overlay.extra = o -> demo.controls(o, device.width / window.scale, device.height / window.scale);
		var start = Sys.time(), last = start, frames = 0, lowered = false;
		App.run(() -> {
			var now = Sys.time();
			overlay.scale = window.scale;
			demo.update(now - start);
			var enc = device.beginFrame();
			if (enc == null) return;
			demo.draw(enc);
			stats.from(demo.renderer);
			overlay.lines.resize(0);
			overlay.lines.push(MODES[demo.mode] + ' ${demo.count}' + (lowered ? ' (LOWERED: A SLOW GPU)' : ''));
			overlay.draw(enc, stats);
			var cpu = Sys.time() - now;
			device.endFrame();
			// (the first frames, the page's start among them, left out)
			if (++frames > 3) stats.add(now - last, cpu);
			// (under 20 fps at the median, or a frame over 0.3 s: a software GPU's; fewer, down to 10,000, until touched)
			if (!demo.touched && demo.count > 10000 && (stats.count >= 10 && stats.percentile(0.5) > 0.05 || frames > 1 && now - last > 0.3)) {
				demo.setCount(Std.int(Math.max(10000, demo.count / 2)));
				stats.clear();
				lowered = true;
			}
			// (the site's numbers: site/numbers.mjs reads the last stats line)
			if (firstFrame < 0) firstFrame = Sys.time() - begun;
			if (now - printed > 0.5 && stats.count > 2) {
				printed = now;
				Sys.println(stats.report(firstFrame, 0, device.textureBytes));
			}
			last = now;
		}, e -> switch e.kind {
			case Close: window.close();
			case KeyDown if (e.key == 0xFF1B): window.close();
			case KeyDown if (e.key >= "1".code && e.key <= "3".code): demo.setMode(e.key - "1".code);
			case PointerDown | PointerMove if (e.kind == PointerDown || e.pointer?.down == true):
				demo.press(e.x / window.scale, e.y / window.scale, device.width / window.scale, device.height / window.scale, e.kind == PointerDown);
			case PointerUp | PointerCancel: demo.release();
			case _:
		});
	}
}
