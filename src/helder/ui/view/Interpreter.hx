package helder.ui.view;

import helder.markup.Plan;
import helder.markup.Syntax;
import helder.ui.*;
import helder.view.Flow.Mountable;

// Markup interpreted: a parsed literal (helder.markup.Syntax) made into
// helder.ui's nodes at run time, in this process, with no build (the
// studio's design files: apps/studio/DESIGN.md). A third Target of the same
// Plan as the macro's and TypeScript's (view's DESIGN.md 7.2), so that what
// is made, in what order, and which attributes go where are the compiler's
// decisions; its steps run at once instead of being written as code. The
// nodes are NodeRenderer's (createElement, setAttribute: the path a name
// known only at run time takes, every attribute's parser), the runtime's
// part a static one's (no holes to bind). What a design cannot run is drawn
// and marked where it is, the rest still drawn: a hole that is not a
// literal ({items.length}), an unknown element, a component (code: not
// drawn yet), a value its attribute rejects; each in errors, at its offset.
class Interpreted implements Mountable<Node> {
	final root:PNode;
	final base:Int;
	// the last mount's nodes, its elements' offsets (where each node's markup starts) and its errors
	public var nodes(default, null):Array<Node> = [];
	public var sources(default, null) = new haxe.ds.ObjectMap<Node, Int>();
	public var errors(default, null):Array<{at:Int, message:String}> = [];

	// (base: the offset of root's text in its file, added to each offset)
	public function new(root:PNode, base = 0) {
		this.root = root;
		this.base = base;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var t = new Interpreter(base);
		sources = t.sources;
		errors = t.errors;
		var out:Array<Node> = [];
		try {
			var m:Mount = new Plan(t, Interpreter.RENDERER).compile(root).run(new Map());
			m.into(parent, before, out);
		} catch (e:Dynamic) {
			// (what the planner rejects, or a step that failed: the whole literal's, marked in its place, after what it made)
			var n = t.failed(Std.string(e), base);
			NodeRenderer.insert(parent, n, before);
			out.push(n);
		}
		return nodes = out;
	}
}

// One step of an interpreted literal: its value in a scope (the literal's
// locals: its holes, its elements)
class Step {
	public final run:Map<String, Dynamic>->Dynamic;
	// (a number or a string as written: Target.isLiteral)
	public final literal:Bool;

	public function new(run, literal = false) {
		this.run = run;
		this.literal = literal;
	}
}

// A hole the interpreter does not run: its code, where it is
class Code {
	public final code:String;
	public final at:Int;

	public function new(code, at) {
		this.code = code;
		this.at = at;
	}
}

class Interpreter implements Target<Step> {
	public static inline final RENDERER = "helder.ui.view.NodeRenderer";
	static final NIL = new Step(_ -> null);
	static final ERROR = "#ef4444";

	public final sources = new haxe.ds.ObjectMap<Node, Int>();
	public final errors:Array<{at:Int, message:String}> = [];

	final base:Int;
	// (the elements made for a name none is, told where they are when located)
	final unknown = new haxe.ds.ObjectMap<Node, String>();

	public function new(base:Int)
		this.base = base;

	// ---- the facts: a design has no types, its values are literals

	public function error(message:String, where:Null<Where>):Dynamic
		throw message;

	public function elements(renderer:String):Null<Array<String>>
		return null;

	// a number, a quoted string, true, false or null; any other code a Code
	public function code(code:String, at:Int, renderer:Null<String>, required:Bool):Null<Step> {
		var t = StringTools.trim(Plan.stripComments(code));
		if (t == "") return required ? new Step(_ -> new Code(code, base + at)) : null;
		if (~/^-?[0-9]+$/.match(t)) {
			var v = Std.parseInt(t);
			return new Step(_ -> v, true);
		}
		if (~/^-?([0-9]+\.[0-9]*|\.[0-9]+)([eE][-+]?[0-9]+)?$/.match(t)) {
			var v = Std.parseFloat(t);
			return new Step(_ -> v, true);
		}
		var q = t.charAt(0);
		if ((q == '"' || q == "'") && t.length >= 2 && t.charAt(t.length - 1) == q) {
			var v = unquote(t.substring(1, t.length - 1), q);
			if (v != null) return new Step(_ -> v, true);
		}
		return switch t {
			case "true": new Step(_ -> true);
			case "false": new Step(_ -> false);
			case "null": NIL;
			case _: new Step(_ -> new Code(t, base + at));
		}
	}

	// (a string's text: its escapes read; null: not one string, or one Haxe interpolates)
	static function unquote(s:String, q:String):Null<String> {
		if (q == "'" && s.indexOf("$") >= 0) return null;
		var b = new StringBuf(), i = 0;
		while (i < s.length) {
			var c = s.charAt(i++);
			if (c == q) return null;
			if (c != "\\") {
				b.add(c);
				continue;
			}
			var e = s.charAt(i++);
			b.add(switch e {
				case "n": "\n";
				case "t": "\t";
				case "r": "\r";
				case _: e;
			});
		}
		return b.toString();
	}

	public function isLiteral(e:Step):Bool
		return e.literal;

	public function isPlain(e:Step):Bool
		return true;

	public function mayRead(e:Step):Bool
		return false;

	public function thunk(e:Step):Step
		return new Step(s -> () -> e.run(s));

	public function isFunction(e:Step):Bool
		return false;

	public function handler(e:Step, name:String, renderer:Null<String>, neutral:Bool, where:Where):Step
		return e;

	public function devKeys():Bool
		return false;

	// (the planner's at is the name's, after "<": the element's start kept, as the source map's)
	public function located(element:Step, at:Int):Null<Step>
		return new Step(s -> {
			var n:Node = element.run(s);
			sources.set(n, base + at - 1);
			var why = unknown.get(n);
			if (why != null) errors.push({at: base + at - 1, message: why});
			null;
		});

	public function liveOn():Bool
		return false;

	public function live(value:Step, at:LiveAt):Null<Step>
		return null;

	public function liveIn(e:Step):Step
		return e;

	public function component(name:String, at:Int, renderer:Null<String>):Component<Step>
		return {callee: new Step(_ -> name), children: null};

	// ---- the code, as steps

	public function ident(name:String):Step
		return new Step(s -> s.get(name));

	public function string(v:String, ?where:Where):Step
		return new Step(_ -> v);

	public function bool(b:Bool, ?where:Where):Step
		return new Step(_ -> b);

	public function nil():Step
		return NIL;

	public function isNull(e:Step):Bool
		return e == NIL;

	public function anyArray(items:Array<Step>):Step
		return new Step(s -> [for (i in items) i.run(s)]);

	public function declare(name:String, e:Step, where:Null<Where>):Step
		return new Step(s -> {
			s.set(name, e.run(s));
			null;
		});

	public function call(of:Callee, name:String, args:Array<Step>, where:Null<Where>):Step {
		var f = fn(of, name);
		return new Step(s -> f([for (a in args) a.run(s)]));
	}

	public function holeDecl(name:String, e:Step, factory:Bool):Step
		return declare(name, e, null);

	public function holeRef(name:String, e:Step):Step
		return ident(name);

	public function callValue(f:Step):Step
		return new Step(s -> (f.run(s) : Void->Any)());

	public function partRef(element:Step, ref:Step, where:Where):Step
		return NIL;

	public function keyScope(name:String, key:Step):Step
		return new Step(s -> name + "[" + Std.string(key.run(s)) + "]");

	// (a component is code: drawn as its place, marked, until a design frame's islands are)
	public function factory(c:Component<Step>, props:Array<{name:String, value:Step, at:Int}>, content:Null<Step>, at:Int, agnostic:Bool):Step
		return new Step(s -> {
			var name:String = c.callee.run(s);
			() -> placeholder(name, base + at - 1);
		});

	public function view(v:Planned<Step>):Step
		return new Step(s -> {
			var scope = s.copy();
			for (h in v.holes)
				h.run(scope);
			(new Mount(scope, v.body) : Mountable<Node>);
		});

	// ---- the renderer's, the runtime's and the neutral elements' functions

	function fn(of:Callee, name:String):Array<Dynamic>->Dynamic
		return switch [of, name] {
			case [Host, "createElement"] | [Neutral, "element"]: a -> element(a[0]);
			case [Host, "insert"]: a -> put(a[0], a[1], a[2], null);
			case [Host, "holdsText"]: a -> NodeRenderer.holdsText(a[0]);
			case [Host, "setProperty"] | [Runtime, "prop"] | [Runtime, "attr"]: a -> set(a[0], a[1], a[2]);
			case [Host, "setStyle"] | [Runtime, "style"]: a -> set(a[0], "style", a[1]);
			case [Neutral, "property"] | [Neutral, "prop"]: a -> set(a[0], a[2], a[3]);
			// (behaviour is code: a design's events and refs do nothing)
			case [Host, "listen"] | [Neutral, "listen"] | [Runtime, "ref"]: _ -> null;
			case [Neutral, "part"]: a -> a[0];
			case [Runtime, "put"]: a -> put(a[0], a[1], a[2], a[3]);
			case [Runtime, "textOf"]: a -> textOf(a[0], a[1]);
			case [Runtime, "flat"]: a -> flat(a[0], a[2]);
			case [Runtime, "text"]: a -> text(a[0], a[1], a[2], a[3], a[4]);
			case [Runtime, "hole"]: a -> run(a[0], a[1], a[2], [a[3]], a[4]);
			case [Runtime, "run"]: a -> run(a[0], a[1], a[2], a[3], a[4]);
			case [Runtime, "component"]: a -> put(a[0], (a[3] : Void->Any)(), a[1], a[2]);
			case [Runtime, "componentIn"]: a -> put(a[1], (a[4] : Void->Any)(), a[2], a[3]);
			case [Runtime, "spread"]: a -> mark(a[0], "a spread is code");
			case _: _ -> throw 'markup: $name has no interpreted step';
		}

	function element(tag:String):Node
		return try NodeRenderer.createElement(tag) catch (_:Dynamic) {
			var n = new Node(tag);
			outline(n);
			unknown.set(n, '<$tag> is no element');
			n;
		};

	function put(parent:Node, n:Node, before:Null<Node>, out:Null<Array<Node>>):Dynamic {
		NodeRenderer.insert(parent, n, before);
		if (out != null) out.push(n);
		return null;
	}

	function set(n:Node, name:String, v:Dynamic):Dynamic {
		if (Std.isOfType(v, Code)) return mark(n, '$name={${(v : Code).code}}: code, not run in a design');
		// (an image by its path: helder.asset's, not read here yet)
		if (name == "src" && Std.isOfType(v, String)) return mark(n, 'src="$v": an image by path, not yet');
		try NodeRenderer.setAttribute(n, name, v) catch (e:Dynamic) mark(n, Std.string(e));
		return null;
	}

	function textOf(el:Node, t:String):Dynamic {
		if (NodeRenderer.holdsText(el)) NodeRenderer.setText(el, t) else put(el, NodeRenderer.createText(t), null, null);
		return null;
	}

	// (text and holes in an element that holds text: its text, a Code's written as it is, marked)
	function flat(el:Node, parts:Array<Dynamic>):Dynamic {
		if (!NodeRenderer.holdsText(el)) return run(el, null, null, parts, false);
		var b = new StringBuf();
		for (p in parts)
			if (Std.isOfType(p, Code)) {
				b.add("{" + (p : Code).code + "}");
				mark(el, '{${(p : Code).code}}: code, not run in a design');
			} else if (isText(p)) b.add(Std.string(p));
		NodeRenderer.setText(el, b.toString());
		return null;
	}

	function text(parent:Node, before:Null<Node>, out:Null<Array<Node>>, t:String, span:Bool):Dynamic {
		var n = span ? NodeRenderer.createElement("span") : NodeRenderer.createText("");
		put(parent, n, before, out);
		NodeRenderer.setText(n, t);
		return null;
	}

	// (a run of text and holes: the text joined, a Code drawn as itself in the error's colour)
	function run(parent:Node, before:Null<Node>, out:Null<Array<Node>>, parts:Array<Dynamic>, span:Bool):Dynamic {
		var b = new StringBuf(), has = false;
		function flush() {
			if (has) text(parent, before, out, b.toString(), span);
			b = new StringBuf();
			has = false;
		}
		for (p in parts)
			if (Std.isOfType(p, Code)) {
				flush();
				var c:Code = p;
				var n = span ? NodeRenderer.createElement("span") : NodeRenderer.createText("");
				NodeRenderer.setText(n, "{" + c.code + "}");
				n.style.color = Color.parse(ERROR);
				put(parent, n, before, out);
				sources.set(n, c.at);
				errors.push({at: c.at, message: '{${c.code}}: code, not run in a design'});
			} else if (isText(p)) {
				b.add(Std.string(p));
				has = true;
			}
		flush();
		return null;
	}

	static inline function isText(v:Dynamic):Bool
		return Std.isOfType(v, String) || Std.isOfType(v, Int) || Std.isOfType(v, Float);

	// (a component's place: its name, outlined)
	function placeholder(name:String, at:Int):Node {
		var n = new Node(name);
		outline(n);
		NodeRenderer.setAttribute(n, "padding", 4);
		var t = new TextNode("<" + name + ">");
		t.style.color = Color.parse(ERROR);
		n.insert(t, 0);
		sources.set(n, at);
		errors.push({at: at, message: '<$name> is code: not drawn in a design yet'});
		return n;
	}

	// the whole literal failed: its message in its place
	public function failed(message:String, at:Int):Node {
		var n = new Node("error");
		outline(n);
		NodeRenderer.setAttribute(n, "padding", 4);
		var t = new TextNode(message);
		t.style.color = Color.parse(ERROR);
		n.insert(t, 0);
		errors.push({at: at, message: message});
		return n;
	}

	function mark(n:Node, message:String):Dynamic {
		outline(n);
		errors.push({at: sources.get(n) ?? -1, message: message});
		return null;
	}

	static function outline(n:Node) {
		n.style.outlineWidth = 1;
		n.style.outlineColor = Color.parse(ERROR);
	}
}

// (a literal's mount: its body run with the parent, before and the nodes made)
private class Mount implements Mountable<Node> {
	final scope:Map<String, Dynamic>;
	final body:Array<Step>;

	public function new(scope, body) {
		this.scope = scope;
		this.body = body;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var out:Array<Node> = [];
		into(parent, before, out);
		return out;
	}

	// (the nodes made pushed to out as they are: those made before a failure too)
	public function into(parent:Node, before:Null<Node>, out:Array<Node>) {
		scope.set("__p", parent);
		scope.set("__b", before);
		scope.set("__o", out);
		for (b in body)
			b.run(scope);
	}
}
