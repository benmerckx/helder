import Course.Hole;
import Course.Piece;
import helder.gfx.shader.Vec3;
import helder.physics.*;
import helder.scene.math.Quat;

// One hole's simulation on helder.physics, stepped at a fixed rate (DT):
// the ball a sphere that slides on the green with a little friction (a
// roll's resistance: it does not turn, the view rolls it), a drag
// proportional to its speed, bounces off rails and posts, carried and
// pushed by moving blocks, lifts and turnstiles (static bodies moved each
// step, their velocities set so contacts see them), pulled gently toward
// the cup when near it and captured below a speed; off the island or in
// the water it is put back where it was hit from, a stroke added.
//
// The pieces with rules of their own are worked here after the physics'
// step: bumpers kick, boosters and wind push, sand and ice change the
// going, portals move the ball, switches swap their gates (which slide
// into the green and out), one-way gates bounce a ball coming the wrong
// way, cracked tiles fall once the ball has rolled off them.
//
// Deterministic: no sin, cos or exp in a step (only arithmetic and square
// roots, the same bits on every target), so a recorded round replays
// (tests: GolfReplay). A step allocates nothing.
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
	// a bumper's kick (m/s, outward), a portal's and a switch's reach, a gate's height and its travel time
	public static inline var KICK = 3.2;
	public static inline var PORTAL = 0.2;
	public static inline var PLATE = 0.2;
	public static inline var GATE_HEIGHT = 0.26;
	public static inline var GATE_TIME = 0.35;
	// a lift's slab, a turnstile's bar's thickness
	public static inline var LIFT_SLAB = 0.2;
	public static inline var BAR = 0.1;
	// speed lost a second in proportion to speed (the grass), and the speed under which the ball stops
	static inline var DRAG = 0.45;
	static inline var STOP = 0.1;

	public final physics = new PhysicsWorld();
	public final hole:Hole;
	public final ball:Body;
	// moving blocks and lifts: the body and its path (base, offset, period, phase)
	public final movers:Array<Body> = [];
	final moverBase:Array<Vec3> = [];
	final moverOffset:Array<Vec3> = [];
	final moverPeriod:Array<Float> = [];
	final moverPhase:Array<Float> = [];
	// (lifts wait at the top and the bottom: a quarter of their period each)
	final moverDwell:Array<Bool> = [];
	// turnstiles: the body, its speed and start angle
	public final spinners:Array<Body> = [];
	public final spinnerSpeed:Array<Float> = [];
	public final spinnerStart:Array<Float> = [];
	// bumpers: x, z, radius, y (4 a bumper), the steps since each last kicked
	final bumpers:Array<Float> = [];
	public final bumperKick:Array<Int> = [];
	// areas: x0, z0, x1, z1, y, kind, ax, az (8 each)
	final areas:Array<Float> = [];
	// portals: x, y, z, tx, ty, tz, dx, dz (8 each)
	final portals:Array<Float> = [];
	// switches: x, y, z, group (4 each), whether the ball is on each
	final plates:Array<Float> = [];
	final onPlate:Array<Bool> = [];
	// gates: their bodies, groups, open (true) or not, how far down (0 up, 1 sunk), their bodies' centres when up
	public final gates:Array<Body> = [];
	public final gateGroup:Array<Int> = [];
	public final gateOpen:Array<Bool> = [];
	public final gateDown:Array<Float> = [];
	final gateBase:Array<Vec3> = [];
	// one-way lines: x0, z0, x1, z1, y, nx, nz (7 each)
	final oneWays:Array<Float> = [];
	// cracked tiles: the body, its place, 0 whole, 1 touched, 2 fallen; the time since the ball left it
	public final tiles:Array<Body> = [];
	final tileBase:Array<Vec3> = [];
	public final tileState:Array<Int> = [];
	public final tileTime:Array<Float> = [];

	// the cup's centre (on the green's top)
	public final cup:Vec3;
	// below this the ball has fallen off
	public final floor:Float;

	public var strokes(default, null) = 0;
	public var steps(default, null) = 0;
	// at rest (a shot may be played), in the cup
	public var resting(default, null) = true;
	public var sunk(default, null) = false;
	// where the ball goes back to after a fall: the last shot's spot when it was played from fixed ground, else the last such
	public var spot(default, null):Vec3;
	var safe:Vec3;
	var onFixed = true;
	// the ball's position before the last step (the view draws between it and now)
	public var previous(default, null):Vec3;

	// this step's events, for the view (cleared by the view when read):
	// the hardest hit's speed change and its direction, a fall, a splash
	// (where), a sinking, a kick (the bumper's index), a portal (its index),
	// a switch thrown (its index), a tile cracked
	public var impact = 0.0;
	public var impactNormal = new Vec3(0, 1, 0);
	public var fell = false;
	public var splashed = false;
	public var splashAt = new Vec3(0, 0, 0);
	public var holed = false;
	public var kicked = -1;
	public var warped = -1;
	public var thrown = -1;
	public var cracked = -1;
	// whether the ball touched the ground in the last step, and the kind of area it is in (0 none, else the AREA_ constants)
	public var grounded(default, null) = false;
	public var area(default, null) = 0;
	var still = 0;
	// (the portal just come out of: not entered again until the ball has left its exit)
	var exitX = 0.0;
	var exitZ = 0.0;
	var exiting = false;

	public static inline var AREA_BOOST = 1;
	public static inline var AREA_WIND = 2;
	public static inline var AREA_SAND = 3;
	public static inline var AREA_ICE = 4;
	public static inline var AREA_WATER = 5;

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
		safe = start;
		previous = start;
		place(0);
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
			case Bumper(x, z, r, y):
				var b = physics.add(new Body(Capsule(r, RAIL_HEIGHT), new Vec3(x, y, z), 0));
				b.restitution = 1;
				b.friction = 0.05;
				for (v in [x, z, r, y])
					bumpers.push(v);
				bumperKick.push(1000);
				return y;
			case Mover(x, z, w, d, y, dx, dz, period, phase):
				mover(new Vec3(x, y + RAIL_HEIGHT * 0.75, z), new Vec3(w / 2, RAIL_HEIGHT * 0.75, d / 2), new Vec3(dx, 0, dz), period, phase, 0.6);
				moverDwell.push(false);
				return y;
			case Lift(x, z, w, d, y0, y1, period, phase):
				var b = mover(new Vec3(x, y0 - LIFT_SLAB / 2, z), new Vec3(w / 2, LIFT_SLAB / 2, d / 2), new Vec3(0, y1 - y0, 0), period, phase, 0.25);
				b.friction = 1;
				moverDwell.push(true);
				return Math.min(y0, y1);
			case Spinner(x, z, len, y, speed, start):
				var b = physics.add(new Body(Box(new Vec3(len / 2, RAIL_HEIGHT / 2, BAR / 2)), new Vec3(x, y + RAIL_HEIGHT / 2 + 0.01, z), 0));
				b.restitution = 0.7;
				b.friction = 0.2;
				spinners.push(b);
				spinnerSpeed.push(speed);
				spinnerStart.push(start);
				return y;
			case Boost(x, z, w, d, y, ax, az):
				addArea(x, z, w, d, y, AREA_BOOST, ax, az);
				return y;
			case Wind(x, z, w, d, y, ax, az):
				addArea(x, z, w, d, y, AREA_WIND, ax, az);
				return y;
			case Sand(x, z, w, d, y):
				addArea(x, z, w, d, y, AREA_SAND, 0, 0);
				return y;
			case Ice(x, z, w, d, y):
				addArea(x, z, w, d, y, AREA_ICE, 0, 0);
				return y;
			case Water(x, z, w, d, y):
				addArea(x, z, w, d, y, AREA_WATER, 0, 0);
				return y;
			case Portal(x, z, y, tx, tz, ty, dx, dz):
				var l = Math.sqrt(dx * dx + dz * dz);
				for (v in [x, y, z, tx, ty, tz, dx / l, dz / l])
					portals.push(v);
				return Math.min(y, ty);
			case Switch(x, z, y, group):
				for (v in [x, y, z, group])
					plates.push(v);
				onPlate.push(false);
				return y;
			case Gate(x0, z0, x1, z1, y, group, open):
				var lx = Math.min(x0, x1), hx = Math.max(x0, x1), lz = Math.min(z0, z1), hz = Math.max(z0, z1);
				// (at least a rail thick)
				if (hx - lx < Course.RAIL) {
					var m = (lx + hx) / 2;
					lx = m - Course.RAIL / 2;
					hx = m + Course.RAIL / 2;
				}
				if (hz - lz < Course.RAIL) {
					var m = (lz + hz) / 2;
					lz = m - Course.RAIL / 2;
					hz = m + Course.RAIL / 2;
				}
				var base = new Vec3((lx + hx) / 2, y + GATE_HEIGHT / 2, (lz + hz) / 2);
				var b = physics.add(new Body(Box(new Vec3((hx - lx) / 2, GATE_HEIGHT / 2, (hz - lz) / 2)), base, 0));
				b.restitution = 0.6;
				b.friction = 0.3;
				gates.push(b);
				gateBase.push(base);
				gateGroup.push(group);
				gateOpen.push(open);
				gateDown.push(open ? 1 : 0);
				return y;
			case OneWay(x0, z0, x1, z1, y, dx, dz):
				var l = Math.sqrt(dx * dx + dz * dz);
				for (v in [x0, z0, x1, z1, y, dx / l, dz / l])
					oneWays.push(v);
				return y;
			case Crumble(x, z, w, d, y):
				var at = new Vec3(x, y - SLAB / 2, z);
				var b = physics.add(new Body(Box(new Vec3(w / 2, SLAB / 2, d / 2)), at, 0));
				green(b);
				tiles.push(b);
				tileBase.push(at);
				tileState.push(0);
				tileTime.push(0);
				return y;
		}
	}

	function mover(base:Vec3, half:Vec3, offset:Vec3, period:Float, phase:Float, restitution:Float):Body {
		var b = physics.add(new Body(Box(half), base, 0));
		b.restitution = restitution;
		b.friction = 0.4;
		movers.push(b);
		moverBase.push(base);
		moverOffset.push(offset);
		moverPeriod.push(period);
		moverPhase.push(phase);
		return b;
	}

	function addArea(x:Float, z:Float, w:Float, d:Float, y:Float, kind:Int, ax:Float, az:Float)
		for (v in [x - w / 2, z - d / 2, x + w / 2, z + d / 2, y, kind, ax, az])
			areas.push(v);

	// the areas: their count, and each one's rectangle, height, kind and push
	public var areaCount(get, never):Int;

	inline function get_areaCount()
		return Std.int(areas.length / 8);

	public inline function areaAt(i:Int, k:Int):Float
		return areas[i * 8 + k];

	public var portalCount(get, never):Int;

	inline function get_portalCount()
		return Std.int(portals.length / 8);

	public inline function portalAt(i:Int, k:Int):Float
		return portals[i * 8 + k];

	public var plateCount(get, never):Int;

	inline function get_plateCount()
		return Std.int(plates.length / 4);

	public inline function plateAt(i:Int, k:Int):Float
		return plates[i * 4 + k];

	public var oneWayCount(get, never):Int;

	inline function get_oneWayCount()
		return Std.int(oneWays.length / 7);

	public inline function oneWayAt(i:Int, k:Int):Float
		return oneWays[i * 7 + k];

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

	// the turn by angle a about y, without trigonometry: the half angle's
	// sine and cosine from their series at a sixteenth of it, then doubled
	// four times (the same bits on every target; the view uses it too)
	public static function yaw(a:Float):Quat {
		// (into -pi..pi)
		var t = a / (2 * Math.PI);
		t -= Math.ffloor(t + 0.5);
		var h = t * Math.PI / 16, h2 = h * h;
		var s = h * (1 - h2 / 6 * (1 - h2 / 20 * (1 - h2 / 42 * (1 - h2 / 72))));
		var c = 1 - h2 / 2 * (1 - h2 / 12 * (1 - h2 / 30 * (1 - h2 / 56)));
		for (_ in 0...4) {
			var s2 = 2 * s * c, c2 = c * c - s * s;
			s = s2;
			c = c2;
		}
		return new Quat(0, s, 0, c);
	}

	// a shot: toward (dx, dz) (any length but zero) at speed (m/s, clamped)
	public function shoot(dx:Float, dz:Float, speed:Float) {
		if (!resting || sunk) return;
		var l = Math.sqrt(dx * dx + dz * dz);
		if (l < 1e-9) return;
		var v = Math.max(MIN_SPEED, Math.min(MAX_SPEED, speed));
		spot = onFixed ? ball.position : safe;
		ball.velocity = ball.velocity + new Vec3(dx / l * v, 0, dz / l * v);
		ball.wake();
		strokes++;
		resting = false;
		still = 0;
	}

	// the moving pieces' places at step n: the movers' ping-pong eased by
	// smoothstep, the turnstiles' angles, the gates sliding (no trigonometry)
	function place(n:Int) {
		var t = n * DT;
		for (i in 0...movers.length) {
			var period = moverPeriod[i], u = t / period + moverPhase[i];
			u -= Math.ffloor(u);
			var p = u < 0.5 ? 2 * u : 2 - 2 * u, dp = (u < 0.5 ? 2 : -2) / period;
			if (moverDwell[i]) {
				p = (p - 0.25) * 2;
				dp *= 2;
				if (p <= 0 || p >= 1) {
					p = p <= 0 ? 0 : 1;
					dp = 0;
				}
			}
			var e = p * p * (3 - 2 * p), de = 6 * p * (1 - p) * dp;
			var b = movers[i], o = moverOffset[i];
			b.position = moverBase[i] + o * e;
			b.velocity = o * de;
		}
		for (i in 0...spinners.length) {
			var b = spinners[i], w = spinnerSpeed[i];
			b.orientation = yaw(spinnerStart[i] + w * t);
			b.angular = new Vec3(0, w, 0);
		}
		for (i in 0...gates.length) {
			var want = gateOpen[i] ? 1.0 : 0.0, d = gateDown[i];
			var step = DT / GATE_TIME;
			var next = d < want ? Math.min(want, d + step) : Math.max(want, d - step);
			gateDown[i] = next;
			var b = gates[i];
			// (sunk: its top 3 cm under the green; moving: its velocity for the contacts)
			var depth = GATE_HEIGHT + 0.03;
			b.position = gateBase[i] - new Vec3(0, depth * next, 0);
			b.velocity = new Vec3(0, -(next - d) * depth / DT, 0);
		}
	}

	public function step() {
		previous = ball.position;
		steps++;
		place(steps);
		for (i in 0...bumperKick.length)
			bumperKick[i]++;
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
		var fixed = grounded && ground != null && movers.indexOf(ground) < 0 && tiles.indexOf(ground) < 0;
		v = rules(v, p, ground);
		area = 0;
		var drag = DRAG, extra = 0.0;
		for (i in 0...areaCount) {
			var o = i * 8;
			if (p.x < areas[o] || p.x > areas[o + 2] || p.z < areas[o + 1] || p.z > areas[o + 3]) continue;
			var y = areas[o + 4], kind = Std.int(areas[o + 5]);
			var foot = p.y - BALL;
			if (kind == AREA_WIND) {
				if (foot > y - 0.5 && foot < y + 1.5) {
					v = v + new Vec3(areas[o + 6] * DT, 0, areas[o + 7] * DT);
					area = kind;
				}
				continue;
			}
			if (kind == AREA_WATER) {
				// (sunk to half its depth under the surface: in)
				if (p.y < y + BALL * 0.3) {
					splashAt = new Vec3(p.x, y, p.z);
					splashed = true;
					putBack();
					return;
				}
				continue;
			}
			if (!grounded || Math.abs(foot - y) > 0.06) continue;
			area = kind;
			switch kind {
				case AREA_BOOST:
					v = v + new Vec3(areas[o + 6] * DT, 0, areas[o + 7] * DT);
				case AREA_SAND:
					drag = 1.8;
					extra = 1.0;
				case AREA_ICE:
					drag = 0.05;
					// (the green's friction given back, mostly: ice hardly slows the ball)
					extra = -0.45;
				case _:
			}
		}
		if (grounded) {
			// (the grass's drag, on the speed relative to what it is on)
			var rel = v - base;
			var flat = Math.sqrt(rel.x * rel.x + rel.z * rel.z);
			var k = 1 - drag * DT;
			// (sand's grip, ice's slip: a constant change of speed against the motion, not past a stop)
			if (extra != 0 && flat > 1e-6) {
				var dvs = extra > 0 ? Math.min(flat, extra * DT) : (flat > 0.25 ? extra * DT : 0);
				k -= dvs / flat;
			}
			v = base + new Vec3(rel.x * k, rel.y, rel.z * k);
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
		}
		ball.velocity = v;
		// (at rest: slow on the ground for a moment, then stopped dead)
		var rel = v - base;
		var flat = rel.x * rel.x + rel.z * rel.z;
		if (grounded && flat < STOP * STOP && rel.y * rel.y < STOP * STOP && area != AREA_BOOST) {
			if (++still >= 12 && !resting) {
				ball.velocity = base;
				resting = true;
				onFixed = fixed;
				if (fixed) safe = ball.position;
			}
		} else if (!grounded || flat > 4 * STOP * STOP) {
			still = 0;
			resting = false;
		}
		if (p.y < floor) {
			fell = true;
			putBack();
		}
	}

	// off the island or in the water: back where it was hit from, a stroke more, the tiles whole again
	function putBack() {
		ball.position = spot;
		previous = spot;
		ball.velocity = new Vec3(0, 0, 0);
		strokes++;
		resting = true;
		onFixed = true;
		still = 0;
		exiting = false;
		for (i in 0...tiles.length) {
			tiles[i].position = tileBase[i];
			tileState[i] = 0;
			tileTime[i] = 0;
		}
	}

	// the pieces' own rules on the ball's new velocity v at p (on ground, or null)
	function rules(v:Vec3, p:Vec3, ground:Null<Body>):Vec3 {
		// (bumpers: off one, at least the kick outward)
		for (i in 0...bumperKick.length) {
			var o = i * 4;
			var dx = p.x - bumpers[o], dz = p.z - bumpers[o + 1], r = bumpers[o + 2] + BALL + 0.02;
			var d2 = dx * dx + dz * dz;
			if (d2 > r * r || d2 < 1e-12 || p.y - BALL > bumpers[o + 3] + RAIL_HEIGHT + 0.1 || bumperKick[i] < 12) continue;
			var d = Math.sqrt(d2), nx = dx / d, nz = dz / d;
			var vn = v.x * nx + v.z * nz;
			if (vn < KICK) {
				v = v + new Vec3(nx * (KICK - vn), 0, nz * (KICK - vn));
				bumperKick[i] = 0;
				kicked = i;
			}
		}
		// (portals: onto one, out of its exit, the speed kept along the exit's heading)
		if (exiting) {
			var dx = p.x - exitX, dz = p.z - exitZ;
			if (dx * dx + dz * dz > (PORTAL + BALL) * (PORTAL + BALL)) exiting = false;
		}
		if (!exiting)
			for (i in 0...portalCount) {
				var o = i * 8;
				var dx = p.x - portals[o], dz = p.z - portals[o + 2];
				if (dx * dx + dz * dz > PORTAL * PORTAL * 0.8 || Math.abs(p.y - BALL - portals[o + 1]) > 0.12) continue;
				var speed = Math.max(1.2, Math.sqrt(v.x * v.x + v.z * v.z));
				var at = new Vec3(portals[o + 3], portals[o + 4] + BALL, portals[o + 5]);
				ball.position = at;
				previous = at;
				exitX = at.x;
				exitZ = at.z;
				exiting = true;
				warped = i;
				return new Vec3(portals[o + 6] * speed, 0, portals[o + 7] * speed);
			}
		// (switches: rolled onto, their group's gates swapped)
		for (i in 0...onPlate.length) {
			var o = i * 4;
			var dx = p.x - plates[o + 0], dz = p.z - plates[o + 2];
			var on = dx * dx + dz * dz < PLATE * PLATE && Math.abs(p.y - BALL - plates[o + 1]) < 0.12;
			if (on && !onPlate[i]) {
				var group = Std.int(plates[o + 3]);
				for (k in 0...gates.length)
					if (gateGroup[k] == group) gateOpen[k] = !gateOpen[k];
				thrown = i;
			}
			onPlate[i] = on;
		}
		// (one-way lines: a ball coming against the way bounced back off the line)
		for (i in 0...oneWayCount) {
			var o = i * 7;
			var ax = oneWays[o], az = oneWays[o + 1], bx = oneWays[o + 2], bz = oneWays[o + 3];
			var nx = oneWays[o + 5], nz = oneWays[o + 6];
			if (Math.abs(p.y - BALL - oneWays[o + 4]) > 0.25) continue;
			var lx = bx - ax, lz = bz - az, len = Math.sqrt(lx * lx + lz * lz);
			var t = ((p.x - ax) * lx + (p.z - az) * lz) / len;
			if (t < -BALL * 0.5 || t > len + BALL * 0.5) continue;
			var s = (p.x - ax) * nx + (p.z - az) * nz, was = (previous.x - ax) * nx + (previous.z - az) * nz;
			var vn = v.x * nx + v.z * nz;
			if (vn < 0 && s < BALL && was > 0) {
				ball.position = new Vec3(p.x + nx * (BALL - s), p.y, p.z + nz * (BALL - s));
				v = v - new Vec3(nx * vn * 1.6, 0, nz * vn * 1.6);
				if (-vn > impact) {
					impact = -vn;
					impactNormal = new Vec3(nx, 0, nz);
				}
			}
		}
		// (cracked tiles: touched, then left a moment: fallen)
		for (i in 0...tiles.length) {
			switch tileState[i] {
				case 0:
					if (ground == tiles[i]) tileState[i] = 1;
				case 1:
					if (ground == tiles[i]) tileTime[i] = 0 else {
						tileTime[i] += DT;
						if (tileTime[i] > 0.25) {
							tileState[i] = 2;
							tileTime[i] = 0;
							tiles[i].position = new Vec3(0, -1000, 0);
							cracked = i;
						}
					}
				case _:
					tileTime[i] += DT;
			}
		}
		return v;
	}

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;
}
