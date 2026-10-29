import Course.Hole;
import Course.Piece;
import helder.gfx.shader.Vec3;
import helder.physics.*;
import helder.scene.math.Quat;

// One hole's simulation on helder.physics, stepped at a fixed rate (DT):
// the ball a sphere that slides on the green with a little friction (a
// roll's resistance: it does not turn, the view rolls it), a drag
// proportional to its speed, bounces off rails and posts, carried and
// pushed by moving blocks (static bodies moved each step, their velocity
// set so contacts see it), pulled gently toward the cup when near it and
// captured below a speed; off the island it is put back where it was hit
// from, a stroke added. Deterministic: no sin, cos or exp in a step (only
// arithmetic and square roots, the same bits on every target), so a
// recorded round replays (tests: GolfReplay). A step allocates nothing.
class Sim {
	public static inline var DT = 1 / 120;
	public static inline var BALL = 0.09;
	public static inline var CUP = 0.16;
	// the slowest and fastest shots (m/s)
	public static inline var MIN_SPEED = 0.6;
	public static inline var MAX_SPEED = 7.0;
	// captured over the cup below this speed (m/s); faster, it hops over
	public static inline var CAPTURE = 1.9;
	// the slab's thickness under a green's top, a rail's height
	public static inline var SLAB = 0.4;
	public static inline var RAIL_HEIGHT = 0.2;
	// speed lost a second in proportion to speed (the grass), and the speed under which the ball stops
	static inline var DRAG = 0.45;
	static inline var STOP = 0.1;

	public final physics = new PhysicsWorld();
	public final hole:Hole;
	public final ball:Body;
	// moving blocks: the body and its path (base, offset, period, phase)
	public final movers:Array<Body> = [];
	final moverBase:Array<Vec3> = [];
	final moverOffset:Array<Vec3> = [];
	final moverPeriod:Array<Float> = [];
	final moverPhase:Array<Float> = [];
	// the cup's centre (on the green's top)
	public final cup:Vec3;
	// below this the ball has fallen off
	public final floor:Float;

	public var strokes(default, null) = 0;
	public var steps(default, null) = 0;
	// at rest (a shot may be played), in the cup
	public var resting(default, null) = true;
	public var sunk(default, null) = false;
	// where the last shot was played from (the ball put back there after a fall)
	public var spot(default, null):Vec3;
	// the ball's position before the last step (the view draws between it and now)
	public var previous(default, null):Vec3;

	// this step's events, for the view (cleared by the view when read):
	// the hardest hit's speed change and its direction, a fall, a sinking, a shot
	public var impact = 0.0;
	public var impactNormal = new Vec3(0, 1, 0);
	public var fell = false;
	public var holed = false;
	// whether the ball touched the ground in the last step
	public var grounded(default, null) = false;
	var still = 0;

	public function new(hole:Hole) {
		this.hole = hole;
		physics.sleepSteps = 1 << 30;
		physics.iterations = 8;
		var low = 0.0;
		for (piece in hole.pieces)
			low = Math.min(low, add(piece));
		floor = low - SLAB - 1.5;
		cup = new Vec3(hole.cup.x, hole.cup.y, hole.cup.z);
		var start = new Vec3(hole.tee.x, hole.tee.y + BALL, hole.tee.z);
		ball = physics.add(new Body(Sphere(BALL), start, 0.045));
		ball.rotates = false;
		ball.restitution = 1;
		// (Coulomb friction is sqrt(ball's * green's): about 0.055 on the green, a slow slide that stands for rolling)
		ball.friction = 0.003;
		spot = start;
		previous = start;
	}

	// a piece's bodies; the lowest height it reaches
	function add(piece:Piece):Float {
		switch piece {
			case Flat(x, z, w, d, y):
				green(physics.add(new Body(Box(new Vec3(w / 2, SLAB / 2, d / 2)), new Vec3(x, y - SLAB / 2, z), 0)));
				return y;
			case RampZ(x, z0, z1, w, y0, y1):
				ramp(new Vec3(x, y0, z0), new Vec3(x, y1, z1), w, false);
				return Math.min(y0, y1);
			case RampX(z, x0, x1, d, y0, y1):
				ramp(new Vec3(x0, y0, z), new Vec3(x1, y1, z), d, true);
				return Math.min(y0, y1);
			case Wall(x0, z0, x1, z1, y):
				var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
				var b = physics.add(new Body(Box(new Vec3((hx - lx) / 2, RAIL_HEIGHT / 2, (hz - lz) / 2)), new Vec3((lx + hx) / 2, y + RAIL_HEIGHT / 2, (lz + hz) / 2), 0));
				b.restitution = 0.72;
				b.friction = 0.3;
				return y;
			case Block(x0, z0, x1, z1, y0, y1):
				var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
				var b = physics.add(new Body(Box(new Vec3((hx - lx) / 2, (y1 - y0) / 2, (hz - lz) / 2)), new Vec3((lx + hx) / 2, (y0 + y1) / 2, (lz + hz) / 2), 0));
				b.restitution = 0.65;
				b.friction = 0.3;
				return y0;
			case Post(x, z, r, y):
				var b = physics.add(new Body(Capsule(r, RAIL_HEIGHT), new Vec3(x, y, z), 0));
				b.restitution = 1;
				b.friction = 0.1;
				return y;
			case Mover(x, z, w, d, y, dx, dz, period, phase):
				var base = new Vec3(x, y + RAIL_HEIGHT * 0.75, z);
				var b = physics.add(new Body(Box(new Vec3(w / 2, RAIL_HEIGHT * 0.75, d / 2)), base, 0));
				b.restitution = 0.6;
				b.friction = 0.4;
				movers.push(b);
				moverBase.push(base);
				moverOffset.push(new Vec3(dx, 0, dz));
				moverPeriod.push(period);
				moverPhase.push(phase);
				return y;
		}
	}

	static function green(b:Body) {
		b.restitution = 0.25;
		b.friction = 1;
	}

	// a slab from a to b (the top's centre line's ends), its width across;
	// turned about the axis across it without trigonometry (half-angle formulas)
	function ramp(a:Vec3, b:Vec3, width:Float, alongX:Bool) {
		var run = alongX ? b.x - a.x : b.z - a.z, rise = b.y - a.y;
		var len = Math.sqrt(run * run + rise * rise);
		var c = Math.abs(run) / len, s = rise / len;
		// (the turn that lifts the +run end by rise: about z for x, about -x for z)
		var sh = Math.sqrt((1 - c) / 2) * (s * (run > 0 ? 1 : -1) >= 0 ? 1 : -1), ch = Math.sqrt((1 + c) / 2);
		var q = alongX ? new Quat(0, 0, sh, ch) : new Quat(-sh, 0, 0, ch);
		var mid = new Vec3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2);
		var up = q.rotate(new Vec3(0, 1, 0));
		var half = alongX ? new Vec3(len / 2, SLAB / 2, width / 2) : new Vec3(width / 2, SLAB / 2, len / 2);
		var body = physics.add(new Body(Box(half), mid - up * (SLAB / 2), 0));
		body.orientation = q;
		green(body);
	}

	// a shot: toward (dx, dz) (any length but zero) at speed (m/s, clamped)
	public function shoot(dx:Float, dz:Float, speed:Float) {
		if (!resting || sunk) return;
		var l = Math.sqrt(dx * dx + dz * dz);
		if (l < 1e-9) return;
		var v = Math.max(MIN_SPEED, Math.min(MAX_SPEED, speed));
		spot = ball.position;
		ball.velocity = new Vec3(dx / l * v, 0, dz / l * v);
		ball.wake();
		strokes++;
		resting = false;
		still = 0;
	}

	// the movers' place at time t: a ping-pong eased by smoothstep (no trigonometry)
	function moveBlocks(t:Float) {
		for (i in 0...movers.length) {
			var period = moverPeriod[i], u = t / period + moverPhase[i];
			u -= Math.ffloor(u);
			var p = u < 0.5 ? 2 * u : 2 - 2 * u, dp = (u < 0.5 ? 2 : -2) / period;
			var e = p * p * (3 - 2 * p), de = 6 * p * (1 - p) * dp;
			var b = movers[i], o = moverOffset[i];
			b.position = moverBase[i] + o * e;
			b.velocity = o * de;
		}
	}

	public function step() {
		previous = ball.position;
		steps++;
		moveBlocks(steps * DT);
		if (sunk) return;
		var before = ball.velocity;
		physics.step(DT);
		var v = ball.velocity, p = ball.position;
		// (the hit: how much the velocity changed beyond gravity)
		var g = physics.gravity * DT;
		var dv = v - before - g;
		var hit = Math.sqrt(dot(dv, dv));
		if (hit > impact) {
			impact = hit;
			impactNormal = dv / Math.max(1e-9, hit);
		}
		// (the ground under it, and how fast it moves)
		var down = physics.ray(p, new Vec3(0, -1, 0), BALL + 0.04, ball);
		var ground = physics.hit;
		grounded = ground != null && down < BALL + 0.03;
		var base = ground != null && grounded ? ground.velocity : new Vec3(0, 0, 0);
		if (grounded) {
			// (the grass's drag, on the speed relative to what it is on)
			var rel = v - base;
			v = base + new Vec3(rel.x * (1 - DRAG * DT), rel.y, rel.z * (1 - DRAG * DT));
			// (the cup's lip: a gentle funnel toward it within twice its radius)
			var cx = cup.x - p.x, cz = cup.z - p.z, d2 = cx * cx + cz * cz;
			if (d2 < 4 * CUP * CUP && Math.abs(p.y - BALL - cup.y) < 0.05) {
				var d = Math.sqrt(d2), speed = Math.sqrt(rel.x * rel.x + rel.z * rel.z);
				if (d < CUP && speed < CAPTURE) {
					sunk = true;
					holed = true;
					resting = false;
					ball.velocity = new Vec3(0, 0, 0);
					return;
				}
				if (d > 1e-6) {
					var pull = 1.6 * DT / d;
					v = v + new Vec3(cx * pull, 0, cz * pull);
				}
			}
			ball.velocity = v;
		}
		// (at rest: slow on the ground for a moment, then stopped dead)
		var rel = v - base;
		var flat = rel.x * rel.x + rel.z * rel.z;
		if (grounded && flat < STOP * STOP && rel.y * rel.y < STOP * STOP) {
			if (++still >= 12 && !resting) {
				ball.velocity = base;
				resting = true;
			}
		} else if (!grounded || flat > 4 * STOP * STOP) {
			still = 0;
			resting = false;
		}
		if (p.y < floor) {
			// (off the island: back where it was hit from, a stroke more)
			ball.position = spot;
			previous = spot;
			ball.velocity = new Vec3(0, 0, 0);
			strokes++;
			fell = true;
			resting = true;
			still = 0;
		}
	}

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;
}
