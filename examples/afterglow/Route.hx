import Board;

// The moth's way over a board: the cells it can reach (open: what it may
// fly through, decided by the prototype), a path to the reachable cell
// nearest a target, and the moth led along it, cutting across where the
// line is clear. A press anywhere leads it there, round what is in its
// way, or as near as it can get.
class Route {
	final board:Board;
	final moth:Flight;
	final open:(i:Int, j:Int) -> Bool;
	var path:Array<Cell> = [];
	var aim:Null<{x:Float, y:Float}> = null;

	public function new(board:Board, moth:Flight, open:(i:Int, j:Int) -> Bool) {
		this.board = board;
		this.moth = moth;
		this.open = open;
	}

	public function cell():Cell
		return {i: Math.floor(moth.x), j: Math.floor(moth.y)};

	// a path to the reachable cell nearest to: the one it reached
	public function to(target:Cell):Cell {
		var from = cell(), cols = board.cols;
		var before = new Map<Int, Int>(), queue = [from], best = from, bestFar = far(from, target);
		before.set(from.i + from.j * cols, -1);
		while (queue.length > 0) {
			var c = queue.shift();
			var e = far(c, target);
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
		// (where it is already: a tap on its own cell, or nowhere nearer)
		path = cells.length == 0 ? [from] : cells;
		aim = null;
		return best;
	}

	public static function far(a:Cell, b:Cell):Float
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

	// along the way, each step: to the farthest of its cells in a clear line
	public function follow() {
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
}
