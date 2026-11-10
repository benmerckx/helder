import Ground;
import Puzzle.Vec;

// A greybox screen's grid: its map (rows from the top; '#' stone, any
// other letter a thing in that cell), cells one unit wide, y up. The moth
// stands on what is solid below it (floor: a cell's standing height, null
// where it falls through).
class Board implements Ground {
	public final cols:Int;
	public final rows:Int;
	final map:Array<String>;
	// what the moth cannot pass (stone; a greybox adds shut gates) and what
	// else it stands on (a perch, a lantern: its height)
	public var solid:(i:Int, j:Int) -> Bool;
	public var stand:(i:Int, j:Int) -> Null<Float> = (i, j) -> null;

	public function new(map:Array<String>) {
		this.map = map;
		rows = map.length;
		cols = map[0].length;
		solid = stone;
	}

	// the letter at a cell (i from the left, j from the bottom); '#' outside
	public function at(i:Int, j:Int):String {
		if (i < 0 || j < 0 || i >= cols || j >= rows) return '#';
		return map[rows - 1 - j].charAt(i);
	}

	// every cell with that letter, in reading order (top row first)
	public function find(letter:String):Array<Cell> {
		var out:Array<Cell> = [];
		for (r in 0...rows)
			for (i in 0...cols)
				if (map[r].charAt(i) == letter) out.push({i: i, j: rows - 1 - r});
		return out;
	}

	public function stone(i:Int, j:Int):Bool
		return at(i, j) == '#';

	public function floor(i:Int, j:Int):Null<Float>
		return solid(i, j) ? j + 1 : stand(i, j);

	public function ground(x:Float, y:Float):Null<Vec> {
		var i = Math.floor(x), j = Math.floor(y);
		while (j >= 0) {
			var f = floor(i, j);
			if (f != null && f <= y + 0.05) return {x: x, y: f, z: Puzzle.FLY};
			j--;
		}
		return null;
	}

	public function flat(x:Float, y:Float, z:Float):Vec
		return {x: x, y: y, z: Puzzle.FLY};

	public function bounds() {
		return {left: 0.3, bottom: 0.3, right: cols - 0.3, top: rows - 0.3};
	}
}

typedef Cell = {i:Int, j:Int};
