import Board;
import Play;
import Sketch.*;
import helder.canvas.Painter;

// Prototype B, the moth alone opens its way: it must reach the screen's
// exit, through stone it cannot pass, shut gates and dark passages it
// will not fly into. Tap a lever or a lamp: the moth flies to it and pulls
// it (or flies as near as it can, and the lever shakes: out of reach).
// A lever flips every gate wired to it (dashed lines in its colour: one
// may open a gate and shut another); a lamp lights its dark passage, or
// puts it out. A press anywhere else leads the moth there, round what is
// in its way.
//
// A map's letters: M the moth, E the exit, A B C gates (shut; a b c open),
// 1 2 3 levers, k a lamp, d its dark passage; links: what each flips.
typedef WayScreen = {name:String, hint:String, map:Array<String>, links:Map<String, String>};

private typedef Gate = {id:String, cell:Cell, open:Bool, shown:Float, across:Bool};
private typedef Mech = {key:String, cell:Cell, on:Bool, shown:Float, pulse:Float, shake:Float};

class Way implements Play {
	public static final screens:Array<WayScreen> = [
		{
			name: "Lamp and lever",
			hint: "Tap the lamp, then the lever.",
			links: ["k" => "d", "1" => "A"],
			map: [
				"#######",
				"#...#E#",
				"#.1.#.#",
				"#...A.#",
				"##d####",
				"#.....#",
				"#.....#",
				"#M..k.#",
				"#######"
			]
		},
		{
			name: "One lever, two gates",
			hint: "A lever can shut a gate as it opens one.",
			links: ["1" => "AB", "2" => "B"],
			map: [
				"#######",
				"##E.###",
				"###b###",
				"###..2#",
				"###A###",
				"#...1.#",
				"#.#####",
				"#M....#",
				"#######"
			]
		},
		{
			name: "Three rooms",
			hint: "Each lever moves two gates.",
			links: ["1" => "AC", "2" => "BA", "3" => "CB"],
			map: [
				"#######",
				"#E.c.3#",
				"#####.#",
				"#2..B.#",
				"##A####",
				"#.....#",
				"#.###1#",
				"#M....#",
				"#######"
			]
		}
	];

	static final COLORS = ["1" => 0xFFFFB347, "2" => 0xFF6FD6E8, "3" => 0xFFFF7FBF, "k" => 0xFFFFD27A];

	public var board(default, null):Board;
	public var moth(default, null):Flight;
	public var solved(default, null) = false;
	public var events(default, null):Array<String> = [];
	final screen:WayScreen;
	final gates:Array<Gate> = [];
	final mechs:Array<Mech> = [];
	final dark:Array<Cell>;
	final exit:Cell;
	var lit = false;
	var light = 0.0;
	var path:Array<Cell> = [];
	var aim:Null<{x:Float, y:Float}> = null;
	var pending:Null<Mech> = null;
	var pressed:Null<Cell> = null;
	var time = 0.0;
	var wake = 0.0;

	public function new(k:Int) {
		screen = screens[k];
		board = new Board(screen.map);
		for (r in 0...board.rows)
			for (i in 0...board.cols) {
				var l = screen.map[r].charAt(i), cell = {i: i, j: board.rows - 1 - r};
				if ("ABCabc".indexOf(l) >= 0) {
					var open = l.toLowerCase() == l;
					gates.push({id: l.toUpperCase(), cell: cell, open: open, shown: open ? 1 : 0,
						across: board.stone(cell.i - 1, cell.j) && board.stone(cell.i + 1, cell.j)});
				}
				if ("123k".indexOf(l) >= 0) mechs.push({key: l, cell: cell, on: false, shown: 0, pulse: 0, shake: 0});
			}
		dark = board.find("d");
		exit = board.find("E")[0];
		var m = board.find("M")[0];
		moth = new Flight(m.i + 0.5, m.j + Flight.FEET, Puzzle.FLY);
		moth.bounds = board.bounds();
		board.solid = (i, j) -> board.stone(i, j) || shut(i, j);
		// (it will not fly into the dark: it stands at its edge)
		board.stand = (i, j) -> !lit && board.at(i, j) == "d" ? j + 1 : null;
	}

	function shut(i:Int, j:Int):Bool {
		for (g in gates)
			if (!g.open && g.cell.i == i && g.cell.j == j) return true;
		return false;
	}

	function open(i:Int, j:Int):Bool
		return !board.solid(i, j) && (lit || board.at(i, j) != "d");

	public function step(dt:Float) {
		time += dt;
		follow();
		moth.step(dt, board);
		var here = cell();
		var p = pending;
		if (p != null && here.i == p.cell.i && here.j == p.cell.j && Math.abs(moth.x - p.cell.i - 0.5) < 0.4) {
			pending = null;
			act(p);
		}
		if (!solved && here.i == exit.i && here.j == exit.j) {
			solved = true;
			events.push("solved");
		}
		for (g in gates)
			g.shown += ((g.open ? 1 : 0) - g.shown) * (1 - Math.exp(-dt * 7));
		for (m in mechs) {
			m.shown += ((m.on ? 1 : 0) - m.shown) * (1 - Math.exp(-dt * 12));
			m.pulse = Math.max(0, m.pulse - dt * 1.5);
			m.shake = Math.max(0, m.shake - dt * 2.5);
		}
		light += ((lit ? 1 : 0) - light) * (1 - Math.exp(-dt * 6));
		if (solved) wake = Math.min(1, wake + dt / 1.2);
	}

	function cell():Cell
		return {i: Math.floor(moth.x), j: Math.floor(moth.y)};

	function act(m:Mech) {
		m.on = !m.on;
		m.pulse = 1;
		for (t in screen.links.get(m.key).split(""))
			if (t == "d") lit = !lit;
			else for (g in gates)
				if (g.id == t) g.open = !g.open;
		events.push('pulled ${m.key}');
	}

	// ---- the way: cells the moth can reach, and a line it can fly

	function route(to:Cell) {
		var from = cell(), cols = board.cols;
		var before = new Map<Int, Int>(), queue = [from], best = from, bestFar = far(from, to);
		before.set(from.i + from.j * cols, -1);
		while (queue.length > 0) {
			var c = queue.shift();
			var e = far(c, to);
			if (e < bestFar - 0.001) {
				best = c;
				bestFar = e;
			}
			for (d in [[0, 1], [1, 0], [0, -1], [-1, 0], [1, 1], [1, -1], [-1, 1], [-1, -1]]) {
				var n = {i: c.i + d[0], j: c.j + d[1]}, key = n.i + n.j * cols;
				if (before.exists(key) || !open(n.i, n.j)) continue;
				if (d[0] != 0 && d[1] != 0 && (!open(c.i + d[0], c.j) || !open(c.i, c.j + d[1]))) continue;
				before.set(key, c.i + c.j * cols);
				queue.push(n);
			}
		}
		var cells:Array<Cell> = [], k = best.i + best.j * cols;
		while (k != from.i + from.j * cols) {
			cells.unshift({i: k % cols, j: Std.int(k / cols)});
			k = before.get(k);
		}
		path = cells;
		if (cells.length == 0) {
			// (where it is already: a tap on its own cell, or nowhere nearer)
			path = [from];
		}
		aim = null;
		return best;
	}

	static function far(a:Cell, b:Cell):Float
		return Math.sqrt(Math.pow(a.i - b.i, 2) + Math.pow(a.j - b.j, 2));

	function clear(x0:Float, y0:Float, x1:Float, y1:Float):Bool {
		var n = Std.int(Math.max(1, Math.sqrt(Math.pow(x1 - x0, 2) + Math.pow(y1 - y0, 2)) / 0.1));
		for (k in 0...n + 1) {
			var x = x0 + (x1 - x0) * k / n, y = y0 + (y1 - y0) * k / n;
			for (o in [[-0.2, -0.2], [0.2, -0.2], [-0.2, 0.2], [0.2, 0.2]])
				if (!open(Math.floor(x + o[0]), Math.floor(y + o[1]))) return false;
		}
		return true;
	}

	// along the way: to the farthest of its cells in a clear line
	function follow() {
		if (path.length == 0) return;
		var far = 0;
		for (k in 0...path.length)
			if (clear(moth.x, moth.y, path[k].i + 0.5, path[k].j + 0.5)) far = k;
		if (far > 0) path.splice(0, far);
		var c = path[0], x = c.i + 0.5, y = c.j + 0.5;
		if (path.length > 1 && Math.abs(moth.x - x) < 0.3 && Math.abs(moth.y - y) < 0.3) {
			path.shift();
			c = path[0];
			x = c.i + 0.5;
			y = c.j + 0.5;
		}
		var a = aim;
		if (a == null || a.x != x || a.y != y) {
			aim = {x: x, y: y};
			moth.lead(x, y);
		}
		if (path.length == 1 && Math.abs(moth.x - x) < 0.1 && Math.abs(moth.y - y) < 0.1) path = [];
	}

	// ---- touch

	public function down(x:Float, y:Float) {
		var at = {i: Math.floor(x), j: Math.floor(y)};
		pending = null;
		for (m in mechs)
			if (Math.abs(x - m.cell.i - 0.5) < 0.62 && Math.abs(y - m.cell.j - 0.5) < 0.62) {
				var reached = route(m.cell);
				if (reached.i == m.cell.i && reached.j == m.cell.j) pending = m;
				else m.shake = 1;
				return;
			}
		pressed = at;
		moth.held = true;
		route(at);
	}

	public function move(x:Float, y:Float) {
		var p = pressed;
		if (p == null) return;
		var at = {i: Math.floor(x), j: Math.floor(y)};
		if (at.i == p.i && at.j == p.j) return;
		pressed = at;
		route(at);
	}

	public function up() {
		pressed = null;
		moth.held = false;
	}

	// ---- drawing (world units, y up)

	public function draw(c:Painter, t:Float) {
		Sketch.stones(c, board);
		for (d in dark) {
			var x = d.i, y = d.j;
			box(c, x, y, 1, 1, mix(0xFF050609, 0xFF3A2E1C, light));
			if (light < 0.5)
				for (k in 0...4)
					line(c, [x + 0.1 + k * 0.25, y + 0.1, x + k * 0.25 - 0.05, y + 0.9], 0.03, 0x40FFFFFF);
			else glow(c, x + 0.5, y + 0.5, 0.8, alpha(0xFFFFD27A, 0.5 * light));
		}
		var ex = exit.i + 0.5, ey = exit.j;
		glow(c, ex, ey + 0.5, 0.9 + wake, alpha(0xFFBFE8FF, 0.45 + 0.1 * Math.sin(t * 2) + wake * 0.5));
		arch(c, ex, ey);
		for (m in mechs) {
			var color = COLORS.get(m.key);
			for (target in screen.links.get(m.key).split("")) {
				var to = target == "d" ? nearest(dark, m.cell) : [for (g in gates) if (g.id == target) g.cell][0];
				line(c, [m.cell.i + 0.5, m.cell.j + 0.5, to.i + 0.5, to.j + 0.5], 0.035 + m.pulse * 0.05, alpha(color, 0.18 + m.pulse * 0.7), 0.1,
					-t * 0.4);
			}
		}
		for (g in gates)
			drawGate(c, g, t);
		for (m in mechs) {
			var color = COLORS.get(m.key), x = m.cell.i + 0.5 + Math.sin(t * 40) * 0.06 * m.shake, y = m.cell.j;
			ring(c, x, y + 0.45, 0.42 + 0.04 * Math.sin(t * 2.8), 0.03, alpha(color, 0.3 + 0.2 * Math.sin(t * 2.8) + m.pulse * 0.5));
			if (m.key == "k") {
				box(c, x - 0.25, y, 0.5, 0.12, 0xFF6E7391, 0.04);
				poly(c, [x - 0.3, y + 0.3, x + 0.3, y + 0.3, x + 0.15, y + 0.12, x - 0.15, y + 0.12], 0xFF8A8FA8);
				if (light > 0.05) {
					glow(c, x, y + 0.55, 0.7, alpha(color, 0.8 * light));
					poly(c, [x - 0.12, y + 0.3, x + 0.12, y + 0.3, x, y + 0.3 + 0.35 * light], 0xFFFFF0C0);
				} else circle(c, x, y + 0.34, 0.06, alpha(color, 0.6 + 0.3 * Math.sin(t * 3)));
			} else {
				var a = Math.PI / 2 + (0.7 - m.shown * 1.4);
				box(c, x - 0.28, y, 0.56, 0.14, 0xFF6E7391, 0.04);
				line(c, [x, y + 0.12, x + Math.cos(a) * 0.5, y + 0.12 + Math.sin(a) * 0.5], 0.07, 0xFFB7B9C9);
				circle(c, x + Math.cos(a) * 0.5, y + 0.12 + Math.sin(a) * 0.5, 0.11, color);
			}
		}
		Sketch.moth(c, moth, t);
	}

	static function nearest(cells:Array<Cell>, to:Cell):Cell {
		var best = cells[0];
		for (c in cells)
			if (far(c, to) < far(best, to)) best = c;
		return best;
	}

	// the exit: an arch of pale light
	function arch(c:Painter, x:Float, y:Float) {
		var p = new helder.canvas.Path();
		p.moveTo(x - 0.32, y);
		p.lineTo(x - 0.32, y + 0.55);
		p.arc(x, y + 0.55, 0.32, Math.PI, 0, true);
		p.lineTo(x + 0.32, y);
		p.close();
		c.fill(p, helder.canvas.Paint.solid(mix(0xFF9FCBE0, 0xFFFFFFFF, wake)));
		line(c, [x - 0.4, y, x - 0.4, y + 0.55], 0.06, 0xFF7C8199);
		line(c, [x + 0.4, y, x + 0.4, y + 0.55], 0.06, 0xFF7C8199);
	}

	function drawGate(c:Painter, g:Gate, t:Float) {
		var x = g.cell.i, y = g.cell.j, s = g.shown;
		box(c, x, y, 1, 1, 0xFF161927);
		// (bars across the way, drawn back into the stone as it opens)
		for (k in 0...4) {
			var o = 0.14 + k * 0.24;
			if (g.across) line(c, [x - 0.02 + s * 0.95, y + o, x + 1.02, y + o], 0.08, 0xFFA59C86);
			else line(c, [x + o, y + s * 0.95 - 0.02, x + o, y + 1.02], 0.08, 0xFFA59C86);
		}
		var wired = [for (m in mechs) if (screen.links.get(m.key).indexOf(g.id) >= 0) m];
		for (k in 0...wired.length)
			circle(c, x + 0.5 + (k - (wired.length - 1) / 2) * 0.3, y + 0.5, 0.11, COLORS.get(wired[k].key));
	}
}
