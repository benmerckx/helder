package helder.markup;

import helder.markup.Syntax;

// The markup compiler's middle (DESIGN.md 7.2): one literal's code, decided
// here for every language, written by a Target in its own (the Haxe macro's
// expressions; helder's compiler, TypeScript's lowering): its holes ({expr}
// children and attribute values, spreads, components' factories) declared
// in source order where the literal is, and its mount: each element made
// by tag and put in its parent, its attributes set (static ones and values
// of a type never reactive straight to the renderer, the others through
// its runtime, which binds the reactive ones), its children after it
// (static text joined, runs of text and holes through the runtime),
// components called through factories (() -> Name({props}), their children
// a literal of their own). Plain Haxe: no macro API.
class Plan<E> {
	// (every literal planned, in order: its id names its holes and locals)
	public static var count = 0;
	// the root (helder.view.Root: RootView), as a literal's renderer: components only, no code to mount
	public static inline final ROOT = "helder.view.Root";

	final target:Target<E>;
	// the renderer it is compiled for; null: agnostic, for every renderer the program reaches (after typing)
	final renderer:Null<String>;
	final id = count++;
	final holes:Array<E> = [];
	final holeNames:Array<{name:String, factory:Bool}> = [];
	var vars = 0;
	// (a literal of components and holes only: its components' factories are
	// holes, shared by mount and parts)
	var shared = false;
	// (where it starts in its root literal: a component's children's, the component's tag)
	final at:Int;

	public function new(target:Target<E>, renderer:Null<String>, at = 0) {
		this.target = target;
		this.renderer = renderer;
		this.at = at;
	}

	public function compile(root:PNode):E {
		shared = valueOnly(root);
		if (renderer == ROOT && !shared) {
			var n = firstNode(root);
			target.error("markup: " + (n == null ? "text" : "<" + n.name + ">") + " needs a renderer's parent: a root (RootView: UiWindow.run's, Render.open's) holds components only (<Surface>...)",
				n == null ? null : {at: n.at, length: n.name.length});
		}
		var body = mountBody(root);
		var parts:Null<Array<E>> = null;
		if (shared) {
			parts = [];
			collect(root, parts);
		}
		return target.view({
			renderer: renderer,
			holes: holes,
			holeNames: holeNames,
			body: body,
			parts: parts,
			at: at
		});
	}

	function mountBody(root:PNode):Array<E> {
		return switch root.kind {
			case PElement(name, attrs, children, at) if (isComponent(name)):
				[component(name, attrs, children, at, target.ident("__p"), target.ident("__b"), target.ident("__o"))];
			case PElement(name, attrs, children, at): element(name, attrs, children, at, target.ident("__p"), true);
			case PFragment(children): this.children(children, target.ident("__p"), target.ident("__b"), target.ident("__o"), target.bool(false));
			case _: [];
		}
	}

	// the literal's hole for e: a local, evaluated in source order (factory: a component's, Void->Any)
	function hole(e:E, factory = false):E {
		var name = '__h${id}_${holes.length}';
		holes.push(target.holeDecl(name, e, factory));
		holeNames.push({name: name, factory: factory});
		return target.holeRef(name, e);
	}

	function fresh(prefix:String):String
		return '__$prefix${id}_${vars++}';

	// (the first element or text of a literal not of components only: null, a text)
	static function firstNode(n:PNode):Null<{name:String, at:Int}>
		return switch n.kind {
			case PElement(name, _, children, at): isComponent(name) ? null : {name: name, at: at};
			case PFragment(children):
				for (c in clean(children)) {
					if (c.kind.match(PText(_))) return null;
					var f = firstNode(c);
					if (f != null || !valueOnly(c)) return f;
				}
				null;
			case _: null;
		}

	// the renderer of the markup in its holes (a root's: none, agnostic)
	inline function inner():Null<String>
		return renderer == ROOT ? null : renderer;

	// content of components, holes and fragments only (no element, no text)
	static function valueOnly(n:PNode):Bool
		return switch n.kind {
			case PElement(name, _, _, _): isComponent(name);
			case PFragment(children): Lambda.foreach(clean(children), valueOnly);
			case PExpr(_, _): true;
			case PText(_): false;
		}

	// a shared literal's parts: its components called, its holes
	function collect(n:PNode, out:Array<E>)
		switch n.kind {
			case PFragment(children):
				for (c in clean(children))
					collect(c, out);
			case PElement(_, _, _, _):
				var f = factories.shift();
				out.push(target.callValue(f));
			case PExpr(_, _):
				out.push(valueHoles.shift());
			case PText(_):
		}

	// (a shared literal's factories and holes, in source order, for collect)
	final factories:Array<E> = [];
	final valueHoles:Array<E> = [];

	static function clean(cs:Array<PNode>):Array<PNode>
		return [for (c in cs) if (exprNotEmpty(c)) c];

	// (the neutral elements: ui's own, a page's renderer realising them as its elements)
	static function isNeutral(name:String):Bool
		return ["view", "text", "scroll", "image", "icon", "field"].indexOf(name) >= 0 || ~/^(view|text|field):/.match(name);

	// a component's tag: dotted, or capitalized
	public static function isComponent(name:String):Bool {
		var last = name.split(".").pop();
		return name.indexOf(".") >= 0 || (last.length > 0 && last.charAt(0) == last.charAt(0).toUpperCase() && last.charAt(0) != last.charAt(0).toLowerCase());
	}

	public static function exprNotEmpty(c:PNode):Bool
		return switch c.kind {
			case PExpr(code, _): StringTools.trim(stripComments(code)) != "";
			case _: true;
		}

	public static function stripComments(s:String):String
		return ~/\/\*[\s\S]*?\*\//g.replace(~/\/\/[^\n]*/g.replace(s, ""), "");

	// an element: made, put in parent (top: before __b, pushed to __o), its
	// attributes, its children; one its renderer does not list (@:elements) an error
	function element(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int, parent:E, top:Bool):Array<E> {
		if (renderer != null) {
			var els = target.elements(renderer);
			if (els != null && els.indexOf(name) < 0)
				target.error("markup: <" + name + "> is no element of " + renderer + " (" + els.join(", ") + ")", {at: at, length: name.length});
		}
		var v = fresh("e");
		var e = target.ident(v);
		var neutral = isNeutral(name);
		var out = [
			target.declare(v, neutral ? target.call(Neutral, "element", [target.string(name)], null) : target.call(Host, "createElement", [target.string(name)], null), null),
			top ? target.call(Runtime, "put", [parent, e, target.ident("__b"), target.ident("__o")], null) : target.call(Host, "insert", [parent, e, target.nil()], null)
		];
		for (a in attrs) {
			var s = attr(e, a, neutral ? name : null);
			if (s != null) out.push(s);
		}
		var kids = clean(children);
		if (kids.length == 0) return out;
		if (Lambda.foreach(kids, k -> k.kind.match(PText(_) | PExpr(_, _)))) {
			// (text only: the element's own text when it holds text)
			var parts = [for (k in kids) part(k)];
			if (Lambda.foreach(kids, k -> k.kind.match(PText(_)))) out.push(target.call(Runtime, "textOf", [e, join(kids)], null));
			else out.push(target.call(Runtime, "flat", [e, target.string(name), target.anyArray(parts)], null));
			return out;
		}
		var t = fresh("t");
		out.push(target.declare(t, target.call(Host, "holdsText", [e], null), null));
		return out.concat(this.children(kids, e, target.nil(), target.nil(), target.ident(t)));
	}

	// children into parent before before (pushed to out), runs of text and
	// holes joined (span: in an element that holds text, as spans)
	function children(cs:Array<PNode>, parent:E, before:E, out:E, span:E):Array<E> {
		var s:Array<E> = [];
		var run:Array<PNode> = [], parts:Array<E> = [];
		var top = !target.isNull(before);
		function flush() {
			if (run.length == 0) return;
			if (Lambda.foreach(run, k -> k.kind.match(PText(_)))) s.push(target.call(Runtime, "text", [parent, before, out, join(run), span], null));
			else if (run.length == 1) s.push(target.call(Runtime, "hole", [parent, before, out, parts[0], span], null));
			else s.push(target.call(Runtime, "run", [parent, before, out, target.anyArray(parts), span], null));
			run = [];
			parts = [];
		}
		for (c in clean(cs))
			switch c.kind {
				case PText(_) | PExpr(_, _):
					run.push(c);
					parts.push(part(c));
				case PElement(name, attrs, children, at) if (isComponent(name)):
					flush();
					s.push(component(name, attrs, children, at, parent, before, out));
				case PElement(name, attrs, children, at):
					flush();
					s = s.concat(element(name, attrs, children, at, parent, top));
				case PFragment(children):
					flush();
					s = s.concat(this.children(children, parent, before, out, target.bool(false)));
			}
		flush();
		return s;
	}

	// a child of a run: its text, or its hole
	function part(c:PNode):E
		return switch c.kind {
			case PText(t): target.string(t);
			case PExpr(code, at):
				var h = hole(target.code(code, at, inner(), false));
				if (shared) valueHoles.push(h);
				h;
			case _: throw "unreachable";
		}

	function join(run:Array<PNode>):E
		return target.string([for (k in run) switch k.kind {
			case PText(t): t;
			case _: "";
		}].join(""));

	// an attribute's statement (null: none, as key)
	function attr(e:E, a:PAttr, ?tag:String):Null<E> {
		var name = a.name;
		var event = StringTools.startsWith(name, "on") && name.length > 2;
		var ap = {at: a.at, length: name.length};
		if (tag != null) return neutralAttr(e, a, tag, event, ap);
		return switch a.value {
			case AStatic(_) | AFlag:
				var v = switch a.value {
					case AStatic(s): target.string(s);
					case _: target.bool(true);
				}
				if (event) target.call(Host, "listen", [e, target.string(name), v], ap);
				else switch name {
					case "key": null;
					case "style": target.call(Host, "setStyle", [e, v], ap);
					case "ref": target.call(Runtime, "attr", [e, target.string(name), v], ap);
					case _: target.call(Host, "setProperty", [e, target.string(name), v], ap);
				}
			case AExpr(code, at):
				var x = target.code(code, at, inner(), true);
				// (a literal number or string: set as a static value is, never bound)
				if (!event && name != "ref" && name != "key" && name != "style" && target.isLiteral(x))
					return target.call(Host, "setProperty", [e, target.string(name), x], ap);
				var plain = !event && name != "ref" && name != "key" && name != "style" && target.isPlain(x);
				var h = hole(x);
				if (event) target.call(Host, "listen", [e, target.string(name), h], ap);
				else switch name {
					case "key": null;
					case "ref": target.call(Runtime, "ref", [e, h], ap);
					case "style": target.call(Runtime, "style", [e, h], ap);
					// (a value never reactive: its hole set as a literal is)
					case _ if (plain): target.call(Host, "setProperty", [e, target.string(name), h], ap);
					case _: target.call(Runtime, "prop", [e, target.string(name), h], ap);
				}
			case ASpread(code, at):
				var h = hole(target.code(code, at, inner(), true));
				target.call(Runtime, "spread", [e, h], ap);
		}
	}

	// a neutral element's attribute: through the renderer's neutral functions where it has them
	function neutralAttr(e:E, a:PAttr, tag:String, event:Bool, ap:Where):Null<E> {
		var name = a.name;
		if (name == "key") return null;
		return switch a.value {
			case AStatic(_) | AFlag:
				var v = switch a.value {
					case AStatic(s): target.string(s);
					case _: target.bool(true);
				}
				event ? target.call(Neutral, "listen", [e, target.string(tag), target.string(name), v],
					ap) : target.call(Neutral, "property", [e, target.string(tag), target.string(name), v], ap);
			case AExpr(code, at):
				var x = target.code(code, at, inner(), true);
				// (a literal, or tag and id, one renderer's only (ui's Node.find, a page's id): in each pass,
				// dropped where its renderer has no use for it)
				if (!event && name != "ref" && target.isLiteral(x))
					return target.call(Neutral, "property", [e, target.string(tag), target.string(name), x], ap);
				// (an agnostic literal's code has no scope: a hole)
				if (!event && name != "ref" && (name == "tag" || name == "id"))
					return target.call(Neutral, "property", [e, target.string(tag), target.string(name), renderer == null ? hole(x) : x], ap);
				// (states: a function of a part's states, its own style: set once, not bound)
				if (name == "states") return target.call(Neutral, "property", [e, target.string(tag), target.string(name), hole(x)], ap);
				var plain = !event && name != "ref" && target.isPlain(x);
				var h = hole(x);
				if (event) target.call(Neutral, "listen", [e, target.string(tag), target.string(name), h], ap);
				// (a part made only for a ref given)
				else if (name == "ref") target.partRef(e, h, ap);
				// (a value never reactive: its hole set as a literal is)
				else if (plain) target.call(Neutral, "property", [e, target.string(tag), target.string(name), h], ap);
				else target.call(Neutral, "prop", [e, target.string(tag), target.string(name), h], ap);
			case ASpread(_, at):
				target.error("markup: a neutral element's attributes are named (no spread: each one realised when compiled)", {at: at, length: 3});
		}
	}

	// a component mounted: the runtime's component with its factory; with the
	// target's dev keys (hxmc.dev), componentIn, in Hot.scope of its name
	// (name[key] with a key attribute: fast refresh's keys, helder.view.Refresh)
	function component(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int, parent:E, before:E, out:E):E {
		if (!target.devKeys()) return target.call(Runtime, "component", [parent, before, out, factory(name, attrs, children, at)], null);
		var key:Null<E> = null;
		for (a in attrs)
			if (a.name == "key")
				key = switch a.value {
					case AStatic(s): target.string(s);
					case AExpr(code, at): hole(target.code(code, at, inner(), true));
					case _: null;
				}
		var scope = key == null ? target.string(name) : target.keyScope(name, key);
		return target.call(Runtime, "componentIn", [scope, parent, before, out, factory(name, attrs, children, at)], null);
	}

	// a component's factory: () -> Name({props}), its content the children
	// prop (a literal of its own, evaluated when it is called: the
	// component's children's renderer, else this one's); its key attribute is
	// no prop. In a literal for one renderer the function for it (Pick), a
	// component pinned to another an error; in an agnostic one chosen when
	// mounted (Pick.call), the factory a hole
	function factory(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int):E {
		var c = target.component(name, at, renderer);
		var props:Array<{name:String, value:E, at:Int}> = [];
		for (a in attrs) {
			if (a.name == "key") continue;
			var ap = {at: a.at, length: a.name.length};
			var v = switch a.value {
				case AStatic(s): target.string(s, ap);
				case AFlag: target.bool(true, ap);
				case AExpr(code, at): target.code(code, at, inner(), true);
				case ASpread(_, at): target.error("markup: a component's props cannot be spread", {at: at, length: 3});
			}
			props.push({name: a.name, value: v, at: a.at});
		}
		var kids = clean(children);
		var content = kids.length > 0 ? new Plan(target, c.children != null ? c.children : renderer, at).compile({kind: PFragment(kids)}) : null;
		var f = target.factory(c, props, content, at, renderer == null);
		if (!shared && renderer != null) return f;
		var h = hole(f, true);
		if (shared) factories.push(h);
		return h;
	}
}

// What a literal's code is written in: the Haxe macro's expressions, helder's
// compiler's, TypeScript's lowering. Its facts need types (a value's, a
// component's), the rest builds code.
interface Target<E> {
	// a fact or a check failed: an error at where (null: the literal), in
	// offsets of the root literal; it throws
	function error(message:String, where:Null<Where>):Dynamic;

	// the elements a renderer lists (null: any name)
	function elements(renderer:String):Null<Array<String>>;
	// an embedded expression ({...}), at an offset of the root literal, its own
	// literals for renderer; null: empty (an error if required)
	function code(code:String, at:Int, renderer:Null<String>, required:Bool):Null<E>;
	// a number or a double-quoted string, as written
	function isLiteral(e:E):Bool;
	// a value of a type never reactive (set once, not bound)
	function isPlain(e:E):Bool;
	// whether components are mounted with fast refresh's keys (hxmc.dev)
	function devKeys():Bool;
	// a component's tag at an offset, for a literal of renderer: its callee
	// (Pick's choice for that renderer), the renderer its children are for
	// (null: the literal's); its checks failing an error
	function component(name:String, at:Int, renderer:Null<String>):Component<E>;

	function ident(name:String):E;
	function string(s:String, ?where:Where):E;
	function bool(b:Bool, ?where:Where):E;
	function nil():E;
	function isNull(e:E):Bool;
	// ([...] : Array<Any>)
	function anyArray(items:Array<E>):E;
	// var name = e
	function declare(name:String, e:E, where:Null<Where>):E;
	// the renderer's (Host), its runtime's (Runtime) or its neutral elements' (Neutral) function called
	function call(of:Callee, name:String, args:Array<E>, where:Null<Where>):E;
	// a hole's declaration: var name:Any = e (a factory's: Void->Any)
	function holeDecl(name:String, e:E, factory:Bool):E;
	// a hole's local, where its expression e is
	function holeRef(name:String, e:E):E;
	// f(), a shared literal's component called
	function callValue(f:E):E;
	// a neutral element's ref: its part made and given only when the ref is not null
	function partRef(element:E, ref:E, where:Where):E;
	// name + "[" + Std.string(key) + "]", fast refresh's scope
	function keyScope(name:String, key:E):E;
	// () -> callee({props, children: content}) (agnostic: through Pick.call)
	function factory(c:Component<E>, props:Array<{name:String, value:E, at:Int}>, content:Null<E>, at:Int, agnostic:Bool):E;
	// the literal's value: its holes, then the View of its mount (or its parts)
	function view(v:Planned<E>):E;
}

enum Callee {
	Host;
	Runtime;
	Neutral;
}

typedef Where = {at:Int, length:Int};

typedef Component<E> = {callee:E, children:Null<String>};

typedef Planned<E> = {
	renderer:Null<String>,
	holes:Array<E>,
	holeNames:Array<{name:String, factory:Bool}>,
	body:Array<E>,
	parts:Null<Array<E>>,
	at:Int
};
