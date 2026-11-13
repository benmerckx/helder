import helder.gfx.shader.Vec3;
import helder.physics.Body;

// The aim's preview: a ghost of the hole's simulation set to the live
// one's state (Sim.mirror: the same step, so the turnstiles, lifts and
// gates are where they will be) and played forward with the shot being
// aimed, its path kept a point a step. Shown clearly up to its first bounce
// (or CLEAR metres, whichever comes first), then fading over FADE: a guide,
// not the answer. It ends at a blocker (a bumper, a gate, a turnstile, a
// sliding block or a lift's side: where the ball meets it), a portal, the
// edge or the water, the cup, or where the ball rests.
//
// Cheap: at most STEPS steps, and fewer as the path is long enough; the
// buffers made once, nothing allocated per prediction (GolfReplay checks);
// worked again only when the aim changes, or on a hole with moving pieces,
// when the live simulation has stepped.
class Aim {
	// the clear part's longest, the fade's length (m)
	public static inline var CLEAR = 3.6;
	public static inline var FADE = 1.4;
	// the most steps a prediction runs (3 s)
	public static inline var STEPS = 360;

	// why the path ends
	public static inline var END_REST = 0;
	public static inline var END_LENGTH = 1;
	public static inline var END_BLOCKER = 2;
	public static inline var END_PORTAL = 3;
	public static inline var END_OFF = 4;
	public static inline var END_CUP = 5;
	public static inline var END_STEPS = 6;

	public var ghost(default, null):Sim;
	// the path: a point a step from the ball (x, y, z: the ball's centre), its length to each
	public final xs:Array<Float>;
	public final ys:Array<Float>;
	public final zs:Array<Float>;
	public final arc:Array<Float>;
	public var count(default, null) = 0;
	// where (along the path) the first bounce is (-1: none), where the fade starts and the path ends
	public var bounce(default, null) = -1.0;
	public var fadeFrom(default, null) = 0.0;
	public var length(default, null) = 0.0;
	public var ending(default, null) = END_REST;
	// the steps the last prediction ran, the predictions made (for the cost)
	public var ran(default, null) = 0;
	public var made(default, null) = 0;
	// (what the last prediction was of)
	var lastDx = 0.0;
	var lastDz = 0.0;
	var lastSpeed = -1.0;
	var lastStep = -1;
	var moving = false;

	public function new(live:Sim) {
		xs = [for (_ in 0...STEPS + 1) 0.0];
		ys = [for (_ in 0...STEPS + 1) 0.0];
		zs = [for (_ in 0...STEPS + 1) 0.0];
		arc = [for (_ in 0...STEPS + 1) 0.0];
		ghost = new Sim(live.hole);
		reset(live);
	}

	// a new hole: a ghost of it
	public function reset(live:Sim) {
		if (ghost.hole != live.hole) ghost = new Sim(live.hole);
		moving = ghost.movers.length > 0 || ghost.spinners.length > 0;
		lastSpeed = -1;
		count = 0;
	}

	// the preview for a shot toward (dx, dz) at speed, worked again only if
	// the shot changed (or, on a hole with moving pieces, the step); whether it was
	public function update(live:Sim, dx:Float, dz:Float, speed:Float):Bool {
		if (dx == lastDx && dz == lastDz && speed == lastSpeed && (!moving || live.steps == lastStep)) return false;
		lastDx = dx;
		lastDz = dz;
		lastSpeed = speed;
		lastStep = live.steps;
		predict(live, dx, dz, speed);
		return true;
	}

	// the path of a shot from the live simulation's state; limit false: on
	// past blockers and portals to where the ball rests, falls or drops (the tests: where the live one does)
	public function predict(live:Sim, dx:Float, dz:Float, speed:Float, limit = true, steps = STEPS) {
		var g = ghost;
		g.mirror(live);
		made++;
		var p = g.ball.position;
		count = 0;
		push(p, 0);
		bounce = -1;
		fadeFrom = CLEAR;
		length = CLEAR + FADE;
		ending = END_STEPS;
		ran = 0;
		g.shoot(dx, dz, speed);
		var cap = limit ? STEPS : steps;
		var along = 0.0;
		while (ran < cap) {
			ran++;
			g.clearEvents();
			g.step();
			// (out of the hole's way: back at the spot, or through a portal; the path ends before)
			if (g.fell || g.splashed) {
				ending = END_OFF;
				break;
			}
			if (g.warped >= 0 && limit) {
				ending = END_PORTAL;
				break;
			}
			var q = g.ball.position;
			var lx = xs[count - 1], ly = ys[count - 1], lz = zs[count - 1];
			var ddx = q.x - lx, ddy = q.y - ly, ddz = q.z - lz;
			along += Math.sqrt(ddx * ddx + ddy * ddy + ddz * ddz);
			if (count <= STEPS) push(q, along);
			if (g.sunk) {
				ending = END_CUP;
				break;
			}
			// (a bumper's kick: a blocker)
			if (g.kicked >= 0 && limit) {
				ending = END_BLOCKER;
				break;
			}
			// (a hit from the side: a rail or a one-way line bends the path, a moving piece or a gate ends it)
			var n = g.impactNormal;
			if (g.impact > 0.25 && n.y < 0.6 && n.y > -0.6) {
				if (blocker(g, q, n) && limit) {
					ending = END_BLOCKER;
					break;
				}
				if (bounce < 0) {
					bounce = along;
					if (limit && bounce < fadeFrom) {
						fadeFrom = bounce;
						length = bounce + FADE;
					}
				}
			}
			if (g.resting) {
				ending = END_REST;
				break;
			}
			if (limit && along >= length) {
				ending = END_LENGTH;
				break;
			}
		}
		if (!limit || along < length) length = along;
		if (fadeFrom > length) fadeFrom = length;
	}

	inline function push(p:Vec3, along:Float) {
		xs[count] = p.x;
		ys[count] = p.y;
		zs[count] = p.z;
		arc[count] = along;
		count++;
	}

	// whether what the ball hit (toward -n from it) is a moving piece or a gate
	static function blocker(g:Sim, q:Vec3, n:Vec3):Bool {
		g.physics.ray(q, new Vec3(-n.x, 0, -n.z), Sim.BALL + 0.08, g.ball);
		var b:Null<Body> = g.physics.hit;
		if (b == null) return false;
		for (s in g.spinners)
			if (s == b) return true;
		for (s in g.gates)
			if (s == b) return true;
		for (s in g.movers)
			if (s == b) return true;
		return false;
	}

	// the point at length s along the path (into px, py, pz)
	public var px(default, null) = 0.0;
	public var py(default, null) = 0.0;
	public var pz(default, null) = 0.0;

	var cursor = 1;

	// (s non-decreasing between calls walks on from the last; less: from the start)
	public function at(s:Float) {
		if (count == 0) return;
		if (cursor < 1 || cursor >= count || arc[cursor - 1] > s) cursor = 1;
		while (cursor < count - 1 && arc[cursor] < s)
			cursor++;
		if (count == 1) {
			px = xs[0];
			py = ys[0];
			pz = zs[0];
			return;
		}
		var a = arc[cursor - 1], b = arc[cursor];
		var t = b > a ? (s - a) / (b - a) : 1.0;
		if (t < 0) t = 0;
		if (t > 1) t = 1;
		px = xs[cursor - 1] + (xs[cursor] - xs[cursor - 1]) * t;
		py = ys[cursor - 1] + (ys[cursor] - ys[cursor - 1]) * t;
		pz = zs[cursor - 1] + (zs[cursor] - zs[cursor - 1]) * t;
	}
}
