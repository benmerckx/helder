package helder.text;

import helder.text.TextLayout.Glyph;

// Arabic shaping: each letter's form from its joining type and its
// neighbours' (Unicode's ArabicShaping: right-joining, dual-joining, join
// causing, transparent marks skipped), the font's GSUB substitutions for
// the forms (the features isol, init, medi, fina of the script arab), then
// its required ligatures (rlig: lam and alef as one glyph, which covers the
// two characters).
class Arabic {
	static inline var U = 0;
	static inline var R = 1;
	static inline var D = 2;
	static inline var C = 3;
	static inline var T = 4;

	public static inline function isArabic(c:Int):Bool
		return c >= 0x600 && c <= 0x6FF || c >= 0x750 && c <= 0x77F || c >= 0x8A0 && c <= 0x8FF;

	public static function joining(c:Int):Int {
		if (c == 0x640 || c == 0x200D) return C;
		if (c >= 0x610 && c <= 0x61A || c >= 0x64B && c <= 0x65F || c == 0x670 || c >= 0x6D6 && c <= 0x6DC || c >= 0x6DF && c <= 0x6E4 || c == 0x6E7
			|| c == 0x6E8 || c >= 0x6EA && c <= 0x6ED || c >= 0x8D3 && c <= 0x8E1 || c >= 0x8E3 && c <= 0x8FF)
			return T;
		if (c >= 0x622 && c <= 0x625 || c == 0x627 || c == 0x629 || c >= 0x62F && c <= 0x632 || c == 0x648 || c >= 0x671 && c <= 0x673
			|| c >= 0x675 && c <= 0x677 || c >= 0x688 && c <= 0x699 || c == 0x6C0 || c >= 0x6C3 && c <= 0x6CB || c == 0x6CD || c == 0x6CF || c == 0x6D2
			|| c == 0x6D3 || c == 0x6D5 || c == 0x6EE || c == 0x6EF || c >= 0x759 && c <= 0x75B || c == 0x76B || c == 0x76C || c == 0x771 || c == 0x773
			|| c == 0x774 || c == 0x778 || c == 0x779 || c >= 0x8AA && c <= 0x8AC || c == 0x8AE || c == 0x8B1 || c == 0x8B2)
			return R;
		if (c == 0x620 || c == 0x626 || c == 0x628 || c >= 0x62A && c <= 0x62E || c >= 0x633 && c <= 0x63F || c >= 0x641 && c <= 0x647 || c == 0x649
			|| c == 0x64A || c == 0x66E || c == 0x66F || c >= 0x678 && c <= 0x687 || c >= 0x69A && c <= 0x6BF || c == 0x6C1 || c == 0x6C2 || c == 0x6CC
			|| c == 0x6CE || c == 0x6D0 || c == 0x6D1 || c >= 0x6FA && c <= 0x6FC || c == 0x6FF || c >= 0x750 && c <= 0x758 || c >= 0x75C && c <= 0x76A
			|| c >= 0x76D && c <= 0x770 || c == 0x772 || c >= 0x775 && c <= 0x777 || c >= 0x77A && c <= 0x77F || c >= 0x8A0 && c <= 0x8A9 || c == 0x8AF
			|| c == 0x8B0 || c >= 0x8B3 && c <= 0x8B4 || c >= 0x8B6 && c <= 0x8C7)
			return D;
		return U;
	}

	// the glyphs (logical order, ids set) with Arabic's forms and ligatures: a new array when a ligature merged glyphs
	public static function shape(gs:Array<Glyph>):Array<Glyph> {
		var any = false;
		for (g in gs)
			if (isArabic(g.cp)) any = true;
		if (!any) return gs;
		var n = gs.length;
		var types = [for (g in gs) isArabic(g.cp) || g.cp == 0x200D ? joining(g.cp) : U];
		for (i in 0...n) {
			var t = types[i];
			if (t != R && t != D) continue;
			var p = i - 1;
			while (p >= 0 && types[p] == T)
				p--;
			var q = i + 1;
			while (q < n && types[q] == T)
				q++;
			var joinsPrev = p >= 0 && (types[p] == D || types[p] == C) && gs[p].font == gs[i].font;
			var joinsNext = t == D && q < n && (types[q] == R || types[q] == D || types[q] == C) && gs[q].font == gs[i].font;
			var form = t == R ? (joinsPrev ? "fina" : "isol") : joinsPrev && joinsNext ? "medi" : joinsPrev ? "fina" : joinsNext ? "init" : "isol";
			var f = gs[i].font;
			for (l in f.gsubLookups("arab", form))
				gs[i].id = f.substitute(l, gs[i].id);
		}
		// the required ligatures, on runs of one face
		var out:Array<Glyph> = [];
		var i = 0;
		while (i < n) {
			var g = gs[i];
			if (isArabic(g.cp)) {
				var f = g.font, merged = false;
				var j = i;
				while (j < n && gs[j].font == f && gs[j].cp != 10)
					j++;
				var ids = [for (k in i...j) gs[k].id];
				for (l in f.gsubLookups("arab", "rlig")) {
					var lig = f.ligature(l, ids, 0);
					if (lig.count > 1) {
						g.id = lig.glyph;
						var last = gs[i + lig.count - 1];
						g.length = last.cluster + last.length - g.cluster;
						g.parts = g.length;
						out.push(g);
						i += lig.count;
						merged = true;
						break;
					}
				}
				if (merged) continue;
			}
			out.push(g);
			i++;
		}
		return out;
	}
}
