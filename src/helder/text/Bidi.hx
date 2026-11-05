package helder.text;

// The Unicode bidirectional algorithm (UAX #9): each character's bidi class
// (from ranges of the scripts written right to left, digits, separators,
// spaces, neutrals and the explicit formatting characters), the
// paragraph's level (its first strong character, isolates skipped, P2-P3,
// or the one given), the explicit embeddings, overrides and isolates
// (X1-X10: the directional status stack, isolating run sequences), then on
// each sequence the weak types (W1-W7), bracket pairs (N0), the neutrals
// (N1-N2) and the implicit levels (I1-I2); checked against Unicode's
// BidiCharacterTest.txt (Bidi.test.hx). reorder gives a line's visual
// order (L1: separators, and spaces and isolates before them and at its
// end, at the paragraph's level; L2: the runs reversed from the highest
// level down), mirror the mirrored form of a character on a right-to-left
// level (L4).
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
	public static inline var LRE = 14;
	public static inline var LRO = 15;
	public static inline var RLE = 16;
	public static inline var RLO = 17;
	public static inline var PDF = 18;
	public static inline var LRI = 19;
	public static inline var RLI = 20;
	public static inline var FSI = 21;
	public static inline var PDI = 22;

	// whether any character of the text is written right to left (else the algorithm is not needed)
	public static function hasRtl(cps:Array<Int>):Bool {
		for (c in cps)
			if (c >= 0x590 && (classOf(c) == R || classOf(c) == AL || c == 0x202B || c == 0x202E || c == 0x2067 || c == 0x2068)) return true;
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
				case 0x202A: LRE;
				case 0x202B: RLE;
				case 0x202C: PDF;
				case 0x202D: LRO;
				case 0x202E: RLO;
				case 0x2066: LRI;
				case 0x2067: RLI;
				case 0x2068: FSI;
				case 0x2069: PDI;
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

	// the embedding level of each character (base: 0, 1, or -1: the first
	// strong character's, isolates skipped): UAX #9 whole, X1 to I2 (explicit
	// embeddings, overrides and isolates, at most 125 deep; isolating run
	// sequences; N0's bracket pairs). The characters X9 removes (the
	// embeddings' and overrides' controls, boundary neutrals) take the level
	// of the character before them.
	public static function levels(cps:Array<Int>, base:Int):{levels:Array<Int>, base:Int} {
		var n = cps.length;
		var initial = [for (c in cps) classOf(c)];
		// (BD9: each isolate initiator's matching PDI, -1: none, to the paragraph's end)
		var match = [for (_ in 0...n) -1];
		for (i in 0...n)
			if (isolate(initial[i])) {
				var depth = 1;
				for (j in i + 1...n) {
					var t = initial[j];
					if (isolate(t)) depth++;
					else if (t == PDI && --depth == 0) {
						match[i] = j;
						break;
					} else if (t == B) break;
				}
			}
		// (P2, P3: the first strong character's, isolates skipped)
		function firstStrong(from:Int, to:Int):Int {
			var i = from;
			while (i < to) {
				var t = initial[i];
				if (t == L) return 0;
				if (t == R || t == AL) return 1;
				if (isolate(t)) {
					if (match[i] < 0) return -1;
					i = match[i];
				}
				i++;
			}
			return -1;
		}
		if (base < 0) {
			base = firstStrong(0, n);
			if (base < 0) base = 0;
		}
		// X1 to X8: the directional status stack
		var types = initial.copy(), lv = [for (_ in 0...n) base];
		var stackLevel = [base], stackOverride = [ON], stackIsolate = [false];
		var overflowIsolates = 0, overflowEmbeddings = 0, validIsolates = 0;
		for (i in 0...n) {
			var t = initial[i], top = stackLevel.length - 1;
			switch t {
				case RLE | LRE | RLO | LRO | RLI | LRI | FSI:
					var iso = isolate(t);
					var rtl = t == RLE || t == RLO || t == RLI || (t == FSI && firstStrong(i + 1, match[i] < 0 ? n : match[i]) == 1);
					if (iso) {
						lv[i] = stackLevel[top];
						if (stackOverride[top] != ON) types[i] = stackOverride[top];
					}
					var level = rtl ? (stackLevel[top] + 1) | 1 : (stackLevel[top] + 2) & ~1;
					if (level <= MAX_DEPTH && overflowIsolates == 0 && overflowEmbeddings == 0) {
						if (iso) validIsolates++;
						stackLevel.push(level);
						stackOverride.push(t == RLO ? R : t == LRO ? L : ON);
						stackIsolate.push(iso);
					} else if (iso) overflowIsolates++;
					else if (overflowIsolates == 0) overflowEmbeddings++;
					if (!iso) lv[i] = stackLevel[stackLevel.length - 1];
				case PDI:
					if (overflowIsolates > 0) overflowIsolates--;
					else if (validIsolates > 0) {
						overflowEmbeddings = 0;
						while (!stackIsolate[stackIsolate.length - 1]) {
							stackLevel.pop();
							stackOverride.pop();
							stackIsolate.pop();
						}
						stackLevel.pop();
						stackOverride.pop();
						stackIsolate.pop();
						validIsolates--;
					}
					top = stackLevel.length - 1;
					lv[i] = stackLevel[top];
					if (stackOverride[top] != ON) types[i] = stackOverride[top];
				case PDF:
					if (overflowIsolates > 0) {} else if (overflowEmbeddings > 0) overflowEmbeddings--;
					else if (!stackIsolate[top] && stackLevel.length >= 2) {
						stackLevel.pop();
						stackOverride.pop();
						stackIsolate.pop();
					}
					lv[i] = stackLevel[stackLevel.length - 1];
				case B:
					lv[i] = base;
				case BN:
					lv[i] = stackLevel[top];
				case _:
					lv[i] = stackLevel[top];
					if (stackOverride[top] != ON) types[i] = stackOverride[top];
			}
		}
		// X9: the controls and boundary neutrals out; X10: the level runs, then the isolating run sequences
		inline function removed(i:Int):Bool
			return isRemoved(initial[i]);
		var embed = lv.copy();
		var runs:Array<Array<Int>> = [], runOf = [for (_ in 0...n) -1];
		for (i in 0...n) {
			if (removed(i)) continue;
			var last = runs.length - 1;
			if (last >= 0 && lv[runs[last][runs[last].length - 1]] == lv[i]) runs[last].push(i) else runs.push([i]);
			runOf[i] = runs.length - 1;
		}
		for (r in 0...runs.length) {
			var first = runs[r][0];
			// (a run starting with a PDI that matches an initiator: in that initiator's sequence)
			if (initial[first] == PDI && match.indexOf(first) >= 0) continue;
			var seq = runs[r].copy();
			while (true) {
				var last = seq[seq.length - 1];
				if (!isolate(initial[last]) || match[last] < 0 || runOf[match[last]] < 0) break;
				for (i in runs[runOf[match[last]]])
					seq.push(i);
			}
			resolve(cps, initial, types, lv, embed, seq, base, n);
		}
		// (the removed: the level of the character before them)
		for (i in 0...n)
			if (removed(i)) lv[i] = i > 0 ? lv[i - 1] : base;
		// L1: segment separators, and the whitespace, isolates and removed controls before them and at the paragraph's end, at its level
		var trailing = true, i = n - 1;
		while (i >= 0) {
			var t = initial[i];
			if (t == S || t == B) {
				lv[i] = base;
				trailing = true;
			} else if (trailing && (t == WS || isolate(t) || t == PDI || removed(i))) lv[i] = base;
			else trailing = false;
			i--;
		}
		return {levels: lv, base: base};
	}

	static inline var MAX_DEPTH = 125;

	static inline function isRemoved(t:Int):Bool
		return t == RLE || t == LRE || t == RLO || t == LRO || t == PDF || t == BN;

	static inline function isolate(t:Int):Bool
		return t == LRI || t == RLI || t == FSI;

	// (W1 to I2 on an isolating run sequence: the indices seq of the paragraph)
	static function resolve(cps:Array<Int>, initial:Array<Int>, types:Array<Int>, lv:Array<Int>, embed:Array<Int>, seq:Array<Int>, base:Int, n:Int) {
		inline function removed(i:Int):Bool
			return isRemoved(initial[i]);
		var m = seq.length, level = embed[seq[0]];
		var before = seq[0] - 1;
		while (before >= 0 && removed(before))
			before--;
		var last = seq[m - 1], after = last + 1;
		while (after < n && removed(after))
			after++;
		var prevLevel = before < 0 ? base : embed[before];
		var nextLevel = isolate(initial[last]) || after >= n ? base : embed[after];
		var sos = (prevLevel > level ? prevLevel : level) & 1 == 1 ? R : L;
		var eos = (nextLevel > level ? nextLevel : level) & 1 == 1 ? R : L;
		var t = [for (i in seq) types[i]];
		// W1: marks take the preceding type (after an isolate's initiator or PDI: ON; at the start: sos)
		for (k in 0...m)
			if (t[k] == NSM) t[k] = k == 0 ? sos : (isolate(t[k - 1]) || t[k - 1] == PDI ? ON : t[k - 1]);
		// W2: European numbers after Arabic letters are Arabic; W3: AL is R
		var strong = sos;
		for (k in 0...m) {
			var x = t[k];
			if (x == L || x == R || x == AL) strong = x;
			if (x == EN && strong == AL) t[k] = AN;
		}
		for (k in 0...m)
			if (t[k] == AL) t[k] = R;
		// W4: a single separator between two numbers of a type
		for (k in 1...m - 1) {
			if (t[k] == ES && t[k - 1] == EN && t[k + 1] == EN) t[k] = EN;
			else if (t[k] == CS && t[k - 1] == t[k + 1] && (t[k - 1] == EN || t[k - 1] == AN)) t[k] = t[k - 1];
		}
		// W5: terminators next to European numbers
		var k = 0;
		while (k < m) {
			if (t[k] == ET) {
				var j = k;
				while (j < m && t[j] == ET)
					j++;
				if (k > 0 && t[k - 1] == EN || j < m && t[j] == EN) for (q in k...j)
					t[q] = EN;
				k = j;
			} else k++;
		}
		// W6: the other separators and terminators are neutral
		for (k in 0...m)
			if (t[k] == ES || t[k] == ET || t[k] == CS) t[k] = ON;
		// W7: European numbers after L (or an L start) are L
		strong = sos;
		for (k in 0...m) {
			if (t[k] == L || t[k] == R) strong = t[k];
			if (t[k] == EN && strong == L) t[k] = L;
		}
		inline function dir(x:Int):Int
			return x == EN || x == AN ? R : x;
		var e = level & 1 == 1 ? R : L;
		// N0: bracket pairs (BD16: at most 63 open) take the embedding's direction, or the context's
		var opens:Array<Int> = [], pairs:Array<Int> = [];
		for (k in 0...m) {
			if (t[k] != ON) continue;
			var c = canonicalBracket(cps[seq[k]]), o = openerOf(c);
			if (closerOf(c) != 0) {
				if (opens.length == 63) break;
				opens.push(k);
			} else if (o != 0) {
				var q = opens.length - 1;
				while (q >= 0 && canonicalBracket(cps[seq[opens[q]]]) != o)
					q--;
				if (q >= 0) {
					pairs.push(opens[q]);
					pairs.push(k);
					opens.resize(q);
				}
			}
		}
		if (pairs.length > 0) {
			var order = [for (q in 0...pairs.length >> 1) q];
			order.sort((x, y) -> pairs[2 * x] - pairs[2 * y]);
			for (q in order) {
				var o = pairs[2 * q], c = pairs[2 * q + 1], found = -1;
				for (j in o + 1...c) {
					var d = dir(t[j]);
					if (d == e) {
						found = e;
						break;
					}
					if (d == L || d == R) found = d;
				}
				if (found < 0) continue;
				if (found != e) {
					// (the opposite inside: the context before the opening bracket decides)
					var ctx = sos, j = o - 1;
					while (j >= 0) {
						var d = dir(t[j]);
						if (d == L || d == R) {
							ctx = d;
							break;
						}
						j--;
					}
					found = ctx == found ? found : e;
				}
				t[o] = t[c] = found;
				// (the marks after each bracket, originally NSM, take its direction)
				for (b in [o, c]) {
					var j = b + 1;
					while (j < m && initial[seq[j]] == NSM) {
						t[j] = found;
						j++;
					}
				}
			}
		}
		// N1, N2: neutrals between two strong of a direction take it, else the embedding's
		inline function neutral(x:Int):Bool
			return x == WS || x == ON || x == S || x == B || x == LRI || x == RLI || x == FSI || x == PDI;
		k = 0;
		while (k < m) {
			if (neutral(t[k])) {
				var j = k;
				while (j < m && neutral(t[j]))
					j++;
				var b = k == 0 ? sos : dir(t[k - 1]), a = j == m ? eos : dir(t[j]);
				var x = b == a ? b : e;
				for (q in k...j)
					t[q] = x;
				k = j;
			} else k++;
		}
		// I1, I2
		for (k in 0...m) {
			var x = t[k], i = seq[k];
			if (level & 1 == 0) lv[i] = x == R ? level + 1 : x == AN || x == EN ? level + 2 : level;
			else lv[i] = x == L || x == EN || x == AN ? level + 1 : level;
		}
	}

	// (Bidi_Paired_Bracket: opening, closing; U+2329 and U+232A as their canonical U+3008 and U+3009)
	static final BRACKETS = [0x0028, 0x0029, 0x005B, 0x005D, 0x007B, 0x007D, 0x0F3A, 0x0F3B, 0x0F3C, 0x0F3D, 0x169B, 0x169C, 0x2045, 0x2046, 0x207D, 0x207E, 0x208D, 0x208E, 0x2308, 0x2309, 0x230A, 0x230B, 0x2329, 0x232A, 0x2768, 0x2769, 0x276A, 0x276B, 0x276C, 0x276D, 0x276E, 0x276F, 0x2770, 0x2771, 0x2772, 0x2773, 0x2774, 0x2775, 0x27C5, 0x27C6, 0x27E6, 0x27E7, 0x27E8, 0x27E9, 0x27EA, 0x27EB, 0x27EC, 0x27ED, 0x27EE, 0x27EF, 0x2983, 0x2984, 0x2985, 0x2986, 0x2987, 0x2988, 0x2989, 0x298A, 0x298B, 0x298C, 0x298D, 0x2990, 0x298F, 0x298E, 0x2991, 0x2992, 0x2993, 0x2994, 0x2995, 0x2996, 0x2997, 0x2998, 0x29D8, 0x29D9, 0x29DA, 0x29DB, 0x29FC, 0x29FD, 0x2E22, 0x2E23, 0x2E24, 0x2E25, 0x2E26, 0x2E27, 0x2E28, 0x2E29, 0x2E55, 0x2E56, 0x2E57, 0x2E58, 0x2E59, 0x2E5A, 0x2E5B, 0x2E5C, 0x3008, 0x3009, 0x300A, 0x300B, 0x300C, 0x300D, 0x300E, 0x300F, 0x3010, 0x3011, 0x3014, 0x3015, 0x3016, 0x3017, 0x3018, 0x3019, 0x301A, 0x301B, 0xFE59, 0xFE5A, 0xFE5B, 0xFE5C, 0xFE5D, 0xFE5E, 0xFF08, 0xFF09, 0xFF3B, 0xFF3D, 0xFF5B, 0xFF5D, 0xFF5F, 0xFF60, 0xFF62, 0xFF63];

	static inline function canonicalBracket(c:Int):Int
		return c == 0x2329 ? 0x3008 : c == 0x232A ? 0x3009 : c;

	// (the closing bracket of an opening one, else 0)
	static function closerOf(c:Int):Int {
		if (c != 0x28 && c != 0x5B && c != 0x7B && c < 0xF3A) return 0;
		var k = 0;
		while (k < BRACKETS.length) {
			if (BRACKETS[k] == c) return BRACKETS[k + 1];
			k += 2;
		}
		return 0;
	}

	static function openerOf(c:Int):Int {
		if (c != 0x29 && c != 0x5D && c != 0x7D && c < 0xF3A) return 0;
		var k = 0;
		while (k < BRACKETS.length) {
			if (BRACKETS[k + 1] == c) return BRACKETS[k];
			k += 2;
		}
		return 0;
	}

	// a line's visual order of the indices start...end: trailing spaces (and
	// tabs) at the base level, then the runs reversed from the highest level
	// down to the lowest odd one
	public static function reorder(cps:Array<Int>, levels:Array<Int>, base:Int, start:Int, end:Int):Array<Int> {
		var lv = [for (i in start...end) levels[i]];
		// (L1: separators and the spaces, isolates and removed controls before them, and those at the line's end)
		inline function blank(c:Int):Bool {
			var t = classOf(c);
			return t == WS || t == LRI || t == RLI || t == FSI || t == PDI || t == BN || t == LRE || t == RLE || t == LRO || t == RLO || t == PDF;
		}
		var k = end - 1, trailing = true;
		while (k >= start) {
			var t = classOf(cps[k]);
			if (t == S || t == B) {
				lv[k - start] = base;
				trailing = true;
			} else if (trailing && blank(cps[k])) lv[k - start] = base;
			else trailing = false;
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
