package hxmc.text;

// Grapheme clusters, the steps a caret takes (UAX #29's rules, simplified):
// a character with what extends it (nonspacing and enclosing marks,
// variation selectors, emoji modifiers, tags, a zero width joiner and the
// pictograph it joins), regional indicators in pairs (a flag), Hangul's
// jamo as syllables, CR LF; spacing marks (Indic vowel signs) are not
// joined yet.
class Grapheme {
	// the boundary after the cluster at i
	public static function next(s:String, i:Int):Int {
		var n = s.length;
		if (i >= n) return n;
		// (from the line's start: regional indicators pair from there)
		var j = lineStart(s, i);
		while (j <= i)
			j = step(s, j);
		return j;
	}

	// the boundary before the cluster that ends at or contains i - 1
	public static function prev(s:String, i:Int):Int {
		if (i <= 0) return 0;
		var j = lineStart(s, i - 1), last = j;
		while (j < i) {
			last = j;
			j = step(s, j);
		}
		return last;
	}

	// whether i is a boundary
	public static function isBoundary(s:String, i:Int):Bool {
		if (i <= 0 || i >= s.length) return true;
		var j = lineStart(s, i - 1);
		while (j < i)
			j = step(s, j);
		return j == i;
	}

	static function lineStart(s:String, i:Int):Int {
		var j = i;
		while (j > 0 && s.charCodeAt(j - 1) != 10)
			j--;
		return j;
	}

	// the end of the cluster that starts at i
	static function step(s:String, i:Int):Int {
		var n = s.length;
		var a = at(s, i), j = i + size(s, i);
		if (a == 13) return j < n && s.charCodeAt(j) == 10 ? j + 1 : j;
		if (a == 10) return j;
		var ri = isRegional(a) ? 1 : 0, pict = isPictographic(a);
		while (j < n) {
			var b = at(s, j);
			if (b == 10 || b == 13) break;
			var joins = extends_(b) || hangul(a, b) || (a == 0x200D && pict && isPictographic(b)) || (ri == 1 && isRegional(b));
			if (!joins) break;
			if (isRegional(b)) ri++;
			if (isPictographic(b)) pict = true;
			a = b;
			j += size(s, j);
		}
		return j;
	}

	// (the units of the character at i: 2 for a surrogate pair, where strings are UTF-16)
	static inline function size(s:String, i:Int):Int
		return StringTools.fastCodeAt(s, i) < 0x10000 && at(s, i) >= 0x10000 ? 2 : 1;

	static function at(s:String, i:Int):Int {
		var c = StringTools.fastCodeAt(s, i);
		if (c >= 0xD800 && c < 0xDC00 && i + 1 < s.length) {
			var d = StringTools.fastCodeAt(s, i + 1);
			if (d >= 0xDC00 && d < 0xE000) return 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00);
		}
		return c;
	}

	// a character that joins the one before it
	static function extends_(c:Int):Bool
		return c == 0x200D || c == 0x200C || c >= 0x20D0 && c <= 0x20F0 || isModifier(c) || c >= 0xE0020 && c <= 0xE007F || c >= 0x300 && Bidi.classOf(c) == Bidi.NSM;

	static inline function isModifier(c:Int):Bool
		return c >= 0x1F3FB && c <= 0x1F3FF;

	static inline function isRegional(c:Int):Bool
		return c >= 0x1F1E6 && c <= 0x1F1FF;

	// (Extended_Pictographic, its main blocks)
	static function isPictographic(c:Int):Bool
		return c >= 0x1F000 && c <= 0x1FAFF && !isRegional(c) && !isModifier(c) || c >= 0x2600 && c <= 0x27BF || c >= 0x2300 && c <= 0x23FF
			|| c >= 0x2B00 && c <= 0x2BFF || c == 0xA9 || c == 0xAE || c == 0x203C || c == 0x2049 || c == 0x2122 || c == 0x2139 || c >= 0x2194 && c <= 0x21AA
			|| c == 0x3030 || c == 0x303D || c == 0x3297 || c == 0x3299;

	// Hangul: L joins L, V and syllables; V and LV join V and T; T and LVT join T
	static function hangul(a:Int, b:Int):Bool {
		var x = jamo(a), y = jamo(b);
		if (x == 0 || y == 0) return false;
		return x == L && (y == L || y == V || y == LV || y == LVT) || (x == V || x == LV) && (y == V || y == T) || (x == T || x == LVT) && y == T;
	}

	static inline var L = 1;
	static inline var V = 2;
	static inline var T = 3;
	static inline var LV = 4;
	static inline var LVT = 5;

	static function jamo(c:Int):Int {
		if (c >= 0x1100 && c <= 0x115F || c >= 0xA960 && c <= 0xA97C) return L;
		if (c >= 0x1160 && c <= 0x11A7 || c >= 0xD7B0 && c <= 0xD7C6) return V;
		if (c >= 0x11A8 && c <= 0x11FF || c >= 0xD7CB && c <= 0xD7FB) return T;
		if (c >= 0xAC00 && c <= 0xD7A3) return (c - 0xAC00) % 28 == 0 ? LV : LVT;
		return 0;
	}
}
