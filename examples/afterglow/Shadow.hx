import Board;
import Play;
import Sketch.*;
import helder.canvas.Gradient;
import helder.canvas.Paint;
import helder.canvas.Painter;
import helder.canvas.Path;

// Prototype C, light and shadow: the moth is the only light, and where it
// is decides what is lit and what is in shadow (cast live from every stone
// and post, and from a bloom once open). The caterpillar crawls home by
// itself, along the one way it knows, but only while it is in the light;
// what lies on that way answers to light and shadow:
//
// - a bloom opens in the light (a pad to step on, and a shadow), closes in
//   the dark;
// - moss grows across a gap in shadow (a bridge), recedes in the light;
// - a shy creature blocks the way, and hides from the light, creeping back
//   when it leaves;
// - a glyph completes when a shadow falls on it exactly: its slot dark,
//   both its sides lit, held a moment; a completed glyph stays, and opens
//   the gates.
//
// Whatever the caterpillar is on, or stepping onto, stays as it is. The only
// input is flying the moth: a tap flies it there, round the stone; it
// hovers a moment and lands on what is below (a ledge, a peg, an open
// bloom), or hovers while held.
//
// A map's letters: M the moth, c the caterpillar, H its home, b a bloom,
// m moss, x a creature, g a glyph, G a gate, p a post, o a peg.
typedef ShadowScreen = {name:String, hint:String, map:Array<String>};

private typedef Thing = {cell:Cell, kind:String, shown:Float, lit:Bool, held:Bool};

class Shadow implements Play {
	public static final screens:Array<ShadowScreen> = [
		{
			name: "A bloom",
			hint: "Light opens the bloom. Light the caterpillar too.",
			map: [
				"#######",
				"#.....#",
				"#.M...#",
				"#.....#",
				"#.....#",
				"#.....#",
				"#....H#",
				"#c..b##",
				"#######"
			]
		},
		{
			name: "Moss",
			hint: "Moss grows across in shadow.",
			map: [
				"#######",
				"#.o...#",
				"#....M#",
				"#..####",
				"#c...H#",
				"###m###",
				"###.###",
				"###.###",
				"#######"
			]
		},
		{
			name: "A bloom's shade",
			hint: "An open bloom casts a shadow.",
			map: [
				"#######",
				"#.....#",
				"#....M#",
				"#..o.##",
				"#.....#",
				"#..b..#",
				"#.c..H#",
				"###m###",
				"#######"
			]
		},
		{
			name: "Shy",
			hint: "It hides from the light. Fly low.",
			map: [
				"#######",
				"#..M..#",
				"#.....#",
				"#.....#",
				"#.....#",
				"#.....#",
				"####.H#",
				"#cx..b#",
				"##m####"
			]
		},
		{
			name: "The glyph",
			hint: "Fit the post's shadow to the glyph.",
			map: [
				"#######",
				"#..o..#",
				"#.....#",
				"#..p.M#",
				"#..g.##",
				"#.....#",
				"#c.G.H#",
				"####m##",
				"#######"
			]
		}
	];

	// the moth's light: how far it reaches
	public static inline var REACH = 4.2;
	static inline var CRAWL = 1.4;
	static inline var POST = 0.1;
	static inline var BLOOM = 0xFFFF8FB8;
	static inline var MOSS = 0xFF7FD68A;
	static inline var SHY = 0xFFFFE27A;
	static inline var GLYPH = 0xFF79DCEB;
	static inline var HOME = 0xFFFFB347;
	static inline var LIGHT = 0xFFFFE6BE;

	public var board(default, null):Board;
	public var moth(default, null):Flight;
	public var solved(default, null) = false;
	public var events(default, null):Array<String> = [];
	final screen:ShadowScreen;
	final things:Array<Thing> = [];
	final shadows = new Shadows();
	final way:Route;
	final home:Cell;
	// the caterpillar: its cell, the one it steps to (and how far), awake
	var at:Cell;
	var next:Null<Cell> = null;
	var walk = 0.0;
	var awake = 0.0;
	var woke = false;
	var waiting:Null<Cell> = null;
	var plan:Array<Cell> = [];
	var gates = false;
	var time = 0.0;
	var wake = 0.0;

	public function new(k:Int) {
		screen = screens[k];
		board = new Board(screen.map);
		for (r in 0...board.rows)
			for (i in 0...board.cols) {
				var l = screen.map[r].charAt(i), cell = {i: i, j: board.rows - 1 - r};
				if ("bmxgG".indexOf(l) >= 0)
					things.push({cell: cell, kind: l, shown: l == "x" || l == "G" ? 1 : 0, lit: false, held: false});
			}
		home = board.find("H")[0];
		at = board.find("c")[0];
		var m = board.find("M")[0];
		moth = new Flight(m.i + 0.5, m.j + Flight.FEET, Puzzle.FLY);
		moth.bounds = board.bounds();
		board.solid = (i, j) -> wall(i, j);
		board.stand = (i, j) -> {
			var l = board.at(i, j);
			if (l == "o") return j + 0.12;
			var t = thing(i, j);
			return t != null && t.kind == "b" && t.shown > 0.9 ? j + 0.85 : t != null && t.kind == "m" && t.shown > 0.9 ? j + 1 : null;
		};
		way = new Route(board, moth, (i, j) -> !wall(i, j));
		occlude();
		look();
	}

	function thing(i:Int, j:Int):Null<Thing> {
		for (t in things)
			if (t.cell.i == i && t.cell.j == j) return t;
		return null;
	}

	// what the moth cannot fly through
	function wall(i:Int, j:Int):Bool {
		if (board.stone(i, j) || board.at(i, j) == "p") return true;
		var t = thing(i, j);
		return t != null && t.kind == "G" && t.shown > 0.05;
	}

	// ---- light

	// every edge between stone (or a shut gate) and air, runs merged; posts,
	// open blooms
	function occlude() {
		shadows.clear();
		inline function solid(i:Int, j:Int)
			return board.stone(i, j) || {
				var t = thing(i, j);
				t != null && t.kind == "G" && t.shown > 0.5;
			};
		for (j in 0...board.rows + 1) {
			// (horizontal: below the row j, above j - 1)
			var run = -1, up = false;
			for (i in 0...board.cols + 1) {
				var a = i < board.cols && solid(i, j - 1), b = i < board.cols && solid(i, j);
				var edge = a != b;
				if (edge && run >= 0 && up != b) {
					shadows.add(run, j, i, j);
					run = -1;
				}
				if (edge && run < 0) {
					run = i;
					up = b;
				}
				if (!edge && run >= 0) {
					shadows.add(run, j, i, j);
					run = -1;
				}
			}
		}
		for (i in 0...board.cols + 1) {
			var run = -1, right = false;
			for (j in 0...board.rows + 1) {
				var a = j < board.rows && solid(i - 1, j), b = j < board.rows && solid(i, j);
				var edge = a != b;
				if (edge && run >= 0 && right != b) {
					shadows.add(i, run, i, j);
					run = -1;
				}
				if (edge && run < 0) {
					run = j;
					right = b;
				}
				if (!edge && run >= 0) {
					shadows.add(i, run, i, j);
					run = -1;
				}
			}
		}
		for (p in board.find("p"))
			shadows.box(p.i + 0.5 - POST, p.j, POST * 2, 1);
		for (t in things)
			if (t.kind == "b" && t.shown > 0.5) {
				var w = 0.4 * t.shown;
				shadows.add(t.cell.i + 0.5 - w, t.cell.j + 0.82, t.cell.i + 0.5 + w, t.cell.j + 0.82);
			}
	}

	inline function lx():Float
		return moth.x;

	inline function ly():Float
		return moth.y;

	public function lit(x:Float, y:Float):Bool {
		var dx = x - lx(), dy = y - ly();
		return dx * dx + dy * dy < REACH * REACH && shadows.sees(lx(), ly(), x, y);
	}

	// how much light falls there (0 in shadow)
	function shine(x:Float, y:Float):Float {
		if (!lit(x, y)) return 0;
		var d = Math.sqrt(Math.pow(x - lx(), 2) + Math.pow(y - ly(), 2)) / REACH;
		return Math.pow(1 - d, 0.6);
	}

	// each thing's light, as seen this step
	function look() {
		for (t in things) {
			var x = t.cell.i + 0.5, y = t.cell.j + 0.5;
			t.lit = switch t.kind {
				case "g": !lit(x, y - 0.25) && !lit(x, y) && !lit(x, y + 0.25) && lit(x - 0.45, y) && lit(x + 0.45, y);
				case "m": lit(x, y) || lit(x, y + 0.35);
				case "x": lit(x, y - 0.15);
				// (above its pad, or under it: not its own shadow)
				case "b": lit(x, y + 0.42) || lit(x, y + 0.2);
				case _: lit(x, y);
			}
		}
	}

	// ---- the caterpillar's way

	// what is under it now, or could be
	function support(i:Int, j:Int, could:Bool):Bool {
		if (board.stone(i, j)) return true;
		var t = thing(i, j);
		if (t == null) return false;
		return switch t.kind {
			case "G": could || t.shown > 0.5;
			case "b" | "m": could || t.shown > 0.95;
			case _: false;
		}
	}

	// what it cannot be in, now or ever
	function blocked(i:Int, j:Int, could:Bool):Bool {
		var l = board.at(i, j);
		if (l == "#" || l == "p" || l == "b" || l == "m") return true;
		var t = thing(i, j);
		if (t == null || could) return false;
		return t.kind == "G" && t.shown > 0.05 || t.kind == "x" && t.shown > 0.15;
	}

	function stands(i:Int, j:Int, could:Bool):Bool
		return !blocked(i, j, could) && support(i, j - 1, could);

	function moves(c:Cell, could:Bool):Array<Cell> {
		var out:Array<Cell> = [];
		for (s in [1, -1]) {
			var i = c.i + s, j = c.j;
			if (stands(i, j, could)) out.push({i: i, j: j});
			else if (support(i, j, could) && !blocked(c.i, j + 1, could) && stands(i, j + 1, could)) out.push({i: i, j: j + 1});
			else if (!blocked(i, j, could) && stands(i, j - 1, could)) out.push({i: i, j: j - 1});
		}
		return out;
	}

	// the way home it knows: as if every bloom were open, all moss grown,
	// no creature in the way, the gates open
	function route():Array<Cell> {
		var cols = board.cols, before = new Map<Int, Int>(), queue = [at];
		before.set(at.i + at.j * cols, -1);
		while (queue.length > 0) {
			var c = queue.shift();
			if (c.i == home.i && c.j == home.j) break;
			for (n in moves(c, true)) {
				var key = n.i + n.j * cols;
				if (before.exists(key)) continue;
				before.set(key, c.i + c.j * cols);
				queue.push(n);
			}
		}
		var key = home.i + home.j * cols;
		if (!before.exists(key)) return [];
		var out:Array<Cell> = [];
		while (key != -1) {
			out.unshift({i: key % cols, j: Std.int(key / cols)});
			key = before.get(key);
		}
		return out;
	}

	function crawl(dt:Float) {
		var n = next;
		if (n != null) {
			walk += dt * CRAWL;
			if (walk >= 1) {
				at = n;
				next = null;
				walk = 0;
			}
			return;
		}
		if (at.i == home.i && at.j == home.j) {
			if (!solved) {
				solved = true;
				events.push("solved");
			}
			return;
		}
		var here = lit(at.i + 0.5, at.j + 0.3);
		awake += ((here ? 1 : 0) - awake) * (1 - Math.exp(-dt * 6));
		if (here && !woke) {
			woke = true;
			events.push("woke");
		}
		plan = route();
		if (!here || plan.length < 2) return;
		var to = plan[1];
		for (m in moves(at, false))
			if (m.i == to.i && m.j == to.j) {
				next = to;
				walk = 0;
				waiting = null;
				return;
			}
		if (waiting == null || waiting.i != at.i || waiting.j != at.j) {
			waiting = at;
			events.push('waits at ${at.i},${at.j}');
		}
	}

	// ---- the step

	public function step(dt:Float) {
		time += dt;
		way.follow();
		moth.step(dt, board);
		occlude();
		look();
		for (t in things)
			t.held = holds(t);
		for (t in things) {
			var was = t.shown;
			switch t.kind {
				case "b" if (!t.held): t.shown = t.lit ? Math.min(1, t.shown + dt / 0.5) : Math.max(0, t.shown - dt / 0.8);
				case "m" if (!t.held): t.shown = t.lit ? Math.max(0, t.shown - dt / 0.6) : Math.min(1, t.shown + dt / 1.2);
				case "x" if (!t.held): t.shown = t.lit ? Math.max(0, t.shown - dt / 0.35) : Math.min(1, t.shown + dt / 1.6);
				case "g" if (t.shown < 1): t.shown = t.lit ? Math.min(1, t.shown + dt / 0.7) : Math.max(0, t.shown - dt / 0.4);
				case "G" if (gates): t.shown = Math.max(0, t.shown - dt / 0.8);
				case _:
			}
			say(t, was);
		}
		if (!gates && [for (t in things) if (t.kind == "g" && t.shown < 1) t].length == 0 && [for (t in things) if (t.kind == "g") t].length > 0) {
			gates = true;
			events.push("gates open");
		}
		crawl(dt);
		if (solved) wake = Math.min(1, wake + dt / 1.2);
	}

	function say(t:Thing, was:Float) {
		var what = t.kind == "b" ? ["closed", "opened"] : t.kind == "m" ? ["receded", "grown"] : t.kind == "x" ? ["hid", "back"] : t.kind == "g" ? ["", "glyph complete"] : null;
		if (what == null) return;
		var name = '${t.kind} ${t.cell.i},${t.cell.j}';
		if (was < 1 && t.shown >= 1 && what[1] != "") events.push('$name ${what[1]}');
		if (was > 0 && t.shown <= 0 && what[0] != "") events.push('$name ${what[0]}');
	}

	// what the caterpillar is on or stepping onto (or into) stays
	function holds(t:Thing):Bool {
		var cells = [at];
		var n = next;
		if (n != null) cells.push(n);
		for (c in cells) {
			if (t.kind == "x" && c.i == t.cell.i && c.j == t.cell.j) return true;
			if ((t.kind == "b" || t.kind == "m") && c.i == t.cell.i && c.j - 1 == t.cell.j) return true;
		}
		return false;
	}

	// ---- touch: the moth flies where it is led, round the stone

	var pressed:Null<Cell> = null;

	public function down(x:Float, y:Float) {
		pressed = {i: Math.floor(x), j: Math.floor(y)};
		moth.held = true;
		way.to(pressed);
	}

	public function move(x:Float, y:Float) {
		var p = pressed;
		if (p == null) return;
		var c = {i: Math.floor(x), j: Math.floor(y)};
		if (c.i == p.i && c.j == p.j) return;
		pressed = c;
		way.to(c);
	}

	public function up() {
		pressed = null;
		moth.held = false;
	}

	// ---- drawing (world units, y up)

	static final path = new Path();

	public function draw(c:Painter, t:Float) {
		box(c, 0, 0, board.cols, board.rows, 0xFF07080D);
		light(c);
		// (the way it knows: faint dots, from where it is home)
		var p = plan;
		for (k in 1...p.length)
			circle(c, p[k].i + 0.5, p[k].j + 0.12, 0.045, alpha(0xFFE8F0C8, 0.25 + 0.15 * shine(p[k].i + 0.5, p[k].j + 0.3)));
		stone(c);
		for (o in board.find("o"))
			peg(c, o);
		for (p in board.find("p"))
			post(c, p);
		for (th in things)
			switch th.kind {
				case "b": bloom(c, th, t);
				case "m": moss(c, th, t);
				case "x": shy(c, th, t);
				case "g": glyph(c, th, t);
				case "G": gate(c, th);
				case _:
			}
		cocoon(c, t);
		caterpillar(c, t);
		Sketch.moth(c, moth, t);
	}

	// the moth's light over the floor: the polygon it sees, from the light
	// and from four points just about it (a soft edge where a shadow is far
	// from what casts it)
	function light(c:Painter) {
		var x = lx(), y = ly();
		for (o in [[0.0, 0.0, 0.6], [0.07, 0.0, 0.1], [-0.07, 0.0, 0.1], [0.0, 0.07, 0.1], [0.0, -0.07, 0.1]]) {
			var px = x + o[0], py = y + o[1];
			if (wall(Math.floor(px), Math.floor(py))) continue;
			var poly = shadows.polygon(px, py, REACH);
			var g = new RadialGradient(px, py, 0, px, py, REACH);
			var a = o[2];
			g.addStop(0, alpha(LIGHT, a * 0.85)).addStop(0.3, alpha(LIGHT, a * 0.6)).addStop(0.7, alpha(LIGHT, a * 0.26)).addStop(1, alpha(LIGHT, 0));
			path.clear();
			path.moveTo(poly[0], poly[1]);
			var k = 2;
			while (k < poly.length) {
				path.lineTo(poly[k], poly[k + 1]);
				k += 2;
			}
			path.close();
			c.fill(path, Paint.shaded(g));
		}
	}

	// stone, dark, its faces that the light sees edged by it (in four
	// strengths: one path each, a few draws whatever the board)
	function stone(c:Painter) {
		path.clear();
		for (j in 0...board.rows)
			for (i in 0...board.cols)
				if (board.stone(i, j)) path.rect(i - 0.01, j - 0.01, 1.02, 1.02);
		c.fill(path, Paint.solid(0xFF262A3C));
		final rims = [for (_ in 0...4) new Path()];
		for (j in 0...board.rows)
			for (i in 0...board.cols)
				if (board.stone(i, j))
					for (s in [[0, 1], [1, 0], [0, -1], [-1, 0]]) {
						if (board.stone(i + s[0], j + s[1])) continue;
						var mx = i + 0.5 + s[0] * 0.5, my = j + 0.5 + s[1] * 0.5;
						// (a face the light is in front of)
						if ((lx() - mx) * s[0] + (ly() - my) * s[1] <= 0) continue;
						var k = shine(mx + s[0] * 0.02, my + s[1] * 0.02);
						if (k <= 0) continue;
						var p = rims[Std.int(Math.min(3, k * 4))];
						var ox = mx - s[0] * 0.04, oy = my - s[1] * 0.04;
						p.moveTo(ox - s[1] * 0.5, oy - s[0] * 0.5);
						p.lineTo(ox + s[1] * 0.5, oy + s[0] * 0.5);
					}
		final pen = new helder.canvas.Stroke(0.08);
		for (n in 0...4)
			if (!rims[n].isEmpty()) c.stroke(rims[n], pen, Paint.solid(alpha(0xFFB8B0D8, 0.2 + 0.65 * (n + 0.5) / 4)));
	}

	function tint(dark:Int, full:Int, x:Float, y:Float):Int
		return mix(dark, full, 0.3 + 0.7 * Math.min(1, shine(x, y) * 1.6));

	function peg(c:Painter, o:Cell) {
		var left = board.stone(o.i - 1, o.j), x = o.i + 0.5;
		var from = left ? o.i : board.stone(o.i + 1, o.j) ? o.i + 1 : x;
		box(c, Math.min(from, x - 0.3), o.j + 0.02, Math.abs(from - x) + 0.3, 0.1, tint(0xFF3A3F55, 0xFF8A8FA8, x, o.j + 0.3), 0.03);
	}

	function post(c:Painter, p:Cell) {
		var x = p.i + 0.5;
		box(c, x - POST, p.j, POST * 2, 1, 0xFF2A2E40);
		line(c, [x - POST - 0.02, p.j + 0.98, x + POST + 0.02, p.j + 0.98], 0.05, 0xFF5D637C);
		// (a chain up to the stone it hangs from)
		var top = p.j + 1;
		while (top < board.rows && !board.stone(p.i, top))
			top++;
		if (top > p.j + 1) line(c, [x, p.j + 1, x, top], 0.025, 0xFF3A3F55, 0.06);
	}

	function bloom(c:Painter, b:Thing, t:Float) {
		var x = b.cell.i + 0.5, y = b.cell.j, s = b.shown;
		var leaf = tint(0xFF203A28, 0xFF4F8A5A, x, y + 0.4), petal = tint(0xFF4A2638, BLOOM, x, y + 0.7);
		// (a stem from the stone below, or a vine from above)
		var below = !board.stone(b.cell.i, b.cell.j - 1) && board.at(b.cell.i, b.cell.j - 1) != "m";
		if (below) {
			var top = b.cell.j + 1;
			while (top < board.rows && !board.stone(b.cell.i, top))
				top++;
			line(c, [x, y + 0.75, x, top], 0.035, leaf);
		} else line(c, [x, y, x, y + 0.72], 0.05, leaf);
		if (s < 0.05) {
			// (a closed bud: a drop, pointing up)
			poly(c, [x, y + 0.98, x - 0.16, y + 0.68, x, y + 0.56, x + 0.16, y + 0.68], petal);
			return;
		}
		// (open: petals fanning out to a flat pad at the cell's top)
		var w = 0.08 + 0.4 * s;
		for (k in 0...5) {
			var u = (k - 2) / 2;
			var tip = x + u * w, h = y + 0.82 + (1 - s) * 0.15 * (1 - Math.abs(u));
			poly(c, [x, y + 0.66, tip - 0.09, h + 0.05, tip + 0.09, h + 0.05], petal);
		}
		box(c, x - w, y + 0.8, w * 2, 0.06, mix(petal, 0xFFFFFFFF, 0.25 * s), 0.03);
		circle(c, x, y + 0.72, 0.07, tint(0xFF5A4A20, 0xFFFFE9B0, x, y + 0.7));
	}

	function moss(c:Painter, m:Thing, t:Float) {
		var x0 = m.cell.i, y = m.cell.j + 1, s = m.shown;
		var color = tint(0xFF24402A, MOSS, x0 + 0.5, y - 0.4);
		// (tufts from either edge, meeting in the middle when grown)
		var n = 7;
		for (k in 0...n) {
			var u = (k + 0.5) / n;
			var reach = Math.min(u, 1 - u) * 2;
			var grown = Math.max(0, Math.min(1, (s * 1.15 - reach) / 0.15 + 1));
			if (grown <= 0) continue;
			var r = 0.11 * grown + 0.02 * Math.sin(t * 2 + k);
			circle(c, x0 + u, y - 0.08, r, color);
			circle(c, x0 + u + 0.05, y - 0.16, r * 0.7, color);
		}
		// (spores on the edges: where it grows from)
		for (e in [x0 + 0.04, x0 + 0.96])
			circle(c, e, y - 0.1, 0.08, color);
		if (s > 0.95) line(c, [x0 + 0.02, y - 0.02, x0 + 0.98, y - 0.02], 0.05, mix(color, 0xFFFFFFFF, 0.2));
	}

	// a shy creature: a dark round thing with two big eyes, drawing back
	// into its burrow (the stone above it, or a hole under it) as it hides
	function shy(c:Painter, x:Thing, t:Float) {
		var up = board.stone(x.cell.i, x.cell.j + 1);
		var bx = x.cell.i + 0.5, base = up ? x.cell.j + 1 : x.cell.j * 1.0, dir = up ? -1 : 1;
		var s = x.shown;
		path.clear();
		path.ellipse(bx, base, 0.3, 0.07, 0, 0, Math.PI * 2);
		c.fill(path, Paint.solid(0xFF020203));
		if (s <= 0.02) {
			// (two eyes in the dark of its burrow)
			for (e in [-0.07, 0.07])
				circle(c, bx + e, base, 0.022, alpha(SHY, 0.7));
			return;
		}
		var h = 0.66 * s, cy = base + dir * h / 2;
		c.save();
		path.clear();
		path.rect(x.cell.i - 0.2, up ? base - 1 : base, 1.4, 1);
		c.clip(path);
		path.clear();
		path.ellipse(bx, cy, 0.32, h / 2 + 0.04, 0, 0, Math.PI * 2);
		c.fill(path, Paint.solid(tint(0xFF1C1626, 0xFF4A3D6B, bx, x.cell.j + 0.4)));
		// (spines: it is in the way)
		for (k in 0...5) {
			var a = (k - 2) * 0.32 + (up ? -Math.PI / 2 : Math.PI / 2);
			var ex = bx + Math.cos(a) * 0.3, ey = cy + Math.sin(a) * (h / 2 + 0.02);
			line(c, [ex, ey, ex + Math.cos(a) * 0.1, ey + Math.sin(a) * 0.1], 0.03, tint(0xFF1C1626, 0xFF6A5A90, bx, x.cell.j + 0.4));
		}
		var ey = base + dir * h * 0.7;
		for (e in [-0.12, 0.12]) {
			circle(c, bx + e, ey, 0.09 * s, 0xFFF4F0E0);
			circle(c, bx + e, ey - 0.01, 0.05 * s, 0xFF120E18);
		}
		c.restore();
	}

	// a glyph: a carved slot between two marks; dark slot, lit marks fill it
	function glyph(c:Painter, g:Thing, t:Float) {
		var x = g.cell.i + 0.5, y = g.cell.j + 0.5, s = g.shown;
		var done = s >= 1;
		var carve = done ? GLYPH : 0xFF7A80A0;
		outline(c, x - 0.09, y - 0.33, 0.18, 0.66, 0.04, alpha(carve, 0.85), 0.06);
		if (s > 0) box(c, x - 0.07, y - 0.31, 0.14, 0.62 * s, alpha(GLYPH, done ? 0.9 : 0.6), 0.05);
		for (e in [-1, 1]) {
			var on = lit(x + e * 0.45, y);
			var col = done ? GLYPH : on ? 0xFFFFF0D0 : 0xFF4A4F66;
			poly(c, [x + e * 0.45, y + 0.12, x + e * 0.35, y, x + e * 0.45, y - 0.12, x + e * 0.55, y], col);
		}
		if (done) glow(c, x, y, 0.8, alpha(GLYPH, 0.35 + 0.1 * Math.sin(t * 2)));
		// (its wires to the gates)
		for (o in things)
			if (o.kind == "G")
				line(c, [x, y - 0.35, o.cell.i + 0.5, o.cell.j + 0.9], 0.03, alpha(done ? GLYPH : 0xFF7A80A0, done ? 0.5 : 0.25), 0.08, -t * 0.3);
	}

	function gate(c:Painter, g:Thing) {
		var x = g.cell.i, y = g.cell.j, h = g.shown;
		if (h <= 0) return;
		// (a slab sinking into the floor as it opens)
		box(c, x + 0.08, y, 0.84, h, 0xFF3D4258, 0.03);
		for (k in 0...3)
			line(c, [x + 0.25 + k * 0.25, y + 0.05, x + 0.25 + k * 0.25, y + h - 0.05], 0.03, 0xFF5D637C);
		circle(c, x + 0.5, y + h - 0.15, 0.06, 0xFF7A80A0);
	}

	// its home: an empty cocoon hung from above, an ember that wakes
	function cocoon(c:Painter, t:Float) {
		var x = home.i + 0.5, y = home.j;
		var top = home.j + 1;
		while (top < board.rows && !board.stone(home.i, top))
			top++;
		line(c, [x, y + 0.9, x, top], 0.03, 0xFF6E6A5A);
		glow(c, x, y + 0.6, 0.6 + wake * 0.8, alpha(HOME, 0.25 + 0.1 * Math.sin(t * 2) + wake * 0.5));
		path.clear();
		path.ellipse(x, y + 0.58, 0.2, 0.34, 0, 0, Math.PI * 2);
		c.fill(path, Paint.solid(mix(0xFF5A4630, HOME, 0.35 + 0.65 * wake)));
		for (k in 0...3)
			line(c, [x - 0.18, y + 0.4 + k * 0.17, x + 0.18, y + 0.46 + k * 0.17], 0.025, alpha(0xFF2A2014, 0.7));
		circle(c, x, y + 0.5, 0.06 + wake * 0.04, mix(0xFFFF8A3C, 0xFFFFF0C0, wake));
	}

	// the caterpillar: a row of round segments, its head the way it goes,
	// curled asleep in the dark
	function caterpillar(c:Painter, t:Float) {
		if (solved && wake >= 1) return;
		var n = next, u = n == null ? 0 : smooth(walk);
		var x = at.i + 0.5, y = at.j * 1.0;
		var dir = 1;
		if (n != null) {
			x += (n.i - at.i) * u;
			y += (n.j - at.j) * u + Math.sin(u * Math.PI) * (n.j != at.j ? 0.25 : 0.05);
			dir = n.i > at.i ? 1 : -1;
		} else if (plan.length > 1) dir = plan[1].i > at.i ? 1 : -1;
		var shade = 0.45 + 0.55 * Math.min(1, shine(x, y + 0.3) * 1.6);
		var body = mix(0xFF2C3320, 0xFFD8E6B0, shade);
		var a = awake;
		if (solved) {
			x = home.i + 0.5;
			y = home.j + 0.3 * wake;
		}
		for (k in 0...6) {
			var o = 5 - k;
			// (awake: in a row, a hump running along it; asleep: wound round)
			var hump = Math.max(0, Math.sin(t * 7 - o * 0.9)) * 0.05 * (n != null ? 1 : 0.3);
			var sx = x - dir * o * 0.11 * a + Math.cos(o * 1.05) * 0.14 * (1 - a);
			var sy = y + 0.1 + hump * a + (Math.sin(o * 1.05) * 0.1 + 0.08) * (1 - a);
			circle(c, sx, sy, k == 5 ? 0.095 : 0.08, k == 5 ? mix(body, 0xFF101208, 0.5) : body);
		}
		var hx = x, hy = y + 0.1;
		if (a > 0.5) {
			circle(c, hx + dir * 0.04, hy + 0.03, 0.022, 0xFFFFFFFF);
			line(c, [hx + dir * 0.03, hy + 0.08, hx + dir * 0.08, hy + 0.17], 0.02, body);
		} else {
			for (k in 0...2)
				circle(c, x + 0.24 + k * 0.08, y + 0.4 + k * 0.1 + 0.02 * Math.sin(t * 2 + k), 0.025 + k * 0.01, alpha(0xFFE8F0C8, 0.4));
		}
	}

	static inline function smooth(u:Float):Float
		return u * u * (3 - 2 * u);
}
