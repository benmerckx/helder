package helder.ui;

// CSS grid's values for Style (Display Grid): track sizes and lists, the
// lines an item spans, the direction auto-placement fills, named areas.
// Parsed from CSS's text: "1fr 200px auto", "repeat(3, minmax(80px, 1fr))",
// "1 / 3", "span 2", "2 / span 3", "header", "'head head' 'side main'".

// a track's sizing function: a length, a percentage of the grid's size, a
// share of the free space (fr), or by its items' content
enum TrackSize {
	Px(v:Float);
	Percent(p:Float);
	Fr(f:Float);
	Auto;
	MinContent;
	MaxContent;
}

// a track: its minimum and maximum sizing functions (minmax(min, max); one
// size is both, a flexible one's minimum auto)
class Track {
	public static final AUTO = new Track(Auto, Auto);

	public final min:TrackSize;
	public final max:TrackSize;

	public function new(min:TrackSize, max:TrackSize) {
		this.min = min;
		this.max = max;
	}

	public static function of(s:TrackSize):Track
		return switch s {
			case Fr(_): new Track(Auto, s);
			case _: new Track(s, s);
		}

	public function toString():String
		return '$min..$max';
}

// the lines an item spans on one axis: start and end lines (1-based, or
// negative from the explicit grid's end; 0: auto) or a span; or lines by
// name: an area's (its start line for the start, its end line for the end;
// "name-start", "name-end" either one), a name no area has the first line
// past the explicit grid (as CSS's implicit lines all have it)
class GridPlacement {
	public static final AUTO = new GridPlacement(0, 0, 1);

	public final start:Int;
	public final end:Int;
	public final span:Int;
	public final startName:Null<String>;
	public final endName:Null<String>;

	public function new(start:Int, end:Int, span:Int, ?startName:String, ?endName:String) {
		this.start = start;
		this.end = end;
		this.span = span < 1 ? 1 : span;
		this.startName = startName;
		this.endName = endName;
	}

	// "auto", "2", "2 / 4", "1 / -1", "span 2", "2 / span 3", "span 2 / 5",
	// "header" (its area's lines), "a / b"
	public static function parse(s:String):GridPlacement {
		var parts = [for (p in StringTools.trim(s).split("/")) StringTools.trim(p)];
		var start = 0, end = 0, span = 1, startName:String = null, endName:String = null;
		function line(p:String, isEnd:Bool) {
			if (p == "" || p == "auto") return;
			if (StringTools.startsWith(p, "span")) {
				var n = Std.parseInt(StringTools.trim(p.substr(4)));
				if (n == null) throw "helder.ui: " + p + " is not a grid span (no named lines)";
				span = n;
				return;
			}
			if (Grid.isName(p)) {
				if (isEnd) endName = p else startName = p;
				return;
			}
			var n = Std.parseInt(p);
			if (n == null || n == 0) throw "helder.ui: " + p + " is not a grid line";
			if (isEnd) end = n else start = n;
		}
		line(parts[0], false);
		if (parts.length > 1) line(parts[1], true);
		// (one name: the end its area's end too)
		else if (startName != null) endName = startName;
		return new GridPlacement(start, end, span, startName, endName);
	}

	public function toString():String
		return (startName ?? '$start') + "/" + (endName ?? '$end') + ' span $span';
}

// the explicit grid's named areas (grid-template-areas): its size in
// columns and rows, each name's rectangle (lines from 0, ends exclusive)
class GridAreas {
	public final columns:Int;
	public final rows:Int;
	public final areas:Map<String, {col:Int, row:Int, colEnd:Int, rowEnd:Int}>;

	public function new(columns, rows, areas) {
		this.columns = columns;
		this.rows = rows;
		this.areas = areas;
	}

	// CSS's strings, one a row: "'head head' 'side main'" (either quotes;
	// "." an unnamed cell); every row as many cells, each name a rectangle
	public static function parse(s:String):GridAreas {
		var rows:Array<Array<String>> = [], i = 0;
		while (i < s.length) {
			var q = s.charAt(i++);
			if (q != '"' && q != "'") {
				if (!StringTools.isSpace(q, 0)) throw "helder.ui: grid areas are quoted rows: " + s;
				continue;
			}
			var close = s.indexOf(q, i);
			if (close < 0) throw "helder.ui: an unclosed row in grid areas: " + s;
			var cells = [], start = i;
			for (k in i...close + 1)
				if (k == close || StringTools.isSpace(s, k)) {
					if (k > start) cells.push(s.substring(start, k));
					start = k + 1;
				}
			if (cells.length == 0 || rows.length > 0 && cells.length != rows[0].length) throw "helder.ui: grid areas' rows of different lengths: " + s;
			rows.push(cells);
			i = close + 1;
		}
		var areas = new Map<String, {col:Int, row:Int, colEnd:Int, rowEnd:Int}>();
		for (r in 0...rows.length)
			for (c in 0...rows[r].length) {
				var name = rows[r][c];
				// (a run of dots: no area)
				if (StringTools.replace(name, ".", "") == "") continue;
				var a = areas.get(name);
				if (a == null) areas.set(name, {col: c, row: r, colEnd: c + 1, rowEnd: r + 1}) else {
					if (c >= a.colEnd) a.colEnd = c + 1;
					if (r >= a.rowEnd) a.rowEnd = r + 1;
				}
			}
		for (name => a in areas)
			for (r in a.row...a.rowEnd)
				for (c in a.col...a.colEnd)
					if (rows[r][c] != name) throw "helder.ui: grid area " + name + " is not a rectangle";
		return new GridAreas(rows.length == 0 ? 0 : rows[0].length, rows.length, areas);
	}
}

// how auto-placed items fill the grid (CSS's grid-auto-flow): by rows or
// by columns; dense, each from the grid's start (filling holes earlier
// items left), not after the one before (markup: "row dense", "dense")
enum abstract GridFlow(Int) {
	var Row;
	var Column;
	var RowDense;
	var ColumnDense;
}

class Grid {
	// a track list: sizes, minmax(), repeat(n, ...)
	public static function tracks(s:String):Array<Track> {
		var out:Array<Track> = [];
		var i = 0, n = s.length;
		function skip()
			while (i < n && StringTools.isSpace(s, i))
				i++;
		// up to a delimiter (consumed for ","; left for ")")
		function word(end:String):String {
			var start = i;
			while (i < n && s.charAt(i) != end)
				i++;
			var w = s.substring(start, i);
			if (end == "," && i < n) i++;
			return StringTools.trim(w);
		}
		// one term: a size or minmax(a, b)
		function term():Array<Track> {
			skip();
			if (s.substr(i, 7) == "minmax(") {
				i += 7;
				var a = word(","), b = word(")");
				i++;
				return [new Track(size(a), size(b))];
			}
			if (s.substr(i, 7) == "repeat(") {
				i += 7;
				var count = Std.parseInt(StringTools.trim(word(",")));
				i++;
				var inner:Array<Track> = [];
				skip();
				while (i < n && s.charAt(i) != ")") {
					inner = inner.concat(term());
					skip();
				}
				i++;
				var r = [];
				for (_ in 0...(count == null ? 1 : count))
					r = r.concat(inner);
				return r;
			}
			var start = i;
			while (i < n && !StringTools.isSpace(s, i) && s.charAt(i) != ")")
				i++;
			return [Track.of(size(s.substring(start, i)))];
		}
		skip();
		while (i < n) {
			out = out.concat(term());
			skip();
		}
		return out;
	}

	// a custom identifier (an area's or a line's name), not a number or keyword
	public static function isName(p:String):Bool {
		if (p == "" || p == "auto" || p == "span") return false;
		var c = p.charCodeAt(0);
		return !(c >= "0".code && c <= "9".code || c == "-".code || c == "+".code);
	}

	// grid-area: "name" (its area on both axes), else "row-start /
	// column-start / row-end / column-end", the ends left out a name's or auto
	public static function area(s:String):{row:GridPlacement, column:GridPlacement} {
		var p = [for (x in StringTools.trim(s).split("/")) StringTools.trim(x)];
		var rowStart = p[0];
		var colStart = p.length > 1 ? p[1] : isName(rowStart) ? rowStart : "auto";
		var rowEnd = p.length > 2 ? p[2] : isName(rowStart) ? rowStart : "auto";
		var colEnd = p.length > 3 ? p[3] : isName(colStart) ? colStart : "auto";
		return {row: GridPlacement.parse(rowStart + " / " + rowEnd), column: GridPlacement.parse(colStart + " / " + colEnd)};
	}

	public static function size(w:String):TrackSize {
		w = StringTools.trim(w).toLowerCase();
		if (w == "auto") return Auto;
		if (w == "min-content") return MinContent;
		if (w == "max-content") return MaxContent;
		if (StringTools.endsWith(w, "fr")) return Fr(Std.parseFloat(w));
		if (StringTools.endsWith(w, "%")) return Percent(Std.parseFloat(w));
		var v = Std.parseFloat(StringTools.replace(w, "px", ""));
		if (Math.isNaN(v)) throw "helder.ui: " + w + " is not a track size";
		return Px(v);
	}
}
