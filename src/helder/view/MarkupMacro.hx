package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.markup.Plan;
import helder.markup.Syntax;

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
		var root = new Parser(src, (message, at, length) -> Context.error(message, position(info.file, info.min + at, length))).document();
		var r = given == null ? placed() : given == ROOT ? ROOT : HostMacro.info(given).path;
		return new Plan(new HaxeTarget(info.file, info.min, e.pos), r).compile(root);
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
	@:allow(helder.view.HaxeTarget) static function neutralMethod():Bool {
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
	@:allow(helder.view.HaxeTarget) static function ownLimits():Null<{only:Array<String>, other:Map<String, Expr>}> {
		var cls = Context.getLocalClass();
		return cls == null || neutralMethod() ? null : limits(cls.get().meta);
	}

	// a component, its callee typed: its name, its class's limits (unless
	// @:neutral), the renderer its return type pins it to, its children's (a
	// children prop of ViewOf<R>); null when it does not type (the call's error then)
	@:allow(helder.view.HaxeTarget) static function component(callee:Expr):Null<{name:String, field:String, limits:Null<{only:Array<String>, other:Map<String, Expr>}>,
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

	// whether an attribute's value may be of a type never reactive, to be
	// told by typing it (plain): an expression of constants, fields,
	// operators and conditions (one with a call, a function or markup in it
	// is left to the runtime to bind or set)
	@:allow(helder.view.HaxeTarget) static function simple(e:Expr):Bool
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

	// an embedded expression, parsed at its place in the file and its
	// literals wrapped, for renderer when given (null: empty, or only comments)
	@:allow(helder.view.HaxeTarget) static function expr(code:String, file:String, at:Int, renderer:Null<String>, required = false):Null<Expr> {
		if (StringTools.trim(Plan.stripComments(code)) == "") {
			if (required) Context.error("markup: an empty expression", position(file, at - 1, code.length + 2));
			return null;
		}
		var e = Context.parseInlineString(code, position(file, at, code.length));
		return transform(e, renderer);
	}

	public static function position(file:String, min:Int, len:Int):Position
		return Context.makePosition({file: file, min: min, max: min + len});

	static final lineCache = new Map<String, Array<Int>>();

	@:allow(helder.view.HaxeTarget) static function lineOf(file:String, offset:Int):Int {
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

// The planner's Target for the macro: a literal's code as Haxe expressions
// (__HOST__, __RT__ and __NEUTRAL__ made the renderer's by forRenderer),
// its errors and facts from typing where the literal is
class HaxeTarget implements Target<Expr> {
	final file:String;
	final base:Int;
	final pos:Position;

	public function new(file:String, base:Int, pos:Position) {
		this.file = file;
		this.base = base;
		this.pos = pos;
	}

	function at(where:Null<Where>):Position
		return where == null ? pos : MarkupMacro.position(file, base + where.at, where.length);

	public function error(message:String, where:Null<Where>):Dynamic
		return Context.error(message, at(where));

	public function elements(renderer:String):Null<Array<String>>
		return HostMacro.info(renderer).elements;

	public function code(code:String, at:Int, renderer:Null<String>, required:Bool):Null<Expr>
		return MarkupMacro.expr(code, file, base + at, renderer, required);

	public function isLiteral(e:Expr):Bool
		return e.expr.match(EConst(CInt(_) | CFloat(_) | CString(_, DoubleQuotes)));

	public function isPlain(e:Expr):Bool
		return MarkupMacro.simple(e) && MarkupMacro.plain(e);

	public function devKeys():Bool
		return Context.defined("hxmc.dev");

	public function component(name:String, at:Int, renderer:Null<String>):Component<Expr> {
		var p = MarkupMacro.position(file, base + at, name.length + 1);
		var callee:Null<Expr> = null;
		for (part in name.split("."))
			callee = callee == null ? {expr: EConst(CIdent(part)), pos: p} : {expr: EField(callee, part), pos: p};
		var c = MarkupMacro.component(callee);
		if (renderer == Plan.ROOT) {
			if (c != null && c.pin != null && c.pin != renderer)
				Context.error("helder.view: <" + name + "> is " + c.pin + "'s markup (it returns " + c.ret
					+ "), not a root's: a root (UiWindow.run's, Render.open's) holds roots (<Surface>) and components of no renderer", p);
		} else if (renderer != null) {
			var target = MarkupMacro.pick(renderer, callee);
			if (target != callee) {
				callee = target;
				c = MarkupMacro.component(target);
			}
			if (c != null && c.pin == Plan.ROOT)
				Context.error("helder.view: <" + name + "> is a root (it returns " + c.ret + "): UiWindow.run's or Render.open's content, not " + renderer + "'s markup", p);
			if (c != null && c.pin != null && c.pin != renderer)
				Context.error("helder.view: <" + name + "> is " + c.pin + "'s markup (it returns " + c.ret + "), not " + renderer + "'s", p);
		}
		return {callee: callee, children: c != null ? c.children : null};
	}

	public function ident(name:String):Expr
		return macro @:pos(pos) $i{name};

	public function string(s:String, ?where:Where):Expr
		return macro @:pos(at(where)) $v{s};

	public function bool(b:Bool, ?where:Where):Expr
		return macro @:pos(at(where)) $v{b};

	public function nil():Expr
		return macro @:pos(pos) null;

	public function isNull(e:Expr):Bool
		return e.expr.match(EConst(CIdent("null")));

	public function anyArray(items:Array<Expr>):Expr
		return macro @:pos(pos) ([$a{items}] : Array<Any>);

	public function declare(name:String, e:Expr, where:Null<Where>):Expr
		return macro @:pos(at(where)) var $name = $e;

	public function call(of:Callee, name:String, args:Array<Expr>, where:Null<Where>):Expr {
		var o = switch of {
			case Host: "__HOST__";
			case Runtime: "__RT__";
			case Neutral: "__NEUTRAL__";
		}
		var p = at(where);
		return {expr: ECall({expr: EField({expr: EConst(CIdent(o)), pos: p}, name), pos: p}, args), pos: p};
	}

	public function holeDecl(name:String, e:Expr, factory:Bool):Expr
		return {expr: EVars([{name: name, type: factory ? macro :Void->Any : macro :Any, expr: e}]), pos: e.pos};

	public function holeRef(name:String, e:Expr):Expr
		return macro @:pos(e.pos) $i{name};

	public function callValue(f:Expr):Expr
		return macro @:pos(pos) $f();

	public function partRef(element:Expr, ref:Expr, where:Where):Expr
		return macro @:pos(at(where)) {
			var r:Dynamic = $ref;
			if (r != null) (r : Dynamic -> Void)(__NEUTRAL__.part($element));
		};

	public function keyScope(name:String, key:Expr):Expr
		return macro @:pos(pos) $v{name + "["} + Std.string($key) + "]";

	public function factory(c:Component<Expr>, props:Array<{name:String, value:Expr, at:Int}>, content:Null<Expr>, at:Int, agnostic:Bool):Expr {
		var callee = c.callee, p = callee.pos;
		var fields:Array<ObjectField> = [];
		for (a in props) {
			// (name_pos: the field name's position, which the compiler reads though ObjectField does not declare it)
			var field:Dynamic = {
				field: a.name,
				expr: a.value,
				quotes: ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(a.name) ? Unquoted : Quoted,
				name_pos: MarkupMacro.position(file, base + a.at, a.name.length)
			};
			fields.push(field);
		}
		if (content != null) fields.push({field: "children", expr: content});
		var props = {expr: EObjectDecl(fields), pos: p};
		var call = agnostic ? macro @:pos(p) helder.view.Pick.call($callee, $props) : {expr: ECall(callee, [props]), pos: p};
		return {expr: EFunction(FAnonymous, {args: [], ret: macro :Any, expr: {expr: EReturn(call), pos: p}}), pos: p};
	}

	public function view(v:Planned<Expr>):Expr {
		var holes = v.holes, body = v.body, renderer = v.renderer;
		var parts = v.parts == null ? macro null : macro function():Array<Any> return ([$a{v.parts}] : Array<Any>);
		var line = MarkupMacro.lineOf(file, base);
		var source = haxe.io.Path.withoutDirectory(file) + ":" + line;
		// (a root's: its parts only, no code to mount)
		if (renderer == Plan.ROOT)
			return macro @:pos(pos) $b{holes.concat([macro @:pos(pos) new helder.view.View($v{HostMacro.id(Plan.ROOT)}, null, 0, null, $parts, $v{source})])};
		var own = MarkupMacro.ownLimits(), cls = Context.getLocalClass();
		if (renderer == null) {
			// (its template in its class, made for each renderer after typing: HostMacro.late)
			var key = HostMacro.id(file + ":" + base + ":" + v.at);
			var decls = [
				for (h in v.holeNames)
					{expr: EVars([{name: h.name, type: h.factory ? macro :Void->Any : macro :Any, expr: null}]), pos: pos}
			];
			var only = own == null ? [] : [for (r in own.only) macro $v{r}];
			if (cls == null) Context.error("markup: a literal outside a class", pos);
			// (and the field it is in: its code kept only if that field is, where DCE can tell, JavaScript)
			var m = Context.getLocalMethod(), c = cls.get();
			var feature = m == null ? "" : c.pack.concat([c.name, m]).join(".");
			c.meta.add(":helder.late", [macro $v{key}, macro $b{decls}, macro $b{body}, macro $a{only}, macro $v{feature}], pos);
			var hs = [for (h in v.holeNames) macro $i{h.name}];
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
}
#end
