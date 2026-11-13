import Course.Hole;
import Course.World;
import helder.gfx.Color;
import helder.gfx.shader.Vec3;
import helder.gfx.shader.Vec4;
import helder.scene.Camera;
import helder.scene.FixedStep;
import helder.scene.Node;
import helder.scene.World as SceneWorld;
import helder.scene.math.MathTools;
import helder.scene.math.Quat;
import helder.scene.render.Fog;
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
// hole's pieces), the camera an <OrbitControls> the game also drives: a
// fly-over from the cup back to the tee when a hole starts, easing behind
// the ball while it rolls and round to face the cup when it stops, in
// close round the cup on a hole-in. The shot is a Press on the same box (a
// press near the ball: the arena gives it the pointer at once).
//
// The juice: the pieces move (turnstiles, lifts, gates sinking, tiles
// falling, boosters' chevrons, portals turning, water rippling), particles
// (Particles: puffs of dust, a trail, splashes, sparks, confetti, the
// dusk's fireflies) drawn instanced, a squash on hits, a shake on hard
// ones, slow motion on a hole-in, a sound for each. Each island has its
// own light and colours (Course.worlds). What the HUD shows are signals,
// written only when they change: a frame of play allocates nothing
// (GOLF_DEMO=<hole> prints the frames' GcStats natively).
class Game {
	public final world = new SceneWorld("golf");
	public final camera:Camera;
	final eye:Node;
	public var kit(default, null):Null<Kit>;
	public var sim(default, null):Sim;
	final clock = new FixedStep(Sim.DT, 8);
	var box:Null<SceneBox>;
	var orbit:Null<OrbitControls>;
	var renderer:Null<Renderer>;
	public final shot = new helder.ui.gesture.Press();

	// --- what the HUD reads
	public final strokes = signal(0);
	// "title", "play" (a hole under way), "done" (holed: the card), "menu"
	public final screen = signal("title");
	// a short message over the scene ("" none)
	public final toast = signal("");
	public final aiming = signal(false);
	public final shots = signal(0);
	public final power = signal(0.0);
	// the hole's card shown (as the camera flies over it)
	public final card = signal(false);
	// the curtain drawn between holes
	public final curtain = signal(false);
	// the box wider than tall (a desktop window, a phone on its side)
	public final wide = signal(false);
	// the island's sky, a CSS gradient
	public final sky:Signal<String>;
	// best strokes per hole (0: not finished), saved
	public final best:Signal<Array<Int>>;
	public final holeIndex:Signal<Int>;
	final save:Save;

	// --- the scene's nodes
	var course = Node.NONE;
	final ball:Node;
	final squash:Node;
	final unsquash:Node;
	final roll:Node;
	final aimDots:Array<Node> = [];
	var ring = Node.NONE;
	var flag = Node.NONE;
	var flagPole = Node.NONE;
	final moverNodes:Array<Node> = [];
	final pistonNodes:Array<Node> = [];
	final spinnerNodes:Array<Node> = [];
	final bumperNodes:Array<Node> = [];
	final bumperPulse:Array<Float> = [];
	final bumperSize:Array<Float> = [];
	final chevrons:Array<Node> = [];
	// (per chevron: its pad's centre x, z, its heading x, z, the pad's length along it, its slot)
	final chevronPath:Array<Float> = [];
	final ripples:Array<Node> = [];
	final rippleArea:Array<Float> = [];
	final rippleAge:Array<Float> = [];
	final portalRings:Array<Node> = [];
	final plateNodes:Array<Node> = [];
	final plateLitNodes:Array<Node> = [];
	final plateFlash:Array<Float> = [];
	final gateNodes:Array<Node> = [];
	final arrows:Array<Node> = [];
	final arrowBase:Array<Float> = [];
	final tileNodes:Array<Node> = [];
	final tileY:Array<Float> = [];
	final windAreas:Array<Float> = [];
	final lights:Array<Node> = [];
	final clouds:Array<Node> = [];
	final cloudBase:Array<Vec3> = [];
	final birds:Array<Node> = [];
	final wings:Array<Node> = [];
	var decorRoot = Node.NONE;
	final sun:Node;
	final sunLight:Light;
	var puffs:Null<Particles>;
	var bits:Null<Particles>;
	var motes:Null<Particles>;
	// the hole's extent (x, z) and middle
	var minX = 0.0;
	var maxX = 0.0;
	var minZ = 0.0;
	var maxZ = 0.0;

	// --- feel
	// the drag's pull (points) for full power, and under which a release does not shoot
	public static inline var PULL = 150.0;
	public static inline var DEAD = 14.0;
	// the camera's ease rates (a second), the time after a touch of the camera before following again
	static inline var FOLLOW = 3.0;
	static inline var TURN = 1.6;
	static inline var HANDS_OFF = 1.2;
	// the fly-over's length (s)
	static inline var INTRO = 3.4;
	// the hole behind the title
	static inline var TITLE = 7;
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
	var wasGrounded = true;
	var airSpeed = 0.0;
	var target = new Vec3(0, 0, 0);
	var ahead = 0.0;
	static inline var AHEAD = 1.7;
	var toastTime = 0.0;
	var introTime = -1.0;
	var curtainTime = -1.0;
	var pending = 0;
	var trailLast = new Vec3(0, 0, 0);
	var dustTime = 0.0;
	var ambientTime = 0.0;
	var themed = -1;
	// (the game's last frame's allocation, GcStats: report)
	public var frameBytes(default, null) = 0.0;
	public var frames(default, null) = 0;

	public function new() {
		save = new Save();
		best = signal(save.best(Course.holes.length));
		eye = world.node("eye");
		camera = Camera.attach(eye, Camera.perspective(1.0, 0.1, 200));
		sun = world.node("sun");
		sunLight = Light.attach(sun, Light.directional(new Vec3(1, 0.95, 0.86), 2.4));
		ball = world.node("ball");
		squash = world.node("squash", ball);
		unsquash = world.node("unsquash", squash);
		roll = world.node("roll", unsquash);
		roll.scale = new Vec3(Sim.BALL * 2, Sim.BALL * 2, Sim.BALL * 2);
		// (the first hole not yet finished)
		var first = 0;
		var b = best.peek();
		while (first < b.length - 1 && b[first] > 0)
			first++;
		holeIndex = signal(first);
		// (the title's backdrop: a hole with something moving on it)
		sim = new Sim(Course.holes[TITLE]);
		sky = signal(gradient(Course.worlds[sim.hole.world]));
		stepFn = stepSim;
		shot.within = nearBall;
		shot.onGesture = g -> aim();
		theme(Course.worlds[sim.hole.world]);
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
		o.maxDistance = 16;
		o.minPitch = 0.22;
		o.maxPitch = 1.4;
		o.rotateSpeed = 0.007;
		o.damping = 0.12;
		place(true);
	}

	public function setup(r:Renderer) {
		renderer = r;
		r.clearColor = new Color(0, 0, 0, 0);
		r.rimPower = 3.0;
		var s = Shadows.cascaded(r.device, 2048, 12);
		s.strength = 0.55;
		r.use(s);
		var post = r.post;
		if (post != null) {
			// (a phone's cheaper bloom: four levels from a quarter of the frame)
			post.bloom = 0.045;
			post.levels = 4;
			post.base = 2;
			post.saturation = 1.06;
			post.contrast = 1.04;
			post.vignette = 0.18;
		}
		lightUp();
		// (a renderer made again: the <Scene> without multisampling or half floats on a GPU that had none; the meshes kept)
		if (kit != null) return;
		kit = new Kit(r.device);
		var k = kit;
		Sounds.start();
		MeshRenderer.attach(roll, k.ball);
		for (_ in 0...12) {
			var n = world.node("aim");
			MeshRenderer.attach(n, k.dot);
			n.visible = false;
			aimDots.push(n);
		}
		puffs = new Particles(world, k.puff, 220, "puffs");
		bits = new Particles(world, k.confetti, 160, "confetti");
		motes = new Particles(world, k.mote, 160, "motes");
		ring = world.node("ring");
		MeshRenderer.attach(ring, k.ring);
		ring.visible = false;
		k.theme(Course.worlds[sim.hole.world]);
		build();
	}

	// --- islands: their light and colours

	static function gradient(w:World):String {
		var s = w.sky;
		return 'linear-gradient(180deg, ${s[0]} 0%, ${s[1]} 50%, ${s[2]} 100%)';
	}

	function theme(w:World) {
		sky(gradient(w));
		lightUp();
	}

	function lightUp() {
		var w = Course.worlds[sim.hole.world];
		var d = new Vec3(w.sun[0], w.sun[1], w.sun[2]);
		sun.position = d * 10;
		sun.lookAt(new Vec3(0, 0, 0));
		sunLight.color = Kit.rgb3(w.sunColor);
		sunLight.intensity = w.sunPower;
		var r = renderer;
		if (r == null) return;
		r.sky = Kit.rgb3(w.ambientSky, 0.55);
		r.ground = Kit.rgb3(w.ambientGround, 0.4);
		r.exposure = w.exposure;
		r.rim = Kit.rgb3(w.sunColor, w.night ? 0.35 : 0.18);
		var fog = new Fog(Kit.rgb3(w.fog), 0.025);
		fog.start = 11;
		fog.max = 0.6;
		r.fog = fog;
		if (kit != null) kit.theme(w);
	}

	// --- holes

	public function play(index:Int) {
		var was = sim.hole.world;
		holeIndex(index);
		sim = new Sim(Course.holes[index]);
		strokes(0);
		shots(0);
		screen("play");
		back = "play";
		sinkTime = -1;
		carded = false;
		timeScale = 1;
		slowTime = 0;
		rollQ = Quat.identity();
		restStep = 0;
		if (ring.valid) ring.visible = false;
		if (puffs != null) puffs.clear();
		if (bits != null) bits.clear();
		if (motes != null) motes.clear();
		if (sim.hole.world != was || themed < 0) {
			themed = sim.hole.world;
			theme(Course.worlds[sim.hole.world]);
		}
		build();
		place(true);
		if (demoShots == null) startIntro();
	}

	// the hole's card and the fly-over
	function startIntro() {
		introTime = 0;
		card(true);
	}

	function endIntro() {
		if (introTime < 0) return;
		introTime = -1;
		card(false);
		place(true);
	}

	// from the title: the first hole not yet finished
	public function start()
		go(holeIndex.peek());

	// the holes' menu over the game, and back to where it was
	var back = "play";

	public function openMenu() {
		var s = screen.peek();
		if (s != "menu") back = s;
		endIntro();
		screen("menu");
	}

	public function closeMenu()
		screen(back);

	// a hole from the menu or the card: behind the curtain
	public function go(index:Int) {
		if (curtainTime >= 0) return;
		pending = index;
		curtainTime = 0;
		curtain(true);
	}

	public function next()
		go((holeIndex.peek() + 1) % Course.holes.length);

	public function retry()
		go(holeIndex.peek());

	// the hole's nodes, from its pieces (made again for each hole)
	function build() {
		var k = kit;
		if (k == null) return;
		if (course.valid) course.dispose();
		course = world.node("course");
		for (a in [
			moverNodes, pistonNodes, spinnerNodes, bumperNodes, chevrons, ripples, portalRings, plateNodes, plateLitNodes, gateNodes, arrows, tileNodes, lights
		])
			a.resize(0);
		for (a in [tileY, bumperPulse, bumperSize, chevronPath, rippleArea, rippleAge, plateFlash, arrowBase, windAreas])
			a.resize(0);
		var h = sim.hole, i = 0;
		minX = minZ = 1e9;
		maxX = maxZ = -1e9;
		inline function extent(x0:Float, z0:Float, x1:Float, z1:Float) {
			minX = Math.min(minX, Math.min(x0, x1));
			maxX = Math.max(maxX, Math.max(x0, x1));
			minZ = Math.min(minZ, Math.min(z0, z1));
			maxZ = Math.max(maxZ, Math.max(z0, z1));
		}
		for (piece in h.pieces) {
			switch piece {
				case Flat(x, z, w, d, y):
					slab(k, x, z, w, d, y, i);
					extent(x - w / 2, z - d / 2, x + w / 2, z + d / 2);
				case RampZ(x, z0, z1, w, y0, y1):
					rampPart(k, new Vec3(x, y0, z0), new Vec3(x, y1, z1), w, false);
					extent(x - w / 2, z0, x + w / 2, z1);
				case RampX(z, x0, x1, d, y0, y1):
					rampPart(k, new Vec3(x0, y0, z), new Vec3(x1, y1, z), d, true);
					extent(x0, z - d / 2, x1, z + d / 2);
				case Wall(x0, z0, x1, z1, y):
					var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
					part(k.rail, new Vec3((lx + hx) / 2, y + Sim.RAIL_HEIGHT / 2, (lz + hz) / 2), new Vec3(hx - lx, Sim.RAIL_HEIGHT, hz - lz));
					// (a stripe of the island's colour along its top)
					part(k.accentBox, new Vec3((lx + hx) / 2, y + Sim.RAIL_HEIGHT + 0.006, (lz + hz) / 2),
						new Vec3(Math.max(0.02, hx - lx - 0.06), 0.012, Math.max(0.02, hz - lz - 0.06)));
				case Block(x0, z0, x1, z1, y0, y1):
					var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
					part(k.rail, new Vec3((lx + hx) / 2, (y0 + y1) / 2, (lz + hz) / 2), new Vec3(hx - lx, y1 - y0, hz - lz));
				case Post(x, z, r, y):
					part(k.post, new Vec3(x, y, z), new Vec3(2 * r, Sim.RAIL_HEIGHT + r, 2 * r));
					part(k.accentCylinder, new Vec3(x, y + Sim.RAIL_HEIGHT + r, z), new Vec3(2 * r * 0.8, 0.03, 2 * r * 0.8));
				case Bumper(x, z, r, y):
					var n = part(k.bumper, new Vec3(x, y, z), new Vec3(2 * r, Sim.RAIL_HEIGHT + 0.04, 2 * r));
					var cap = world.node("cap", n);
					MeshRenderer.attach(cap, k.bumperCap);
					cap.position = new Vec3(0, 1, 0);
					cap.scale = new Vec3(0.75, 0.15, 0.75);
					bumperNodes.push(n);
					bumperPulse.push(0);
					bumperSize.push(2 * r);
				case Mover(x, z, w, d, y, _, _, _, _):
					moverNodes.push(part(k.mover, new Vec3(x, y, z), new Vec3(w, Sim.RAIL_HEIGHT * 1.5, d)));
					pistonNodes.push(Node.NONE);
				case Lift(x, z, w, d, y0, y1, _, _):
					var n = world.node("lift", course);
					var top = world.node("top", n);
					MeshRenderer.attach(top, k.grass);
					top.position = new Vec3(0, -0.035, 0);
					top.scale = new Vec3(w - 0.04, 0.07, d - 0.04);
					var side = world.node("side", n);
					MeshRenderer.attach(side, k.liftTop);
					side.position = new Vec3(0, -Sim.LIFT_SLAB / 2 - 0.01, 0);
					side.scale = new Vec3(w, Sim.LIFT_SLAB - 0.02, d);
					moverNodes.push(n);
					var piston = part(k.piston, new Vec3(x, Math.min(y0, y1) - 1.2, z), new Vec3(0.3, 1, 0.3));
					pistonNodes.push(piston);
					extent(x - w / 2, z - d / 2, x + w / 2, z + d / 2);
				case Spinner(x, z, len, y, _, _):
					var n = world.node("spinner", course);
					n.position = new Vec3(x, y, z);
					var bar = world.node("bar", n);
					MeshRenderer.attach(bar, k.spinner);
					bar.position = new Vec3(0, Sim.RAIL_HEIGHT / 2 + 0.01, 0);
					bar.scale = new Vec3(len, Sim.RAIL_HEIGHT, Sim.BAR);
					var hub = world.node("hub", n);
					MeshRenderer.attach(hub, k.hub);
					hub.scale = new Vec3(0.2, Sim.RAIL_HEIGHT + 0.08, 0.2);
					spinnerNodes.push(n);
				case Boost(x, z, w, d, y, ax, az):
					part(k.boost, new Vec3(x, y + 0.004, z), new Vec3(w, 0.008, d));
					var l = Math.sqrt(ax * ax + az * az), hx = ax / l, hz = az / l;
					var along = Math.abs(hx) * w + Math.abs(hz) * d, across = Math.abs(hx) * d + Math.abs(hz) * w;
					for (c in 0...3) {
						var n = part(k.chevron, new Vec3(x, y + 0.008, z), new Vec3(across * 0.6, 0.12, across * 0.6));
						n.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(-hx, -hz));
						chevrons.push(n);
						for (v in [x, z, hx, hz, along, c, y])
							chevronPath.push(v);
					}
				case Wind(x, z, w, d, y, ax, az):
					for (v in [x, z, w, d, y, ax, az])
						windAreas.push(v);
				case Sand(x, z, w, d, y):
					part(k.sand, new Vec3(x, y + 0.002, z), new Vec3(w, 0.006, d));
				case Ice(x, z, w, d, y):
					part(k.ice, new Vec3(x, y + 0.002, z), new Vec3(w, 0.006, d));
				case Water(x, z, w, d, y):
					part(k.water, new Vec3(x, y - 0.02, z), new Vec3(w, 0.04, d));
					// (the pool's bed: a rock under it, its sides rising to the surface)
					part(k.rockDark, new Vec3(x, y - 0.3, z), new Vec3(w * 1.02, 0.9, d * 1.02));
					var t = 0.08;
					part(k.rockBox, new Vec3(x, y - 0.17, z - d / 2 - t / 2), new Vec3(w + 2 * t, 0.34, t));
					part(k.rockBox, new Vec3(x, y - 0.17, z + d / 2 + t / 2), new Vec3(w + 2 * t, 0.34, t));
					part(k.rockBox, new Vec3(x - w / 2 - t / 2, y - 0.17, z), new Vec3(t, 0.34, d));
					part(k.rockBox, new Vec3(x + w / 2 + t / 2, y - 0.17, z), new Vec3(t, 0.34, d));
					for (_ in 0...3) {
						var n = part(k.ripple, new Vec3(x, y + 0.005, z), new Vec3(0, 0, 0));
						n.visible = false;
						ripples.push(n);
						for (v in [x, z, w, d, y])
							rippleArea.push(v);
						rippleAge.push(-Math.random() * 1.5);
					}
					extent(x - w / 2, z - d / 2, x + w / 2, z + d / 2);
				case Portal(x, z, y, tx, tz, ty, dx, dz):
					for (end in 0...2) {
						var px = end == 0 ? x : tx, py = end == 0 ? y : ty, pz = end == 0 ? z : tz;
						part(k.portal, new Vec3(px, py, pz), new Vec3(Sim.PORTAL * 2, 0.012, Sim.PORTAL * 2));
						var r = part(k.portalRing, new Vec3(px, py, pz), new Vec3(Sim.PORTAL * 2.3, 0.05, Sim.PORTAL * 2.3));
						portalRings.push(r);
						if (end == 1) {
							var a = part(k.arrow, new Vec3(px + dx * 0.32, py + 0.01, pz + dz * 0.32), new Vec3(0.18, 0.4, 0.18));
							a.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(-dx, -dz));
						}
					}
				case Switch(x, z, y, group):
					var g = group % Kit.GROUPS.length;
					var base = part(k.rail, new Vec3(x, y, z), new Vec3(Sim.PLATE * 2.4, 0.02, Sim.PLATE * 2.4));
					var n = part(k.plates[g], new Vec3(x, y, z), new Vec3(Sim.PLATE * 2, 0.035, Sim.PLATE * 2));
					var lit = part(k.plateLit[g], new Vec3(x, y, z), new Vec3(Sim.PLATE * 2, 0.035, Sim.PLATE * 2));
					lit.visible = false;
					plateNodes.push(n);
					plateLitNodes.push(lit);
					plateFlash.push(0);
				case Gate(_, _, _, _, _, group, _):
					var b = sim.gates[gateNodes.length];
					var n = world.node("gate", course);
					var body = world.node("body", n);
					MeshRenderer.attach(body, k.gates[group % Kit.GROUPS.length]);
					switch b.shape {
						case Box(half):
							body.scale = new Vec3(half.x * 2, half.y * 2, half.z * 2);
						case _:
					}
					n.position = b.position;
					gateNodes.push(n);
				case OneWay(x0, z0, x1, z1, y, dx, dz):
					var lx = x1 - x0, lz = z1 - z0, len = Math.sqrt(lx * lx + lz * lz);
					var pane = part(k.pane, new Vec3((x0 + x1) / 2, y + 0.09, (z0 + z1) / 2), new Vec3(len, 0.18, 0.02));
					pane.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(-lz, lx));
					var nn = Std.int(Math.max(1, Math.round(len / 0.35)));
					for (j in 0...nn) {
						var t = (j + 0.5) / nn;
						var a = part(k.arrow, new Vec3(x0 + lx * t, y + 0.004, z0 + lz * t), new Vec3(0.22, 0.25, 0.22));
						a.rotation = Quat.axisAngle(new Vec3(0, 1, 0), Math.atan2(-dx, -dz));
						arrows.push(a);
						for (v in [x0 + lx * t, z0 + lz * t, dx, dz, y, j])
							arrowBase.push(v);
					}
				case Crumble(x, z, w, d, y):
					var n = world.node("tile", course);
					n.position = new Vec3(x, y, z);
					var top = world.node("top", n);
					MeshRenderer.attach(top, k.crumble);
					top.position = new Vec3(0, -0.07, 0);
					top.scale = new Vec3(w - 0.03, 0.14, d - 0.03);
					for (c in 0...2) {
						var line = world.node("crack", n);
						MeshRenderer.attach(line, k.crack);
						line.position = new Vec3((c - 0.5) * w * 0.3, 0.001, (0.5 - c) * d * 0.2);
						line.rotation = Quat.axisAngle(new Vec3(0, 1, 0), c == 0 ? 0.7 : -0.5);
						line.scale = new Vec3(w * 0.55, 0.004, 0.025);
					}
					var under = world.node("under", n);
					MeshRenderer.attach(under, k.rock);
					under.position = new Vec3(0, -0.12, 0);
					under.scale = new Vec3(w * 0.9, 0.35, d * 0.9);
					tileNodes.push(n);
					tileY.push(y);
			}
			i++;
		}
		var c = sim.cup;
		part(k.rim, new Vec3(c.x, c.y - 0.002, c.z), new Vec3(2 * Sim.CUP + 0.06, 0.006, 2 * Sim.CUP + 0.06));
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
		var w = Course.worlds[sim.hole.world];
		// (dusk: lanterns by the tee and the cup, lighting the green round them)
		if (w.night) {
			lantern(k, t.x - 0.75, t.y, t.z + 0.15, 0xffc27a);
			lantern(k, c.x + 0.55, c.y, c.z - 0.35, 0xffd9a0);
		}
		decor(k);
		syncBall(0);
	}

	function part(mesh:helder.scene.render.Mesh, at:Vec3, size:Vec3):Node {
		var n = world.node("part", course);
		MeshRenderer.attach(n, mesh);
		n.position = at;
		n.scale = size;
		return n;
	}

	// (a green: its turf, a lip of the darker green round it, the rock under it)
	function slab(k:Kit, x:Float, z:Float, w:Float, d:Float, y:Float, i:Int) {
		part(i % 2 == 0 ? k.grass : k.grassDark, new Vec3(x, y - 0.07, z), new Vec3(w, 0.14, d));
		part(i % 2 == 0 ? k.grassDark : k.grass, new Vec3(x, y - 0.17, z), new Vec3(w + 0.04, 0.08, d + 0.04));
		var depth = 0.8 + 0.3 * Math.min(w, d);
		part(i % 3 == 2 ? k.rockDark : k.rock, new Vec3(x, y - 0.2, z), new Vec3(w * 1.02, depth, d * 1.02));
	}

	function lantern(k:Kit, x:Float, y:Float, z:Float, color:Int) {
		part(k.pole, new Vec3(x, y, z), new Vec3(0.04, 0.55, 0.04));
		var n = part(k.lantern, new Vec3(x, y + 0.6, z), new Vec3(0.12, 0.14, 0.12));
		if (lights.length < 3) {
			var l = world.node("lamp", course);
			l.position = new Vec3(x, y + 0.7, z);
			Light.attach(l, Light.pointLight(Kit.rgb3(color), 3.0, 3.2));
			lights.push(l);
		}
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

	// far islands, clouds and birds round the course (scenery, not touched by the ball), made again for each hole round its extent
	function decor(k:Kit) {
		clouds.resize(0);
		cloudBase.resize(0);
		birds.resize(0);
		wings.resize(0);
		var root = world.node("decor", course);
		var cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
		var rx = (maxX - minX) / 2 + 4, rz = (maxZ - minZ) / 2 + 4;
		var w = Course.worlds[sim.hole.world];
		var spots = [
			[-1.0, 0.2, -2.2, 1.6], [1.0, -0.6, -1.5, 2.0], [-0.9, -1.0, 0.8, 1.4], [0.8, 0.9, -3.0, 1.2], [-0.5, 1.3, -4.0, 1.8], [1.4, 0.1, 1.0, 1.0],
			[0.2, -1.6, -3.0, 2.4], [-1.5, -0.4, -2.0, 1.5]
		];
		var j = 0;
		for (s in spots) {
			var isle = world.node("isle", root);
			isle.position = new Vec3(cx + s[0] * rx, s[2], cz + s[1] * rz);
			var size = s[3];
			var top = world.node("top", isle);
			MeshRenderer.attach(top, k.grass);
			top.scale = new Vec3(size, 0.16, size);
			var under = world.node("under", isle);
			MeshRenderer.attach(under, j % 2 == 0 ? k.rockDark : k.rock);
			under.position = new Vec3(0, -0.08, 0);
			under.scale = new Vec3(size * 1.05, size * 1.1, size * 1.05);
			for (t in 0...(size > 1.5 ? 2 : 1)) {
				var tree = world.node("tree", isle);
				tree.position = new Vec3(size * (0.15 - t * 0.35), 0.08, -size * (0.1 - t * 0.25));
				var trunk = world.node("trunk", tree);
				MeshRenderer.attach(trunk, k.trunk);
				trunk.scale = new Vec3(0.1, 0.3, 0.1);
				var leaves = world.node("leaves", tree);
				MeshRenderer.attach(leaves, k.leaves);
				leaves.position = new Vec3(0, 0.25, 0);
				var ts = t == 0 ? 1.0 : 0.7;
				leaves.scale = new Vec3(0.55 * ts, 0.8 * ts, 0.55 * ts);
			}
			if (j % 3 == 1) {
				var stone = world.node("stone", isle);
				MeshRenderer.attach(stone, k.stone);
				stone.position = new Vec3(-size * 0.25, 0.1, size * 0.2);
				stone.scale = new Vec3(0.3, 0.2, 0.25);
			}
			clouds.push(isle);
			cloudBase.push(isle.position);
			j++;
		}
		var puffs = w.night ? 3 : 5;
		for (i in 0...puffs) {
			var c = world.node("cloud", root);
			var a = i * 2.4 + 0.5;
			c.position = new Vec3(cx + Math.cos(a) * (rx + 9), 6 + (i % 3) * 1.5, cz + Math.sin(a) * (rz + 9) - 4);
			for (p in 0...3) {
				var puff = world.node("puff", c);
				MeshRenderer.attach(puff, k.cloud);
				puff.position = new Vec3((p - 1) * 0.8, p == 1 ? 0.25 : 0, 0);
				var s = p == 1 ? 1.4 : 1.0;
				puff.scale = new Vec3(s * 1.3, s * 0.8, s);
			}
			clouds.push(c);
			cloudBase.push(c.position);
		}
		// (birds by day, circling high over the hole)
		if (!w.night)
			for (b in 0...4) {
				var bird = world.node("bird", root);
				for (side in 0...2) {
					var wing = world.node("wing", bird);
					MeshRenderer.attach(wing, k.wing);
					wing.scale = new Vec3(side == 0 ? 0.32 : -0.32, 0.12, 1);
					wings.push(wing);
				}
				birds.push(bird);
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

	// whether a press at x, y (box points) is near enough the ball to shoot (a press during the fly-over skips it)
	function nearBall(x:Float, y:Float):Bool {
		if (introTime >= 0) {
			endIntro();
			return false;
		}
		if (screen.peek() != "play" || !sim.resting || sim.sunk || curtainTime >= 0) return false;
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
				if (aimPower > 0 && sim.resting) {
					// (a curve: fine control for putts, the full range still there)
					var speed = Sim.MIN_SPEED + (Sim.MAX_SPEED - Sim.MIN_SPEED) * Math.pow(aimPower, 1.6);
					shootNow(aimDir.x, aimDir.z, speed, aimPower);
				}
				aimPower = 0;
			case Cancelled | Failed | Possible:
				aiming(false);
				aimPower = 0;
		}
	}

	function shootNow(dx:Float, dz:Float, speed:Float, power:Float) {
		sim.shoot(dx, dz, speed);
		strokes(sim.strokes);
		shots(n -> n + 1);
		Sounds.hit(power);
		trauma = Math.min(1, trauma + power * 0.22);
		var p = sim.ball.position;
		if (puffs != null) puffs.burst(Std.int(4 + power * 8), p.x, p.y - Sim.BALL * 0.6, p.z, 0.4 + power, 0.4, 0.5, 0.09, 0.5, 2.5, 0xffffff);
	}

	// --- the frame

	// a frame at time t (seconds): the simulation's steps for the time since the last, then the view
	public function frame(t:Float) {
		var before = hxmc.GcStats.bytesAllocated();
		var dt = lastTime < 0 ? 0 : Math.min(0.1, t - lastTime);
		lastTime = t;
		realTime += dt;
		var b = box;
		if (b != null) {
			var w = b.width > b.height * 1.05;
			if (w != wide.peek()) wide(w);
		}
		// (slow motion after a hole-in, easing back)
		if (slowTime > 0) {
			slowTime = Math.max(0, slowTime - dt);
			var k = slowTime / 1.3;
			timeScale = 1 - 0.75 * k * k * (3 - 2 * k);
		} else timeScale = 1;
		var gameDt = dt * timeScale;
		clock.advance(gameDt, stepFn);
		events();
		syncBall(gameDt);
		aimView();
		pieces(gameDt, dt);
		trail(gameDt);
		juice(gameDt, dt);
		ambient(dt);
		if (puffs != null) puffs.update(gameDt, realTime);
		if (bits != null) bits.update(gameDt, realTime);
		if (motes != null) motes.update(gameDt, realTime);
		follow(dt);
		transition(dt);
		frames++;
		if (frames == 1) Sys.println('floating greens: ${Course.holes.length} holes, drawing');
		frameBytes = hxmc.GcStats.bytesAllocated() - before;
		stat();
	}

	// the curtain between holes: drawn, the hole changed behind it, opened
	function transition(dt:Float) {
		if (curtainTime < 0) return;
		var was = curtainTime;
		curtainTime += dt;
		if (was < 0.3 && curtainTime >= 0.3) play(pending);
		if (curtainTime >= 0.36) {
			curtainTime = -1;
			curtain(false);
		}
	}

	// (made once: a method passed as a function is a new closure each time)
	final stepFn:Float->Void;

	function stepSim(dt:Float) {
		sim.step();
		demoStep();
	}

	// --- a demo (GOLF_DEMO=<hole>: its recorded shots played, each at the step GolfReplay plays it; GcStats per frame printed natively)

	var demoShots:Null<Array<Array<Float>>>;
	var demoNext = 0;
	var restStep = 0;
	var statFrames = 0;
	var statAllocating = 0;
	var statBytes = 0.0;
	var statMax = 0.0;

	public function demo(hole:Int, shots:Array<Array<Float>>) {
		demoShots = shots;
		Sys.println("golf: demo of hole " + (hole + 1));
		demoNext = 0;
		play(hole);
		endIntro();
	}

	function demoStep() {
		var list = demoShots;
		if (list == null) return;
		if (!sim.resting) {
			restStep = -1;
			return;
		}
		if (restStep < 0) restStep = sim.steps;
		if (sim.sunk || demoNext >= list.length) return;
		var s = list[demoNext];
		var wait = s.length > 3 ? Std.int(s[3]) : GolfReplay.WAIT;
		if (sim.steps - restStep >= wait) {
			demoNext++;
			shootNow(s[0], s[1], s[2], (s[2] - Sim.MIN_SPEED) / (Sim.MAX_SPEED - Sim.MIN_SPEED));
			restStep = -1;
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
			Sys.println('golf: $statFrames frames, $statAllocating allocated ($statBytes bytes, at most $statMax), strokes ${sim.strokes}${sim.sunk ? ", holed" : ""}, ${renderer != null ? renderer.draws : 0} draws');
	}

	// the simulation's events: hits (squash, shake, a sound), kicks, portals, switches, tiles, a fall or a splash, a hole-in
	function events() {
		var p = sim.ball.position;
		if (sim.impact > 0.9) {
			var n = sim.impactNormal;
			// (a squash along the hit's direction: the ball turned so y is that way)
			squashAxis = fromTo(new Vec3(0, 1, 0), n);
			squashSpeed -= Math.min(9, sim.impact * 2.2);
			if (sim.impact > 2.4) trauma = Math.min(1, trauma + (sim.impact - 2.4) * 0.1);
			Sounds.bounce(Math.min(1, sim.impact / 6));
			if (puffs != null && sim.impact > 1.6)
				puffs.burst(Std.int(Math.min(8, sim.impact * 1.5)), p.x - n.x * Sim.BALL, p.y - n.y * Sim.BALL, p.z - n.z * Sim.BALL, 0.6, 0.5, 0.45, 0.07, 0.5,
					3, 0xffffff);
		}
		sim.impact = 0;
		// (landing after a flight: a puff of dust)
		if (sim.grounded && !wasGrounded && airSpeed > 1.6 && puffs != null) {
			var c = sim.area == Sim.AREA_SAND ? 0xf3d9a4 : 0xffffff;
			puffs.burst(10, p.x, p.y - Sim.BALL, p.z, 1.0, 0.6, 0.6, 0.1, 1.0, 3, c);
			Sounds.land(Math.min(1, airSpeed / 5));
		}
		if (!sim.grounded) airSpeed = Math.max(airSpeed, -sim.ball.velocity.y) else airSpeed = 0;
		wasGrounded = sim.grounded;
		if (sim.kicked >= 0) {
			var i = sim.kicked;
			sim.kicked = -1;
			if (i < bumperPulse.length) bumperPulse[i] = 1;
			Sounds.boing();
			if (motes != null) motes.burst(6, p.x, p.y, p.z, 1.2, 1.0, 0.4, 0.05, 2, 2, 0xff8fa0);
		}
		if (sim.warped >= 0) {
			var i = sim.warped;
			sim.warped = -1;
			Sounds.warp();
			var m = motes;
			if (m != null) {
				m.burst(14, sim.portalAt(i, 0), sim.portalAt(i, 1) + 0.05, sim.portalAt(i, 2), 1.2, 1.4, 0.7, 0.06, 1.5, 2, 0xc9a8ff);
				m.burst(14, p.x, p.y, p.z, 1.2, 1.4, 0.7, 0.06, 1.5, 2, 0xc9a8ff);
			}
			trailLast = p;
			rollQ = Quat.identity();
		}
		if (sim.thrown >= 0) {
			var i = sim.thrown;
			sim.thrown = -1;
			if (i < plateFlash.length) plateFlash[i] = 1;
			Sounds.click();
			Sounds.rumble();
			var group = Std.int(sim.plateAt(i, 3));
			if (motes != null) motes.burst(10, sim.plateAt(i, 0), sim.plateAt(i, 1) + 0.04, sim.plateAt(i, 2), 1, 1.2, 0.6, 0.05, 2, 2,
				Kit.GROUPS[group % Kit.GROUPS.length]);
			// (the gates it moved: dust where they slide)
			for (k in 0...sim.gates.length)
				if (sim.gateGroup[k] == group && puffs != null) {
					var g = sim.gates[k].position;
					puffs.burst(8, g.x, g.y - Sim.GATE_HEIGHT / 2 + 0.02, g.z, 0.8, 0.4, 0.6, 0.09, 0.5, 3, 0xffffff);
				}
		}
		if (sim.cracked >= 0) {
			var i = sim.cracked;
			sim.cracked = -1;
			Sounds.crumble();
			if (i < tileNodes.length && bits != null) {
				var t = tileNodes[i].position;
				for (_ in 0...10)
					bits.emit(t.x + (bits.random() - 0.5) * 0.6, t.y - 0.05, t.z + (bits.random() - 0.5) * 0.9, (bits.random() - 0.5) * 0.6,
						bits.random() * 0.5, (bits.random() - 0.5) * 0.6, 1.4, 0.12, 6, 0.3, 0xd2c46a, 6);
			}
		}
		if (sim.fell) {
			sim.fell = false;
			strokes(sim.strokes);
			show("Out of bounds  +1");
			Sounds.fall();
			rollQ = Quat.identity();
			appear();
		}
		if (sim.splashed) {
			sim.splashed = false;
			strokes(sim.strokes);
			show("Splash!  +1");
			Sounds.splash();
			var s = sim.splashAt;
			if (puffs != null) {
				puffs.burst(16, s.x, s.y, s.z, 1.0, 2.6, 0.8, 0.08, 7, 1, 0xbfe9ff);
				puffs.burst(8, s.x, s.y, s.z, 0.5, 3.4, 0.9, 0.06, 7, 1, 0xffffff);
			}
			// (a ring on the water where it went in)
			for (k in 0...ripples.length)
				if (rippleAge[k] > 0.9 || rippleAge[k] < 0) {
					ripples[k].position = new Vec3(s.x, s.y + 0.005, s.z);
					rippleAge[k] = 0;
					break;
				}
			rollQ = Quat.identity();
			appear();
		}
		if (sim.holed) {
			sim.holed = false;
			strokes(sim.strokes);
			sinkTime = 0;
			slowTime = 1.3;
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
		if (sim.resting && !wasResting && !sim.sunk) {
			// (stopped: the camera comes round to face the cup)
			var c = sim.cup;
			wantYaw = Math.atan2(p.x - c.x, p.z - c.z);
			turning = true;
		}
		wasResting = sim.resting;
	}

	// (put back: a puff where it reappears)
	function appear() {
		var p = sim.ball.position;
		trailLast = p;
		if (motes != null) motes.burst(10, p.x, p.y, p.z, 0.8, 1, 0.5, 0.05, 1, 2, 0xffffff);
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
			if (sinkTime > 1.25 && !carded) {
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
			kit.dotMaterial.emissive = new Vec3(c.x * 0.5, c.y * 0.5, c.z * 0.5);
		}
		for (i in 0...n) {
			var d = aimDots[i];
			d.visible = i < shown;
			if (i >= shown) continue;
			var f = (i + 1) / n;
			// (the dots creep outward, a pulse along the line)
			var dist = 0.22 + (f + (realTime * 0.6 % (1 / n))) * (0.4 + aimPower * 2.6);
			d.position = new Vec3(p.x + aimDir.x * dist, p.y - Sim.BALL * 0.55, p.z + aimDir.z * dist);
			var size = 0.12 * (1 - f * 0.6);
			d.scale = new Vec3(size, size * 0.6, size);
		}
	}

	// the trail: puffs dropped behind the moving ball, shrinking
	function trail(dt:Float) {
		var pf = puffs;
		if (pf == null) return;
		var p = ball.position;
		var v = sim.ball.velocity;
		var sp2 = v.x * v.x + v.y * v.y + v.z * v.z;
		var fast = sp2 > 1.4 * 1.4 && sinkTime < 0;
		var dx = p.x - trailLast.x, dy = p.y - trailLast.y, dz = p.z - trailLast.z;
		if (fast && dx * dx + dy * dy + dz * dz > 0.07 * 0.07) {
			trailLast = p;
			var k = Math.min(1, Math.sqrt(sp2) / 6);
			pf.emit(p.x, p.y, p.z, 0, 0.05, 0, 0.3 + 0.2 * k, Sim.BALL * (1.2 + 0.6 * k), 0, 0, 0xffffff);
		} else if (!fast) trailLast = p;
		// (rolling through sand: a little kicked up)
		if (sim.area == Sim.AREA_SAND && !sim.resting) {
			dustTime -= dt;
			if (dustTime <= 0) {
				dustTime = 0.06;
				pf.emit(p.x, p.y - Sim.BALL * 0.7, p.z, -v.x * 0.15 + (pf.random() - 0.5) * 0.3, 0.5, -v.z * 0.15 + (pf.random() - 0.5) * 0.3, 0.5, 0.06, 2, 1,
					0xf3d9a4);
			}
		}
		// (over a booster: sparks)
		if (sim.area == Sim.AREA_BOOST && motes != null) {
			dustTime -= dt;
			if (dustTime <= 0) {
				dustTime = 0.03;
				motes.emit(p.x, p.y - Sim.BALL * 0.5, p.z, -v.x * 0.2 + (motes.random() - 0.5) * 0.6, 0.6, -v.z * 0.2 + (motes.random() - 0.5) * 0.6, 0.35, 0.04, 3, 1,
					0xffb060);
			}
		}
	}

	// confetti from the cup, a ring, sparks
	function burst() {
		var c = sim.cup;
		var w = Course.worlds[sim.hole.world];
		var colors = [0xff8a80, 0xffd166, 0x7ec8f8, 0xb39ddb, 0x8fd694, w.accent];
		var b = bits;
		if (b != null)
			for (i in 0...90) {
				var a = b.random() * Math.PI * 2, out = 0.6 + b.random() * 1.6, up = 3.2 + b.random() * 2.2;
				b.emit(c.x, c.y + 0.05, c.z, Math.cos(a) * out, up, Math.sin(a) * out, 2.4 + b.random() * 0.8, 0.07, 4.5, 1.6, colors[i % colors.length],
					6 + b.random() * 6);
			}
		if (motes != null) motes.burst(30, c.x, c.y + 0.05, c.z, 1.6, 2.8, 1.2, 0.05, 2.5, 1.5, 0xfff0b0);
		if (ring.valid) {
			ring.visible = true;
			ring.position = new Vec3(c.x, c.y + 0.01, c.z);
		}
		ringTime = 0;
	}

	var ringTime = -1.0;

	// the pieces moving as the simulation has them, between its steps
	function pieces(gameDt:Float, dt:Float) {
		var a = clock.alpha;
		var t = (sim.steps + a) * Sim.DT;
		for (i in 0...moverNodes.length) {
			var b = sim.movers[i];
			var at = b.position + b.velocity * (a * Sim.DT);
			var n = moverNodes[i];
			var piston = pistonNodes[i];
			switch b.shape {
				case Box(half):
					if (piston.isNone) n.position = new Vec3(at.x, at.y - Sim.RAIL_HEIGHT * 0.75, at.z) else {
						var top = at.y + half.y;
						n.position = new Vec3(at.x, top, at.z);
						var bottom = piston.position.y;
						piston.scale = new Vec3(0.3, Math.max(0.01, top - Sim.LIFT_SLAB - bottom), 0.3);
					}
				case _:
			}
		}
		for (i in 0...spinnerNodes.length)
			spinnerNodes[i].rotation = Sim.yaw(sim.spinnerStart[i] + sim.spinnerSpeed[i] * t);
		for (i in 0...bumperNodes.length) {
			var k = bumperPulse[i];
			if (k <= 0) continue;
			k = Math.max(0, k - dt * 4);
			bumperPulse[i] = k;
			var n = bumperNodes[i], r = bumperSize[i] * (1 + 0.35 * k * k);
			n.scale = new Vec3(r, Sim.RAIL_HEIGHT + 0.04, r);
		}
		for (i in 0...chevrons.length) {
			var o = i * 7;
			var x = chevronPath[o], z = chevronPath[o + 1], hx = chevronPath[o + 2], hz = chevronPath[o + 3], along = chevronPath[o + 4];
			var u = (realTime * 1.4 + chevronPath[o + 5] / 3) % 1;
			var d = (u - 0.5) * along * 0.75;
			var n = chevrons[i];
			n.position = new Vec3(x + hx * d, chevronPath[o + 6] + 0.008, z + hz * d);
			var s = n.scale.x;
			var fade = Math.sin(u * Math.PI);
			n.scale = new Vec3(s, 0.12 * fade + 0.01, s);
		}
		for (i in 0...gateNodes.length) {
			var b = sim.gates[i];
			gateNodes[i].position = b.position + b.velocity * (a * Sim.DT);
		}
		for (i in 0...plateNodes.length) {
			var f = plateFlash[i];
			if (f > 0) plateFlash[i] = Math.max(0, f - dt * 1.2);
			plateLitNodes[i].visible = f > 0;
			plateNodes[i].visible = f <= 0;
		}
		for (i in 0...portalRings.length) {
			var r = portalRings[i];
			r.rotation = Quat.axisAngle(new Vec3(0, 1, 0), realTime * 1.5 + i);
			var pulse = 1 + 0.08 * Math.sin(realTime * 4 + i * 1.3);
			r.scale = new Vec3(Sim.PORTAL * 2.3 * pulse, 0.05 + 0.03 * Math.sin(realTime * 3 + i), Sim.PORTAL * 2.3 * pulse);
		}
		for (i in 0...arrows.length) {
			var o = i * 6;
			var u = Math.sin(realTime * 3 - arrowBase[o + 5] * 0.6);
			arrows[i].position = new Vec3(arrowBase[o] + arrowBase[o + 2] * 0.05 * u, arrowBase[o + 4] + 0.004, arrowBase[o + 1] + arrowBase[o + 3] * 0.05 * u);
		}
		for (i in 0...tileNodes.length) {
			var n = tileNodes[i], b = Std.int(sim.tileState[i]);
			var base = sim.tiles[i].position;
			switch b {
				case 0:
					n.visible = true;
					n.position = new Vec3(base.x, base.y + Sim.SLAB / 2, base.z);
					n.rotation = Quat.identity();
				case 1:
					// (touched: trembling while the ball is on it)
					var j = 0.006 * Math.sin(realTime * 70 + i);
					n.position = new Vec3(base.x + j, base.y + Sim.SLAB / 2, base.z - j);
				case _:
					// (fallen: down and turning, then gone)
					var ft = sim.tileTime[i];
					n.position = new Vec3(n.position.x, tileY[i] - 4.9 * ft * ft, n.position.z);
					n.rotation = Quat.axisAngle(new Vec3(1, 0, 0.4), ft * 1.6);
					n.visible = ft < 1.6;
			}
		}
		// (ripples spreading on the water)
		for (i in 0...ripples.length) {
			var age = rippleAge[i] += dt;
			var n = ripples[i];
			if (age < 0) continue;
			if (age > 2.2) {
				// (again somewhere else on the pool)
				var o = i * 5, pf = puffs;
				var rx = pf != null ? pf.random() : 0.5, rz = pf != null ? pf.random() : 0.5;
				n.position = new Vec3(rippleArea[o] + (rx - 0.5) * rippleArea[o + 2] * 0.8, rippleArea[o + 4] + 0.005,
					rippleArea[o + 1] + (rz - 0.5) * rippleArea[o + 3] * 0.8);
				rippleAge[i] = age = 0;
			}
			var k = age / 2.2;
			n.visible = true;
			var r = 0.1 + k * 0.9;
			n.scale = new Vec3(r, 0.012 * (1 - k) + 0.001, r);
		}
		// (gusts: specks blown across their area)
		var pf = puffs;
		if (pf != null)
			for (i in 0...Std.int(windAreas.length / 7)) {
				var o = i * 7;
				if (pf.random() > dt * 9) continue;
				var x = windAreas[o], z = windAreas[o + 1], w = windAreas[o + 2], d = windAreas[o + 3], y = windAreas[o + 4];
				var ax = windAreas[o + 5], az = windAreas[o + 6], l = Math.sqrt(ax * ax + az * az);
				var hx = ax / l, hz = az / l;
				// (from the upwind edge, anywhere along it)
				var sx = x - hx * w / 2 + (1 - Math.abs(hx)) * (pf.random() - 0.5) * w;
				var sz = z - hz * d / 2 + (1 - Math.abs(hz)) * (pf.random() - 0.5) * d;
				var speed = 2.8 + pf.random(), sy = y + 0.08 + pf.random() * 0.7;
				var life = Math.max(w * Math.abs(hx), d * Math.abs(hz)) / speed;
				// (a streak: a few specks one behind the other, the front one biggest)
				for (k in 0...6)
					pf.emit(sx - hx * k * 0.045, sy, sz - hz * k * 0.045, hx * speed, 0, hz * speed, life, 0.048 - k * 0.006, 0, 0, 0xffffff);
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
		if (ringTime >= 0 && ring.valid) {
			ringTime += gameDt;
			var k = Math.min(1, ringTime / 0.8);
			ring.visible = k < 1;
			var r = 0.3 + k * 2.0;
			ring.scale = new Vec3(r, 0.05 * (1 - k) + 0.005, r);
			if (k >= 1) ringTime = -1;
		}
		if (toastTime > 0) {
			toastTime -= dt;
			if (toastTime <= 0) toast("");
		}
	}

	// the scenery's life: islands bobbing, clouds drifting, birds circling, fireflies at dusk
	function ambient(dt:Float) {
		for (i in 0...clouds.length) {
			var b = cloudBase[i];
			clouds[i].position = new Vec3(b.x + Math.sin(realTime * 0.05 + i) * 0.6, b.y + Math.sin(realTime * 0.6 + i * 1.7) * 0.12, b.z);
		}
		var cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
		for (i in 0...birds.length) {
			var a = realTime * 0.18 + i * 0.5, r = 13 + i * 0.7;
			var bird = birds[i];
			bird.position = new Vec3(cx + Math.cos(a) * r + (i % 2) * 0.5, 6.5 + i * 0.4 + Math.sin(realTime * 0.8 + i) * 0.2, cz + Math.sin(a) * r);
			// (facing along the circle, the wings flapping)
			bird.rotation = Quat.axisAngle(new Vec3(0, 1, 0), -a);
			var flap = Math.sin(realTime * 9 + i * 1.7) * 0.6;
			wings[i * 2].rotation = Quat.axisAngle(new Vec3(0, 0, 1), flap);
			wings[i * 2 + 1].rotation = Quat.axisAngle(new Vec3(0, 0, 1), -flap);
		}
		var m = motes;
		if (m != null && Course.worlds[sim.hole.world].night) {
			ambientTime -= dt;
			if (ambientTime <= 0) {
				ambientTime = 0.25;
				var x = minX - 1 + m.random() * (maxX - minX + 2), z = minZ - 1 + m.random() * (maxZ - minZ + 2);
				m.emit(x, 0.2 + m.random() * 1.2, z, (m.random() - 0.5) * 0.3, (m.random() - 0.3) * 0.15, (m.random() - 0.5) * 0.3, 4 + m.random() * 2, 0.035,
					0, 0, 0xffe48a);
			}
		}
	}

	// --- the camera

	// where the camera rests behind the ball facing the cup
	var restYaw = 0.0;
	var restTarget = new Vec3(0, 0, 0);

	function rest() {
		var p = sim.ball.position, c = sim.cup;
		restYaw = Math.atan2(p.x - c.x, p.z - c.z);
		restTarget = new Vec3(p.x - Math.sin(restYaw) * AHEAD, p.y, p.z - Math.cos(restYaw) * AHEAD);
	}

	// the camera behind the tee facing the cup (now), or eased toward it
	function place(now:Bool) {
		var o = orbit;
		if (o == null) return;
		rest();
		o.yaw = restYaw;
		ahead = AHEAD;
		target = restTarget;
		o.target = target;
		o.pitch = 0.78;
		o.distance = wide.peek() ? 6.0 : 6.5;
		o.apply();
		turning = false;
	}

	function follow(dt:Float) {
		var o = orbit;
		if (o == null) return;
		if (o.gesture.active) {
			touched = 0;
			turning = false;
			if (introTime >= 0) endIntro();
		} else touched += dt;
		var s = screen.peek();
		if (s == "title" || (s == "menu" && back == "title")) {
			// (the title: a slow turn round the hole)
			var cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
			o.target = new Vec3(cx, 0, cz);
			o.yaw += dt * 0.12;
			o.pitch = 0.62;
			o.distance = Math.max(7, Math.max(maxX - minX, maxZ - minZ) * 0.95 + 2);
			o.apply();
			return;
		}
		if (introTime >= 0) {
			introTime += dt;
			flyOver(o);
			if (introTime >= INTRO) endIntro();
			return;
		}
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
		// (holed: in close, lower, turning slowly round the cup)
		if (sinkTime >= 0 && touched > HANDS_OFF) {
			var e = Math.min(1, dt * 1.6);
			o.yaw += dt * 0.45 * Math.max(0.2, 1 - sinkTime / 5);
			o.distance += (3.4 - o.distance) * e;
			o.pitch += (0.5 - o.pitch) * e;
		}
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

	// the fly-over: from high over the cup, round and down to behind the ball
	function flyOver(o:OrbitControls) {
		rest();
		var u = Math.min(1, introTime / INTRO);
		// (a moment over the cup, then the sweep: smootherstep)
		var k = u < 0.25 ? 0 : (u - 0.25) / 0.75;
		var e = k * k * k * (k * (k * 6 - 15) + 10);
		var c = sim.cup;
		var size = Math.max(maxX - minX, maxZ - minZ);
		var from = new Vec3(c.x, c.y, c.z);
		var endDistance = wide.peek() ? 6.0 : 6.5;
		var startYaw = restYaw + 1.1 - u * 0.4;
		// (a tall screen sees less across: from farther)
		var far = Math.max(5, size * 0.6 + 3) * (wide.peek() ? 1 : 1.35);
		o.target = from + (restTarget - from) * e;
		o.yaw = startYaw + wrap(restYaw - startYaw) * e;
		o.pitch = 1.15 + (0.78 - 1.15) * e;
		o.distance = far + (endDistance - far) * e;
		target = o.target;
		ahead = AHEAD;
		o.apply();
	}

	// --- helpers

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
