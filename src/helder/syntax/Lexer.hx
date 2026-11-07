package helder.syntax;

import helder.syntax.Scanner.Lang;

// A token's class for highlighting (Lexer's): what a theme colours
enum abstract TokenClass(Int) from Int to Int {
	var Plain = 0;
	var Keyword = 1;
	// strings, template chunks, regular expressions, a markup attribute's "value"
	var Str = 2;
	var Num = 3;
	var Comment = 4;
	// a name that starts with a capital letter, a built-in type (string, number...)
	var Type = 5;
	// a name called (f(...)), or declared by function
	var Function = 6;
	// markup's tag names (TSX, Haxe markup)
	var Tag = 7;
	// markup's attribute names, decorators and Haxe's metadata (@:name)
	var Attribute = 8;
	var Punct = 9;

	public static inline var COUNT = 10;

	public function name():String
		return switch (cast this : TokenClass) {
			case Plain: "plain";
			case Keyword: "keyword";
			case Str: "string";
			case Num: "number";
			case Comment: "comment";
			case Type: "type";
			case Function: "function";
			case Tag: "tag";
			case Attribute: "attribute";
			case Punct: "punctuation";
		}
}

// The tokens of a file line by line, for highlighting an editor's lines
// (helder.ui.code): Scanner's reading of TypeScript, TSX and Haxe markup
// (its strings and templates with their substitutions, comments, regular
// expressions told from division by what comes before, markup where an
// expression starts, by the same rules), made resumable at any line's
// start. A line is read from a state (an Int: the stack of what is open
// at its start, block comments, templates, multi-line strings, markup
// tags and contents, holes and substitutions with their braces, and
// whether an expression may start) and gives the next line's: an editor
// reads only from an edited line until a line's state is the one it had
// before. States are interned (equal stacks, equal Ints); a line read
// allocates nothing once its tokens' array is large enough, but for a
// state never seen before.
//
//   var lx = new Lexer(Tsx), out = [], state = lx.start();
//   for (line in lines) {
//     out.resize(0);
//     state = lx.line(line, state, out);   // out: start, end, TokenClass, ...
//   }
//
// Unlike Scanner it does not backtrack across lines: a "<" read as markup
// where it was a comparison or a generic's (`a <b` after an operator)
// stays markup until the line where the tag would end. Plain tokens
// (names, whitespace, markup text) are not given.
class Lexer {
	public final lang:Lang;

	// (the frames of a state's stack: kind in the low 4 bits, EXPR (code: an expression may start next), braces open above it)
	static inline var CODE = 0;
	// a markup hole's code ({...}): "}" with no brace open ends it
	static inline var HOLE = 1;
	// a template's substitution (${...})
	static inline var SUBST = 2;
	// `...` (TypeScript), '...' (Haxe)
	static inline var TEMPLATE = 3;
	static inline var COMMENT = 4;
	// an opening tag's attributes
	static inline var TAG = 5;
	// a closing tag, after its name
	static inline var CLOSE = 6;
	// markup's content: text, elements, holes
	static inline var CHILDREN = 7;
	// a Haxe string over several lines ("...")
	static inline var STRING = 8;
	static inline var EXPR = 16;
	// (code: the last token was a ")": markup may follow, as after if (...), for (...))
	static inline var PAREN = 32;
	static inline var BRACE = 64;
	static inline var MAX_DEPTH = 48;

	// (interned states: their stacks, and their ids by hash)
	final states:Array<Array<Int>> = [];
	final byHash = new Map<Int, Array<Int>>();
	// (the line being read: its stack, text, tokens, place)
	final stack:Array<Int> = [];
	var depth = 0;
	var s = "";
	var n = 0;
	var i = 0;
	var out:Array<Int> = [];
	// (the last name was function's: the next is a declared function)
	var declares = false;

	public function new(lang:Lang) {
		this.lang = lang;
		stack[0] = CODE | EXPR;
		depth = 1;
		intern();
	}

	// the state of a file's first line
	public inline function start():Int
		return 0;

	// the states made so far (each a distinct stack)
	public inline function stateCount():Int
		return states.length;

	// a line's tokens from its state (appended to out: start, end, class, in
	// order, relative to the line, Plain left out), the next line's state
	public function line(text:String, state:Int, out:Array<Int>):Int {
		s = text;
		n = text.length;
		i = 0;
		this.out = out;
		declares = false;
		var st = states[state];
		depth = st.length;
		for (k in 0...depth)
			stack[k] = st[k];
		while (i < n)
			step();
		this.out = null;
		s = "";
		return intern();
	}

	// (the state now as an id: an equal stack's, else a new one)
	function intern():Int {
		var h = depth;
		for (k in 0...depth)
			h = (h * 31 + stack[k]) | 0;
		var ids = byHash.get(h);
		if (ids != null)
			for (id in ids) {
				var st = states[id];
				if (st.length != depth) continue;
				var same = true;
				for (k in 0...depth)
					if (st[k] != stack[k]) {
						same = false;
						break;
					}
				if (same) return id;
			}
		var id = states.length;
		states.push([for (k in 0...depth) stack[k]]);
		if (ids == null) byHash.set(h, [id]) else ids.push(id);
		return id;
	}

	inline function code(k:Int):Int
		return k < n ? StringTools.fastCodeAt(s, k) : -1;

	inline function top():Int
		return stack[depth - 1];

	inline function setTop(f:Int)
		stack[depth - 1] = f;

	function push(f:Int) {
		if (depth >= MAX_DEPTH) return;
		stack[depth++] = f;
	}

	function pop() {
		if (depth > 1) depth--;
		else stack[0] = CODE | EXPR;
	}

	function emit(start:Int, end:Int, cls:Int) {
		if (end <= start) return;
		var l = out.length;
		if (l >= 3 && out[l - 2] == start && out[l - 1] == cls) {
			out[l - 2] = end;
			return;
		}
		out.push(start);
		out.push(end);
		out.push(cls);
	}

	function step() {
		switch top() & 15 {
			case COMMENT:
				var e = s.indexOf("*/", i);
				if (e < 0) {
					emit(i, n, Comment);
					i = n;
				} else {
					emit(i, e + 2, Comment);
					i = e + 2;
					pop();
				}
			case TEMPLATE:
				template();
			case STRING:
				var st = i;
				while (i < n && code(i) != '"'.code)
					i += code(i) == "\\".code ? 2 : 1;
				if (i >= n) {
					emit(st, n, Str);
					i = n;
				} else {
					emit(st, ++i, Str);
					pop();
				}
			case TAG:
				tag();
			case CLOSE:
				close();
			case CHILDREN:
				children();
			case _:
				code_();
		}
	}

	// ---- code

	function code_() {
		var c = code(i);
		if (c == " ".code || c == "\t".code || c == "\r".code || c == 0xFEFF) {
			i++;
			return;
		}
		var f = top(), exprStart = f & EXPR != 0, paren = f & PAREN != 0;
		if (paren) setTop(f &= ~PAREN);
		if (c == "/".code && code(i + 1) == "/".code) {
			emit(i, n, Comment);
			i = n;
			return;
		}
		if (c == "/".code && code(i + 1) == "*".code) {
			emit(i, i + 2, Comment);
			i += 2;
			push(COMMENT);
			return;
		}
		if (c == "{".code) {
			setTop((f + BRACE) | EXPR);
			emit(i, ++i, Punct);
			return;
		}
		if (c == "}".code) {
			emit(i, ++i, Punct);
			if (f >= BRACE) setTop((f - BRACE) & ~EXPR) else if (f & 15 == HOLE || f & 15 == SUBST) pop();
			return;
		}
		if (c == "(".code || c == "[".code || c == ",".code || c == ";".code) {
			setTop(f | EXPR);
			emit(i, ++i, Punct);
			return;
		}
		if (c == ")".code || c == "]".code) {
			setTop(f & ~EXPR | (c == ")".code ? PAREN : 0));
			emit(i, ++i, Punct);
			return;
		}
		if (c == '"'.code) {
			setTop(f & ~EXPR);
			if (lang == Haxe) {
				var st = i++;
				while (i < n && code(i) != '"'.code)
					i += code(i) == "\\".code ? 2 : 1;
				if (i >= n) {
					emit(st, n, Str);
					i = n;
					push(STRING);
				} else emit(st, ++i, Str);
			} else quoted(c);
			return;
		}
		if (c == "'".code && lang != Haxe) {
			setTop(f & ~EXPR);
			quoted(c);
			return;
		}
		if (c == "'".code || c == "`".code && lang != Haxe) {
			setTop(f & ~EXPR);
			emit(i, ++i, Str);
			push(TEMPLATE);
			return;
		}
		if (lang == Haxe && c == "~".code && code(i + 1) == "/".code) {
			if (regex(i, i + 1)) return;
		}
		if (lang != Haxe && c == "/".code && exprStart) {
			if (regex(i, i)) return;
		}
		if (c >= "0".code && c <= "9".code || c == ".".code && isDigit(code(i + 1))) {
			number();
			setTop(f & ~EXPR);
			return;
		}
		if (c == "#".code && lang == Haxe && isIdentStart(code(i + 1))) {
			var st = i++;
			while (i < n && isIdentPart(code(i)))
				i++;
			emit(st, i, Keyword);
			return;
		}
		if (c == "@".code) {
			var st = i++;
			if (code(i) == ":".code) i++;
			while (i < n && (isIdentPart(code(i)) || code(i) == ".".code))
				i++;
			emit(st, i, Attribute);
			return;
		}
		if (c == "<".code && lang != Ts && (exprStart || paren) && markup()) return;
		if (isIdentStart(c)) {
			ident();
			return;
		}
		// (operators: an expression starts after them)
		setTop(f | EXPR);
		emit(i, ++i, Punct);
	}

	// "..." or '...' on one line (an unterminated one: to the line's end)
	function quoted(q:Int) {
		var st = i++;
		while (i < n && code(i) != q)
			i += code(i) == "\\".code ? 2 : 1;
		if (i > n) i = n;
		emit(st, i < n ? ++i : n, Str);
	}

	// /.../flags from slash (Haxe: ~/.../ from the tilde): false when it ends with the line (division then)
	function regex(from:Int, slash:Int):Bool {
		var k = slash + 1, cls = false;
		while (k < n) {
			var c = code(k);
			if (c == "\\".code) k++;
			else if (c == "[".code) cls = true;
			else if (c == "]".code) cls = false;
			else if (c == "/".code && !cls) break;
			k++;
		}
		if (k >= n) return false;
		k++;
		while (k < n && isIdentPart(code(k)))
			k++;
		emit(from, k, Str);
		i = k;
		setTop(top() & ~EXPR);
		return true;
	}

	function number() {
		var st = i;
		if (code(i) == "0".code && (code(i + 1) | 32 == "x".code || code(i + 1) | 32 == "b".code || code(i + 1) | 32 == "o".code)) i += 2;
		while (i < n) {
			var c = code(i);
			if (isDigit(c) || isIdentPart(c) && c != "$".code) {
				if ((c == "e".code || c == "E".code) && (code(i + 1) == "+".code || code(i + 1) == "-".code) && isDigit(code(i + 2))) i += 2;
				else i++;
			} else if (c == ".".code && isDigit(code(i + 1))) i++;
			else break;
		}
		emit(st, i, Num);
	}

	function ident() {
		var st = i++;
		while (i < n && isIdentPart(code(i)))
			i++;
		var k = keyword(st, i);
		var f = top();
		if (k == KW) {
			emit(st, i, Keyword);
			setTop(f | EXPR);
			declares = isWord(st, i, "function");
			return;
		}
		if (k == VALUE) {
			emit(st, i, Keyword);
			setTop(f & ~EXPR);
			declares = false;
			return;
		}
		setTop(f & ~EXPR);
		if (k == BUILTIN) {
			emit(st, i, Type);
			declares = false;
			return;
		}
		// (called: a "(" next, spaces between)
		var j = i;
		while (j < n && (code(j) == " ".code || code(j) == "\t".code))
			j++;
		var first = code(st);
		if (declares || code(j) == "(".code) emit(st, i, Function) else if (first >= "A".code && first <= "Z".code) emit(st, i, Type);
		declares = false;
	}

	inline function isWord(a:Int, b:Int, w:String):Bool {
		if (b - a != w.length) return false;
		var same = true;
		for (k in 0...w.length)
			if (StringTools.fastCodeAt(s, a + k) != StringTools.fastCodeAt(w, k)) {
				same = false;
				break;
			}
		return same;
	}

	static inline var NONE = 0;
	static inline var KW = 1;
	static inline var VALUE = 2;
	static inline var BUILTIN = 3;

	// (the words by their length, for a look up without a substring)
	static final TS_WORDS = byLength([
		"break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for",
		"function", "if", "import", "in", "instanceof", "new", "return", "switch", "throw", "try", "typeof", "var", "void", "while", "with", "yield", "let",
		"static", "implements", "interface", "package", "private", "protected", "public", "await", "async", "as", "of", "type", "namespace", "declare", "abstract",
		"readonly", "keyof", "infer", "is", "satisfies", "from", "get", "set", "accessor", "override", "unique", "asserts", "module", "global"
	]);
	static final HX_WORDS = byLength([
		"abstract", "break", "case", "cast", "catch", "class", "continue", "default", "do", "dynamic", "else", "enum", "extends", "extern", "final", "for",
		"function", "if", "implements", "import", "in", "inline", "interface", "macro", "new", "operator", "overload", "override", "package", "private",
		"public", "return", "static", "switch", "throw", "try", "typedef", "untyped", "using", "var", "while", "from", "to", "is", "as"
	]);
	static final TS_VALUES = byLength(["this", "true", "false", "null", "super", "undefined"]);
	static final HX_VALUES = byLength(["this", "true", "false", "null", "super", "trace"]);
	static final TS_BUILTINS = byLength(["any", "number", "string", "boolean", "never", "unknown", "object", "symbol", "bigint"]);
	static final HX_BUILTINS = byLength(["Int", "Float", "Bool", "String", "Void", "Dynamic", "Null"]);

	static function byLength(words:Array<String>):Array<Array<String>> {
		var out:Array<Array<String>> = [for (_ in 0...13) []];
		for (w in words)
			out[w.length].push(w);
		return out;
	}

	function keyword(a:Int, b:Int):Int {
		var l = b - a;
		if (l >= 13) return NONE;
		var hx = lang == Haxe;
		if (inList((hx ? HX_WORDS : TS_WORDS)[l], a)) return KW;
		if (inList((hx ? HX_VALUES : TS_VALUES)[l], a)) return VALUE;
		if (inList((hx ? HX_BUILTINS : TS_BUILTINS)[l], a)) return BUILTIN;
		return NONE;
	}

	function inList(words:Array<String>, a:Int):Bool {
		for (w in words) {
			var k = 0;
			while (k < w.length && StringTools.fastCodeAt(s, a + k) == StringTools.fastCodeAt(w, k))
				k++;
			if (k == w.length) return true;
		}
		return false;
	}

	// ---- templates

	function template() {
		var q = lang == Haxe ? "'".code : "`".code;
		var st = i;
		while (i < n) {
			var c = code(i);
			if (c == "\\".code) {
				i += 2;
				continue;
			}
			if (c == q) {
				emit(st, ++i, Str);
				pop();
				return;
			}
			if (c == "$".code && lang == Haxe && code(i + 1) == "$".code) {
				i += 2;
				continue;
			}
			if (c == "$".code && code(i + 1) == "{".code) {
				emit(st, i, Str);
				emit(i, i + 2, Punct);
				i += 2;
				push(SUBST | EXPR);
				return;
			}
			if (c == "$".code && lang == Haxe && isIdentStart(code(i + 1))) {
				emit(st, i, Str);
				emit(i, i + 1, Punct);
				i++;
				while (i < n && isIdentPart(code(i)))
					i++;
				st = i;
				continue;
			}
			i++;
		}
		if (i > n) i = n;
		emit(st, n, Str);
	}

	// ---- markup

	// a tag's or an attribute's name at i (markup's: letters, "_", ":", then digits, "-", "." too): its end
	function nameEnd(k:Int):Int {
		var st = k;
		while (k < n) {
			var c = code(k);
			var ok = (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == ":".code
				|| (k > st && ((c >= "0".code && c <= "9".code) || c == "-".code || c == ".".code));
			if (!ok) break;
			k++;
		}
		return k;
	}

	// markup at the "<" at i (where an expression starts): read and true, or false (code)
	function markup():Bool {
		var next = code(i + 1);
		if (next == ">".code) {
			setTop(top() & ~EXPR);
			emit(i, i + 2, Punct);
			i += 2;
			push(CHILDREN);
			return true;
		}
		if (!(next == "_".code || (next >= "a".code && next <= "z".code) || (next >= "A".code && next <= "Z".code))) return false;
		var e = nameEnd(i + 1);
		// (a generic's parameters: <T,>, <T extends U>, <T = U>)
		var after = code(e);
		if (after == ",".code || after == "=".code && code(e + 1) != "{".code && code(e + 1) != '"'.code && code(e + 1) != "'".code) return false;
		if (lang == Tsx && after == " ".code && s.substr(e + 1, 8) == "extends ") return false;
		setTop(top() & ~EXPR);
		emit(i, i + 1, Punct);
		emit(i + 1, e, Tag);
		i = e;
		push(TAG);
		return true;
	}

	function tag() {
		var c = code(i);
		if (c == " ".code || c == "\t".code || c == "\r".code) {
			i++;
			return;
		}
		if (c == "/".code && code(i + 1) == "*".code) {
			emit(i, i + 2, Comment);
			i += 2;
			push(COMMENT);
			return;
		}
		if (c == "/".code && code(i + 1) == "/".code) {
			emit(i, n, Comment);
			i = n;
			return;
		}
		if (c == ">".code) {
			emit(i, ++i, Punct);
			setTop(CHILDREN);
			return;
		}
		if (c == "/".code && code(i + 1) == ">".code) {
			emit(i, i + 2, Punct);
			i += 2;
			pop();
			return;
		}
		if (c == "{".code) {
			emit(i, ++i, Punct);
			push(HOLE | EXPR);
			return;
		}
		if (c == '"'.code || c == "'".code) {
			quoted(c);
			return;
		}
		if (c == "=".code) {
			emit(i, ++i, Punct);
			return;
		}
		var e = nameEnd(i);
		if (e > i) {
			emit(i, e, Attribute);
			i = e;
		} else i++;
	}

	function close() {
		var c = code(i);
		if (c == ">".code) {
			emit(i, ++i, Punct);
			// (the closing tag and the element's content)
			pop();
			pop();
			return;
		}
		var e = nameEnd(i);
		if (e > i) {
			emit(i, e, Tag);
			i = e;
		} else i++;
	}

	function children() {
		var c = code(i);
		if (c == "<".code) {
			if (code(i + 1) == "/".code) {
				emit(i, i + 2, Punct);
				i += 2;
				var e = nameEnd(i);
				emit(i, e, Tag);
				i = e;
				push(CLOSE);
				return;
			}
			var next = code(i + 1);
			if (next == ">".code) {
				emit(i, i + 2, Punct);
				i += 2;
				push(CHILDREN);
				return;
			}
			var e = nameEnd(i + 1);
			emit(i, i + 1, Punct);
			emit(i + 1, e, Tag);
			i = e;
			push(TAG);
			return;
		}
		if (c == "{".code) {
			emit(i, ++i, Punct);
			push(HOLE | EXPR);
			return;
		}
		while (i < n && code(i) != "<".code && code(i) != "{".code)
			i++;
	}

	static inline function isDigit(c:Int):Bool
		return c >= "0".code && c <= "9".code;

	static inline function isIdentStart(c:Int):Bool
		return (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == "$".code || c >= 0x80;

	static inline function isIdentPart(c:Int):Bool
		return isIdentStart(c) || isDigit(c);
}
