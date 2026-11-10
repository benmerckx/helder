import Board;
import Play;
import Sketch.*;
import helder.canvas.Painter;

// Prototype A, light routing: get light to the one dark, waiting thing.
// The moth is the light: on a perch it shines the perch's way. A crystal
// sends on any light that reaches it the way it points (tap: a quarter
// turn); a shutter stops light (drag it, or tap it, to its other slot); a
// lantern, kindled by the moth (tap it: the moth flies there), shines on
// its own. Beams are traced cell by cell each step: what you see is all
// there is.
//
// A map's letters: P perch, C crystal, L lantern, G the goal, S a shutter
// (s its other slot), M the moth; dirs: the ways of P, C and L in reading
// order (U, R, D, L).
typedef LightScreen = {name:String, hint:String, goal:String, need:Int, map:Array<String>, dirs:String};

private typedef Aimed = {i:Int, j:Int, dir:Int, shown:Float, lit:Bool, pulse:Float};
private typedef Shutter = {slots:Array<Cell>, at:Int, shown:Float, pulse:Float};
private typedef Beam = {points:Array<Float>, source:Int};

class Light implements Play {
	public static final screens:Array<LightScreen> = [
		{
			name: "One crystal",
			hint: "Fly to the perch. Tap the crystal.",
			goal: "cocoon",
			need: 1,
			dirs: "LU",
			map: [
				"#######",
				"#.....#",
				"#.C..G#",
				"#.....#",
				"#..#..#",
				"#.....#",
				"#.P...#",
				"#....M#",
				"#######"
			]
		},
		{
			name: "Two crystals",
			hint: "Drag the shutter aside.",
			goal: "lantern",
			need: 1,
			dirs: "URD",
			map: [
				"#######",
				"#.....#",
				"#.#.CG#",
				"#.M...#",
				"#.#...#",
				"#...Ss#",
				"#.....#",
				"#P..C.#",
				"#######"
			]
		},
		{
			name: "Two lights",
			hint: "Tap the lantern: the moth kindles it.",
			goal: "flower",
			need: 2,
			dirs: "ULU",
			map: [
				"#######",
				"#..C.L#",
				"#.#.###",
				"#.#G#.#",
				"#.#.#.#",
				"#.sS..#",
				"#.....#",
				"#M.P..#",
				"#######"
			]
		}
	];

	static final DX = [0, 1, 0, -1];
	static final DY = [1, 0, -1, 0];
	static inline var BEAM = 0xFFFFE9B0;
	static inline var STONE = 0xFF454A61;
	static inline var CRYSTAL = 0xFF79DCEB;
	static inline var GOAL = 0xFFFFA43C;

	public var board(default, null):Board;
	public var moth(default, null):Flight;
	public var solved(default, null) = false;
	public var events(default, null):Array<String> = [];
	final screen:LightScreen;
	final perches:Array<Aimed> = [];
	final crystals:Array<Aimed> = [];
	final lanterns:Array<Aimed> = [];
	final shutters:Array<Shutter> = [];
	final goal:Cell;
	var beams:Array<Beam> = [];
	var previews:Array<Beam> = [];
	var reached = 0;
	var wake = 0.0;
	var time = 0.0;
	var kindling:Null<Aimed> = null;
	var grabbed:Null<Shutter> = null;
	var grabX = 0.0;
	var grabY = 0.0;
	var dragged = false;
	var leading = false;

	public function new(k:Int) {
		screen = screens[k];
		board = new Board(screen.map);
		var dirs = [for (d in screen.dirs.split("")) "URDL".indexOf(d)], n = 0;
		for (r in 0...board.rows)
			for (i in 0...board.cols) {
				var letter = screen.map[r].charAt(i), j = board.rows - 1 - r;
				var list = letter == "P" ? perches : letter == "C" ? crystals : letter == "L" ? lanterns : null;
				if (list != null) {
					var d = dirs[n++];
					list.push({i: i, j: j, dir: d, shown: d, lit: false, pulse: 0});
				}
			}
		for (s in board.find("S")) {
			var other = board.find("s");
			other.sort((a, b) -> far(a, s) < far(b, s) ? -1 : 1);
			shutters.push({slots: [s, other[0]], at: 0, shown: 0, pulse: 0});
		}
		goal = board.find("G")[0];
		var m = board.find("M")[0];
		moth = new Flight(m.i + 0.5, m.j + Flight.FEET, Puzzle.FLY);
		moth.bounds = board.bounds();
		board.stand = (i, j) -> {
			for (p in perches)
				if (p.i == i && p.j == j) return j + 0.3;
			return lantern(i, j) != null ? j + 0.55 : null;
		};
		trace();
	}

	static function far(a:Cell, b:Cell):Float
		return Math.abs(a.i - b.i) + Math.abs(a.j - b.j);

	public function step(dt:Float) {
		time += dt;
		moth.step(dt, board);
		var k = kindling;
		if (k != null && near(k, 0.5)) {
			k.lit = !k.lit;
			k.pulse = 1;
			kindling = null;
			events.push(k.lit ? "kindled" : "snuffed");
		}
		for (c in crystals) {
			var d = c.dir - c.shown;
			// (the short way round: 3 to 0 is a quarter turn on)
			if (d < -2) c.shown -= 4;
			c.shown += (c.dir - c.shown) * (1 - Math.exp(-dt * 14));
		}
		for (s in shutters)
			s.shown += (s.at - s.shown) * (1 - Math.exp(-dt * 12));
		for (a in perches.concat(crystals).concat(lanterns))
			a.pulse = Math.max(0, a.pulse - dt * 2);
		for (s in shutters)
			s.pulse = Math.max(0, s.pulse - dt * 2);
		trace();
		if (!solved && reached >= screen.need) {
			solved = true;
			events.push("solved");
		}
		if (solved) wake = Math.min(1, wake + dt / 1.2);
	}

	function near(a:Aimed, r:Float):Bool
		return Math.sqrt(Math.pow(moth.x - a.i - 0.5, 2) + Math.pow(moth.y - a.j - 0.5, 2)) < r;

	// every beam as it is: from each perch the moth is at, each lit lantern
	function trace() {
		beams = [];
		previews = [];
		var sources = new Map<Int, Bool>();
		for (c in crystals)
			c.lit = false;
		for (k in 0...perches.length) {
			var p = perches[k], b = ray(p.i, p.j, p.dir, k, near(p, 0.55));
			(near(p, 0.55) ? beams : previews).push(b.beam);
			if (b.goal && near(p, 0.55)) sources.set(k, true);
		}
		for (k in 0...lanterns.length) {
			var l = lanterns[k], b = ray(l.i, l.j, l.dir, 100 + k, l.lit);
			(l.lit ? beams : previews).push(b.beam);
			if (b.goal && l.lit) sources.set(100 + k, true);
		}
		reached = [for (_ in sources) 1].length;
	}

	function ray(i:Int, j:Int, dir:Int, source:Int, real:Bool):{beam:Beam, goal:Bool} {
		var points = [i + 0.5, j + 0.5], seen = new Map<Int, Bool>(), goal = false;
		for (_ in 0...200) {
			var ni = i + DX[dir], nj = j + DY[dir];
			if (board.stone(ni, nj) || shut(ni, nj)) {
				points.push(i + 0.5 + DX[dir] * 0.5);
				points.push(j + 0.5 + DY[dir] * 0.5);
				break;
			}
			if (lantern(ni, nj) != null || (ni == this.goal.i && nj == this.goal.j)) {
				goal = ni == this.goal.i && nj == this.goal.j;
				points.push(ni + 0.5 - DX[dir] * 0.32);
				points.push(nj + 0.5 - DY[dir] * 0.32);
				break;
			}
			var c = crystal(ni, nj);
			if (c != null) {
				points.push(ni + 0.5);
				points.push(nj + 0.5);
				var key = (ni * 64 + nj) * 4 + dir;
				if (seen.exists(key)) break;
				seen.set(key, true);
				if (real) c.lit = true;
				dir = c.dir;
			}
			i = ni;
			j = nj;
		}
		return {beam: {points: points, source: source}, goal: goal};
	}

	function shut(i:Int, j:Int):Bool {
		for (s in shutters) {
			var c = s.slots[s.at];
			if (c.i == i && c.j == j) return true;
		}
		return false;
	}

	function crystal(i:Int, j:Int):Null<Aimed> {
		for (c in crystals)
			if (c.i == i && c.j == j) return c;
		return null;
	}

	function lantern(i:Int, j:Int):Null<Aimed> {
		for (l in lanterns)
			if (l.i == i && l.j == j) return l;
		return null;
	}

	// ---- touch

	public function down(x:Float, y:Float) {
		var best:Null<Dynamic> = null, kind = "", d = 0.62;
		function consider(i:Int, j:Int, what:String, thing:Dynamic) {
			var e = Math.sqrt(Math.pow(x - i - 0.5, 2) + Math.pow(y - j - 0.5, 2));
			if (e < d) {
				d = e;
				best = thing;
				kind = what;
			}
		}
		for (c in crystals)
			consider(c.i, c.j, "crystal", c);
		for (l in lanterns)
			consider(l.i, l.j, "lantern", l);
		for (s in shutters)
			consider(s.slots[s.at].i, s.slots[s.at].j, "shutter", s);
		for (p in perches)
			consider(p.i, p.j, "perch", p);
		switch kind {
			case "crystal":
				var c:Aimed = best;
				c.dir = (c.dir + 1) % 4;
				c.pulse = 1;
				events.push("turned");
			case "shutter":
				grabbed = best;
				grabX = x;
				grabY = y;
				dragged = false;
			case "lantern":
				var l:Aimed = best;
				kindling = l;
				fly(l.i + 0.5, l.j + 0.5);
				moth.held = false;
			case "perch":
				var p:Aimed = best;
				fly(p.i + 0.5, p.j + 0.5);
			case _:
				kindling = null;
				fly(x, y);
		}
	}

	function fly(x:Float, y:Float) {
		moth.held = true;
		moth.lead(x, y);
		leading = true;
	}

	public function move(x:Float, y:Float) {
		var s = grabbed;
		if (s != null) {
			var from = s.slots[s.at], to = s.slots[1 - s.at];
			var ax = to.i - from.i, ay = to.j - from.j, l = Math.sqrt(ax * ax + ay * ay);
			if (((x - grabX) * ax + (y - grabY) * ay) / l > 0.45) {
				slide(s);
				grabX = x;
				grabY = y;
				dragged = true;
			}
			return;
		}
		if (leading && moth.held) moth.lead(x, y);
	}

	public function up() {
		var s = grabbed;
		if (s != null && !dragged) slide(s);
		grabbed = null;
		moth.held = false;
		leading = false;
	}

	function slide(s:Shutter) {
		s.at = 1 - s.at;
		s.pulse = 1;
		events.push("slid");
	}

	// ---- drawing (world units, y up)

	public function draw(c:Painter, t:Float) {
		Sketch.stones(c, board);
		for (s in shutters) {
			var a = s.slots[0], b = s.slots[1];
			line(c, [a.i + 0.5, a.j + 0.5, b.i + 0.5, b.j + 0.5], 0.16, 0xFF0D0F18);
			for (slot in s.slots)
				outline(c, slot.i + 0.1, slot.j + 0.1, 0.8, 0.8, 0.03, 0x40FFFFFF, 0.08);
		}
		for (b in previews)
			line(c, b.points, 0.05, 0x55FFE9B0, 0.12, -t * 0.6);
		for (b in beams) {
			line(c, b.points, 0.42, 0x30FFD27A);
			line(c, b.points, 0.16, 0x70FFE9B0);
			line(c, b.points, 0.06, 0xFFFFFBEA);
			var n = b.points.length;
			glow(c, b.points[n - 2], b.points[n - 1], 0.35, 0xA0FFE9B0);
		}
		drawGoal(c, t);
		for (p in perches) {
			var x = p.i + 0.5, y = p.j;
			var manned = near(p, 0.55);
			if (!manned) ring(c, x, y + 0.5, 0.42 + 0.04 * Math.sin(t * 3), 0.03, alpha(0xFFB07CFF, 0.35 + 0.2 * Math.sin(t * 3)));
			box(c, x - 0.3, y, 0.6, 0.3, 0xFF6E7391, 0.05);
			box(c, x - 0.18, y + 0.24, 0.36, 0.08, manned ? 0xFFE0CCFF : 0xFF9A8FB8, 0.03);
			arrow(c, x, y + 0.5, p.dir, 0.4, manned ? 0xFFFFF4D0 : 0xAAB07CFF);
		}
		for (k in crystals) {
			var x = k.i + 0.5, y = k.j + 0.5, a = Math.PI / 2 - k.shown * Math.PI / 2;
			if (k.lit) glow(c, x, y, 0.7, 0x90A8F4FF);
			ring(c, x, y, 0.4 + 0.03 * Math.sin(t * 2.6 + k.i), 0.025, alpha(CRYSTAL, 0.25 + 0.15 * Math.sin(t * 2.6 + k.i)) );
			var r = 0.3 + k.pulse * 0.06;
			poly(c, [x + r * Math.cos(a), y + r * Math.sin(a), x + r * 0.7 * Math.cos(a + 2.2), y + r * 0.7 * Math.sin(a + 2.2),
				x - r * 0.45 * Math.cos(a), y - r * 0.45 * Math.sin(a), x + r * 0.7 * Math.cos(a - 2.2), y + r * 0.7 * Math.sin(a - 2.2)],
				k.lit ? 0xFFDDFBFF : CRYSTAL);
			// (the notch: the way it sends light)
			circle(c, x + r * 0.55 * Math.cos(a), y + r * 0.55 * Math.sin(a), 0.05, 0xFF1A2A40);
		}
		for (s in shutters) {
			var a = s.slots[0], b = s.slots[1];
			var x = a.i + (b.i - a.i) * s.shown + 0.5, y = a.j + (b.j - a.j) * s.shown + 0.5;
			var along = b.i != a.i;
			outline(c, x - 0.44, y - 0.44, 0.88, 0.88, 0.03, alpha(0xFFE8D9B5, 0.3 + 0.2 * Math.sin(t * 2.2)), 0.1);
			box(c, x - 0.4, y - 0.4, 0.8, 0.8, 0xFF8C8370, 0.08);
			// (grips across the way it slides)
			for (g in [-0.15, 0, 0.15])
				if (along) line(c, [x + g, y - 0.22, x + g, y + 0.22], 0.05, 0xFF5E5748) else line(c, [x - 0.22, y + g, x + 0.22, y + g], 0.05, 0xFF5E5748);
		}
		for (l in lanterns) {
			var x = l.i + 0.5, y = l.j + 0.5;
			if (l.lit) glow(c, x, y, 1.0, 0xA0FF8AD0);
			else ring(c, x, y, 0.42 + 0.04 * Math.sin(t * 3), 0.03, alpha(0xFFFF8AD0, 0.3 + 0.2 * Math.sin(t * 3)));
			line(c, [x, y + 0.3, x, y + 0.5], 0.04, 0xFF6E7391);
			box(c, x - 0.2, y - 0.28, 0.4, 0.56, l.lit ? 0xFFFFB8E4 : 0xFF4D3E57, 0.14);
			box(c, x - 0.09, y - 0.14, 0.18, 0.26, l.lit ? 0xFFFFFFFF : 0xFF2A2233, 0.06);
			arrow(c, x, y, l.dir, 0.42, l.lit ? 0xFFFFF4D0 : 0xAAFF8AD0);
		}
		Sketch.moth(c, moth, t);
	}

	function drawGoal(c:Painter, t:Float) {
		var x = goal.i + 0.5, y = goal.j + 0.5, w = wake;
		var body = mix(0xFF2C2635, GOAL, w);
		if (w > 0) glow(c, x, y, 0.8 + w * 1.4, alpha(GOAL, 0.7 * w));
		else ring(c, x, y, 0.45 + 0.05 * Math.sin(t * 1.8), 0.035, alpha(GOAL, 0.25 + 0.2 * Math.sin(t * 1.8)));
		switch screen.goal {
			case "cocoon":
				line(c, [x, y + 0.5, x, y + 0.34], 0.03, 0xFF6E7391);
				var p = new helder.canvas.Path();
				p.ellipse(x, y - 0.02, 0.2 + w * 0.03, 0.34, 0, 0, Math.PI * 2);
				c.fill(p, helder.canvas.Paint.solid(body));
				for (k in 0...3)
					line(c, [x - 0.18, y - 0.18 + k * 0.16, x + 0.18, y - 0.12 + k * 0.16], 0.025, alpha(0xFF000000, 0.35));
			case "lantern":
				line(c, [x, y + 0.5, x, y + 0.3], 0.04, 0xFF6E7391);
				box(c, x - 0.22, y - 0.3, 0.44, 0.6, body, 0.15);
				box(c, x - 0.1, y - 0.15, 0.2, 0.28, w > 0 ? 0xFFFFF3D6 : 0xFF1B1622, 0.06);
			case _:
				// (a closed bud: its petals part as it wakes)
				line(c, [x, y - 0.5, x, y - 0.1], 0.05, 0xFF4E7A52);
				for (k in [-1, 1])
					poly(c, [x, y - 0.15, x + k * (0.08 + w * 0.3), y + 0.1, x + k * (0.02 + w * 0.15), y + 0.38], body);
				poly(c, [x - 0.08, y - 0.12, x + 0.08, y - 0.12, x, y + 0.34 - w * 0.1], mix(0xFF3A3144, 0xFFFFD27A, w));
		}
		// (a pip a light it waits for, filled as one reaches it)
		for (k in 0...screen.need) {
			var px = x + (k - (screen.need - 1) / 2) * 0.22, py = y - 0.62;
			circle(c, px, py, 0.07, k < reached || solved ? 0xFFFFE9B0 : 0xFF3A3448);
			ring(c, px, py, 0.07, 0.02, 0x80FFE9B0);
		}
	}

	static function arrow(c:Painter, x:Float, y:Float, dir:Int, r:Float, color:Int) {
		var dx = DX[dir], dy = DY[dir], px = -dy, py = dx;
		var tx = x + dx * r, ty = y + dy * r;
		poly(c, [tx + dx * 0.1, ty + dy * 0.1, tx + px * 0.08, ty + py * 0.08, tx - px * 0.08, ty - py * 0.08], color);
	}
}
