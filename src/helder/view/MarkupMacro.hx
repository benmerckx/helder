package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;

// The markup macro: a markup literal (Haxe's parser gives @:markup "<...>",
// the source as written from its "<") is wrapped by the Markup build macro
// (View.literal) and compiled when it is typed, for the renderer that owns
// it (MarkupMacro.literal):
//
//   {var h0:Any = <hole>; ...; new helder.view.View(<renderer>, function(parent, before, out) {...}, ...)}
//
// its holes ({expr} children and attribute values, spreads) evaluated in
// source order where the literal is, and a mount function of direct calls
// to the renderer (Host) and its runtime: each element made by tag, put in
// its parent, its attributes set (static ones and values of a type never
// reactive straight to the renderer, the others through the runtime, which
// binds the reactive ones), its children after it: static text joined at
// compile time, runs of text and holes through the runtime (whether a hole
// is text is known when it runs); components called by the runtime in an
// owner of their own, through a factory (() -> Name({props})), so that
// Haxe checks the props, their children a literal of their own. The
// expressions inside a literal are parsed at their positions in the file
// (errors point into the markup) and wrapped in turn, so markup nests
// through them ({[for (i in items) <text>{i}</text>]}).
//
// The renderer (README, "Renderers in markup"): the literal around it (its
// holes' literals, a component's children unless the component's children
// prop is ViewOf<S>), Render.render's parent, the type expected (ViewOf<R>),
// the enclosing function's return type, its class's one @:renderer; else
// none: the literal is agnostic, its mount code a template in its class's
// metadata, made for each renderer the program reaches after typing
// (HostMacro.late), its factories holes. A class's literals limited to some
// renderers (@:renderer(helder.ui.view.NodeRenderer)): another's code a
// throw; its components, in another renderer's markup, the function of the
// same name of the class it names for that renderer (@:renderer(...,
// helder.web.DomRenderer => DomControls): Pick), else an error naming it
// and the renderer. A function of such a class marked @:neutral is for
// every renderer (a single-source component: its elements the neutral ones,
// view, text, view:button..., each renderer realising them).
class MarkupMacro {
	@:allow(helder.view.Literal) static var count = 0;
	// the root (helder.view.Root: RootView), as a literal's renderer: components only, no code to mount
	public static inline final ROOT = "helder.view.Root";

	// the Markup interface's build macro: every field's literals wrapped
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

	// e with its markup literals wrapped, to be compiled when typed: for renderer when given (the literal around them's)
	public static function transform(e:Expr, ?renderer:String):Expr
		return switch e.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(_))}):
				renderer == null ? macro @:pos(e.pos) helder.view.View.literal($e) : macro @:pos(e.pos) helder.view.View.literalFor($v{renderer}, $e);
			// (wrapped already)
			case ECall({expr: EField(_, "literal" | "literalFor")}, args) if (args.length > 0 && args[args.length - 1].expr.match(EMeta({name: ":markup"}, _))): e;
			case _: e.map(x -> transform(x, renderer));
		}

	// content placed in renderer's nodes (Render.render): a literal compiled for it
	public static function place(content:Expr, renderer:String):Expr
		return switch content.expr {
			case EMeta({name: ":markup"}, {expr: EConst(CString(_))}): macro @:pos(content.pos) helder.view.View.literalFor($v{renderer}, $content);
			case ECall({expr: EField(_, "literal")}, [m = {expr: EMeta({name: ":markup"}, _)}]): macro @:pos(content.pos) helder.view.View.literalFor($v{renderer}, $m);
			case EParenthesis(x): place(x, renderer);
			case _: content;
		}

	// a literal being typed (View.literal), for renderer given, else the one where it is
	public static function literal(e:Expr, given:Null<String>):Expr {
		var src = switch e.expr {
			case EMeta(_, {expr: EConst(CString(s))}): s;
			case _: return Context.error("markup: a literal expected", e.pos);
		}
		var info = Context.getPosInfos(e.pos);
		var root = new Parser(src, info.file, info.min).document();
		var r = given == null ? placed() : given == ROOT ? ROOT : HostMacro.info(given).path;
		return new Literal(info.file, info.min, e.pos, r).compile(root);
	}

	// (the renderer a literal is for from where it is: the type expected, the enclosing
	// function's return type, its class's one @:renderer; null: none, agnostic)
	static function placed():Null<String> {
		var r = HostMacro.viewOf(Context.getExpectedType());
		if (r != null) return r;
		if (neutralMethod()) return null;
		var cls = Context.getLocalClass(), m = Context.getLocalMethod();
		if (cls == null) return null;
		if (m != null) {
			var f = field(cls.get(), m);
			if (f != null)
				r = try switch f.type {
					case TFun(_, ret): HostMacro.pinOf(ret);
					case _: null;
				} catch (_:Dynamic) null;
			if (r != null) return r;
		}
		var l = limits(cls.get().meta);
		return l != null && l.only.length == 1 ? l.only[0] : null;
	}

	static function field(c:ClassType, name:String):Null<ClassField> {
		for (f in c.statics.get())
			if (f.name == name) return f;
		for (f in c.fields.get())
			if (f.name == name) return f;
		return null;
	}

	// (the function being typed is @:neutral: for every renderer, its class's @:renderer aside)
	@:allow(helder.view.Literal) static function neutralMethod():Bool {
		var cls = Context.getLocalClass(), m = Context.getLocalMethod();
		if (cls == null || m == null) return false;
		var f = field(cls.get(), m);
		return f != null && f.meta.has(":neutral");
	}

	// (a class's @:renderer: the renderers its literals are for, by class path; the class each other one's markup calls instead)
	public static function limits(meta:MetaAccess):Null<{only:Array<String>, other:Map<String, Expr>}> {
		var m = meta.extract(":renderer");
		if (m.length == 0) return null;
		var only = [], other = new Map<String, Expr>();
		for (e in (m[0].params == null ? [] : m[0].params))
			switch e.expr {
				case EBinop(OpArrow, r, c): other.set(HostMacro.resolve(r), c);
				case _: only.push(HostMacro.resolve(e));
			}
		return {only: only, other: other};
	}

	// (the literal being typed's class's limits, unless its function is @:neutral)
	@:allow(helder.view.Literal) static function ownLimits():Null<{only:Array<String>, other:Map<String, Expr>}> {
		var cls = Context.getLocalClass();
		return cls == null || neutralMethod() ? null : limits(cls.get().meta);
	}

	// a component, its callee typed: its name, its class's limits (unless
	// @:neutral), the renderer its return type pins it to, its children's (a
	// children prop of ViewOf<R>); null when it does not type (the call's error then)
	@:allow(helder.view.Literal) static function component(callee:Expr):Null<{name:String, field:String, limits:Null<{only:Array<String>, other:Map<String, Expr>}>,
		pin:Null<String>, ret:String, children:Null<String>}> {
		var t = try Context.typeExpr(callee) catch (_:Dynamic) return null;
		var name = callee.toString(), fieldName = name.split(".").pop(), l = null;
		switch t.expr {
			case TField(_, FStatic(c, cf)):
				name = c.get().name + "." + cf.get().name;
				fieldName = cf.get().name;
				if (!cf.get().meta.has(":neutral")) l = limits(c.get().meta);
			case _:
		}
		var pin = null, ret = "", children = null;
		switch Context.follow(t.t) {
			case TFun(args, r):
				pin = HostMacro.pinOf(r);
				ret = haxe.macro.TypeTools.toString(r);
				if (args.length > 0) switch Context.follow(args[0].t) {
					case TAnonymous(a):
						for (f in a.get().fields)
							if (f.name == "children") children = HostMacro.viewOf(f.type);
					case _:
				}
			case _:
		}
		return {name: name, field: fieldName, limits: l, pin: pin, ret: ret, children: children};
	}

	// the function renderer's markup calls for callee (Pick.callee): itself, or
	// its class's counterpart for that renderer; none an error
	public static function pick(renderer:String, callee:Expr):Expr {
		var c = component(callee);
		if (c == null || c.limits == null || c.limits.only.indexOf(renderer) >= 0) return callee;
		var o = counterpart(c.limits.other.get(renderer), c.field, callee.pos);
		if (o != null) return o;
		return Context.error("helder.view: " + c.name + " has no version for " + renderer + " (@:renderer names none)", callee.pos);
	}

	static function counterpart(cls:Null<Expr>, field:String, pos:Position):Null<Expr> {
		if (cls == null) return null;
		var has = switch Context.getType(cls.toString()) {
			case TInst(k, _): Lambda.exists(k.get().statics.get(), f -> f.name == field);
			case _: false;
		}
		return has ? macro @:pos(pos) $cls.$field : null;
	}

	// the call of callee for the renderer mounting it (Pick.call): an agnostic
	// literal's, chosen when it runs (Render.pass) among its class's renderers
	public static function pickCall(callee:Expr, props:Expr):Expr {
		var c = component(callee);
		if (c == null || c.limits == null) return macro @:pos(callee.pos) ($callee($props) : Any);
		var cases:Array<Case> = [];
		for (r in c.limits.only)
			cases.push({values: [macro $v{HostMacro.id(r)}], expr: macro @:pos(callee.pos) ($callee($props) : Any)});
		for (r => cls in c.limits.other) {
			var o = counterpart(cls, c.field, callee.pos);
			if (o != null) cases.push({values: [macro $v{HostMacro.id(r)}], expr: macro @:pos(callee.pos) ($o($props) : Any)});
		}
		return {
			expr: ESwitch(macro helder.view.Render.pass, cases, macro @:pos(callee.pos) (throw $v{"helder.view: " + c.name + " has no version for this renderer"} : Any)),
			pos: callee.pos
		};
	}

	// the code made for renderer path: __HOST__ its class, __RT__ its runtime
	// (a reactive attribute with a literal name bound with the renderer's
	// setter for that name, when it has setter: Renders), the neutral
	// elements its own way; late (an agnostic literal's, after typing): what
	// it cannot do a throw, not an error
	public static function forRenderer(body:Array<Expr>, path:String, late:Bool):Array<Expr> {
		var i = HostMacro.info(path);
		var host = path.split("."), rt = HostMacro.runtime(path), setter = i.setter, neutral = i.neutral, native = i.native;
		function sub(e:Expr):Expr
			return switch e.expr {
				// (a neutral element: the renderer's neutral functions, else its own)
				case ECall({expr: EField({expr: EConst(CIdent("__NEUTRAL__"))}, _)}, _) if (!neutral && !native && late):
					macro @:pos(e.pos) (throw $v{"helder.view: " + path + " realises no neutral elements"} : Dynamic);
				case ECall({expr: EField({expr: EConst(CIdent("__NEUTRAL__"))}, _)}, _) if (!neutral && !native):
					Context.error("markup: " + path + " realises no neutral elements (view, text, view:button...: neutralElement and the rest, or neutralNative)", e.pos);
				case ECall({expr: EField({expr: EConst(CIdent("__NEUTRAL__"))}, f)}, args):
					var a = [for (x in args) sub(x)];
					switch [f, neutral] {
						case ["element", true]: macro @:pos(e.pos) $p{host}.neutralElement(${a[0]});
						case ["element", false]: macro @:pos(e.pos) $p{host}.createElement(${a[0]});
						case ["property", true]: macro @:pos(e.pos) $p{host}.neutralProperty(${a[0]}, ${a[1]}, ${a[2]}, ${a[3]});
						case ["property", false]: macro @:pos(e.pos) $p{host}.setProperty(${a[0]}, ${a[2]}, ${a[3]});
						// (bound: the setter given the name the realiser chooses, its DOM name for one setter of all)
						case ["prop", true]: macro @:pos(e.pos) $p{rt}.propWith(${a[0]}, $p{host}.neutralName(${a[1]}, ${a[2]}), ${a[3]}, $p{host}.neutralSetter(${a[1]}, ${a[2]}));
						case ["prop", false] if (setter): macro @:pos(e.pos) $p{rt}.propWith(${a[0]}, ${a[2]}, ${a[3]}, $p{host}.setter(${a[2]}));
						case ["prop", false]: macro @:pos(e.pos) $p{rt}.prop(${a[0]}, ${a[2]}, ${a[3]});
						case ["listen", true]: macro @:pos(e.pos) $p{host}.neutralListen(${a[0]}, ${a[1]}, ${a[2]}, ${a[3]});
						case ["listen", false]: macro @:pos(e.pos) $p{host}.listen(${a[0]}, ${a[2]}, ${a[3]});
						case ["part", true]: macro @:pos(e.pos) $p{host}.part(${a[0]});
						case ["part", false]: a[0];
						case _: throw "markup: " + f;
					}
				case EConst(CIdent("__HOST__")): macro @:pos(e.pos) $p{host};
				case EConst(CIdent("__RT__")): macro @:pos(e.pos) $p{rt};
				case ECall({expr: EField({expr: EConst(CIdent("__RT__"))}, "prop")}, [el, name = {expr: EConst(CString(s, _))}, v]) if (setter):
					macro @:pos(e.pos) $p{rt}.propWith(${sub(el)}, $name, ${sub(v)}, $p{host}.setter($v{s}));
				case EObjectDecl(fields):
					// (copied: a template is made for several renderers; map would lose the fields' name_pos)
					{expr: EObjectDecl([for (f in fields) {var c:Dynamic = Reflect.copy(f); c.expr = sub(f.expr); c;}]), pos: e.pos};
				case _: e.map(sub);
			}
		return [for (e in body) sub(e)];
	}

	@:allow(helder.view.Literal) static function exprNotEmpty(c:PNode):Bool
		return switch c.kind {
			case PExpr(code, _): StringTools.trim(stripComments(code)) != "";
			case _: true;
		}

	// whether an attribute's value may be of a type never reactive, to be
	// told by typing it (plain): an expression of constants, fields,
	// operators and conditions (one with a call, a function or markup in it
	// is left to the runtime to bind or set)
	@:allow(helder.view.Literal) static function simple(e:Expr):Bool
		return switch e.expr {
			case EConst(_): true;
			case EField(o, _) | EParenthesis(o) | EUnop(_, _, o) | ECheckType(o, _) | ECast(o, null): simple(o);
			case EBinop(_, a, b) | EArray(a, b): simple(a) && simple(b);
			case ETernary(c, a, b) | EIf(c, a, b) if (b != null): simple(c) && simple(a) && simple(b);
			case _: false;
		}

	// whether a value is of a type never reactive (a String, Int, Float or
	// Bool, an enum abstract of one, null of one): set once, as a literal is,
	// not bound (a function, a Signal, Dynamic or a type it cannot tell still
	// bound by the runtime); typed where the literal is
	public static function plain(x:Expr):Bool {
		var t = try Context.typeof(x) catch (_:Dynamic) return false;
		function of(t:haxe.macro.Type):Bool
			return switch Context.follow(t) {
				case TInst(_.get() => {pack: [], name: "String"}, _): true;
				case TAbstract(_.get() => {pack: [], name: "Int" | "Float" | "Bool"}, _): true;
				case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): of(p);
				case TAbstract(_.get() => a, _) if (a.meta.has(":enum")): of(a.type);
				case _: false;
			}
		return of(t);
	}

	@:allow(helder.view.Literal) static function isComponent(name:String):Bool {
		var last = name.split(".").pop();
		return name.indexOf(".") >= 0 || (last.length > 0 && last.charAt(0) == last.charAt(0).toUpperCase() && last.charAt(0) != last.charAt(0).toLowerCase());
	}

	// an embedded expression, parsed at its place in the file and its
	// literals wrapped, for renderer when given (null: empty, or only comments)
	@:allow(helder.view.Literal) static function expr(code:String, file:String, at:Int, renderer:Null<String>, required = false):Null<Expr> {
		if (StringTools.trim(stripComments(code)) == "") {
			if (required) Context.error("markup: an empty expression", position(file, at - 1, code.length + 2));
			return null;
		}
		var e = Context.parseInlineString(code, position(file, at, code.length));
		return transform(e, renderer);
	}

	static function stripComments(s:String):String
		return ~/\/\*[\s\S]*?\*\//g.replace(~/\/\/[^\n]*/g.replace(s, ""), "");

	public static function position(file:String, min:Int, len:Int):Position
		return Context.makePosition({file: file, min: min, max: min + len});

	static final lineCache = new Map<String, Array<Int>>();

	@:allow(helder.view.Literal) static function lineOf(file:String, offset:Int):Int {
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
	// the renderer it is compiled for; null: agnostic, for every renderer the program reaches (after typing)
	final renderer:Null<String>;
	final id = MarkupMacro.count++;
	final holes:Array<Expr> = [];
	final holeTypes:Array<{name:String, type:ComplexType}> = [];
	var vars = 0;
	// (a literal of components and holes only: its components' factories are
	// holes, shared by mount and parts)
	var shared = false;

	// (where it starts in its root literal: a component's children's, the component's tag)
	final at:Int;

	public function new(file:String, base:Int, pos:Position, renderer:Null<String>, at = 0) {
		this.file = file;
		this.base = base;
		this.pos = pos;
		this.renderer = renderer;
		this.at = at;
	}

	static final P = macro __p;
	static final B = macro __b;
	static final O = macro __o;

	public function compile(root:PNode):Expr {
		shared = valueOnly(root);
		if (renderer == MarkupMacro.ROOT && !shared) {
			var n = firstNode(root);
			Context.error("markup: " + (n == null ? "text" : "<" + n.name + ">") + " needs a renderer's parent: a root (RootView: App.run's, Render.open's) holds components only (<Surface>...)",
				n == null ? pos : MarkupMacro.position(file, base + n.at, n.name.length));
		}
		var body = mountBody(root);
		var parts = macro null;
		if (shared) {
			var items = [];
			collect(root, items);
			parts = macro function():Array<Any> return ([$a{items}] : Array<Any>);
		}
		var line = MarkupMacro.lineOf(file, base);
		var source = haxe.io.Path.withoutDirectory(file) + ":" + line;
		// (a root's: its parts only, no code to mount)
		if (renderer == MarkupMacro.ROOT)
			return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View($v{HostMacro.id(MarkupMacro.ROOT)}, null, 0, null, $parts, $v{source})])};
		var own = MarkupMacro.ownLimits(), cls = Context.getLocalClass();
		if (renderer == null) {
			// (its template in its class, made for each renderer after typing: HostMacro.late)
			var key = HostMacro.id(file + ":" + base + ":" + at);
			var decls = [for (h in holeTypes) {expr: EVars([{name: h.name, type: h.type, expr: null}]), pos: pos}];
			var only = own == null ? [] : [for (r in own.only) macro $v{r}];
			if (cls == null) Context.error("markup: a literal outside a class", pos);
			cls.get().meta.add(":helder.late", [macro $v{key}, macro $b{decls}, macro $b{body}, macro $a{only}], pos);
			var hs = [for (h in holeTypes) macro $i{h.name}];
			return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View(0, null, $v{key}, ([$a{hs}] : Array<Any>), $parts, $v{source})])};
		}
		var info = HostMacro.reach(renderer);
		var code = own != null && own.only.indexOf(renderer) < 0 ? [
			macro @:pos(pos) throw $v{"helder.view: " + cls.get().name + " markup is not for " + renderer + " (@:renderer)"}
		] : MarkupMacro.forRenderer(body, renderer, false);
		var n = info.node;
		var mount = macro function(__p0:Dynamic, __b0:Dynamic, __o0:Dynamic):Void {
			var __p:$n = cast __p0;
			var __b:Null<$n> = cast __b0;
			var __o:Null<Array<$n>> = cast __o0;
			$b{code};
		};
		return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View($v{info.id}, $mount, 0, null, $parts, $v{source})])};
	}

	function mountBody(root:PNode):Array<Expr> {
		return switch root.kind {
			case PElement(name, attrs, children, at) if (MarkupMacro.isComponent(name)):
				[component(name, attrs, children, at, macro __p, macro __b, macro __o)];
			case PElement(name, attrs, children, at): element(name, attrs, children, at, P, true);
			case PFragment(children): this.children(children, P, B, O, macro false);
			case _: [];
		}
	}

	// the literal's hole for e: a local, evaluated in source order
	function hole(e:Expr, ?type:ComplexType):Expr {
		var name = '__h${id}_${holes.length}';
		var t = type == null ? macro :Any : type;
		holes.push({expr: EVars([{name: name, type: t, expr: e}]), pos: e.pos});
		holeTypes.push({name: name, type: t});
		return macro @:pos(e.pos) $i{name};
	}

	function fresh(prefix:String):String
		return '__$prefix${id}_${vars++}';

	// (the first element or text of a literal not of components only: null, a text)
	static function firstNode(n:PNode):Null<{name:String, at:Int}>
		return switch n.kind {
			case PElement(name, _, children, at): MarkupMacro.isComponent(name) ? null : {name: name, at: at};
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
		return renderer == MarkupMacro.ROOT ? null : renderer;

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

	// (the neutral elements: ui's own, a page's renderer realising them as its elements)
	static function isNeutral(name:String):Bool
		return ["view", "text", "scroll", "image", "icon", "field"].indexOf(name) >= 0 || ~/^(view|text|field):/.match(name);

	// an element: made, put in parent (top: before __b, pushed to __o), its
	// attributes, its children; one its renderer does not list (@:elements) an error
	function element(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int, parent:Expr, top:Bool):Array<Expr> {
		if (renderer != null) {
			var els = HostMacro.info(renderer).elements;
			if (els != null && els.indexOf(name) < 0)
				Context.error("markup: <" + name + "> is no element of " + renderer + " (" + els.join(", ") + ")", MarkupMacro.position(file, base + at, name.length));
		}
		var v = fresh("e");
		var e = macro $i{v};
		var neutral = isNeutral(name);
		var out = [
			neutral ? macro @:pos(pos) var $v = __NEUTRAL__.element($v{name}) : macro @:pos(pos) var $v = __HOST__.createElement($v{name}),
			top ? macro @:pos(pos) __RT__.put($parent, $e, __b, __o) : macro @:pos(pos) __HOST__.insert($parent, $e, null)
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
					s.push(component(name, attrs, children, at, parent, before, out));
				case PElement(name, attrs, children, at):
					flush();
					s = s.concat(element(name, attrs, children, at, parent, top));
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
				var h = hole(MarkupMacro.expr(code, file, base + at, inner()));
				if (shared) valueHoles.push(h);
				h;
			case _: throw "unreachable";
		}

	static function join(run:Array<PNode>):Expr
		return macro $v{[for (k in run) switch k.kind {
			case PText(t): t;
			case _: "";
		}].join("")};

	// (a value of a type never reactive: set as a literal is, not bound)
	function plainValue(x:Expr):Bool
		return MarkupMacro.simple(x) && MarkupMacro.plain(x);

	// an attribute's statement (null: none, as key)
	function attr(e:Expr, a:PAttr, ?tag:String):Null<Expr> {
		var name = a.name;
		var event = StringTools.startsWith(name, "on") && name.length > 2;
		var ap = MarkupMacro.position(file, base + a.at, name.length);
		if (tag != null) return neutralAttr(e, a, tag, event, ap);
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
				var x = MarkupMacro.expr(code, file, base + at, inner(), true);
				// (a literal number or string: set as a static value is, never bound)
				if (!event && name != "ref" && name != "key" && name != "style" && x.expr.match(EConst(CInt(_) | CFloat(_) | CString(_, DoubleQuotes))))
					return macro @:pos(ap) __HOST__.setProperty($e, $v{name}, $x);
				var plain = !event && name != "ref" && name != "key" && name != "style" && plainValue(x);
				var h = hole(x);
				if (event) macro @:pos(ap) __HOST__.listen($e, $v{name}, $h);
				else switch name {
					case "key": null;
					case "ref": macro @:pos(ap) __RT__.ref($e, $h);
					case "style": macro @:pos(ap) __RT__.style($e, $h);
					// (a value never reactive: its hole set as a literal is)
					case _ if (plain): macro @:pos(ap) __HOST__.setProperty($e, $v{name}, $h);
					case _: macro @:pos(ap) __RT__.prop($e, $v{name}, $h);
				}
			case ASpread(code, at):
				var h = hole(MarkupMacro.expr(code, file, base + at, inner(), true));
				macro @:pos(ap) __RT__.spread($e, $h);
		}
	}

	// a neutral element's attribute: through the renderer's neutral functions where it has them
	function neutralAttr(e:Expr, a:PAttr, tag:String, event:Bool, ap:Position):Null<Expr> {
		var name = a.name;
		if (name == "key") return null;
		return switch a.value {
			case AStatic(_) | AFlag:
				var v = switch a.value {
					case AStatic(s): macro $v{s};
					case _: macro true;
				}
				event ? macro @:pos(ap) __NEUTRAL__.listen($e, $v{tag}, $v{name}, $v) : macro @:pos(ap) __NEUTRAL__.property($e, $v{tag}, $v{name}, $v);
			case AExpr(code, at):
				var x = MarkupMacro.expr(code, file, base + at, inner(), true);
				// (a literal, or tag and id, one renderer's only (ui's Node.find, a page's id): in each pass,
				// dropped where its renderer has no use for it)
				if (!event && name != "ref" && x.expr.match(EConst(CInt(_) | CFloat(_) | CString(_, DoubleQuotes))))
					return macro @:pos(ap) __NEUTRAL__.property($e, $v{tag}, $v{name}, $x);
				// (an agnostic literal's code has no scope: a hole)
				if (!event && name != "ref" && (name == "tag" || name == "id"))
					return macro @:pos(ap) __NEUTRAL__.property($e, $v{tag}, $v{name}, ${renderer == null ? hole(x) : x});
				// (states: a function of a part's states, its own style: set once, not bound)
				if (name == "states") return macro @:pos(ap) __NEUTRAL__.property($e, $v{tag}, $v{name}, ${hole(x)});
				var plain = !event && name != "ref" && plainValue(x);
				var h = hole(x);
				if (event) macro @:pos(ap) __NEUTRAL__.listen($e, $v{tag}, $v{name}, $h);
				// (a part made only for a ref given)
				else if (name == "ref") macro @:pos(ap) {
					var r:Dynamic = $h;
					if (r != null) (r : Dynamic -> Void)(__NEUTRAL__.part($e));
				};
				// (a value never reactive: its hole set as a literal is)
				else if (plain) macro @:pos(ap) __NEUTRAL__.property($e, $v{tag}, $v{name}, $h);
				else macro @:pos(ap) __NEUTRAL__.prop($e, $v{tag}, $v{name}, $h);
			case ASpread(_, at):
				Context.error("markup: a neutral element's attributes are named (no spread: each one realised when compiled)", MarkupMacro.position(file, base + at, 3));
		}
	}

	// a component mounted: the runtime's component with its factory; under
	// -D hxmc.dev componentIn, in Hot.scope of its name (name[key] with a key
	// attribute: fast refresh's keys, helder.view.Refresh)
	function component(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int, parent:Expr, before:Expr, out:Expr):Expr {
		if (!Context.defined("hxmc.dev")) return macro @:pos(pos) __RT__.component($parent, $before, $out, ${factory(name, attrs, children, at)});
		var key:Null<Expr> = null;
		for (a in attrs)
			if (a.name == "key")
				key = switch a.value {
					case AStatic(s): macro $v{s};
					case AExpr(code, at): hole(MarkupMacro.expr(code, file, base + at, inner(), true));
					case _: null;
				}
		var scope = key == null ? macro $v{name} : macro $v{name + "["} + Std.string($key) + "]";
		return macro @:pos(pos) __RT__.componentIn($scope, $parent, $before, $out, ${factory(name, attrs, children, at)});
	}

	// a component's factory: () -> Name({props}), its content the children
	// prop (a literal of its own, evaluated when it is called: the
	// component's children's renderer, else this one's); its key attribute is
	// no prop. In a literal for one renderer the function for it (Pick), a
	// component pinned to another an error; in an agnostic one chosen when
	// mounted (Pick.call), the factory a hole
	function factory(name:String, attrs:Array<PAttr>, children:Array<PNode>, at:Int):Expr {
		var p = MarkupMacro.position(file, base + at, name.length + 1);
		var callee:Null<Expr> = null;
		for (part in name.split("."))
			callee = callee == null ? {expr: EConst(CIdent(part)), pos: p} : {expr: EField(callee, part), pos: p};
		var c = MarkupMacro.component(callee);
		if (renderer == MarkupMacro.ROOT) {
			if (c != null && c.pin != null && c.pin != renderer)
				Context.error("helder.view: <" + name + "> is " + c.pin + "'s markup (it returns " + c.ret
					+ "), not a root's: a root (App.run's, Render.open's) holds roots (<Surface>) and components of no renderer", p);
		} else if (renderer != null) {
			var target = MarkupMacro.pick(renderer, callee);
			if (target != callee) {
				callee = target;
				c = MarkupMacro.component(target);
			}
			if (c != null && c.pin == MarkupMacro.ROOT)
				Context.error("helder.view: <" + name + "> is a root (it returns " + c.ret + "): App.run's or Render.open's content, not " + renderer + "'s markup", p);
			if (c != null && c.pin != null && c.pin != renderer)
				Context.error("helder.view: <" + name + "> is " + c.pin + "'s markup (it returns " + c.ret + "), not " + renderer + "'s", p);
		}
		var fields:Array<ObjectField> = [];
		for (a in attrs) {
			if (a.name == "key") continue;
			var ap = MarkupMacro.position(file, base + a.at, a.name.length);
			var v = switch a.value {
				case AStatic(s): macro @:pos(ap) $v{s};
				case AFlag: macro @:pos(ap) true;
				case AExpr(code, at): MarkupMacro.expr(code, file, base + at, inner(), true);
				case ASpread(_, at): Context.error("markup: a component's props cannot be spread", MarkupMacro.position(file, base + at, 3));
			}
			// (name_pos: the field name's position, which the compiler reads though ObjectField does not declare it)
			var field:Dynamic = {field: a.name, expr: v, quotes: ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(a.name) ? Unquoted : Quoted, name_pos: ap};
			fields.push(field);
		}
		var kids = clean(children);
		if (kids.length > 0) {
			var r = c != null && c.children != null ? c.children : renderer;
			fields.push({field: "children", expr: new Literal(file, base, pos, r, at).compile({kind: PFragment(kids)})});
		}
		var props = {expr: EObjectDecl(fields), pos: p};
		var call = renderer == null ? macro @:pos(p) helder.view.Pick.call($callee, $props) : {expr: ECall(callee, [props]), pos: p};
		var f = {expr: EFunction(FAnonymous, {args: [], ret: macro :Any, expr: {expr: EReturn(call), pos: p}}), pos: p};
		if (!shared && renderer != null) return f;
		var h = hole(f, macro :Void->Any);
		if (shared) factories.push(h);
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
