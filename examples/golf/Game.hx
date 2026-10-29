import Course.Hole;
import helder.gfx.Color;
import helder.gfx.shader.Mat4;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.FixedStep;
import helder.scene.Node;
import helder.scene.World;
import helder.scene.math.MathTools;
import helder.scene.math.Quat;
import helder.scene.render.Light;
import helder.scene.render.MeshRenderer;
import helder.scene.render.Renderer;
import helder.scene.render.Shadows;
import helder.scene.view.OrbitControls;
import helder.scene.view.SceneBox;
import helder.view.graph.Graph.*;
import helder.view.graph.Signal;

// The game: a hole's Sim stepped at its fixed rate from ui's clock, drawn
// by helder.scene in a <Scene> box (its nodes made here in code, from the
// hole's pieces), the camera an <OrbitControls> the game also drives (it
// eases behind the ball while it rolls, and round to face the cup when it
// stops), the shot a ShotGesture on the same box (a press near the ball:
// the arena gives it the pointer), and the juice: a trail, a squash on
// hits, a shake on hard ones, slow motion, confetti and the flag on a
// hole-in. What the HUD shows are signals, written only when they change:
// a frame allocates nothing (measured: GcStats, report()).
class Game {
	public final world = new World("golf");
	public final camera:Camera;
	final eye:Node;
	public var kit(default, null):Null<Kit>;
	public var sim(default, null):Sim;
	final clock = new FixedStep(Sim.DT, 8);
	var box:Null<SceneBox>;
	var orbit:Null<OrbitControls>;
	public final shot = new ShotGesture();

	// --- what the HUD reads
	public final holeIndex = signal(0);
	public final strokes = signal(0);
	// "play" (a hole under way), "done" (holed: the card), "menu"
	public final screen = signal("play");
	// a short message over the scene ("" none), and its serial (a new one each time, for its animation)
	public final toast = signal("");
	public final aiming = signal(false);
	public final shots = signal(0);
	public final power = signal(0.0);
	// best strokes per hole (0: not finished), saved
	public final best:Signal<Array<Int>>;
	final save:Save;

	// --- the scene's nodes
	var course = Node.NONE;
	final ball:Node;
	final squash:Node;
	final unsquash:Node;
	final roll:Node;
	final aimDots:Array<Node> = [];
	final trail:Array<Node> = [];
	final trailAge:Array<Float> = [];
	var trailNext = 0;
	var trailLast = new Vec3(0, 0, 0);
	final confetti:Array<Node> = [];
	// (velocities as three floats each: a struct value in an Array is boxed, each write an allocation)
	final confettiVel:Array<Float> = [];
	final confettiSpin:Array<Float> = [];
	var confettiTime = -1.0;
	var ring = Node.NONE;
	var flag = Node.NONE;
	var flagPole = Node.NONE;
	final moverNodes:Array<Node> = [];
	final clouds:Array<Node> = [];
	final cloudBase:Array<Vec3> = [];
	final light:Node;

	// --- feel
	// the drag's pull (points) for full power, and under which a release does not shoot
	public static inline var PULL = 150.0;
	public static inline var DEAD = 14.0;
	// the camera's ease rates (a second), the time after a touch of the camera before following again
	static inline var FOLLOW = 3.0;
	static inline var TURN = 1.6;
	static inline var HANDS_OFF = 1.2;
	var aimDir = new Vec3(0, 0, -1);
	var aimPower = 0.0;
	var rollQ = Quat.identity();
	var squashAmount = 0.0;
	var squashSpeed = 0.0;
	var squashAxis = Quat.identity();
	var trauma = 0.0;
	var timeScale = 1.0;
	var slowTime = 0.0;
	var sinkTime = -1.0;
	var carded = false;
	var lastTime = -1.0;
	var realTime = 0.0;
	var touched = 99.0;
	var wantYaw = 0.0;
	var turning = false;
	var wasResting = true;
	var target = new Vec3(0, 0, 0);
	var ahead = 0.0;
	static inline var AHEAD = 1.7;
	var toastTime = 0.0;
	// (the game's last frame's allocation, GcStats: report)
	public var frameBytes(default, null) = 0.0;
	public var frames(default, null) = 0;

	public function new() {
		save = new Save();
		best = signal(save.best(Course.holes.length));
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(1.0, 0.1, 200));
		light = world.node("sun");
		light.position = new Vec3(4, 9, 6);
		light.lookAt(new Vec3(0, 0, 0));
		Light.attach(light, Light.directional(new Vec3(1, 0.95, 0.86), 2.4));
		ball = world.node("ball");
		squash = world.node("squash", ball);
		unsquash = world.node("unsquash", squash);
		roll = world.node("roll", unsquash);
		roll.scale = new Vec3(Sim.BALL * 2, Sim.BALL * 2, Sim.BALL * 2);
		sim = new Sim(Course.holes[0]);
		stepFn = stepSim;
		shot.near = nearBall;
		shot.onGesture = g -> aim();
	}

	// --- set up by the <Scene>: its box, its renderer, its controls

	public function attach(b:SceneBox) {
		box = b;
		b.addGesture(shot);
	}

	public function controls(o:OrbitControls) {
		orbit = o;
		o.enablePan = false;
		o.minDistance = 2.2;
		o.maxDistance = 14;
		o.minPitch = 0.28;
		o.maxPitch = 1.35;
		o.rotateSpeed = 0.007;
		o.damping = 0.12;
		place(true);
	}

	public function setup(r:Renderer) {
		r.clearColor = new Color(0, 0, 0, 0);
		r.sky = new Vec3(0.34, 0.38, 0.5);
		r.ground = new Vec3(0.26, 0.22, 0.2);
		r.exposure = 0.95;
		var s = Shadows.cascaded(r.device, 2048, 12);
		s.strength = 0.6;
		r.use(s);
		kit = new Kit(r.device);
		Sounds.start();
		var k = kit;
		MeshRenderer.attach(roll, k.ball);
		for (_ in 0...12) {
			var n = world.node("aim");
			MeshRenderer.attach(n, k.dot);
			n.visible = false;
			aimDots.push(n);
		}
		for (_ in 0...20) {
			var n = world.node("trail");
			MeshRenderer.attach(n, k.trail);
			n.visible = false;
			trail.push(n);
			trailAge.push(99);
		}
		for (i in 0...48) {
			var n = world.node("confetti");
			MeshRenderer.attach(n, k.confetti[i % k.confetti.length]);
			n.visible = false;
			confetti.push(n);
			for (_ in 0...3) {
				confettiVel.push(0);
				confettiSpin.push(0);
			}
		}
		ring = world.node("ring");
		MeshRenderer.attach(ring, k.ring);
		ring.visible = false;
		decor();
		build();
	}

	// --- holes

	public function play(index:Int) {
		holeIndex(index);
		sim = new Sim(Course.holes[index]);
		strokes(0);
		screen("play");
		back = "play";
		sinkTime = -1;
		carded = false;
		confettiTime = -1;
		timeScale = 1;
		rollQ = Quat.identity();
		if (ring.valid) ring.visible = false;
		for (n in confetti)
			n.visible = false;
		for (i in 0...trail.length)
			trailAge[i] = 99;
		build();
		place(true);
	}

	// the holes' menu over the game, and back to where it was
	var back = "play";

	public function openMenu() {
		var s = screen.peek();
		if (s != "menu") back = s;
		screen("menu");
	}

	public function closeMenu()
		screen(back);

	public function next()
		play((holeIndex.peek() + 1) % Course.holes.length);

	public function retry()
		play(holeIndex.peek());

	// the hole's nodes, from its pieces (made again for each hole)
	function build() {
		var k = kit;
		if (k == null) return;
		if (course.valid) course.dispose();
		course = world.node("course");
		moverNodes.resize(0);
		var h = sim.hole, i = 0;
		for (piece in h.pieces) {
			switch piece {
				case Flat(x, z, w, d, y):
					var top = part(i % 2 == 0 ? k.grass : k.grassDark, new Vec3(x, y - 0.07, z), new Vec3(w, 0.14, d));
					var depth = 0.7 + 0.25 * Math.min(w, d);
					part(i % 3 == 2 ? k.rockDark : k.rock, new Vec3(x, y - 0.14, z), new Vec3(w, depth, d));
				case RampZ(x, z0, z1, w, y0, y1):
					rampPart(k, new Vec3(x, y0, z0), new Vec3(x, y1, z1), w, false);
				case RampX(z, x0, x1, d, y0, y1):
					rampPart(k, new Vec3(x0, y0, z), new Vec3(x1, y1, z), d, true);
				case Wall(x0, z0, x1, z1, y):
					var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
					part(k.rail, new Vec3((lx + hx) / 2, y + Sim.RAIL_HEIGHT / 2, (lz + hz) / 2), new Vec3(hx - lx, Sim.RAIL_HEIGHT, hz - lz));
				case Block(x0, z0, x1, z1, y0, y1):
					var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
					part(k.rail, new Vec3((lx + hx) / 2, (y0 + y1) / 2, (lz + hz) / 2), new Vec3(hx - lx, y1 - y0, hz - lz));
				case Post(x, z, r, y):
					part(k.post, new Vec3(x, y, z), new Vec3(2 * r, Sim.RAIL_HEIGHT + r, 2 * r));
				case Mover(x, z, w, d, y, _, _, _, _):
					moverNodes.push(part(k.mover, new Vec3(x, y, z), new Vec3(w, Sim.RAIL_HEIGHT * 1.5, d)));
			}
			i++;
		}
		var c = sim.cup;
		part(k.rim, new Vec3(c.x, c.y - 0.002, c.z), new Vec3(2 * Sim.CUP + 0.05, 0.006, 2 * Sim.CUP + 0.05));
		part(k.hole, new Vec3(c.x, c.y - 0.001, c.z), new Vec3(2 * Sim.CUP, 0.006, 2 * Sim.CUP));
		flagPole = part(k.pole, new Vec3(c.x, c.y, c.z), new Vec3(0.025, 1.0, 0.025));
		flag = world.node("flag", course);
		flag.position = new Vec3(c.x, c.y + 0.72, c.z);
		var cloth = world.node("cloth", flag);
		MeshRenderer.attach(cloth, k.flag);
		cloth.position = new Vec3(0.012, 0, 0);
		cloth.scale = new Vec3(0.34, 0.26, 1);
		var t = sim.hole.tee;
		part(k.tee, new Vec3(t.x, t.y, t.z), new Vec3(0.34, 0.012, 0.34));
		syncBall(0);
	}

	function part(mesh:helder.scene.render.Mesh, at:Vec3, size:Vec3):Node {
		var n = world.node("part", course);
		MeshRenderer.attach(n, mesh);
		n.position = at;
		n.scale = size;
		return n;
	}

	// (a ramp's slab: the body's own place and turn, as Sim makes them)
	function rampPart(k:Kit, a:Vec3, b:Vec3, width:Float, alongX:Bool) {
		var run = alongX ? b.x - a.x : b.z - a.z, rise = b.y - a.y;
		var len = Math.sqrt(run * run + rise * rise);
		var angle = Math.atan2(rise, Math.abs(run)) * (run > 0 ? 1 : -1);
		var q = alongX ? Quat.axisAngle(new Vec3(0, 0, 1), angle) : Quat.axisAngle(new Vec3(1, 0, 0), -angle);
		var up = q.rotate(new Vec3(0, 1, 0));
		var mid = new Vec3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2);
		var n = part(k.grass, mid - up * 0.07, alongX ? new Vec3(len, 0.14, width) : new Vec3(width, 0.14, len));
		n.rotation = q;
		var under = part(k.rock, mid - up * 0.14, alongX ? new Vec3(len * 0.98, 0.5, width) : new Vec3(width, 0.5, len * 0.98));
		under.rotation = q;
	}

	// far islands and clouds round the course (decoration, not touched by the ball)
	function decor() {
		var k = kit;
		var spots = [
			[-7.0, -3.0, -2.2, 1.6], [8.0, -9.0, -1.5, 2.0], [-9.0, -12.0, 0.8, 1.4], [6.0, 4.0, -3.0, 1.2], [-4.0, 7.0, -4.0, 1.8], [12.0, -2.0, 1.0, 1.0],
			[3.5, -22.0, -4.0, 2.4], [-14.0, 2.0, -2.0, 1.5]
		];
		for (s in spots) {
			var root = world.node("isle");
			root.position = new Vec3(s[0], s[2], s[1]);
			var size = s[3];
			var top = world.node("top", root);
			MeshRenderer.attach(top, k.grass);
			top.scale = new Vec3(size, 0.16, size);
			var under = world.node("under", root);
			MeshRenderer.attach(under, k.rockDark);
			under.position = new Vec3(0, -0.08, 0);
			under.scale = new Vec3(size, size * 0.9, size);
			var tree = world.node("tree", root);
			tree.position = new Vec3(size * 0.15, 0.08, -size * 0.1);
			var trunk = world.node("trunk", tree);
			MeshRenderer.attach(trunk, k.trunk);
			trunk.scale = new Vec3(0.1, 0.3, 0.1);
			var leaves = world.node("leaves", tree);
			MeshRenderer.attach(leaves, k.leaves);
			leaves.position = new Vec3(0, 0.25, 0);
			leaves.scale = new Vec3(0.55, 0.8, 0.55);
			clouds.push(root);
			cloudBase.push(root.position);
		}
		for (c in [[-5.0, 4.0, -8.0], [6.0, 5.0, -14.0], [-10.0, 3.0, -18.0], [9.0, 6.0, 2.0], [0.0, 7.0, -26.0]]) {
			var root = world.node("cloud");
			root.position = new Vec3(c[0], c[1], c[2]);
			for (j in 0...3) {
				var puff = world.node("puff", root);
				MeshRenderer.attach(puff, k.cloud);
				puff.position = new Vec3((j - 1) * 0.8, j == 1 ? 0.25 : 0, 0);
				var s = j == 1 ? 1.4 : 1.0;
				puff.scale = new Vec3(s * 1.3, s * 0.8, s);
			}
			clouds.push(root);
			cloudBase.push(root.position);
		}
	}

	// --- the shot

	// (the ball's place on the box, points; z > 1: behind the camera)
	var screenX = 0.0;
	var screenY = 0.0;

	function project(p:Vec3) {
		var b = box;
		if (b == null) return;
		var w = Math.max(1, b.width), h = Math.max(1, b.height);
		var q = MathTools.transformPoint(camera.viewProjection(w / h), p);
		screenX = (q.x + 1) / 2 * w;
		screenY = (1 - q.y) / 2 * h;
	}

	// whether a press at x, y (box points) is near enough the ball to shoot
	function nearBall(x:Float, y:Float):Bool {
		if (screen.peek() != "play" || !sim.resting || sim.sunk) return false;
		project(sim.ball.position);
		var dx = x - screenX, dy = y - screenY;
		// (the ball's size on screen, at least a finger's)
		return dx * dx + dy * dy < 56 * 56;
	}

	// the point of the plane y = height under box point x, y (false: none)
	var hitX = 0.0;
	var hitZ = 0.0;

	function ground(x:Float, y:Float, height:Float):Bool {
		var b = box;
		if (b == null) return false;
		var w = Math.max(1, b.width), h = Math.max(1, b.height);
		var inv = MathTools.inverse(camera.viewProjection(w / h));
		var nx = x / w * 2 - 1, ny = 1 - y / h * 2;
		var a = MathTools.transformPoint(inv, new Vec3(nx, ny, 0)), c = MathTools.transformPoint(inv, new Vec3(nx, ny, 1));
		var d = c - a;
		if (Math.abs(d.y) < 1e-6) return false;
		var t = (height - a.y) / d.y;
		if (t < 0) return false;
		hitX = a.x + d.x * t;
		hitZ = a.z + d.z * t;
		return true;
	}

	// the gesture's state: the aim (opposite the pull from the ball), its power, the shot on release
	function aim() {
		var g = shot;
		switch g.state {
			case Began | Changed:
				var p = sim.ball.position;
				project(p);
				var px = g.x - screenX, py = g.y - screenY;
				var pull = Math.sqrt(px * px + py * py);
				aimPower = Math.min(1, Math.max(0, (pull - DEAD) / (PULL - DEAD)));
				if (pull > 1 && ground(screenX - px / pull * 60, screenY - py / pull * 60, p.y)) {
					var dx = hitX - p.x, dz = hitZ - p.z, l = Math.sqrt(dx * dx + dz * dz);
					if (l > 1e-6) aimDir = new Vec3(dx / l, 0, dz / l);
				}
				aiming(aimPower > 0);
				power(Math.round(aimPower * 100) / 100);
				touched = 99;
			case Ended:
				aiming(false);
				if (aimPower > 0) {
					// (a curve: fine control for putts, the full range still there)
					var speed = Sim.MIN_SPEED + (Sim.MAX_SPEED - Sim.MIN_SPEED) * Math.pow(aimPower, 1.6);
					sim.shoot(aimDir.x, aimDir.z, speed);
					strokes(sim.strokes);
					shots(n -> n + 1);
					Sounds.hit(aimPower);
					trauma = Math.min(1, trauma + aimPower * 0.25);
				}
				aimPower = 0;
			case Cancelled | Failed | Possible:
				aiming(false);
				aimPower = 0;
		}
	}

	// --- the frame

	// a frame at time t (seconds): the simulation's steps for the time since the last, then the view
	public function frame(t:Float) {
		var before = hxmc.GcStats.bytesAllocated();
		var dt = lastTime < 0 ? 0 : Math.min(0.1, t - lastTime);
		lastTime = t;
		realTime += dt;
		// (slow motion after a hole-in, easing back)
		if (slowTime > 0) {
			slowTime = Math.max(0, slowTime - dt);
			var k = slowTime / 1.1;
			timeScale = 1 - 0.8 * k * k * (3 - 2 * k);
		} else timeScale = 1;
		var gameDt = dt * timeScale;
		clock.advance(gameDt, stepFn);
		events();
		syncBall(gameDt);
		aimView();
		trailView(dt);
		juice(gameDt, dt);
		follow(dt);
		frames++;
		if (frames == 2) Sys.println('floating greens: ${Course.holes.length} holes, drawing');
		frameBytes = hxmc.GcStats.bytesAllocated() - before;
		demoFrame(dt);
		stat();
	}

	// (made once: a method passed as a function is a new closure each time)
	final stepFn:Float->Void;

	function stepSim(dt:Float)
		sim.step();

	// --- a demo (natively: GOLF_DEMO=<hole>, its recorded shots played, GcStats per frame printed)

	var demoShots:Null<Array<Array<Float>>>;
	var demoNext = 0;
	var demoWait = 0.0;
	var statFrames = 0;
	var statAllocating = 0;
	var statBytes = 0.0;
	var statMax = 0.0;

	public function demo(hole:Int, shots:Array<Array<Float>>) {
		play(hole);
		demoShots = shots;
		Sys.println("golf: demo of hole " + (hole + 1));
		demoNext = 0;
		demoWait = 1.5;
	}

	function demoFrame(dt:Float) {
		var list = demoShots;
		if (list == null) return;
		if (sim.resting && !sim.sunk && demoNext < list.length) {
			demoWait -= dt;
			if (demoWait <= 0) {
				var s = list[demoNext++];
				sim.shoot(s[0], s[1], s[2]);
				strokes(sim.strokes);
				shots(n -> n + 1);
				Sounds.hit(0.6);
				demoWait = 1.0;
			}
		}
	}

	// (the frame's allocation, counted after the first seconds: what a frame of play costs)
	function stat() {
		if (demoShots == null || realTime < 3) return;
		statFrames++;
		if (frameBytes > 0) {
			statAllocating++;
			statBytes += frameBytes;
			if (frameBytes > statMax) statMax = frameBytes;
		}
		if (statFrames % 60 == 0)
			Sys.println('golf: $statFrames frames, $statAllocating allocated ($statBytes bytes, at most $statMax), strokes ${sim.strokes}${sim.sunk ? ", holed" : ""}');
	}

	// the simulation's events: hits (squash, shake, a sound), a fall, a hole-in
	function events() {
		if (sim.impact > 0.9) {
			var n = sim.impactNormal;
			// (a squash along the hit's direction: the ball turned so y is that way)
			squashAxis = fromTo(new Vec3(0, 1, 0), n);
			squashSpeed -= Math.min(9, sim.impact * 2.2);
			if (sim.impact > 2.4) trauma = Math.min(1, trauma + (sim.impact - 2.4) * 0.12);
			Sounds.bounce(Math.min(1, sim.impact / 6));
		}
		sim.impact = 0;
		if (sim.fell) {
			sim.fell = false;
			strokes(sim.strokes);
			show("Out of bounds  +1");
			Sounds.splash();
			rollQ = Quat.identity();
		}
		if (sim.holed) {
			sim.holed = false;
			strokes(sim.strokes);
			sinkTime = 0;
			slowTime = 1.1;
			burst();
			Sounds.cup();
			var b = best.peek(), i = holeIndex.peek();
			if (b[i] == 0 || sim.strokes < b[i]) {
				var copy = b.copy();
				copy[i] = sim.strokes;
				best(copy);
				save.write(copy);
			}
		}
		if (sim.resting && !wasResting) {
			// (stopped: the camera comes round to face the cup)
			var p = sim.ball.position, c = sim.cup;
			wantYaw = Math.atan2(p.x - c.x, p.z - c.z);
			turning = true;
		}
		wasResting = sim.resting;
	}

	public function show(text:String) {
		toast(text);
		toastTime = 1.8;
	}

	function syncBall(dt:Float) {
		var a = clock.alpha, p = sim.previous, q = sim.ball.position;
		var at = new Vec3(p.x + (q.x - p.x) * a, p.y + (q.y - p.y) * a, p.z + (q.z - p.z) * a);
		if (sinkTime >= 0) {
			// (into the cup: down, with a little rattle round the rim)
			sinkTime += dt;
			var k = Math.min(1, sinkTime / 0.45), c = sim.cup;
			var r = (1 - k) * 0.05;
			at = new Vec3(c.x + Math.sin(sinkTime * 40) * r, c.y + Sim.BALL - k * k * 0.32, c.z + Math.cos(sinkTime * 40) * r);
			if (sinkTime > 0.6 && !carded) {
				carded = true;
				if (screen.peek() == "play") screen("done") else back = "done";
			}
		}
		ball.position = at;
		// (rolling: turned about the axis across its motion by distance / radius)
		var v = sim.ball.velocity;
		var speed = Math.sqrt(v.x * v.x + v.z * v.z);
		if (speed > 1e-3 && sinkTime < 0) {
			var axis = new Vec3(-v.z / speed, 0, v.x / speed);
			rollQ = (Quat.axisAngle(axis, speed * dt / Sim.BALL) * rollQ).normalized();
		}
		roll.rotation = rollQ;
		// (the squash: a spring back to round)
		squashSpeed += (-260 * squashAmount - 16 * squashSpeed) * Math.min(dt, 0.033);
		squashAmount += squashSpeed * Math.min(dt, 0.033);
		squashAmount = Math.max(-0.4, Math.min(0.4, squashAmount));
		var s = squashAmount;
		squash.rotation = squashAxis;
		squash.scale = new Vec3(1 - s * 0.5, 1 + s, 1 - s * 0.5);
		unsquash.rotation = squashAxis.conjugate();
	}

	// the aim: dots from the ball the way it will go, longer and warmer with power
	function aimView() {
		var on = aimPower > 0 && shot.active;
		var p = sim.ball.position;
		var n = aimDots.length;
		var shown = on ? Std.int(3 + aimPower * (n - 3)) : 0;
		if (kit != null) {
			var c0 = new Vec4(1, 1, 1, 1), c1 = Kit.rgb(0xffd166), c2 = Kit.rgb(0xff6b6b);
			var k = aimPower;
			var c = k < 0.6 ? lerp4(c0, c1, k / 0.6) : lerp4(c1, c2, (k - 0.6) / 0.4);
			kit.dotMaterial.baseColor = c;
		}
		for (i in 0...n) {
			var d = aimDots[i];
			d.visible = i < shown;
			if (i >= shown) continue;
			var f = (i + 1) / n;
			var dist = 0.22 + f * (0.4 + aimPower * 2.6);
			d.position = new Vec3(p.x + aimDir.x * dist, p.y - Sim.BALL * 0.55, p.z + aimDir.z * dist);
			var size = 0.13 * (1 - f * 0.6);
			d.scale = new Vec3(size, size * 0.6, size);
		}
	}

	// the trail: spheres dropped behind the moving ball, shrinking
	function trailView(dt:Float) {
		var p = ball.position;
		var v = sim.ball.velocity;
		var fast = v.x * v.x + v.y * v.y + v.z * v.z > 1.5 * 1.5 && sinkTime < 0;
		var dx = p.x - trailLast.x, dy = p.y - trailLast.y, dz = p.z - trailLast.z;
		if (fast && dx * dx + dy * dy + dz * dz > 0.06 * 0.06) {
			trailLast = p;
			trailAge[trailNext] = 0;
			trail[trailNext].position = p;
			trailNext = (trailNext + 1) % trail.length;
		} else if (!fast) trailLast = p;
		for (i in 0...trail.length) {
			var age = trailAge[i] += dt;
			var life = 1 - age / 0.32;
			var n = trail[i];
			n.visible = life > 0;
			if (life <= 0) continue;
			var s = Sim.BALL * 1.7 * life;
			n.scale = new Vec3(s, s, s);
		}
	}

	// confetti from the cup
	function burst() {
		confettiTime = 0;
		var c = sim.cup;
		// (a fixed pattern, golden-angle spread: no random numbers)
		for (i in 0...confetti.length) {
			var a = i * 2.39996, up = 3.2 + (i % 5) * 0.45, out = 0.9 + (i % 7) * 0.22;
			setVec(confettiVel, i, new Vec3(Math.cos(a) * out, up, Math.sin(a) * out));
			setVec(confettiSpin, i, new Vec3(Math.sin(a * 3), 1, Math.cos(a * 2)));
			var n = confetti[i];
			n.position = new Vec3(c.x, c.y + 0.05, c.z);
			n.scale = new Vec3(0.06, 0.012, 0.04);
			n.visible = true;
		}
		if (ring.valid) {
			ring.visible = true;
			ring.position = new Vec3(c.x, c.y + 0.01, c.z);
		}
	}

	function juice(gameDt:Float, dt:Float) {
		// (the flag waving; up and spinning on a hole-in)
		if (flag.valid) {
			var lift = sinkTime >= 0 ? Math.min(1, sinkTime / 0.5) : 0;
			var c = sim.cup;
			flag.position = new Vec3(c.x, c.y + 0.72 + lift * 0.3, c.z);
			flag.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.sin(realTime * 2.2) * 0.25 + lift * lift * realTime * 6);
			flagPole.scale = new Vec3(0.025, 1.0 + lift * 0.3, 0.025);
		}
		if (confettiTime >= 0) {
			confettiTime += gameDt;
			var g = gameDt * 6.0;
			for (i in 0...confetti.length) {
				var n = confetti[i], v = getVec(confettiVel, i);
				// (gravity, and a flutter's drag)
				v = new Vec3(v.x * (1 - 1.8 * gameDt), v.y - g, v.z * (1 - 1.8 * gameDt));
				if (v.y < -0.8) v = new Vec3(v.x, -0.8, v.z);
				setVec(confettiVel, i, v);
				n.position = n.position + v * gameDt;
				var s = getVec(confettiSpin, i);
				n.rotation = Quat.axisAngle(s, confettiTime * 9 + i);
				n.visible = confettiTime < 2.6;
			}
			if (ring.valid) {
				var k = Math.min(1, confettiTime / 0.7);
				ring.visible = k < 1;
				var r = 0.3 + k * 1.6;
				ring.scale = new Vec3(r, 0.05 * (1 - k) + 0.005, r);
				kit.ringMaterial.baseColor = new Vec4(1, 0.9, 0.55, 0.7 * (1 - k));
			}
			if (confettiTime > 2.6) confettiTime = -1;
		}
		// (moving blocks drawn where the simulation has them, between its steps)
		var a = clock.alpha;
		for (i in 0...moverNodes.length) {
			var b = sim.movers[i];
			var at = b.position + b.velocity * (a * Sim.DT);
			var n = moverNodes[i];
			n.position = new Vec3(at.x, at.y - Sim.RAIL_HEIGHT * 0.75, at.z);
		}
		// (the far islands bob, the clouds drift)
		for (i in 0...clouds.length) {
			var b = cloudBase[i];
			clouds[i].position = new Vec3(b.x + Math.sin(realTime * 0.05 + i) * 0.6, b.y + Math.sin(realTime * 0.6 + i * 1.7) * 0.12, b.z);
		}
		if (toastTime > 0) {
			toastTime -= dt;
			if (toastTime <= 0) toast("");
		}
	}

	// --- the camera

	// the camera behind the tee facing the cup (now), or eased toward it
	function place(now:Bool) {
		var o = orbit;
		if (o == null) return;
		var p = sim.ball.position, c = sim.cup;
		o.yaw = Math.atan2(p.x - c.x, p.z - c.z);
		ahead = AHEAD;
		target = new Vec3(p.x - Math.sin(o.yaw) * ahead, p.y, p.z - Math.cos(o.yaw) * ahead);
		o.target = target;
		o.pitch = 0.78;
		o.distance = 6.5;
		o.apply();
		turning = false;
	}

	function follow(dt:Float) {
		var o = orbit;
		if (o == null) return;
		if (o.gesture.active) {
			touched = 0;
			turning = false;
		} else touched += dt;
		// (the target eases to the ball; the ball in the cup: to the cup)
		var p = ball.position;
		var k = 1 - 1 / (1 + FOLLOW * dt + FOLLOW * FOLLOW * dt * dt * 0.5);
		// (looking ahead of the ball, so that on a tall screen the course ahead fills it; less while it rolls, none once holed)
		// (near the cup, half way to it: the cup and the ball both in view)
		var cx = sim.cup.x - p.x, cz = sim.cup.z - p.z, toCup = Math.sqrt(cx * cx + cz * cz);
		var want = sinkTime >= 0 ? 0 : sim.resting ? Math.min(AHEAD, toCup * 0.5) : AHEAD * 0.4;
		ahead += (want - ahead) * Math.min(1, dt * 1.5);
		p = new Vec3(p.x - Math.sin(o.yaw) * ahead, p.y, p.z - Math.cos(o.yaw) * ahead);
		target = target + (p - target) * k;
		o.target = target;
		// (rolling: round behind it, unless the player turned the camera a moment ago)
		var v = sim.ball.velocity, speed = Math.sqrt(v.x * v.x + v.z * v.z);
		if (touched > HANDS_OFF && !sim.resting && speed > 0.8 && sinkTime < 0) {
			// (not round to face it when it comes back at the camera: off a rail, down a slope)
			var behind = Math.atan2(-v.x, -v.z);
			if (Math.abs(wrap(behind - o.yaw)) < 1.4) {
				wantYaw = behind;
				turning = true;
			} else turning = false;
		}
		// (holed: a slow turn round the cup)
		if (sinkTime >= 0 && touched > HANDS_OFF) o.yaw += dt * 0.35;
		if (turning && touched > HANDS_OFF && !shot.active) {
			var d = wrap(wantYaw - o.yaw);
			var rate = sim.resting ? TURN * 1.3 : TURN * Math.min(1, speed / 3);
			o.yaw += d * Math.min(1, rate * dt);
			if (Math.abs(d) < 0.01) turning = false;
		}
		o.apply();
		// (the shake: trauma squared, a few sines' noise)
		trauma = Math.max(0, trauma - dt * 1.4);
		if (trauma > 0) {
			var s = trauma * trauma * 0.07, t = realTime;
			eye.position = eye.position + new Vec3(Math.sin(t * 47) * s, Math.sin(t * 59 + 1) * s, Math.sin(t * 53 + 2) * s);
		}
	}

	// --- helpers

	static inline function getVec(a:Array<Float>, i:Int):Vec3
		return new Vec3(a[3 * i], a[3 * i + 1], a[3 * i + 2]);

	static inline function setVec(a:Array<Float>, i:Int, v:Vec3) {
		a[3 * i] = v.x;
		a[3 * i + 1] = v.y;
		a[3 * i + 2] = v.z;
	}

	static function wrap(a:Float):Float {
		while (a > Math.PI)
			a -= 2 * Math.PI;
		while (a < -Math.PI)
			a += 2 * Math.PI;
		return a;
	}

	static inline function lerp4(a:Vec4, b:Vec4, t:Float):Vec4
		return new Vec4(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t);

	// the turn taking unit a to unit b
	static function fromTo(a:Vec3, b:Vec3):Quat {
		var d = a.x * b.x + a.y * b.y + a.z * b.z;
		if (d < -0.9999) return new Quat(1, 0, 0, 0);
		var c = new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
		return new Quat(c.x, c.y, c.z, 1 + d).normalized();
	}
}
