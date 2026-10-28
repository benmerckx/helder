package helder.typescript.js;

import helder.typescript.js.Values;
import helder.typescript.js.Lib.*;

enum RxNode {
	RChar(c:Int);
	RAny;
	// (ranges: inclusive pairs)
	RSet(ranges:Array<Int>, negated:Bool);
	RStart;
	REnd;
	RWord(negated:Bool);
	RGroup(index:Int, node:RxNode);
	RLook(behind:Bool, negated:Bool, node:RxNode);
	RBackref(index:Int);
	RNamedBackref(name:String);
	RRepeat(node:RxNode, min:Int, max:Int, greedy:Bool, firstGroup:Int, lastGroup:Int);
	RSeq(items:Array<RxNode>);
	RAlt(options:Array<RxNode>);
}

class JsRegExp extends JsObject {
	public var source:String;
	public var flags:String;
	public var program:RxNode;
	public var groupCount:Int;
	public var groupNames:Array<String>;
	override public function tag():String return "RegExp";
}

// Regular expressions: a parser for JavaScript pattern syntax and a
// backtracking matcher (continuation passing), with the RegExp built-ins.
class Regex {
	public static var RegExpProto:JsObject;
	public static function isRegExp(v:Dynamic):Bool return Std.isOfType(v, JsRegExp);

	// Parsing.
	var p:String;
	var i = 0;
	var unicode:Bool;
	var groups = 0;
	var names:Array<String> = [];
	var hasNamed = false;
	function new(p:String, unicode:Bool) {
		this.p = p;
		this.unicode = unicode;
	}

	function fail(message:String):Dynamic return error("SyntaxError", "Invalid regular expression: /" + p + "/: " + message);

	function peek():Int return i < p.length ? code(i) : -1;

	function code(at:Int):Int {
		var c = p.charCodeAt(at);
		if (unicode && c >= 0xd800 && c <= 0xdbff && at + 1 < p.length) {
			var d = p.charCodeAt(at + 1);
			if (d >= 0xdc00 && d <= 0xdfff) return (c - 0xd800) * 1024 + (d - 0xdc00) + 0x10000;
		}
		return c;
	}

	function next():Int {
		var c = code(i);
		i += c > 0xffff ? 2 : 1;
		return c;
	}

	function eat(c:Int):Bool {
		if (peek() == c) {
			i++;
			return true;
		}
		return false;
	}

	function disjunction():RxNode {
		var options = [sequence()];
		while (eat("|".code)) options.push(sequence());
		return options.length == 1 ? options[0] : RAlt(options);
	}

	function sequence():RxNode {
		var items:Array<RxNode> = [];
		while (i < p.length && peek() != "|".code && peek() != ")".code) {
			var groupStart = groups;
			var atom = term();
			if (atom == null) continue;
			items.push(quantified(atom, groupStart));
		}
		return items.length == 1 ? items[0] : RSeq(items);
	}

	function quantified(atom:RxNode, groupStart:Int):RxNode {
		var min = -1, max = -1;
		var c = peek();
		if (c == "*".code) {
			i++;
			min = 0;
			max = -1;
		}
		else if (c == "+".code) {
			i++;
			min = 1;
			max = -1;
		}
		else if (c == "?".code) {
			i++;
			min = 0;
			max = 1;
		}
		else if (c == "{".code) {
			var save = i;
			i++;
			var a = number();
			if (a < 0) {
				i = save;
				if (unicode) fail("Incomplete quantifier");
				return atom;
			}
			min = a;
			max = a;
			if (eat(",".code)) {
				max = peek() == "}".code ? -1 : number();
			}
			if (!eat("}".code)) {
				i = save;
				if (unicode) fail("Incomplete quantifier");
				min = -1;
				return atom;
			}
			if (max >= 0 && max < min) fail("numbers out of order in {} quantifier");
		}
		else return atom;
		switch (atom) {
			case RStart | REnd | RWord(_): fail("Nothing to repeat");
			case RLook(true, _, _): fail("Invalid quantifier");
			case _:
		}
		var greedy = !eat("?".code);
		return RRepeat(atom, min, max, greedy, groupStart + 1, groups);
	}

	function number():Int {
		var start = i;
		var n = 0;
		while (i < p.length && peek() >= 48 && peek() <= 57) {
			n = Std.int(Math.min(n * 10 + (peek() - 48), 2147483647));
			i++;
		}
		return i == start ? -1 : n;
	}

	function term():RxNode {
		var c = next();
		switch (c) {
			case "^".code: return RStart;
			case "$".code: return REnd;
			case ".".code: return RAny;
			case "(".code:
				if (eat("?".code)) {
					var k = next();
					if (k == ":".code) {
						var n = disjunction();
						if (!eat(")".code)) fail("Unterminated group");
						return RGroup(-1, n);
					}
					if (k == "=".code || k == "!".code) {
						var n = disjunction();
						if (!eat(")".code)) fail("Unterminated group");
						return RLook(false, k == "!".code, n);
					}
					if (k == "<".code) {
						if (eat("=".code) || peek() == "!".code && eat("!".code)) {
							var negated = p.charCodeAt(i - 1) == "!".code;
							var n = disjunction();
							if (!eat(")".code)) fail("Unterminated group");
							return RLook(true, negated, n);
						}
						var close = p.indexOf(">", i);
						if (close < 0) fail("Invalid capture group name");
						var name = p.substring(i, close);
						i = close + 1;
						if (names.indexOf(name) >= 0) fail("Duplicate capture group name");
						var index = ++groups;
						while (names.length < index) names.push(null);
						names[index - 1] = name;
						hasNamed = true;
						var n = disjunction();
						if (!eat(")".code)) fail("Unterminated group");
						return RGroup(index, n);
					}
					return fail("Invalid group");
				}
				var index = ++groups;
				while (names.length < index) names.push(null);
				var n = disjunction();
				if (!eat(")".code)) fail("Unterminated group");
				return RGroup(index, n);
			case ")".code: return fail("Unmatched ')'");
			case "[".code: return characterClass();
			case "*".code | "+".code | "?".code: return fail("Nothing to repeat");
			case "{".code:
				if (unicode) fail("Lone quantifier brackets");
				return RChar(c);
			case "}".code | "]".code:
				if (unicode) fail("Lone quantifier brackets");
				return RChar(c);
			case "\\".code: return atomEscape();
			case _: return RChar(c);
		}
	}
	static var digitRanges = [48, 57];
	static var wordRanges = [48, 57, 65, 90, 95, 95, 97, 122];
	static var spaceRanges = [9, 13, 32, 32, 160, 160, 0x1680, 0x1680, 0x2000, 0x200a, 0x2028, 0x2029, 0x202f, 0x202f, 0x205f, 0x205f, 0x3000, 0x3000, 0xfeff, 0xfeff];
	function atomEscape():RxNode {
		if (i >= p.length) fail("\\ at end of pattern");
		var c = peek();
		if (c == "b".code) {
			i++;
			return RWord(false);
		}
		if (c == "B".code) {
			i++;
			return RWord(true);
		}
		if (c >= "1".code && c <= "9".code) {
			var n = number();
			return RBackref(n);
		}
		if (c == "k".code && (unicode || hasNamedAhead())) {
			i++;
			if (!eat("<".code)) fail("Invalid named reference");
			var close = p.indexOf(">", i);
			if (close < 0) fail("Invalid named reference");
			var name = p.substring(i, close);
			i = close + 1;
			return RNamedBackref(name);
		}
		var set = classEscape();
		if (set != null) return set;
		return RChar(characterEscape());
	}

	function hasNamedAhead():Bool return p.indexOf("(?<") >= 0 && p.indexOf("(?<=") != p.indexOf("(?<") || hasNamed;

	// (\d \D \w \W \s \S \p{...}: a set, else null)
	function classEscape():RxNode {
		var c = peek();
		switch (c) {
			case "d".code | "D".code:
				i++;
				return RSet(digitRanges, c == "D".code);
			case "w".code | "W".code:
				i++;
				return RSet(wordRanges, c == "W".code);
			case "s".code | "S".code:
				i++;
				return RSet(spaceRanges, c == "S".code);
			case "p".code | "P".code if (unicode):
				i++;
				if (!eat("{".code)) fail("Invalid property name");
				var close = p.indexOf("}", i);
				if (close < 0) fail("Invalid property name");
				var name = p.substring(i, close);
				i = close + 1;
				return RSet(property(name), c == "P".code);
			case _: return null;
		}
	}

	function property(name:String):Array<Int> {
		var eq = name.indexOf("=");
		if (eq >= 0) name = name.substr(eq + 1);
		return switch (name) {
			case "L" | "Letter" | "Alphabetic" | "Alpha": [65, 90, 97, 122, 170, 170, 181, 181, 186, 186, 192, 214, 216, 246, 248, 0x2c1, 0x370, 0x3ff, 0x400, 0x52f, 0x531, 0x587, 0x5d0, 0x5ea, 0x620, 0x64a, 0x904, 0x939, 0x3040, 0x30ff, 0x4e00, 0x9fff, 0xac00, 0xd7a3];
			case "Lu" | "Uppercase_Letter" | "Uppercase": [65, 90, 192, 214, 216, 222, 0x391, 0x3a9, 0x410, 0x42f];
			case "Ll" | "Lowercase_Letter" | "Lowercase": [97, 122, 223, 246, 248, 255, 0x3b1, 0x3c9, 0x430, 0x44f];
			case "N" | "Number" | "Nd" | "Decimal_Number" | "digit": [48, 57, 0x660, 0x669, 0x6f0, 0x6f9, 0x966, 0x96f, 0xff10, 0xff19];
			case "P" | "Punctuation": [33, 35, 37, 42, 44, 47, 58, 59, 63, 64, 91, 93, 95, 95, 123, 123, 125, 125, 161, 161, 167, 167, 171, 171, 182, 183, 187, 187, 191, 191, 0x2010, 0x2027, 0x3001, 0x3003];
			case "Emoji" | "Emoji_Presentation" | "Extended_Pictographic": [0x2600, 0x27bf, 0x1f300, 0x1faff];
			case "Latin": [65, 90, 97, 122, 170, 170, 186, 186, 192, 214, 216, 246, 248, 0x24f];
			case "Greek": [0x370, 0x3ff];
			case "Cyrillic": [0x400, 0x52f];
			case "Han": [0x2e80, 0x2fdf, 0x3005, 0x3007, 0x3021, 0x3029, 0x3400, 0x4dbf, 0x4e00, 0x9fff, 0xf900, 0xfaff, 0x20000, 0x2fa1f];
			case "White_Space" | "space": spaceRanges;
			case "Any": [0, 0x10ffff];
			case "ASCII": [0, 127];
			case _: fail("Invalid property name");
		};
	}

	function characterEscape():Int {
		var c = next();
		return switch (c) {
			case "n".code: 10;
			case "r".code: 13;
			case "t".code: 9;
			case "v".code: 11;
			case "f".code: 12;
			case "0".code if (!(peek() >= 48 && peek() <= 57)): 0;
			case "c".code:
				var l = peek();
				if (l >= 65 && l <= 90 || l >= 97 && l <= 122) {
					i++;
					l % 32;
				} else {
					i--;
					92;
				}
			case "x".code:
				var h = hex(2);
				if (h < 0) {
					if (unicode) fail("Invalid escape");
					"x".code;
				} else h;
			case "u".code:
				if (unicode && eat("{".code)) {
					var close = p.indexOf("}", i);
					var v = Std.parseInt("0x" + p.substring(i, close));
					i = close + 1;
					if (v == null || v > 0x10ffff) fail("Invalid Unicode escape");
					v;
				}
				else {
					var h = hex(4);
					if (h < 0) {
						if (unicode) fail("Invalid Unicode escape");
						"u".code;
					}
					else if (unicode && h >= 0xd800 && h <= 0xdbff && p.substr(i, 2) == "\\u") {
						var save = i;
						i += 2;
						var l = hex(4);
						if (l >= 0xdc00 && l <= 0xdfff) (h - 0xd800) * 1024 + (l - 0xdc00) + 0x10000; else {
							i = save;
							h;
						}
					}
					else h;
				}
			case _:
				if (unicode && !(c == "^".code || c == "$".code || c == "\\".code || c == ".".code || c == "*".code || c == "+".code || c == "?".code || c == "(".code || c == ")".code || c == "[".code || c == "]".code || c == "{".code || c == "}".code || c == "|".code || c == "/".code || c == "-".code)) fail("Invalid escape");
				c;
		};
	}

	function hex(n:Int):Int {
		var v = 0;
		for (k in 0...n) {
			if (i + k >= p.length) return -1;
			var c = p.charCodeAt(i + k);
			var d = c >= 48 && c <= 57 ? c - 48 : c >= 65 && c <= 70 ? c - 55 : c >= 97 && c <= 102 ? c - 87 : -1;
			if (d < 0) return -1;
			v = v * 16 + d;
		}
		i += n;
		return v;
	}

	function characterClass():RxNode {
		var negated = eat("^".code);
		var ranges:Array<Int> = [];
		while (true) {
			if (i >= p.length) fail("Unterminated character class");
			if (eat("]".code)) break;
			var lo = classAtom(ranges);
			if (lo < 0) continue;
			if (peek() == "-".code && i + 1 < p.length && p.charCodeAt(i + 1) != "]".code) {
				i++;
				var hi = classAtom(ranges);
				if (hi < 0) {
					if (unicode) fail("Invalid character class");
					ranges.push(lo);
					ranges.push(lo);
					ranges.push(45);
					ranges.push(45);
					continue;
				}
				if (hi < lo) fail("Range out of order in character class");
				ranges.push(lo);
				ranges.push(hi);
			}
			else {
				ranges.push(lo);
				ranges.push(lo);
			}
		}
		return RSet(ranges, negated);
	}

	// (a class member: a character, or -1 after adding an escape set's ranges)
	function classAtom(ranges:Array<Int>):Int {
		var c = next();
		if (c != "\\".code) return c;
		var e = peek();
		if (e == "b".code) {
			i++;
			return 8;
		}
		if (e == "-".code) {
			i++;
			return 45;
		}
		var set = classEscape();
		if (set != null) {
			switch (set) {
				case RSet(rs, false): for (r in rs) ranges.push(r);
				case RSet(rs, true):
					var prev = 0;
					var k = 0;
					while (k < rs.length) {
						if (rs[k] > prev) {
							ranges.push(prev);
							ranges.push(rs[k] - 1);
						}
						prev = rs[k + 1] + 1;
						k += 2;
					}
					if (prev <= 0x10ffff) {
						ranges.push(prev);
						ranges.push(0x10ffff);
					}
				case _:
			}
			return -1;
		}
		return characterEscape();
	}

	static function resolveNames(n:RxNode, names:Array<String>, groups:Int):RxNode {
		return switch (n) {
			case RNamedBackref(name):
				var k = names.indexOf(name);
				if (k < 0) error("SyntaxError", "Invalid named capture referenced");
				RBackref(k + 1);
			case RBackref(k) if (k > groups): RBackref(-k);
			case RGroup(i, x): RGroup(i, resolveNames(x, names, groups));
			case RLook(b, neg, x): RLook(b, neg, resolveNames(x, names, groups));
			case RRepeat(x, a, z, g, f, l): RRepeat(resolveNames(x, names, groups), a, z, g, f, l);
			case RSeq(xs): RSeq([for (x in xs) resolveNames(x, names, groups)]);
			case RAlt(xs): RAlt([for (x in xs) resolveNames(x, names, groups)]);
			case _: n;
		};
	}
	// (patterns are parsed once per source and flags)
	static var cache:Map<String, {program:RxNode, groups:Int, names:Array<String>}> = [];
	public static function compile(source:String, flags:String):JsRegExp {
		for (k in 0...flags.length) {
			var f = flags.charAt(k);
			if ("dgimsuvy".indexOf(f) < 0 || flags.indexOf(f) != k) error("SyntaxError", "Invalid flags supplied to RegExp constructor '" + flags + "'");
		}
		var key = flags + "/" + source;
		var compiled = cache.get(key);
		if (compiled == null) {
			var parser = new Regex(source, flags.indexOf("u") >= 0 || flags.indexOf("v") >= 0);
			var program = parser.disjunction();
			if (parser.i < source.length) parser.fail("Unmatched ')'");
			compiled = {program: resolveNames(program, parser.names, parser.groups), groups: parser.groups, names: parser.names};
			cache.set(key, compiled);
		}
		var r = new JsRegExp(RegExpProto);
		r.source = source;
		r.flags = flags;
		r.groupCount = compiled.groups;
		r.groupNames = compiled.names;
		r.program = compiled.program;
		r.setOwn("lastIndex", 0.0, Attr.HIDDEN | Attr.LOCKED);
		return r;
	}

	// Matching.
	var s:String;
	var caps:Array<Int>;
	var ignoreCase:Bool;
	var multiline:Bool;
	var dotAll:Bool;
	var steps = 0;
	function at(k:Int):Int {
		var c = s.charCodeAt(k);
		if (unicode && c >= 0xd800 && c <= 0xdbff && k + 1 < s.length) {
			var d = s.charCodeAt(k + 1);
			if (d >= 0xdc00 && d <= 0xdfff) return (c - 0xd800) * 1024 + (d - 0xdc00) + 0x10000;
		}
		return c;
	}

	static inline function width(c:Int):Int return c > 0xffff ? 2 : 1;

	static function lineTerminator(c:Int):Bool return c == 10 || c == 13 || c == 0x2028 || c == 0x2029;

	function wordAt(k:Int):Bool {
		if (k < 0 || k >= s.length) return false;
		var c = s.charCodeAt(k);
		return c >= 48 && c <= 57 || c >= 65 && c <= 90 || c >= 97 && c <= 122 || c == 95;
	}

	static function canonical(c:Int):Int {
		if (c < 128) return c >= 97 && c <= 122 ? c - 32 : c;
		if (c > 0xffff) return c;
		var u = String.fromCharCode(c).toUpperCase();
		return u.length == 1 && u.charCodeAt(0) >= 128 ? u.charCodeAt(0) : c;
	}

	function inSet(c:Int, ranges:Array<Int>):Bool {
		var k = 0;
		while (k < ranges.length) {
			if (c >= ranges[k] && c <= ranges[k + 1]) return true;
			k += 2;
		}
		if (ignoreCase) {
			var alternatives = [String.fromCharCode(c).toLowerCase(), String.fromCharCode(c).toUpperCase()];
			for (a in alternatives) if (a.length == 1) {
				var x = a.charCodeAt(0);
				if (x != c) {
					k = 0;
					while (k < ranges.length) {
						if (x >= ranges[k] && x <= ranges[k + 1]) return true;
						k += 2;
					}
				}
			}
		}
		return false;
	}

	// (one single-character node at position k: the next position, or -1)
	function single(n:RxNode, k:Int):Int {
		if (k >= s.length) return -1;
		var c = at(k);
		return switch (n) {
			case RChar(x): (c == x || ignoreCase && canonical(c) == canonical(x)) ? k + width(c) : -1;
			case RAny: (dotAll || !lineTerminator(c)) ? k + width(c) : -1;
			case RSet(r, neg): inSet(c, r) != neg ? k + width(c) : -1;
			case _: -1;
		};
	}

	function match(n:RxNode, k:Int, next:Int->Bool):Bool {
		if (++steps > 50000000) error("RangeError", "Maximum regular expression backtracking exceeded");
		switch (n) {
			case RChar(_) | RAny | RSet(_, _):
				var j = single(n, k);
				return j >= 0 && next(j);
			case RStart: return (k == 0 || multiline && lineTerminator(s.charCodeAt(k - 1))) && next(k);
			case REnd: return (k == s.length || multiline && lineTerminator(s.charCodeAt(k))) && next(k);
			case RWord(neg): return (wordAt(k - 1) != wordAt(k)) != neg && next(k);
			case RGroup(-1, x): return match(x, k, next);
			case RGroup(g, x):
				var ps = caps[2 * g], pe = caps[2 * g + 1];
				if (match(x, k, j -> {
					var qs = caps[2 * g], qe = caps[2 * g + 1];
					caps[2 * g] = k;
					caps[2 * g + 1] = j;
					if (next(j)) return true;
					caps[2 * g] = qs;
					caps[2 * g + 1] = qe;
					return false;})) return true;
				caps[2 * g] = ps;
				caps[2 * g + 1] = pe;
				return false;
			case RLook(behind, neg, x):
				var saved = caps.copy();
				var found = false;
				if (behind) {
					var start = k;
					while (start >= 0 && !found) {
						if (match(x, start, j -> j == k)) found = true; else start--;
					}
				}
				else found = match(x, k, _ -> true);
				if (neg) {
					caps = saved;
					return !found && next(k);
				}
				if (!found) {
					caps = saved;
					return false;
				}
				if (next(k)) return true;
				caps = saved;
				return false;
			case RBackref(g):
				if (g < 0 || caps[2 * g] < 0) return next(k);
				var sub = s.substring(caps[2 * g], caps[2 * g + 1]);
				if (k + sub.length > s.length) return false;
				var here = s.substr(k, sub.length);
				if (here != sub && !(ignoreCase && here.toUpperCase() == sub.toUpperCase())) return false;
				return next(k + sub.length);
			case RSeq(items): return matchSequence(items, 0, k, next);
			case RAlt(options):
				for (o in options) if (match(o, k, next)) return true;
				return false;
			case RRepeat(x, min, max, greedy, first, last):
				switch (x) {
					case RChar(_) | RAny | RSet(_, _):
						// (single characters: positions found iteratively)
						var positions = [k];
						var j = k;
						while (max < 0 || positions.length - 1 < max) {
							var nj = single(x, j);
							if (nj < 0) break;
							positions.push(nj);
							j = nj;
						}
						if (positions.length - 1 < min) return false;
						if (greedy) {
							var c = positions.length - 1;
							while (c >= min) {
								if (next(positions[c])) return true;
								c--;
							}
						}
						else for (c in min...positions.length) if (next(positions[c])) return true;
						return false;
					case _: return repeat(x, min, max, greedy, first, last, 0, k, next);
				}
			case RNamedBackref(_): return false;
		}
	}

	function matchSequence(items:Array<RxNode>, index:Int, k:Int, next:Int->Bool):Bool {
		if (index == items.length) return next(k);
		return match(items[index], k, j -> matchSequence(items, index + 1, j, next));
	}

	function repeat(x:RxNode, min:Int, max:Int, greedy:Bool, first:Int, last:Int, count:Int, k:Int, next:Int->Bool):Bool {
		if (count >= min && !greedy && next(k)) return true;
		if (max < 0 || count < max) {
			// (captures inside the quantified atom restart each iteration)
			var saved = caps.slice(2 * first, 2 * last + 2);
			for (g in first...last + 1) {
				caps[2 * g] = -1;
				caps[2 * g + 1] = -1;
			}
			if (match(x, k, j -> j == k && count >= min ? false : repeat(x, min, max, greedy, first, last, count + 1, j, next))) return true;
			for (t in 0...saved.length) caps[2 * first + t] = saved[t];
		}
		return count >= min && greedy && next(k);
	}

	// A match starting exactly at k: captures (start/end pairs, group 0 first), or null.
	public static function matchAt(r:JsRegExp, s:String, k:Int):Array<Int> {
		var m = new Regex(r.source, r.flags.indexOf("u") >= 0 || r.flags.indexOf("v") >= 0);
		m.s = s;
		m.ignoreCase = r.flags.indexOf("i") >= 0;
		m.multiline = r.flags.indexOf("m") >= 0;
		m.dotAll = r.flags.indexOf("s") >= 0;
		m.caps = [for (_ in 0...2 * (r.groupCount + 1)) -1];
		var end = -1;
		if (!m.match(r.program, k, j -> {
			end = j;
			return true;})) return null;
		m.caps[0] = k;
		m.caps[1] = end;
		return m.caps;
	}

	// RegExpBuiltinExec: the match object (array with index, input, groups), or null.
	public static function exec(r:JsRegExp, s:String):Dynamic {
		var global = r.flags.indexOf("g") >= 0, sticky = r.flags.indexOf("y") >= 0, unicode = r.flags.indexOf("u") >= 0 || r.flags.indexOf("v") >= 0;
		var lastIndex = toLength(get(r, "lastIndex"));
		if (!global && !sticky) lastIndex = 0;
		if (lastIndex > s.length) {
			if (global || sticky) put(r, "lastIndex", 0);
			return null;
		}
		var k = Std.int(lastIndex);
		var caps:Array<Int> = null;
		while (k <= s.length) {
			caps = matchAt(r, s, k);
			if (caps != null || sticky) break;
			k = advance(s, k, unicode);
		}
		if (caps == null) {
			if (global || sticky) put(r, "lastIndex", 0);
			return null;
		}
		if (global || sticky) put(r, "lastIndex", caps[1]);
		return result(r, s, caps);
	}

	static function result(r:JsRegExp, s:String, caps:Array<Int>):Dynamic {
		var items:Array<Dynamic> = [for (g in 0...r.groupCount + 1) caps[2 * g] < 0 ? undef() : s.substring(caps[2 * g], caps[2 * g + 1])];
		var a:JsArray = cast array(items);
		a.setOwn("index", caps[0]);
		a.setOwn("input", s);
		var groups:Dynamic = undef();
		if (r.groupNames.filter(n -> n != null).length > 0) {
			var g = new JsObject(null);
			for (k in 0...r.groupNames.length) if (r.groupNames[k] != null) g.setOwn(r.groupNames[k], items[k + 1]);
			groups = g;
		}
		a.setOwn("groups", groups);
		if (r.flags.indexOf("d") >= 0) {
			var indices:JsArray = cast array([for (g in 0...r.groupCount + 1) caps[2 * g] < 0 ? undef() : array([caps[2 * g], caps[2 * g + 1]])]);
			var ig:Dynamic = undef();
			if (groups != undef()) {
				var g = new JsObject(null);
				for (k in 0...r.groupNames.length) if (r.groupNames[k] != null) g.setOwn(r.groupNames[k], get(indices, k + 1));
				ig = g;
			}
			indices.setOwn("groups", ig);
			a.setOwn("indices", indices);
		}
		return a;
	}

	static function toLength(v:Dynamic):Float {
		var n = toIntegerOrInfinity(v);
		return n < 0 ? 0 : Math.min(n, 9007199254740991.0);
	}

	static function advance(s:String, k:Int, unicode:Bool):Int {
		if (unicode && k + 1 < s.length) {
			var c = s.charCodeAt(k);
			if (c >= 0xd800 && c <= 0xdbff) {
				var d = s.charCodeAt(k + 1);
				if (d >= 0xdc00 && d <= 0xdfff) return k + 2;
			}
		}
		return k + 1;
	}

	// (exec through a possibly overridden exec method, as RegExpExec does)
	static function regExpExec(r:Dynamic, s:String):Dynamic {
		var f = get(r, "exec");
		if (Std.isOfType(f, JsFunction) && (f : JsFunction).native != null && Std.isOfType(r, JsRegExp)) return exec(r, s);
		if (isCallable(f)) {
			var v = call(f, r, [s]);
			if (v != null && !isObject(v)) error("TypeError", "exec result must be an object or null");
			return v;
		}
		return exec(thisRegExp(r, "exec"), s);
	}

	static function thisRegExp(t:Dynamic, name:String):JsRegExp {
		if (!Std.isOfType(t, JsRegExp)) error("TypeError", "RegExp.prototype." + name + " requires that 'this' be a RegExp object");
		return t;
	}

	public static function create(source:String, flags:String):Dynamic return compile(source, flags);

	public static function setup():Void {
		RegExpProto = new JsObject(Builtins.ObjectProto);
		var ctor = Builtins.nativeFunction("RegExp", 2, (_, a, nt) -> {
			var pattern = arg(a, 0), flags = arg(a, 1);
			if (nt == undef() && Std.isOfType(pattern, JsRegExp) && flags == undef()) return pattern;
			var source = Std.isOfType(pattern, JsRegExp) ? (pattern : JsRegExp).source : pattern == undef() ? "(?:)" : Seed.text(pattern);
			var f = flags == undef() ? (Std.isOfType(pattern, JsRegExp) ? (pattern : JsRegExp).flags : "") : Seed.text(flags);
			var r = compile(source == "" ? "(?:)" : source, f);
			if (nt != undef()) r.proto = protoFrom(nt, RegExpProto);
			return r;
		}, true);
		ctor.setOwn("prototype", RegExpProto, Attr.HIDDEN | Attr.READONLY | Attr.LOCKED);
		RegExpProto.setOwn("constructor", ctor, Attr.HIDDEN);
		Builtins.globals.set("RegExp", ctor);
		(Builtins.globals.get("globalThis") : JsObject).setOwn("RegExp", ctor, Attr.HIDDEN);
		function method(name:String, arity:Int, fn:(Dynamic, Array<Dynamic>, Dynamic) -> Dynamic) RegExpProto.setOwn(name, Builtins.nativeFunction(Symbols.functionName(name), arity, fn), Attr.HIDDEN);
		function getter(name:String, fn:JsRegExp->Dynamic) RegExpProto.setOwn(name, new Accessor(Builtins.nativeFunction("get " + name, 0, (t, _, _) -> t == RegExpProto ? (name == "source" ? "(?:)" : name == "flags" ? "" : undef()) : fn(thisRegExp(t, name))), null), Attr.HIDDEN);
		getter("source", r -> escapeSource(r.source));
		getter("flags", r -> {
			var out = "";
			for (f in ["d", "g", "i", "m", "s", "u", "v", "y"]) if (r.flags.indexOf(f) >= 0) out += f;
			return out;});
		for (pair in [["global", "g"], ["ignoreCase", "i"], ["multiline", "m"], ["dotAll", "s"], ["unicode", "u"], ["unicodeSets", "v"], ["sticky", "y"], ["hasIndices", "d"]]) getter(pair[0], r -> r.flags.indexOf(pair[1]) >= 0);
		method("exec", 1, (t, a, _) -> exec(thisRegExp(t, "exec"), Seed.text(arg(a, 0))));
		method("test", 1, (t, a, _) -> regExpExec(t, Seed.text(arg(a, 0))) != null);
		method("toString", 0, (t, _, _) -> "/" + Seed.text(get(t, "source")) + "/" + Seed.text(get(t, "flags")));
		method("compile", 2, (t, a, _) -> {
			var r = thisRegExp(t, "compile");
			var c = compile(arg(a, 0) == undef() ? "(?:)" : Seed.text(arg(a, 0)), arg(a, 1) == undef() ? "" : Seed.text(arg(a, 1)));
			r.source = c.source;
			r.flags = c.flags;
			r.program = c.program;
			r.groupCount = c.groupCount;
			r.groupNames = c.groupNames;
			put(r, "lastIndex", 0);
			return r;});
		method("\x00@@match", 1, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var flags = Seed.text(get(t, "flags"));
			if (flags.indexOf("g") < 0) return regExpExec(t, s);
			put(t, "lastIndex", 0);
			var out:Array<Dynamic> = [];
			while (true) {
				var m = regExpExec(t, s);
				if (m == null) break;
				var text = Seed.text(get(m, 0));
				out.push(text);
				if (text == "") put(t, "lastIndex", advance(s, Std.int(toLength(get(t, "lastIndex"))), flags.indexOf("u") >= 0));
			}
			return out.length == 0 ? null : array(out);
		});
		method("\x00@@matchAll", 1, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var flags = Seed.text(get(t, "flags"));
			var r = compile((t : JsRegExp).source, flags);
			put(r, "lastIndex", get(t, "lastIndex"));
			var done = false;
			var global = flags.indexOf("g") >= 0;
			var it = new JsObject(Builtins.IteratorProto);
			it.setOwn("next", Builtins.nativeFunction("next", 0, (_, _, _) -> {
				if (done) return object(["value", "done"], [undef(), true]);
				var m = exec(r, s);
				if (m == null) {
					done = true;
					return object(["value", "done"], [undef(), true]);
				}
				if (!global) done = true;
				else if (Seed.text(get(m, 0)) == "") put(r, "lastIndex", advance(s, Std.int(toLength(get(r, "lastIndex"))), flags.indexOf("u") >= 0));
				return object(["value", "done"], [m, false]);
			}), Attr.HIDDEN);
			it.setOwn(Symbols.toStringTag, "RegExp String Iterator", Attr.HIDDEN);
			return it;
		});
		method("\x00@@search", 1, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var previous = get(t, "lastIndex");
			put(t, "lastIndex", 0);
			var m = regExpExec(t, s);
			put(t, "lastIndex", previous);
			return m == null ? -1 : get(m, "index");
		});
		method("\x00@@split", 2, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var limit = arg(a, 1) == undef() ? 4294967295.0 : toUint32(arg(a, 1));
			var r:JsRegExp = thisRegExp(t, "split");
			var unicode = r.flags.indexOf("u") >= 0;
			var out:Array<Dynamic> = [];
			if (limit == 0) return array(out);
			if (s.length == 0) return array(matchAt(r, s, 0) != null ? [] : [s]);
			var p = 0, q = 0;
			while (q < s.length) {
				var caps = matchAt(r, s, q);
				if (caps == null || caps[1] == p || caps[1] > s.length) {
					q = advance(s, q, unicode);
					continue;
				}
				out.push(s.substring(p, q));
				if (out.length >= limit) return array(out);
				for (g in 1...r.groupCount + 1) {
					out.push(caps[2 * g] < 0 ? undef() : s.substring(caps[2 * g], caps[2 * g + 1]));
					if (out.length >= limit) return array(out);
				}
				p = caps[1];
				q = p;
			}
			out.push(s.substr(p));
			return array(out);
		});
		method("\x00@@replace", 2, (t, a, _) -> {
			var s = Seed.text(arg(a, 0));
			var replaceValue = arg(a, 1);
			var functional = isCallable(replaceValue);
			var template = functional ? "" : Seed.text(replaceValue);
			var flags = Seed.text(get(t, "flags"));
			var global = flags.indexOf("g") >= 0;
			if (global) put(t, "lastIndex", 0);
			var results:Array<Dynamic> = [];
			while (true) {
				var m = regExpExec(t, s);
				if (m == null) break;
				results.push(m);
				if (!global) break;
				if (Seed.text(get(m, 0)) == "") put(t, "lastIndex", advance(s, Std.int(toLength(get(t, "lastIndex"))), flags.indexOf("u") >= 0));
			}
			var out = new StringBuf();
			var next = 0;
			for (m in results) {
				var matched = Seed.text(get(m, 0));
				var position = Std.int(Math.max(Math.min(toIntegerOrInfinity(get(m, "index")), s.length), 0));
				var n = Std.int(Builtins.lengthOf(m));
				var captures:Array<Dynamic> = [for (k in 1...n) {
					var c = get(m, k);
					c == undef() ? c : Seed.text(c);
				}];
				var groups = get(m, "groups");
				var replacement = functional ? Seed.text(call(replaceValue, undef(), ([matched] : Array<Dynamic>).concat(captures).concat([position, s]).concat(groups == undef() ? [] : [groups]))) : expand(template, matched, s, position, captures, groups == undef() ? null : toObject(groups));
				if (position >= next) {
					out.add(s.substring(next, position));
					out.add(replacement);
					next = position + matched.length;
				}
			}
			out.add(s.substr(next));
			return out.toString();
		});
	}

	static function escapeSource(source:String):String {
		var out = new StringBuf();
		var inClass = false;
		var k = 0;
		while (k < source.length) {
			var c = source.charAt(k);
			if (c == "\\") {
				out.add(c);
				if (k + 1 < source.length) out.add(source.charAt(k + 1));
				k += 2;
				continue;
			}
			if (c == "[") inClass = true; else if (c == "]") inClass = false;
			if (c == "/" && !inClass) out.add("\\/"); else if (c == "\n") out.add("\\n"); else if (c == "\r") out.add("\\r"); else out.add(c);
			k++;
		}
		return out.toString();
	}

	// GetSubstitution: $$, $&, $`, $', $n, $nn and $<name> in a replacement string.
	public static function expand(replacement:String, matched:String, str:String, position:Int, captures:Array<Dynamic>, named:Dynamic):String {
		if (replacement.indexOf("$") < 0) return replacement;
		var out = new StringBuf();
		var i = 0;
		var m = captures.length;
		while (i < replacement.length) {
			var c = replacement.charAt(i);
			if (c != "$" || i + 1 >= replacement.length) {
				out.add(c);
				i++;
				continue;
			}
			var next = replacement.charAt(i + 1);
			switch (next) {
				case "$":
					out.add("$");
					i += 2;
				case "&":
					out.add(matched);
					i += 2;
				case "`":
					out.add(str.substr(0, position));
					i += 2;
				case "'":
					out.add(str.substr(Std.int(Math.min(position + matched.length, str.length))));
					i += 2;
				case "<":
					if (named == null || named == undef()) {
						out.add("$<");
						i += 2;
						continue;
					}
					var close = replacement.indexOf(">", i + 2);
					if (close < 0) {
						out.add("$<");
						i += 2;
						continue;
					}
					var v = get(named, replacement.substring(i + 2, close));
					if (v != undef()) out.add(Seed.text(v));
					i = close + 1;
				case _:
					var d1 = next.charCodeAt(0) - 48;
					if (d1 < 0 || d1 > 9) {
						out.add("$");
						i++;
						continue;
					}
					var d2 = i + 2 < replacement.length ? replacement.charCodeAt(i + 2) - 48 : -1;
					if (d2 >= 0 && d2 <= 9 && d1 * 10 + d2 >= 1 && d1 * 10 + d2 <= m) {
						var v = captures[d1 * 10 + d2 - 1];
						if (v != undef()) out.add(Seed.text(v));
						i += 3;
						continue;
					}
					if (d1 >= 1 && d1 <= m) {
						var v = captures[d1 - 1];
						if (v != undef()) out.add(Seed.text(v));
						i += 2;
						continue;
					}
					out.add("$");
					i++;
			}
		}
		return out.toString();
	}
}
