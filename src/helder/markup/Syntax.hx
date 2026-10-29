package helder.markup;

// A markup literal's syntax, the same in Haxe (the literal's source as
// written) and TypeScript (built from TSX's tree): elements, fragments,
// attributes, text with JSX's whitespace rule and entities decoded,
// holes ({expr} children and attribute values, kept as their code and
// offset). Plain Haxe: used by the Haxe macro and by helder's compiler.

enum PKind {
	PElement(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int);
	PFragment(children:Array<PNode>);
	PText(text:String);
	PExpr(code:String, at:Int);
}

typedef PNode = {kind:PKind};
typedef PAttr = {name:String, value:PValue, at:Int};

enum PValue {
	AStatic(s:String);
	AFlag;
	AExpr(code:String, at:Int);
	ASpread(code:String, at:Int);
}

// A recursive-descent parser of a markup literal: elements, fragments,
// attributes (name="text", name='text', name={expr}, name, {...expr}),
// text with entities, {expr} children (balanced braces, strings and
// comments skipped); errors at their offset in the literal (fail)
class Parser {
	final s:String;
	// (an error: its message and where, an offset in s and a length; it throws)
	final fail:(message:String, at:Int, length:Int) -> Dynamic;
	var i = 0;

	public function new(s:String, fail) {
		this.s = s;
		this.fail = fail;
	}

	function error(msg:String, at:Int, len = 1):Dynamic
		return fail("markup: " + msg, at, len);

	public function document():PNode {
		var n = element();
		skipSpace();
		if (i < s.length) error("one root element (wrap several in <>...</>)", i);
		return n;
	}

	function element():PNode {
		var start = i;
		expect("<");
		var name = readName();
		if (name == "") {
			expect(">");
			var children = content("");
			return {kind: PFragment(children)};
		}
		var attrs:Array<PAttr> = [];
		while (true) {
			skipSpace();
			if (i >= s.length) error("unterminated <" + name + ">", start, name.length + 1);
			var c = s.charAt(i);
			if (c == "/") {
				i++;
				expect(">");
				return {kind: PElement(name, attrs, [], start + 1)};
			}
			if (c == ">") {
				i++;
				break;
			}
			if (c == "{") {
				var at = i;
				var code = braces();
				var t = StringTools.trim(code);
				if (!StringTools.startsWith(t, "...")) error("an attribute is name={expr}; {...expr} spreads", at, code.length + 2);
				var off = code.indexOf("...") + 3;
				attrs.push({name: "...", value: ASpread(code.substr(off), at + 1 + off), at: at});
				continue;
			}
			var anAt = i;
			var an = readName();
			if (an == "") error("an attribute name", i);
			skipSpace();
			if (i < s.length && s.charAt(i) == "=") {
				i++;
				skipSpace();
				var q = s.charAt(i);
				if (q == '"' || q == "'") {
					var e = s.indexOf(q, i + 1);
					if (e < 0) error("unterminated attribute value", i);
					attrs.push({name: an, value: AStatic(Entities.decode(s.substring(i + 1, e))), at: anAt});
					i = e + 1;
				} else if (q == "{") {
					var at = i + 1;
					var code = braces();
					attrs.push({name: an, value: AExpr(code, at), at: anAt});
				} else error("an attribute value: \"text\" or {expr}", i);
			} else attrs.push({name: an, value: AFlag, at: anAt});
		}
		var children = content(name);
		return {kind: PElement(name, attrs, children, start + 1)};
	}

	// children until </name>
	function content(name:String):Array<PNode> {
		var out:Array<PNode> = [];
		var text = new StringBuf(), hasText = false;
		function flush() {
			if (!hasText) return;
			var t = Whitespace.clean(text.toString());
			if (t != null) out.push({kind: PText(Entities.decode(t))});
			text = new StringBuf();
			hasText = false;
		}
		while (true) {
			if (i >= s.length) error("unterminated <" + name + ">: no </" + name + ">", 0, name.length + 1);
			var c = s.charAt(i);
			if (c == "<") {
				if (s.charAt(i + 1) == "/") {
					flush();
					var at = i;
					i += 2;
					var closing = readName();
					skipSpace();
					expect(">");
					if (closing != name) error("</" + closing + "> closes <" + name + ">", at, closing.length + 3);
					return out;
				}
				flush();
				out.push(element());
			} else if (c == "{") {
				flush();
				var at = i + 1;
				var code = braces();
				out.push({kind: PExpr(code, at)});
			} else {
				text.add(c);
				hasText = true;
				i++;
			}
		}
	}

	// {...}: the code between the braces (balanced; strings, their ${...},
	// comments and nested markup skipped, the markup read as markup)
	function braces():String {
		var start = i;
		expect("{");
		var depth = 1;
		// (whether each open "(" is a condition's, after if, while or for; whether the last closed one was)
		var parens:Array<Bool> = [], cond = false;
		while (i < s.length) {
			var c = s.charAt(i);
			switch c {
				case "{":
					depth++;
					i++;
				case "}":
					depth--;
					i++;
					if (depth == 0) return s.substring(start + 1, i - 1);
				case "(":
					parens.push(["if", "while", "for"].indexOf(wordBefore(start)) >= 0);
					i++;
				case ")":
					cond = parens.length > 0 && parens.pop();
					i++;
				case '"' | "'":
					i++;
					while (i < s.length && s.charAt(i) != c) {
						if (s.charAt(i) == "\\") i += 2;
						else if (c == "'" && s.charAt(i) == "$" && s.charAt(i + 1) == "{") {
							i++;
							braces();
						} else if (c == "'" && s.substr(i, 2) == "$$") i += 2;
						else i++;
					}
					i++;
				case "/" if (s.charAt(i + 1) == "/"):
					while (i < s.length && s.charAt(i) != "\n")
						i++;
				case "/" if (s.charAt(i + 1) == "*"):
					var e = s.indexOf("*/", i + 2);
					i = e < 0 ? s.length : e + 2;
				case "<" if (markupAt(start, cond)):
					element();
				case _:
					i++;
			}
		}
		return error("unterminated {", start);
	}

	// whether the "<" at i starts markup: "<name" or "<>" where an expression
	// starts (not after a value: a name, a number, ")" but a condition's, "]",
	// a string; after return, throw, else, do, untyped)
	function markupAt(start:Int, cond:Bool):Bool {
		var n = s.charCodeAt(i + 1);
		if (!(n == ">".code || n == "_".code || (n >= "a".code && n <= "z".code) || (n >= "A".code && n <= "Z".code))) return false;
		var w = wordBefore(start);
		if (w != "") return ["return", "throw", "else", "do", "untyped"].indexOf(w) >= 0;
		var j = i - 1;
		while (j > start && StringTools.isSpace(s, j))
			j--;
		return switch s.charAt(j) {
			case ")": cond;
			case "]" | '"' | "'": false;
			case _: true;
		}
	}

	// the name or number right before i (spaces between), or ""
	function wordBefore(start:Int):String {
		var j = i;
		while (j > start + 1 && StringTools.isSpace(s, j - 1))
			j--;
		var e = j;
		while (j > start + 1 && ~/[A-Za-z0-9_]/.match(s.charAt(j - 1)))
			j--;
		return s.substring(j, e);
	}

	function readName():String {
		var start = i;
		while (i < s.length) {
			var c = s.charCodeAt(i);
			var ok = (c >= "a".code && c <= "z".code) || (c >= "A".code && c <= "Z".code) || c == "_".code || c == ":".code
				|| (i > start && ((c >= "0".code && c <= "9".code) || c == "-".code || c == ".".code));
			if (!ok) break;
			i++;
		}
		return s.substring(start, i);
	}

	function skipSpace() {
		while (i < s.length && StringTools.isSpace(s, i))
			i++;
	}

	function expect(c:String) {
		if (s.substr(i, c.length) != c) error('"$c" expected', i);
		i += c.length;
	}
}

// JSX's rule for text between tags: lines trimmed (the first line's start
// and the last's end kept), lines empty after that dropped, the rest joined
// with one space; null when nothing is left
class Whitespace {
	public static function clean(t:String):Null<String> {
		var lines = t.split("\n");
		var out = [];
		for (k in 0...lines.length) {
			var l = StringTools.replace(lines[k], "\t", " ");
			if (k > 0) l = StringTools.ltrim(l);
			if (k < lines.length - 1) l = StringTools.rtrim(l);
			if (lines.length > 1 && StringTools.trim(l) == "") continue;
			out.push(l);
		}
		var r = out.join(" ");
		return r == "" ? null : r;
	}
}

class Entities {
	public static function decode(s:String):String {
		if (s.indexOf("&") < 0) return s;
		return ~/&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);/g.map(s, r -> {
			var e = r.matched(1);
			if (StringTools.startsWith(e, "#x")) return String.fromCharCode(Std.parseInt("0x" + e.substr(2)));
			if (StringTools.startsWith(e, "#")) return String.fromCharCode(Std.parseInt(e.substr(1)));
			return switch e {
				case "amp": "&";
				case "lt": "<";
				case "gt": ">";
				case "quot": '"';
				case "apos": "'";
				case "nbsp": " ";
				case "lbrace": "{";
				case "rbrace": "}";
				case _: r.matched(0);
			}
		});
	}
}
