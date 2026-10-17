package hxmc.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.ExprTools;

// The markup macro: a markup literal (Haxe's parser gives
// @:markup "<...>", the source as written from its "<") becomes
//
//   {var h0:Any = <hole>; ...; new hxmc.view.View(function(parent, before, out) {...}, parts, "File.hx:12")}
//
// its holes ({expr} children and attribute values, spreads) evaluated in
// source order where the literal is, and a mount function of direct calls
// to the renderer (Host) and Render: each element made by tag, put in its
// parent, its attributes set (static ones straight to the renderer, holes
// through Render, which binds the reactive ones), its children after it:
// static text joined at compile time, runs of text and holes through
// Render (whether a hole is text is known when it runs); components called
// by Render.component in an owner of their own, through a factory
// (() -> Name({props})), so that Haxe checks the props, their children a
// literal of their own. The expressions inside a literal are parsed at
// their positions in the file (errors point into the markup) and
// transformed in turn, so markup nests through them
// ({[for (i in items) <text>{i}</text>]}).
class MarkupMacro {
	@:allow(hxmc.view.Literal) static var count = 0;

	// the Markup interface's build macro: every field's literals
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null): fn.expr = transform(fn.expr);
				case FVar(t, e) if (e != null): f.kind = FVar(t, transform(e));
				case FProp(g, s, t, e) if (e != null): f.kind = FProp(g, s, t, transform(e));
				case _:
			}
		return fields;
	}

	// e with its markup literals compiled
	public static function transform(e:Expr):Expr
		return switch e.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(s))}): compile(s, e.pos);
			case _: e.map(transform);
		}

	static function compile(src:String, pos:Position):Expr {
		var info = Context.getPosInfos(pos);
		var root = new Parser(src, info.file, info.min).document();
		return new Literal(info.file, info.min, pos).compile(root);
	}

	@:allow(hxmc.view.Literal) static function exprNotEmpty(c:PNode):Bool
		return switch c.kind {
			case PExpr(code, _): StringTools.trim(stripComments(code)) != "";
			case _: true;
		}

	@:allow(hxmc.view.Literal) static function isComponent(name:String):Bool {
		var last = name.split(".").pop();
		return name.indexOf(".") >= 0 || (last.length > 0 && last.charAt(0) == last.charAt(0).toUpperCase() && last.charAt(0) != last.charAt(0).toLowerCase());
	}

	// an embedded expression, parsed at its place in the file and
	// transformed (null: empty, or only comments)
	@:allow(hxmc.view.Literal) static function expr(code:String, file:String, at:Int, required = false):Null<Expr> {
		if (StringTools.trim(stripComments(code)) == "") {
			if (required) Context.error("markup: an empty expression", position(file, at - 1, code.length + 2));
			return null;
		}
		var e = Context.parseInlineString(code, position(file, at, code.length));
		return transform(e);
	}

	static function stripComments(s:String):String
		return ~/\/\*[\s\S]*?\*\//g.replace(~/\/\/[^\n]*/g.replace(s, ""), "");

	public static function position(file:String, min:Int, len:Int):Position
		return Context.makePosition({file: file, min: min, max: min + len});

	static final lineCache = new Map<String, Array<Int>>();

	@:allow(hxmc.view.Literal) static function lineOf(file:String, offset:Int):Int {
		var starts = lineCache.get(file);
		if (starts == null) {
			starts = [0];
			var content = try sys.io.File.getContent(file) catch (e:Dynamic) "";
			for (i in 0...content.length)
				if (content.charCodeAt(i) == "\n".code) starts.push(i + 1);
			lineCache.set(file, starts);
		}
		var line = 1;
		for (i in 0...starts.length)
			if (starts[i] <= offset) line = i + 1;
		return line;
	}
}

// One literal's code: its holes' declarations, its mount function's statements
class Literal {
	final file:String;
	final base:Int;
	final pos:Position;
	final id = MarkupMacro.count++;
	final holes:Array<Expr> = [];
	var vars = 0;
	// (a literal of components and holes only: its components' factories are
	// holes, shared by mount and parts)
	var shared = false;

	public function new(file:String, base:Int, pos:Position) {
		this.file = file;
		this.base = base;
		this.pos = pos;
	}

	static final P = macro __p;
	static final B = macro __b;
	static final O = macro __o;

	public function compile(root:PNode):Expr {
		shared = valueOnly(root);
		// (the mount code for each renderer: the holes made by the first pass, found again by the others)
		var rs = HostMacro.renderers();
		var cases:Array<Case> = [];
		var only:Null<Expr> = null;
		for (i in 0...rs.length) {
			pass = i;
			cursor = 0;
			var body = forRenderer(mountBody(root), i);
			var n = rs[i].node;
			var typed = macro {
				var __p:$n = cast __p0;
				var __b:Null<$n> = cast __b0;
				var __o:Null<Array<$n>> = cast __o0;
				$b{body};
			};
			if (rs.length == 1) only = typed else cases.push({values: [macro $v{i}], expr: typed});
		}
		var mountExpr = only != null ? only : {expr: ESwitch(macro __r, cases, macro {}), pos: pos};
		var parts = macro null;
		if (shared) {
			var items = [];
			collect(root, items);
			parts = macro function():Array<Any> return ([$a{items}] : Array<Any>);
		}
		var line = MarkupMacro.lineOf(file, base);
		var source = haxe.io.Path.withoutDirectory(file) + ":" + line;
		var mount = macro function(__r:Int, __p0:Dynamic, __b0:Dynamic, __o0:Dynamic):Void $mountExpr;
		var out = holes.concat([macro @:pos(pos) new hxmc.view.View($mount, $parts, $v{source})]);
		return macro @:pos(pos) $b{out};
	}

	// (which renderer's code is being made; the next hole to find again)
	var pass = 0;
	var cursor = 0;

	// the code made for a renderer: __HOST__ its class, __RT__ its runtime
	static function forRenderer(body:Array<Expr>, i:Int):Array<Expr> {
		var host = HostMacro.rendererPath(i), rt = HostMacro.runtime(i);
		function sub(e:Expr):Expr
			return switch e.expr {
				case EConst(CIdent("__HOST__")): macro @:pos(e.pos) $p{host};
				case EConst(CIdent("__RT__")): macro @:pos(e.pos) $p{rt};
				case EObjectDecl(fields):
					// (in place: map would lose the fields' name_pos)
					for (f in fields)
						f.expr = sub(f.expr);
					e;
				case _: e.map(sub);
			}
		return [for (e in body) sub(e)];
	}

	function mountBody(root:PNode):Array<Expr> {
		return switch root.kind {
			case PElement(name, attrs, children, at) if (MarkupMacro.isComponent(name)):
				[macro @:pos(pos) __RT__.component(__p, __b, __o, ${factory(name, attrs, children, at)})];
			case PElement(name, attrs, children, _): element(name, attrs, children, P, true);
			case PFragment(children): this.children(children, P, B, O, macro false);
			case _: [];
		}
	}

	// the literal's hole for e: a local, evaluated in source order
	function hole(e:Expr, ?type:ComplexType):Expr {
		if (pass > 0) {
			var name = '__h${id}_${cursor++}';
			return macro @:pos(e.pos) $i{name};
		}
		var name = '__h${id}_${holes.length}';
		holes.push({expr: EVars([{name: name, type: type == null ? macro :Any : type, expr: e}]), pos: e.pos});
		return macro @:pos(e.pos) $i{name};
	}

	function fresh(prefix:String):String
		return '__$prefix${id}_${vars++}';

	// content of components, holes and fragments only (no element, no text)
	static function valueOnly(n:PNode):Bool
		return switch n.kind {
			case PElement(name, _, _, _): MarkupMacro.isComponent(name);
			case PFragment(children): Lambda.foreach(clean(children), valueOnly);
			case PExpr(_, _): true;
			case PText(_): false;
		}

	// a shared literal's parts: its components called, its holes
	function collect(n:PNode, out:Array<Expr>)
		switch n.kind {
			case PFragment(children):
				for (c in clean(children))
					collect(c, out);
			case PElement(_, _, _, _):
				var f = factories.shift();
				out.push(macro $f());
			case PExpr(_, _):
				out.push(valueHoles.shift());
			case PText(_):
		}

	// (a shared literal's factories and holes, in source order, for collect)
	final factories:Array<Expr> = [];
	final valueHoles:Array<Expr> = [];

	static function clean(cs:Array<PNode>):Array<PNode>
		return [for (c in cs) if (MarkupMacro.exprNotEmpty(c)) c];

	// an element: made, put in parent (top: before __b, pushed to __o), its
	// attributes, its children
	function element(name:String, attrs:Array<PAttr>, children:Array<PNode>, parent:Expr, top:Bool):Array<Expr> {
		var v = fresh("e");
		var e = macro $i{v};
		var out = [
			macro @:pos(pos) var $v = __HOST__.createElement($v{name}),
			top ? macro @:pos(pos) __RT__.put($parent, $e, __b, __o) : macro @:pos(pos) __HOST__.insert($parent, $e, null)
		];
		for (a in attrs) {
			var s = attr(e, a);
			if (s != null) out.push(s);
		}
		var kids = clean(children);
		if (kids.length == 0) return out;
		if (Lambda.foreach(kids, k -> k.kind.match(PText(_) | PExpr(_, _)))) {
			// (text only: the element's own text when it holds text)
			var parts = [for (k in kids) part(k)];
			if (Lambda.foreach(kids, k -> k.kind.match(PText(_)))) out.push(macro @:pos(pos) __RT__.textOf($e, ${join(kids)}));
			else out.push(macro @:pos(pos) __RT__.flat($e, $v{name}, ([$a{parts}] : Array<Any>)));
			return out;
		}
		var t = fresh("t");
		out.push(macro @:pos(pos) var $t = __HOST__.holdsText($e));
		return out.concat(this.children(kids, e, macro null, macro null, macro $i{t}));
	}

	// children into parent before before (pushed to out), runs of text and
	// holes joined (span: in an element that holds text, as spans)
	function children(cs:Array<PNode>, parent:Expr, before:Expr, out:Expr, span:Expr):Array<Expr> {
		var s:Array<Expr> = [];
		var run:Array<PNode> = [], parts:Array<Expr> = [];
		var top = !before.expr.match(EConst(CIdent("null")));
		function flush() {
			if (run.length == 0) return;
			if (Lambda.foreach(run, k -> k.kind.match(PText(_)))) s.push(macro @:pos(pos) __RT__.text($parent, $before, $out, ${join(run)}, $span));
			else if (run.length == 1) s.push(macro @:pos(pos) __RT__.hole($parent, $before, $out, ${parts[0]}, $span));
			else s.push(macro @:pos(pos) __RT__.run($parent, $before, $out, ([$a{parts}] : Array<Any>), $span));
			run = [];
			parts = [];
		}
		for (c in clean(cs))
			switch c.kind {
				case PText(_) | PExpr(_, _):
					run.push(c);
					parts.push(part(c));
				case PElement(name, attrs, children, at) if (MarkupMacro.isComponent(name)):
					flush();
					s.push(macro @:pos(pos) __RT__.component($parent, $before, $out, ${factory(name, attrs, children, at)}));
				case PElement(name, attrs, children, _):
					flush();
					s = s.concat(element(name, attrs, children, parent, top));
				case PFragment(children):
					flush();
					s = s.concat(this.children(children, parent, before, out, macro false));
			}
		flush();
		return s;
	}

	// a child of a run: its text, or its hole
	function part(c:PNode):Expr
		return switch c.kind {
			case PText(t): macro $v{t};
			case PExpr(code, at):
				var h = hole(MarkupMacro.expr(code, file, base + at));
				if (shared && pass == 0) valueHoles.push(h);
				h;
			case _: throw "unreachable";
		}

	static function join(run:Array<PNode>):Expr
		return macro $v{[for (k in run) switch k.kind {
			case PText(t): t;
			case _: "";
		}].join("")};

	// an attribute's statement (null: none, as key)
	function attr(e:Expr, a:PAttr):Null<Expr> {
		var name = a.name;
		var event = StringTools.startsWith(name, "on") && name.length > 2;
		var ap = MarkupMacro.position(file, base + a.at, name.length);
		return switch a.value {
			case AStatic(_) | AFlag:
				var v = switch a.value {
					case AStatic(s): macro $v{s};
					case _: macro true;
				}
				if (event) macro @:pos(ap) __HOST__.listen($e, $v{name}, $v);
				else switch name {
					case "key": null;
					case "style": macro @:pos(ap) __HOST__.setStyle($e, $v);
					case "ref": macro @:pos(ap) __RT__.attr($e, $v{name}, $v);
					case _: macro @:pos(ap) __HOST__.setProperty($e, $v{name}, $v);
				}
			case AExpr(code, at):
				var x = MarkupMacro.expr(code, file, base + at, true);
				// (a literal number or string: set as a static value is, never bound)
				if (!event && name != "ref" && name != "key" && name != "style" && x.expr.match(EConst(CInt(_) | CFloat(_) | CString(_, DoubleQuotes))))
					return macro @:pos(ap) __HOST__.setProperty($e, $v{name}, $x);
				var h = hole(x);
				if (event) macro @:pos(ap) __HOST__.listen($e, $v{name}, $h);
				else switch name {
					case "key": null;
					case "ref": macro @:pos(ap) __RT__.ref($e, $h);
					case "style": macro @:pos(ap) __RT__.style($e, $h);
					case _: macro @:pos(ap) __RT__.prop($e, $v{name}, $h);
				}
			case ASpread(code, at):
				var h = hole(MarkupMacro.expr(code, file, base + at, true));
				macro @:pos(ap) __RT__.spread($e, $h);
		}
	}

	// a component's factory: () -> Name({props}), its content the children
	// prop (a literal of its own, evaluated when it is called)
	function factory(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int):Expr {
		var fields:Array<ObjectField> = [];
		for (a in attrs) {
			var ap = MarkupMacro.position(file, base + a.at, a.name.length);
			var v = switch a.value {
				case AStatic(s): macro @:pos(ap) $v{s};
				case AFlag: macro @:pos(ap) true;
				case AExpr(code, at): MarkupMacro.expr(code, file, base + at, true);
				case ASpread(_, at): Context.error("markup: a component's props cannot be spread", MarkupMacro.position(file, base + at, 3));
			}
			// (name_pos: the field name's position, which the compiler reads though ObjectField does not declare it)
			var field:Dynamic = {field: a.name, expr: v, quotes: ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(a.name) ? Unquoted : Quoted, name_pos: ap};
			fields.push(field);
		}
		var kids = clean(children);
		if (kids.length > 0) fields.push({field: "children", expr: new Literal(file, base, pos).compile({kind: PFragment(kids)})});
		var p = MarkupMacro.position(file, base + at, name.length + 1);
		var callee = macro @:pos(p) $p{name.split(".")};
		var props = {expr: EObjectDecl(fields), pos: p};
		var call = {expr: ECall(callee, [props]), pos: p};
		var f = {expr: EFunction(FAnonymous, {args: [], ret: macro :Any, expr: {expr: EReturn(call), pos: p}}), pos: p};
		if (!shared) return f;
		var h = hole(f, macro :Void->Any);
		if (pass == 0) factories.push(h);
		return h;
	}
}

// --- the markup's own syntax ---

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
// comments skipped); errors at their offset in the file
class Parser {
	final s:String;
	final file:String;
	final base:Int;
	var i = 0;

	public function new(s:String, file:String, base:Int) {
		this.s = s;
		this.file = file;
		this.base = base;
	}

	function error(msg:String, at:Int, len = 1):Dynamic
		return Context.error("markup: " + msg, MarkupMacro.position(file, base + at, len));

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
#end
