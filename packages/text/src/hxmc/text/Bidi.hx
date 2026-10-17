package hxmc.text;

// The Unicode bidirectional algorithm (UAX #9) for a paragraph without
// explicit embeddings: each character's bidi class (from ranges of the
// scripts written right to left, digits, separators, spaces and neutrals;
// the explicit formatting characters taken as boundary neutrals), the
// paragraph's level (its first strong character, P2-P3, or the one given),
// then the weak types (W1-W7), the neutrals (N1-N2) and the implicit levels
// (I1-I2). reorder gives a line's visual order (L1: its trailing spaces at
// the paragraph's level; L2: the runs reversed from the highest level down),
// mirror the mirrored form of a character on a right-to-left level (L4).
class Bidi {
	public static inline var L = 0;
	public static inline var R = 1;
	public static inline var AL = 2;
	public static inline var EN = 3;
	public static inline var ES = 4;
	public static inline var ET = 5;
	public static inline var AN = 6;
	public static inline var CS = 7;
	public static inline var NSM = 8;
	public static inline var BN = 9;
	public static inline var B = 10;
	public static inline var S = 11;
	public static inline var WS = 12;
	public static inline var ON = 13;

	// whether any character of the text is written right to left (else the algorithm is not needed)
	public static function hasRtl(cps:Array<Int>):Bool {
		for (c in cps)
			if (c >= 0x590 && (classOf(c) == R || classOf(c) == AL)) return true;
		return false;
	}

	public static function classOf(c:Int):Int {
		if (c < 0x80) {
			if (c >= "0".code && c <= "9".code) return EN;
			if (c >= "A".code && c <= "Z".code || c >= "a".code && c <= "z".code) return L;
			return switch c {
				case 0x09 | 0x0B | 0x1F: S;
				case 0x0A | 0x0D | 0x1C | 0x1D | 0x1E: B;
				case 0x0C | 0x20: WS;
				case 0x23 | 0x24 | 0x25: ET;
				case 0x2B | 0x2D: ES;
				case 0x2C | 0x2E | 0x2F | 0x3A: CS;
				case _ if (c < 0x20 || c == 0x7F): BN;
				case _: ON;
			}
		}
		if (c < 0x590) {
			if (c >= 0x300 && c <= 0x36F) return NSM;
			if (c >= 0x483 && c <= 0x489) return NSM;
			return switch c {
				case 0x85: B;
				case 0xA0: CS;
				case 0xA2 | 0xA3 | 0xA4 | 0xA5 | 0xB0 | 0xB1: ET;
				case 0xAD: BN;
				case 0xB2 | 0xB3 | 0xB9: EN;
				case 0xAB | 0xBB | 0xA1 | 0xA6 | 0xA7 | 0xA8 | 0xA9 | 0xAC | 0xAE | 0xAF | 0xB4 | 0xB6 | 0xB7 | 0xB8 | 0xBF | 0xD7 | 0xF7: ON;
				case _ if (c < 0xA0): BN;
				case _: L;
			}
		}
		if (c <= 0x5FF) {
			// Hebrew: points and accents are marks
			if (c >= 0x591 && c <= 0x5BD || c == 0x5BF || c == 0x5C1 || c == 0x5C2 || c == 0x5C4 || c == 0x5C5 || c == 0x5C7) return NSM;
			return R;
		}
		if (c <= 0x6FF) {
			// Arabic
			if (c >= 0x660 && c <= 0x669 || c == 0x66B || c == 0x66C) return AN;
			if (c >= 0x6F0 && c <= 0x6F9) return EN;
			if (c >= 0x600 && c <= 0x605 || c == 0x6DD) return AN;
			if (c == 0x60C) return CS;
			if (c == 0x66A) return ET;
			if (c >= 0x610 && c <= 0x61A || c >= 0x64B && c <= 0x65F || c == 0x670 || c >= 0x6D6 && c <= 0x6DC || c >= 0x6DF && c <= 0x6E4 || c == 0x6E7
				|| c == 0x6E8 || c >= 0x6EA && c <= 0x6ED)
				return NSM;
			if (c == 0x6DE || c == 0x6E9) return ON;
			return AL;
		}
		if (c <= 0x7BF) {
			// Syriac, Arabic Supplement, Thaana
			if (c >= 0x711 && c == 0x711 || c >= 0x730 && c <= 0x74A || c >= 0x7A6 && c <= 0x7B0) return NSM;
			return AL;
		}
		if (c <= 0x8FF) {
			// NKo, Samaritan, Mandaic (R); Arabic Extended (AL)
			if (c >= 0x7EB && c <= 0x7F3 || c >= 0x816 && c <= 0x82D || c >= 0x859 && c <= 0x85B || c >= 0x8D3 && c <= 0x8FF) return NSM;
			return c >= 0x860 ? AL : R;
		}
		if (c >= 0x2000 && c <= 0x206F) {
			return switch c {
				case 0x2028: WS;
				case 0x2029: B;
				case 0x200E: L;
				case 0x200F: R;
				case _ if (c <= 0x200A): WS;
				case _ if (c >= 0x200B && c <= 0x200D || c >= 0x2060): BN;
				case _ if (c >= 0x2030 && c <= 0x2034): ET;
				case 0x2044: CS;
				case 0x202F: CS;
				case _: ON;
			}
		}
		if (c >= 0x20A0 && c <= 0x20CF) return ET;
		if (c >= 0x2070 && c <= 0x2079 && c != 0x2071 && c != 0x2072 && c != 0x2073 || c >= 0x2080 && c <= 0x2089) return EN;
		if (c >= 0x2190 && c <= 0x2BFF) return ON;
		if (c == 0x3000) return WS;
		if (c >= 0x3001 && c <= 0x3003 || c >= 0x3008 && c <= 0x3011) return ON;
		if (c >= 0xFB1D && c <= 0xFB4F) return c == 0xFB1E ? NSM : c == 0xFB29 ? ES : R;
		if (c >= 0xFB50 && c <= 0xFDFF) return AL;
		if (c >= 0xFE70 && c <= 0xFEFE) return AL;
		if (c == 0xFEFF) return BN;
		if (c >= 0xFE00 && c <= 0xFE0F || c >= 0xFE20 && c <= 0xFE2F) return NSM;
		if (c >= 0xFF10 && c <= 0xFF19) return EN;
		if (c >= 0x10800 && c <= 0x10FFF) return c >= 0x10D00 && c <= 0x10D3F || c >= 0x10F30 && c <= 0x10F6F ? AL : R;
		if (c >= 0x1E800 && c <= 0x1EFFF) return c >= 0x1EC70 && c <= 0x1EEFF ? AL : R;
		return L;
	}

	// the embedding level of each character (base: 0, 1, or -1: the first strong character's)
	public static function levels(cps:Array<Int>, base:Int):{levels:Array<Int>, base:Int} {
		var n = cps.length;
		var t = [for (c in cps) classOf(c)];
		if (base < 0) {
			base = 0;
			for (k in t)
				if (k == L) break else if (k == R || k == AL) {
					base = 1;
					break;
				}
		}
		var sos = base & 1 == 1 ? R : L;
		// (boundary neutrals out: their types taken from the preceding character, as X9 removes them)
		for (i in 0...n)
			if (t[i] == BN) t[i] = i > 0 ? t[i - 1] : sos;
		// W1: marks take the preceding type (at the start: sos)
		for (i in 0...n)
			if (t[i] == NSM) t[i] = i == 0 ? sos : t[i - 1];
		// W2: European numbers after Arabic letters are Arabic; W3: AL is R
		var last = sos;
		for (i in 0...n) {
			var k = t[i];
			if (k == L || k == R || k == AL) last = k;
			if (k == EN && last == AL) t[i] = AN;
		}
		for (i in 0...n)
			if (t[i] == AL) t[i] = R;
		// W4: a single separator between two numbers of a type
		for (i in 1...n - 1) {
			if (t[i] == ES && t[i - 1] == EN && t[i + 1] == EN) t[i] = EN;
			else if (t[i] == CS && t[i - 1] == t[i + 1] && (t[i - 1] == EN || t[i - 1] == AN)) t[i] = t[i - 1];
		}
		// W5: terminators next to European numbers
		var i = 0;
		while (i < n) {
			if (t[i] == ET) {
				var j = i;
				while (j < n && t[j] == ET)
					j++;
				if (i > 0 && t[i - 1] == EN || j < n && t[j] == EN) for (k in i...j)
					t[k] = EN;
				i = j;
			} else i++;
		}
		// W6: the other separators and terminators are neutral
		for (i in 0...n)
			if (t[i] == ES || t[i] == ET || t[i] == CS) t[i] = ON;
		// W7: European numbers after L (or an L start) are L
		last = sos;
		for (i in 0...n) {
			if (t[i] == L || t[i] == R) last = t[i];
			if (t[i] == EN && last == L) t[i] = L;
		}
		// N1, N2: neutrals between two strong of a direction take it, else the embedding's
		inline function strong(k:Int):Int
			return k == EN || k == AN ? R : k;
		i = 0;
		while (i < n) {
			if (t[i] == WS || t[i] == ON || t[i] == S || t[i] == B) {
				var j = i;
				while (j < n && (t[j] == WS || t[j] == ON || t[j] == S || t[j] == B))
					j++;
				var before = i == 0 ? sos : strong(t[i - 1]), after = j == n ? sos : strong(t[j]);
				var k = before == after ? before : (base & 1 == 1 ? R : L);
				for (m in i...j)
					t[m] = k;
				i = j;
			} else i++;
		}
		// I1, I2
		var out = [for (k in t) if (base & 1 == 0) (k == R ? base + 1 : k == AN || k == EN ? base + 2 : base) else (k == L || k == EN || k == AN ? base + 1 : base)];
		return {levels: out, base: base};
	}

	// a line's visual order of the indices start...end: trailing spaces (and
	// tabs) at the base level, then the runs reversed from the highest level
	// down to the lowest odd one
	public static function reorder(cps:Array<Int>, levels:Array<Int>, base:Int, start:Int, end:Int):Array<Int> {
		var lv = [for (i in start...end) levels[i]];
		var k = end - 1;
		while (k >= start && (classOf(cps[k]) == WS || classOf(cps[k]) == S)) {
			lv[k - start] = base;
			k--;
		}
		var order = [for (i in start...end) i];
		var high = 0, lowOdd = 999;
		for (l in lv) {
			if (l > high) high = l;
			if (l & 1 == 1 && l < lowOdd) lowOdd = l;
		}
		var level = high;
		while (level >= lowOdd && level > 0) {
			var i = 0;
			while (i < order.length) {
				if (lv[i] >= level) {
					var j = i;
					while (j < order.length && lv[j] >= level)
						j++;
					// (reversed: the indices and their levels)
					var a = i, b = j - 1;
					while (a < b) {
						var t = order[a];
						order[a] = order[b];
						order[b] = t;
						var u = lv[a];
						lv[a] = lv[b];
						lv[b] = u;
						a++;
						b--;
					}
					i = j;
				} else i++;
			}
			level--;
		}
		return order;
	}

	// the mirrored character (Bidi_Mirroring_Glyph) of the common pairs, or c
	public static function mirror(c:Int):Int
		return switch c {
			case "(".code: ")".code;
			case ")".code: "(".code;
			case "<".code: ">".code;
			case ">".code: "<".code;
			case "[".code: "]".code;
			case "]".code: "[".code;
			case "{".code: "}".code;
			case "}".code: "{".code;
			case 0xAB: 0xBB;
			case 0xBB: 0xAB;
			case 0x2039: 0x203A;
			case 0x203A: 0x2039;
			case 0x2264: 0x2265;
			case 0x2265: 0x2264;
			case 0x3008: 0x3009;
			case 0x3009: 0x3008;
			case 0x300A: 0x300B;
			case 0x300B: 0x300A;
			case 0x300C: 0x300D;
			case 0x300D: 0x300C;
			case 0x3010: 0x3011;
			case 0x3011: 0x3010;
			case _: c;
		}
}
