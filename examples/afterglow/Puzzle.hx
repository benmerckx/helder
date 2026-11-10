import Screens;

// A screen's play, deterministic: stepped at a fixed rate from where the
// moth is, nothing random, nothing from physics. Light wakes what it
// reaches: a glyph charges while lit and, once full, moves its pieces to
// their next state (then it must go dark before it moves them again); a
// piece held by eyes stays open only while they are all lit; a lantern,
// once woken, is a light of its own. The snail crawls towards the moth's
// light, as far as the way it is on goes: along walks joined end to end at
// one height, through no shut gate, over no piece that is moving. A
// piece that carries takes the snail with it. Nothing fails: anything done
// can be done again.
//
// Distances to the moth are measured as seen: everything is brought along
// the line of sight to the plane the moth flies in (flat).
class Puzzle {
	public static inline var STEP = 1 / 60;
	// the plane the moth flies in, in front of all the stone
	public static inline var FLY = -1.25;
	// how far the moth's light wakes a glyph, the snail, a lantern; a lantern's
	public static inline var REACH = 1.0;
	public static inline var LANTERN = 0.9;
	static inline var CHARGE = 0.6;
	static inline var CRAWL = 0.8;

	public final screen:Screen;
	public final pieces:Array<Part>;
	public final glyphs:Array<Sign>;
	public final snail:Snail;
	public var solved(default, null) = false;
	// what has happened, for the sounds and the flashes: "glyph a", "piece left", "home"
	public final events:Array<String> = [];

	// where the eye is (seen from there)
	public var eye:Vec;

	public function new(screen:Screen, eye:Vec) {
		this.screen = screen;
		this.eye = eye;
		pieces = [for (p in screen.pieces) new Part(p)];
		for (p in pieces)
			if (p.def.hang != null) p.parent = part(p.def.hang.piece);
		glyphs = [for (g in screen.glyphs) new Sign(g)];
		var s = screen.snail;
		snail = new Snail(s[0], s[1], s[2], screen.asleep == true);
	}

	public function part(name:String):Part {
		for (p in pieces)
			if (p.def.name == name) return p;
		throw 'No piece $name';
	}

	public function glyph(name:String):Sign {
		for (g in glyphs)
			if (g.def.name == name) return g;
		throw 'No glyph $name';
	}

	// a point as seen, on the moth's plane
	public function flat(x:Float, y:Float, z:Float):Vec {
		var s = (eye.z - FLY) / (eye.z - z);
		return {x: eye.x + (x - eye.x) * s, y: eye.y + (y - eye.y) * s, z: FLY};
	}

	// a point on the moth's plane, seen on the plane at z
	public function deep(x:Float, y:Float, z:Float):Vec {
		var s = (eye.z - z) / (eye.z - FLY);
		return {x: eye.x + (x - eye.x) * s, y: eye.y + (y - eye.y) * s, z: z};
	}

	// one step; moth: where it is (the world's)
	public function step(moth:Vec) {
		var m = flat(moth.x, moth.y, moth.z);
		for (p in pieces)
			if (p.lantern != null && !p.awake) {
				var l = lanternAt(p);
				if (near(l, m, REACH)) {
					p.awake = true;
					events.push('lantern ${p.def.name}');
				}
			}
		for (g in glyphs) {
			var at = flat(g.def.at[0], g.def.at[1], g.def.at[2]);
			var lit = near(at, m, REACH);
			g.near = Math.max(0, 1 - (dist(at, m) - REACH) / 1.6);
			for (p in pieces)
				if (p.awake && near(at, lanternAt(p), LANTERN)) lit = true;
			g.charge = clamp(g.charge + (lit ? STEP : -STEP) / CHARGE);
			g.lit = lit;
			if (g.charge <= 0) g.armed = true;
			if (g.def.drives == null || !g.armed || g.charge < 1) continue;
			// (it moves its pieces when all can go: none moving, none with
			// the snail on it that would drop it)
			var ready = true;
			for (name in g.def.drives) {
				var p = part(name);
				if (p.moving() || (onto(p) && p.def.carries != true)) ready = false;
			}
			if (!ready) {
				g.charge = 0.9;
				continue;
			}
			g.armed = false;
			events.push('glyph ${g.def.name}');
			for (name in g.def.drives) {
				var p = part(name);
				if (onto(p)) snail.ride = p;
				p.go((p.state + 1) % p.def.states.length);
				events.push('piece ${p.def.name}');
			}
		}
		for (p in pieces)
			if (p.def.holds != null) {
				var open = true;
				for (name in p.def.holds)
					if (glyph(name).charge < 1) open = false;
				// (never shut on the snail)
				var b = p.def.blocks;
				if (!open && b != null && snail.x > b[0] + p.x - 0.3 && snail.x < b[1] + p.x + 0.3 && Math.abs(snail.y - b[2]) < 0.3) open = true;
				var want = open ? 1 : 0;
				if (p.target != want) {
					p.go(want);
					events.push('piece ${p.def.name}');
				}
			}
		// (pieces move; the snail rides the one carrying it)
		var rx = 0.0, ry = 0.0;
		for (p in pieces) {
			var x = p.x, y = p.y;
			p.advance(STEP);
			if (snail.ride == p) {
				rx = p.x - x;
				ry = p.y - y;
			}
		}
		for (p in pieces)
			if (p.parent != null) p.hangFrom(p.parent);
		snail.x += rx;
		snail.y += ry;
		hints();
		if (snail.ride != null && !snail.ride.moving()) snail.ride = null;
		crawl(moth);
	}

	// what the moth's light is about to do: a glyph near it or charging
	// lights its pieces' edges and stirs them towards their next state
	function hints() {
		for (p in pieces) {
			p.hint = 0;
			p.nudge = 0;
			if (p.lantern != null) p.light = p.awake ? Math.min(1, p.light + STEP / 0.6) : 0;
		}
		for (g in glyphs)
			if (g.def.drives != null)
				for (name in g.def.drives) {
					var p = part(name);
					p.hint = Math.max(p.hint, g.near * 0.35 + g.charge * 0.8);
					if (g.armed && !p.moving()) p.nudge = Math.max(p.nudge, g.charge);
				}
		for (p in pieces)
			if (p.def.holds != null) {
				var lit = 0.0, near = 0.0;
				for (name in p.def.holds) {
					var g = glyph(name);
					lit += g.charge / p.def.holds.length;
					near = Math.max(near, g.near);
				}
				p.hint = lit * 0.8 + near * 0.3;
				if (p.target == 0 && !p.moving()) p.nudge = lit * 0.5;
			}
	}

	function crawl(moth:Vec) {
		var s = snail;
		if (s.moving) s.phase += STEP;
		if (s.home > 0) {
			s.home = Math.min(1, s.home + STEP / 1.6);
			s.out = Math.max(0, s.out - STEP / 0.8);
			return;
		}
		var m = flat(moth.x, moth.y, moth.z);
		if (s.asleep) {
			var at = flat(s.x, s.y + 0.2, s.z);
			if (!near(at, m, REACH * 1.2)) return;
			s.asleep = false;
			events.push("snail");
		}
		s.out = Math.min(1, s.out + STEP / 0.9);
		if (s.ride != null || s.out < 1) return;
		// (the way it is on, and the point of it nearest the light)
		var way = reach();
		if (way == null) return;
		var seen = deep(m.x, m.y, s.z);
		s.z += (way.z - s.z) * 0.1;
		var goal = clamp2(seen.x, way.a + 0.12, way.b - 0.12);
		// (led near its door, it goes in)
		var h = screen.home;
		if (Math.abs(s.y - h[1]) < 0.1 && h[0] > way.a && h[0] < way.b && Math.abs(seen.x - h[0]) < 1.0) goal = h[0];
		var d = goal - s.x;
		if (Math.abs(d) > 0.03) {
			s.facing = d > 0 ? 1 : -1;
			s.x += s.facing * Math.min(Math.abs(d), CRAWL * STEP);
			s.moving = true;
		} else s.moving = false;
		if (Math.abs(s.y - h[1]) < 0.1 && Math.abs(s.x - h[0]) < 0.3) {
			s.home = STEP;
			s.moving = false;
			solved = true;
			events.push("home");
		}
	}

	// the way the snail is on: the walks at its height joined end to end,
	// cut where a gate is shut; pieces moving left out
	public function reach():Null<{a:Float, b:Float, z:Float}> {
		var s = snail, spans:Array<Array<Float>> = [], z = s.z;
		for (w in walks(false))
			if (Math.abs(w[2] - s.y) < 0.06) {
				spans.push([w[0], w[1]]);
				if (s.x >= w[0] && s.x <= w[1]) z = w[3];
			}
		spans.sort((a, b) -> a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);
		var joined:Array<Array<Float>> = [];
		for (w in spans) {
			var last = joined[joined.length - 1];
			if (last != null && w[0] <= last[1] + 0.06) last[1] = Math.max(last[1], w[1]);
			else joined.push(w.copy());
		}
		for (p in pieces) {
			var b = p.def.blocks;
			if (b == null) continue;
			// (shut while its foot is below the snail's shell)
			if (b[2] + p.y > s.y + 0.3 || b[3] + p.y < s.y) continue;
			var x0 = b[0] + p.x, x1 = b[1] + p.x;
			joined = [
				for (w in joined)
					for (part in [[w[0], Math.min(w[1], x0)], [Math.max(w[0], x1), w[1]]])
						if (part[1] - part[0] > 0.01) part
			];
		}
		for (w in joined)
			if (s.x >= w[0] - 0.02 && s.x <= w[1] + 0.02) return {a: w[0], b: w[1], z: z};
		return null;
	}

	// the walks where they are now (moving: also those of pieces moving)
	public function walks(moving:Bool):Array<Array<Float>> {
		var out = [for (w in screen.walks) w];
		for (p in pieces) {
			if (p.def.walks == null || (!moving && p.moving())) continue;
			for (w in p.def.walks)
				out.push([w[0] + p.x, w[1] + p.x, w[2] + p.y, w[3]]);
		}
		return out;
	}

	// the highest walk under (x, y) on the moth's plane, within reach below:
	// where the moth lands (the world's point on it), else null
	public function ground(x:Float, y:Float):Null<Vec> {
		var best:Null<Vec> = null;
		for (w in walks(true)) {
			var front = w[3] + 0.6;
			var at = deep(x, y, front);
			if (at.x < w[0] + 0.1 || at.x > w[1] - 0.1) continue;
			if (w[2] > at.y + 0.35 || w[2] < at.y - 3) continue;
			if (best == null || w[2] > best.y) best = {x: at.x, y: w[2], z: front};
		}
		return best;
	}

	// whether the snail is on piece p
	function onto(p:Part):Bool {
		if (p.def.walks == null) return false;
		for (w in p.def.walks)
			if (Math.abs(w[2] + p.y - snail.y) < 0.06 && snail.x > w[0] + p.x - 0.05 && snail.x < w[1] + p.x + 0.05) return true;
		return false;
	}

	public function lanternAt(p:Part):Vec {
		var l = p.def.lantern;
		return l == null ? {x: 0, y: 0, z: 0} : flat(l[0] + p.x, l[1] + p.y, l[2]);
	}

	static function dist(a:Vec, b:Vec):Float
		return Math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

	static inline function near(a:Vec, b:Vec, r:Float):Bool
		return dist(a, b) < r;

	static inline function clamp(x:Float):Float
		return x < 0 ? 0 : x > 1 ? 1 : x;

	static inline function clamp2(x:Float, a:Float, b:Float):Float
		return a > b ? (a + b) / 2 : x < a ? a : x > b ? b : x;
}

typedef Vec = {x:Float, y:Float, z:Float};

// a piece as it plays: its state, and its pose (dx, dy, turn) easing
// from the last state's to the next's
class Part {
	public final def:Piece;
	public var state(default, null):Int;
	public var target(default, null):Int;
	public var x = 0.0;
	public var y = 0.0;
	public var turn = 0.0;
	public var awake = false;
	// a lantern's light (0 to 1); the moth's hint at what it will do, and the stir towards it
	public var light = 0.0;
	public var hint = 0.0;
	public var nudge = 0.0;
	public var parent:Null<Part> = null;
	public final lantern:Null<Array<Float>>;
	var from:Array<Float>;
	var t = 1.0;

	public function new(def:Piece) {
		this.def = def;
		lantern = def.lantern;
		state = target = def.start ?? 0;
		from = def.states[state];
		x = from[0];
		y = from[1];
		turn = from[2];
	}

	public function moving():Bool
		return t < 1;

	// the pose drawn: stirred a little towards the next state
	public function shown():Array<Float> {
		var next = def.states[(state + 1) % def.states.length], k = nudge * 0.07;
		return [x + (next[0] - x) * k, y + (next[1] - y) * k, turn + (next[2] - turn) * k];
	}

	public function go(next:Int) {
		from = [x, y, turn];
		target = next;
		t = 0;
	}

	public function advance(dt:Float) {
		if (t >= 1) return;
		t = Math.min(1, t + dt / (def.time ?? 1.1));
		var to = def.states[target], k = settle(t);
		x = from[0] + (to[0] - from[0]) * k;
		y = from[1] + (to[1] - from[1]) * k;
		turn = from[2] + (to[2] - from[2]) * k;
		if (t >= 1) state = target;
	}

	// upright, at the point it hangs from on its parent as that turns
	public function hangFrom(p:Part) {
		var at = def.hang.at, pv = p.def.pivot ?? [0, 0], pose = p.shown();
		var dx = at[0] - pv[0], dy = at[1] - pv[1], c = Math.cos(pose[2]), s = Math.sin(pose[2]);
		x = pv[0] + dx * c - dy * s + pose[0] - at[0];
		y = pv[1] + dx * s + dy * c + pose[1] - at[1];
	}

	// eased in, then settling into place with a little weight
	static function settle(t:Float):Float {
		var k = t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
		return k + Math.sin(t * Math.PI) * Math.sin(t * Math.PI * 3) * 0.04 * t;
	}
}

class Sign {
	public final def:Glyph;
	public var charge = 0.0;
	public var armed = true;
	public var lit = false;
	public var near = 0.0;

	public function new(def:Glyph)
		this.def = def;
}

class Snail {
	public var x:Float;
	public var y:Float;
	public var z:Float;
	public var asleep:Bool;
	public var out:Float;
	public var facing = 1;
	public var moving = false;
	public var phase = 0.0;
	public var home = 0.0;
	public var ride:Null<Part> = null;

	public function new(x:Float, y:Float, z:Float, asleep:Bool) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.asleep = asleep;
		out = asleep ? 0 : 1;
	}
}
