package helder.ui.access;

// The units assistive technology reads a text input's text by (UI
// Automation's TextUnit, NSAccessibility's ranges, Android's movement
// granularities), in UTF-16 indices as AccessNode's caret and selection:
// characters (a surrogate pair one), words with the spaces after them,
// lines and paragraphs through their line break, the whole.
enum abstract TextUnit(Int) {
	var Character;
	var Word;
	var Line;
	var Paragraph;
	var Document;
}

class TextUnits {
	// the text's pieces of a unit, [start, end) ranges covering it (one, empty, for no text)
	public static function pieces(s:String, unit:TextUnit):Array<Array<Int>> {
		var out = [], i = 0, n = s.length;
		inline function space(c:Int)
			return c == " ".code || c == "\t".code || c == "\n".code;
		while (i < n) {
			var end = i;
			switch unit {
				case Character:
					var c = s.charCodeAt(i);
					end = i + (c >= 0xD800 && c < 0xDC00 && i + 1 < n ? 2 : 1);
				case Word:
					while (end < n && !space(s.charCodeAt(end)))
						end++;
					while (end < n && space(s.charCodeAt(end)))
						end++;
				case Line | Paragraph:
					while (end < n && s.charCodeAt(end) != "\n".code)
						end++;
					if (end < n) end++;
				case Document:
					end = n;
			}
			if (end <= i) end = i + 1;
			out.push([i, end]);
			i = end;
		}
		if (out.length == 0) out.push([0, 0]);
		return out;
	}

	// the index of the piece holding i (the text's end: the last)
	static function index(ps:Array<Array<Int>>, i:Int):Int {
		for (k in 0...ps.length)
			if (i < ps[k][1]) return k;
		return ps.length - 1;
	}

	// the piece holding i
	public static function at(s:String, i:Int, unit:TextUnit):Array<Int> {
		var ps = pieces(s, unit);
		return ps[index(ps, i)];
	}

	// a range moved by count units (UI Automation's Move): onto that unit,
	// or kept empty at its start when it was empty; how many it moved
	public static function move(s:String, start:Int, end:Int, unit:TextUnit, count:Int):{start:Int, end:Int, moved:Int} {
		var ps = pieces(s, unit), k = index(ps, start);
		// (back from inside a unit: its start is the first step)
		var target = count < 0 && start > ps[k][0] ? k + count + 1 : k + count;
		if (target < 0) target = 0;
		if (target >= ps.length) target = ps.length - 1;
		var moved = target - k + (count < 0 && start > ps[k][0] ? -1 : 0);
		if (count < 0 && moved < count) moved = count;
		var p = ps[target];
		return end > start ? {start: p[0], end: p[1], moved: moved} : {start: p[0], end: p[0], moved: moved};
	}

	// an endpoint moved by count units' boundaries (MoveEndpointByUnit); how many it moved
	public static function moveBoundary(s:String, at:Int, unit:TextUnit, count:Int):{at:Int, moved:Int} {
		var bounds = [for (p in pieces(s, unit)) p[0]];
		if (bounds[bounds.length - 1] != s.length) bounds.push(s.length);
		var moved = 0;
		while (count > 0) {
			var next = -1;
			for (b in bounds)
				if (b > at) {
					next = b;
					break;
				}
			if (next < 0) break;
			at = next;
			moved++;
			count--;
		}
		while (count < 0) {
			var prev = -1;
			var i = bounds.length;
			while (i-- > 0)
				if (bounds[i] < at) {
					prev = bounds[i];
					break;
				}
			if (prev < 0) break;
			at = prev;
			moved--;
			count++;
		}
		return {at: at, moved: moved};
	}
}
