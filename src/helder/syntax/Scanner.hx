package helder.syntax;

import helder.syntax.Cst;

// The languages helder.syntax reads: TypeScript (.ts: no markup), TSX
// (.tsx), Haxe (.hx: its markup literals) and a design file's (.helder:
// markup alone, its holes' code read as TSX's)
enum abstract Lang(Int) {
	var Ts;
	var Tsx;
	var Haxe;
	var Markup;

	public static function of(path:String):Lang
		return StringTools.endsWith(path, ".tsx") ? Tsx : StringTools.endsWith(path, ".hx") ? Haxe : StringTools.endsWith(path, ".helder") ? Markup : Ts;
}

// A file read into its concrete syntax tree (Cst), from its text alone (no
// compiler): code as tokens and bracket groups, strings with their
// substitutions, comments and regular expressions told from division by
// the token before; markup where an expression starts, by the rules of
// the language's own parser: TSX's "<" after an operator, an opening
// bracket, a keyword (return, yield...) or nothing, and Haxe's as
// helder.markup.Syntax reads a literal (Parser.markupAt: not after a value,
// a name or a number, but after return, throw, else, do, untyped, a
// condition's ")" or metadata). Markup that does not read as markup (a
// generic arrow `<T,>() =>` in TSX, a comparison) is read again as
// tokens. Brackets that do not balance (Haxe's #if branches) leave the
// file flat: tokens only, no groups or markup (Document.structured false).
class Scanner {
	final s:String;
	final lang:Lang;
	var i = 0;
	// (flat: brackets as tokens, no markup)
	var flat = false;
	// where a "<" that could start markup did not read as markup (a generic arrow, a comparison): read as code
	public final backtracks:Array<Int> = [];

	static final TS_PUNCT = [
		">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=",
		"*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>"
	];
	static final HX_PUNCT = [
		"...", "<<=", ">>=", ">>>", "=>", "->", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<",
		">>"
	];
	// (the words after which an expression starts: markup and regular expressions)
	static final TS_STARTERS = ["return", "yield", "await", "case", "default", "else", "do", "typeof", "void", "delete", "in", "of", "throw"];
	static final TS_REGEX = TS_STARTERS.concat(["instanceof", "new"]);
	static final HX_STARTERS = ["return", "throw", "else", "do", "untyped"];

	public function new(s:String, lang:Lang) {
		this.s = s;
		this.lang = lang;
	}

	// the file's tree: structured, else flat; error: why it is flat (null: it is not)
	public static function read(s:String, lang:Lang):{root:Node, error:Null<String>, backtracks:Array<Int>} {
		var sc = new Scanner(s, lang);
		try {
			var items = sc.items(-1);
			return {root: new Node(File, 0, s.length, items), error: null, backtracks: sc.backtracks};
		} catch (e:Fail) {
			var flat = new Scanner(s, lang);
			flat.flat = true;
			var items = try flat.items(-1) catch (e2:Fail) [new Node(Trivia, 0, s.length)];
			return {root: new Node(File, 0, s.length, items), error: e.message + " at " + e.at, backtracks: []};
		}
	}

	function fail(message:String, ?at:Int):Dynamic
		throw new Fail(message, at == null ? i : at);

	inline function code(k:Int):Int
		return k < s.length ? StringTools.fastCodeAt(s, k) : -1;

	inline function at(c:String):Bool
		return code(i) == StringTools.fastCodeAt(c, 0);

	// ---- code

	// items until closer (a character's code; -1: the end of the file), not consumed
	function items(closer:Int, ?into:Array<Node>):Array<Node> {
		var out:Array<Node> = into == null ? [] : into;
		// (the significant items before, the last first: what an expression may start after)
		var prev:Null<Node> = null, prev2:Null<Node> = null, prev3:Null<Node> = null;
		while (true) {
			if (i >= s.length) {
				if (closer >= 0) fail('"' + String.fromCharCode(closer) + '" expected', i);
				return out;
			}
			var t = trivia();
			if (t != null) {
				out.push(t);
				continue;
			}
			var c = code(i);
			if (c == closer) return out;
			var n:Node;
			if (!flat && (c == "(".code || c == "[".code || c == "{".code)) n = group(c);
			else if (!flat && (c == ")".code || c == "]".code || c == "}".code)) return fail('unbalanced "' + String.fromCharCode(c) + '"');
			else if (c == "<".code && !flat && lang != Ts && markupStarts(prev, prev2, prev3)) {
				var save = i;
				n = try element() catch (e:Fail) {
					i = save;
					backtracks.push(save);
					null;
				};
				if (n == null) n = punct();
			} else if (c == '"'.code || (c == "'".code && lang != Haxe)) n = string(c);
			else if (c == "'".code) n = template("'".code);
			else if (c == "`".code && lang != Haxe) n = template("`".code);
			else if (c == "~".code && lang == Haxe && code(i + 1) == "/".code) n = regex(i + 1, i);
			else if (c == "/".code && lang != Haxe && regexStarts(prev)) n = regex(i, i);
			else if (isDigit(c) || (c == ".".code && isDigit(code(i + 1)))) n = number();
			else if (isIdentStart(code(i))) n = ident();
			else n = punct();
			out.push(n);
			prev3 = prev2;
			prev2 = prev;
			prev = n;
		}
	}

	// whitespace and comments at i (null: none)
	function trivia():Null<Node> {
		var start = i;
		while (i < s.length) {
			var c = code(i);
			if (c == " ".code || c == "\t".code || c == "\n".code || c == "\r".code || c == 0xFEFF) i++;
			else if (c == "/".code && code(i + 1) == "/".code) {
				while (i < s.length && code(i) != "\n".code)
					i++;
			} else if (c == "/".code && code(i + 1) == "*".code) {
				var e = s.indexOf("*/", i + 2);
				i = e < 0 ? s.length : e + 2;
			} else break;
		}
		return i > start ? new Node(Trivia, start, i) : null;
	}

	function group(open:Int):Node {
		var start = i;
		var close = open == "(".code ? ")".code : open == "[".code ? "]".code : "}".code;
		var parts = items(close, [new Node(Punct, i, ++i)]);
		parts.push(new Node(Punct, i, ++i));
		return new Node(Group, start, i, parts);
	}

	function punct():Node {
		var start = i;
		var c = code(i);
		var list = c < 128 ? (lang == Haxe ? HX_BY : TS_BY)[c] : null;
		if (list != null)
			for (p in list) {
				var k = 1;
				while (k < p.length && code(i + k) == StringTools.fastCodeAt(p, k))
					k++;
				if (k == p.length) {
					i += p.length;
					return new Node(Punct, start, i);
				}
			}
		i++;
		return new Node(Punct, start, i);
	}

	// (the operators of more than one character by their first, the longest first)
	static final TS_BY = byFirst(TS_PUNCT);
	static final HX_BY = byFirst(HX_PUNCT);

	static function byFirst(list:Array<String>):Array<Null<Array<String>>> {
		var out:Array<Null<Array<String>>> = [for (_ in 0...128) null];
		for (p in list) {
			var c = StringTools.fastCodeAt(p, 0);
			if (out[c] == null) out[c] = [];
			out[c].push(p);
		}
		return out;
	}

	function ident():Node {
		var start = i;
		i++;
		while (i < s.length && isIdentPart(code(i)))
			i++;
		return new Node(Ident, start, i);
	}

	function number():Node {
		var start = i;
		if (code(i) == "0".code && (code(i + 1) == "x".code || code(i + 1) == "X".code || code(i + 1) == "b".code || code(i + 1) == "o".code)) i += 2;
		while (i < s.length) {
			var c = code(i);
			if (isDigit(c) || isIdentPart(c) && c != "$".code) {
				// (an exponent's sign)
				if ((c == "e".code || c == "E".code) && (code(i + 1) == "+".code || code(i + 1) == "-".code) && isDigit(code(i + 2))
					&& !StringTools.startsWith(s.substr(start, 2).toLowerCase(), "0x")) i += 2;
				else i++;
			} else if (c == ".".code && isDigit(code(i + 1))) i++;
			else break;
		}
		return new Node(Num, start, i);
	}

	// "...", '...' (escapes: a backslash and the next)
	function string(q:Int):Node {
		var start = i;
		i++;
		while (i < s.length && code(i) != q) {
			if (code(i) == "\\".code) i++;
			else if (code(i) == "\n".code && lang != Haxe) fail("unterminated string", start);
			i++;
		}
		if (i >= s.length) fail("unterminated string", start);
		i++;
		return new Node(Str, start, i);
	}

	// `...${code}...` (TypeScript), '...${code}...$name...' (Haxe: $$ a dollar)
	function template(q:Int):Node {
		var start = i;
		var parts:Array<Node> = [];
		var chunk = i;
		i++;
		while (true) {
			if (i >= s.length) fail("unterminated string", start);
			var c = code(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == q) {
				i++;
				parts.push(new Node(Chunk, chunk, i));
				break;
			}
			if (c == "$".code && q == "'".code && code(i + 1) == "$".code) {
				i += 2;
				continue;
			}
			if (c == "$".code && code(i + 1) == "{".code) {
				if (i > chunk) parts.push(new Node(Chunk, chunk, i));
				var subStart = i;
				var o = new Node(Punct, i, i + 2);
				i += 2;
				var inner = flat ? flatUntil([o]) : items("}".code, [o]);
				inner.push(new Node(Punct, i, ++i));
				parts.push(new Node(Subst, subStart, i, inner));
				chunk = i;
				continue;
			}
			i++;
		}
		return new Node(Template, start, i, parts);
	}

	// (a flat file's substitution: its code as tokens to the "}" closing it)
	function flatUntil(out:Array<Node>):Array<Node> {
		var depth = 0;
		while (i < s.length) {
			var t = trivia();
			if (t != null) {
				out.push(t);
				continue;
			}
			var c = code(i);
			if (c == "}".code && depth == 0) return out;
			if (c == "{".code) depth++;
			if (c == "}".code) depth--;
			out.push(c == '"'.code ? string(c) : c == "'".code && lang != Haxe ? string(c) : c == "'".code || c == "`".code ? template(c) : isIdentStart(c) ? ident() : punct());
		}
		return fail("unterminated substitution");
	}

	// /.../flags (Haxe: ~/.../flags, from tilde)
	function regex(slash:Int, from:Int):Node {
		var start = from;
		i = slash + 1;
		var cls = false;
		while (true) {
			if (i >= s.length || code(i) == "\n".code) fail("unterminated regular expression", start);
			var c = code(i);
			if (c == "\\".code) i++;
			else if (c == "[".code) cls = true;
			else if (c == "]".code) cls = false;
			else if (c == "/".code && !cls) break;
			i++;
		}
		i++;
		while (i < s.length && isIdentPart(code(i)))
			i++;
		return new Node(Regex, start, i);
	}

	// whether "/" starts a regular expression: after nothing, an operator or a keyword that starts one
	function regexStarts(prev:Null<Node>):Bool {
		if (prev == null) return true;
		return switch prev.kind {
			case Punct: true;
			case Ident: TS_REGEX.indexOf(prev.text(s)) >= 0;
			case _: false;
		}
	}

	// whether the "<" at i starts markup (a name, or ">" a fragment's)
	function markupStarts(prev:Null<Node>, prev2:Null<Node>, prev3:Null<Node>):Bool {
		var n = code(i + 1);
		if (!(n == ">".code || n == "_".code || (n >= "a".code && n <= "z".code) || (n >= "A".code && n <= "Z".code))) return false;
		if (prev == null) return true;
		return switch prev.kind {
			case Punct: true;
			case Ident:
				var w = prev.text(s);
				lang == Haxe ? HX_STARTERS.indexOf(w) >= 0 || meta(prev2, prev3) : TS_STARTERS.indexOf(w) >= 0;
			case Group:
				// (a condition's ")": if (...), while (...), for (...); Haxe's metadata's arguments: @:pos(p))
				var open = s.charAt(prev.start);
				if (open == "{") return lang != Haxe;
				if (open != "(") return false;
				var w = prev2 != null && prev2.kind == Ident ? prev2.text(s) : "";
				["if", "while", "for"].indexOf(w) >= 0 || (lang == Haxe && prev2 != null && prev2.kind == Ident && meta(prev3, null));
			case _: false;
		}
	}

	// (the name before is metadata's: @name, @:name)
	function meta(before:Null<Node>, _:Null<Node>):Bool {
		if (before == null || before.kind != Punct) return false;
		var t = before.text(s);
		return t == "@" || (t == ":" && before.start > 0 && s.charAt(before.start - 1) == "@");
	}

	// ---- markup

	// <name attrs>content</name>, <name attrs/>, <>content</>
	function element():Node {
		var start = i;
		var open = openTag();
		var tag = open.first(TagName);
		var name = tag == null ? "" : tag.text(s);
		var parts = [open];
		if (s.charAt(open.end - 2) == "/" && name != "") return new Node(Element, start, i, parts);
		while (true) {
			if (i >= s.length) fail("unterminated <" + name + ">", start);
			var c = code(i);
			if (c == "<".code && code(i + 1) == "/".code) {
				var close = closeTag();
				var cn = close.first(TagName);
				var closing = cn == null ? "" : cn.text(s);
				if (closing != name) fail("</" + closing + "> closes <" + name + ">", close.start);
				parts.push(close);
				return new Node(Element, start, i, parts);
			}
			if (c == "<".code) parts.push(element());
			else if (c == "{".code) parts.push(hole(Hole));
			else parts.push(text());
		}
	}

	function openTag():Node {
		var start = i;
		var parts = [new Node(Punct, i, ++i)];
		var name = readName();
		if (name != null) parts.push(name);
		if (name == null && !at(">")) fail("a tag's name");
		while (true) {
			var t = markupSpace();
			if (t != null) parts.push(t);
			if (i >= s.length) fail("unterminated tag", start);
			if (at(">")) {
				parts.push(new Node(Punct, i, ++i));
				return new Node(OpenTag, start, i, parts);
			}
			if (at("/") && s.charAt(i + 1) == ">" && name != null) {
				parts.push(new Node(Punct, i, i += 2));
				return new Node(OpenTag, start, i, parts);
			}
			if (name == null) fail("a fragment has no attributes");
			if (at("{")) {
				var h = hole(Spread);
				// (an attribute is name={code}; {...code} spreads)
				var first = h.significant()[1];
				if (first == null || first.text(s) != "...") fail("{...code} spreads", h.start);
				parts.push(h);
				continue;
			}
			parts.push(attr());
		}
	}

	function attr():Node {
		var start = i;
		var name = readName();
		if (name == null) fail("an attribute's name");
		var parts = [new Node(Ident, name.start, name.end)];
		var save = i;
		var t = markupSpace();
		if (!at("=")) {
			i = save;
			return new Node(Attr, start, i, parts);
		}
		if (t != null) parts.push(t);
		parts.push(new Node(Punct, i, ++i));
		var t2 = markupSpace();
		if (t2 != null) parts.push(t2);
		var q = s.charAt(i);
		if (q == '"' || q == "'") {
			var e = s.indexOf(q, i + 1);
			if (e < 0) fail("unterminated attribute value");
			parts.push(new Node(Str, i, e + 1));
			i = e + 1;
		} else if (q == "{") parts.push(hole(Hole));
		else fail('an attribute\'s value: "text" or {code}');
		return new Node(Attr, start, i, parts);
	}

	// {code}: a hole of markup (kind Hole, or Spread)
	function hole(kind:Kind):Node {
		var start = i;
		var parts = items("}".code, [new Node(Punct, i, ++i)]);
		parts.push(new Node(Punct, i, ++i));
		return new Node(kind, start, i, parts);
	}

	function closeTag():Node {
		var start = i;
		var parts = [new Node(Punct, i, i += 2)];
		var t = markupSpace();
		if (t != null) parts.push(t);
		var name = readName();
		if (name != null) parts.push(name);
		var t2 = markupSpace();
		if (t2 != null) parts.push(t2);
		if (!at(">")) fail('">" expected');
		parts.push(new Node(Punct, i, ++i));
		return new Node(CloseTag, start, i, parts);
	}

	function text():Node {
		var start = i;
		while (i < s.length && code(i) != "<".code && code(i) != "{".code)
			i++;
		return new Node(Text, start, i);
	}

	// (whitespace, and comments, between a tag's parts)
	function markupSpace():Null<Node>
		return trivia();

	// a tag's or an attribute's name, as helder.markup.Syntax reads it: letters, "_", ":", then digits, "-", "." too
	function readName():Null<Node> {
		var start = i;
		while (i < s.length) {
			var c = code(i);
			var ok = (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == ":".code
				|| (i > start && ((c >= "0".code && c <= "9".code) || c == "-".code || c == ".".code));
			if (!ok) break;
			i++;
		}
		return i > start ? new Node(TagName, start, i) : null;
	}

	static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	static inline function isIdentStart(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == "$".code || c >= 0x80;

	static inline function isIdentPart(c:Int):Bool
		return isIdentStart(c) || isDigit(c);
}

class Fail {
	public final message:String;
	public final at:Int;

	public function new(message:String, at:Int) {
		this.message = message;
		this.at = at;
	}

	public function toString():String
		return '$message at $at';
}
