package hxmc.ui;

// CSS grid's values for Style (Display Grid): track sizes and lists, the
// lines an item spans, the direction auto-placement fills. Parsed from
// CSS's text: "1fr 200px auto", "repeat(3, minmax(80px, 1fr))", "1 / 3",
// "span 2", "2 / span 3".

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
// negative from the explicit grid's end; 0: auto) or a span
class GridPlacement {
	public static final AUTO = new GridPlacement(0, 0, 1);

	public final start:Int;
	public final end:Int;
	public final span:Int;

	public function new(start:Int, end:Int, span:Int) {
		this.start = start;
		this.end = end;
		this.span = span < 1 ? 1 : span;
	}

	// "auto", "2", "2 / 4", "1 / -1", "span 2", "2 / span 3", "span 2 / 5"
	public static function parse(s:String):GridPlacement {
		var parts = [for (p in StringTools.trim(s).split("/")) StringTools.trim(p)];
		var start = 0, end = 0, span = 1;
		function line(p:String, isEnd:Bool) {
			if (p == "" || p == "auto") return;
			if (StringTools.startsWith(p, "span")) {
				var n = Std.parseInt(StringTools.trim(p.substr(4)));
				span = n == null ? 1 : n;
				return;
			}
			var n = Std.parseInt(p);
			if (n == null || n == 0) throw "hxmc.ui: " + p + " is not a grid line";
			if (isEnd) end = n else start = n;
		}
		line(parts[0], false);
		if (parts.length > 1) line(parts[1], true);
		return new GridPlacement(start, end, span);
	}

	public function toString():String
		return '$start/$end span $span';
}

enum abstract GridFlow(Int) {
	var Row;
	var Column;
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

	public static function size(w:String):TrackSize {
		w = StringTools.trim(w).toLowerCase();
		if (w == "auto") return Auto;
		if (w == "min-content") return MinContent;
		if (w == "max-content") return MaxContent;
		if (StringTools.endsWith(w, "fr")) return Fr(Std.parseFloat(w));
		if (StringTools.endsWith(w, "%")) return Percent(Std.parseFloat(w));
		var v = Std.parseFloat(StringTools.replace(w, "px", ""));
		if (Math.isNaN(v)) throw "hxmc.ui: " + w + " is not a track size";
		return Px(v);
	}
}
