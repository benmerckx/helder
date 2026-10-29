package helder.typescript.lower;

import haxe.ds.Vector;
import hxmc.ir.Ir;
import helder.markup.Plan;
import helder.markup.Syntax;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.ir.Builder;
import helder.typescript.lower.Api;

// A TSX literal's code as the planner writes it (helder.markup.Plan's
// Target<TsMarkup>), lowered by Tsx: the program's expressions where the
// literal is, the mount's calls to its renderer (pure IR, on Haxe values).
enum TsMarkup {
	MIdent(name:String);
	MString(s:String);
	MBool(b:Bool);
	MNull;
	// a TypeScript expression (a hole's, an attribute's value), its literals for renderer
	MCode(n:Node, renderer:Null<String>);
	// () => e: a hole that reads (3.3), bound
	MThunk(e:TsMarkup);
	// a listener: the program's function as Haxe's, given the event
	MHandler(e:TsMarkup);
	MArray(items:Array<TsMarkup>);
	MDeclare(name:String, e:TsMarkup);
	MCall(of:Callee, name:String, args:Array<TsMarkup>);
	MHoleDecl(name:String, e:TsMarkup, factory:Bool);
	MHoleRef(name:String);
	MCallValue(f:TsMarkup);
	MPartRef(el:TsMarkup, ref:TsMarkup);
	MKeyScope(name:String, key:TsMarkup);
	MFactory(c:Component<TsMarkup>, props:Array<{name:String, value:TsMarkup, at:Int}>, content:Null<TsMarkup>, agnostic:Bool, at:Int);
	MView(v:Planned<TsMarkup>);
	// a component's function: one of helder's statics, or the program's value (its tag)
	MHaxeComponent(c:MClass, m:MMember);
	MScriptComponent(tag:Node);
}

// TSX through helder.markup's planner (DESIGN.md 7.2): the same decisions
// as Haxe's markup (renderer boundaries, components, neutral elements,
// bound holes, handlers), its facts from the manifest (a renderer's
// elements, a component's props that read, its children's renderer) and
// from TypeScript's types (whether a value may read: 3.3; is of a type
// never reactive). A literal's holes are evaluated where it is (the
// program's values, made Haxe's), its mount is IR on Haxe values calling its
// renderer and its runtime (ViewRuntime_<renderer>) directly, as the markup
// macro's code does; an agnostic literal's mount is made for each renderer
// the manifest reaches, installed at the start (ViewRuntime's late), as
// HostMacro's late code is.
@:access(helder.typescript.lower.Frontend)
class Tsx {
	final f:Frontend;
	final bridge:Haxe;
	final manifest:Manifest;
	final api:Api;
	// (the planner's offsets: nodes by number)
	public final nodes:Array<Node> = [];
	// the renderer a literal is compiled for, given by where it is (a call's ViewOf<R> argument, Render.render's content, a hole of another's)
	public final placed:Map<Node, String> = [];
	final agnostic:Array<{key:Int, holes:Array<String>, body:Array<TsMarkup>}> = [];
	// (the get accessors of the program's classes, by their names' symbols: a read through one may read, 3.3)
	final getters:Map<String, Bool> = [];
	public final dev:Bool;
	var serial = 0;

	public function new(f:Frontend, bridge:Haxe, api:Api, dev:Bool) {
		this.f = f;
		this.bridge = bridge;
		this.manifest = bridge.manifest;
		this.api = api;
		this.dev = dev;
		for (sf in f.src.files) for (i in 1...sf.count) if (sf.kindAt(i) == KindGetAccessor) {
			var name = sf.node(i).name();
			if (name != null && name.symbol != null) getters.set(name.symbol, true);
		}
	}

	var b(get, never):Builder;

	function get_b():Builder return f.b;

	public function at(n:Node):Int {
		nodes.push(n);
		return nodes.length - 1;
	}

	// ---- a literal, where the program has it: its View, as the program's value

	public function literal(n:Node):Ex {
		var root = parse(n);
		var renderer = placed.get(n);
		var target = new TsTarget(this, n);
		var e = new Plan(target, renderer).compile(root);
		return value(e, n);
	}

	// (a node's PNode: elements, fragments, attributes, text by JSX's whitespace rule, holes)
	function parse(n:Node):PNode {
		return switch n.kind {
			case KindJsxElement:
				var open = n.openingElement();
				{kind: PElement(tagOf(open.tagName()), attributes(open.attributes()), children(n.jsxChildren()), at(n))};
			case KindJsxSelfClosingElement:
				{kind: PElement(tagOf(n.tagName()), attributes(n.attributes()), [], at(n))};
			case KindJsxFragment:
				{kind: PFragment(children(n.jsxChildren()))};
			case _: f.fail(n, "unsupported TSX");
		}
	}

	function children(list:Array<Node>):Array<PNode> {
		var out:Array<PNode> = [];
		for (c in list) switch c.kind {
			case KindJsxText | KindJsxTextAllWhiteSpaces:
				var t = Whitespace.clean(c.text);
				if (t != null) out.push({kind: PText(Entities.decode(t))});
			case KindJsxExpression if (c.dotDotDotToken() != null): f.fail(c, "a spread among TSX children");
			case KindJsxExpression if (c.expression() == null): out.push({kind: PExpr("", at(c))});
			case KindJsxExpression: out.push({kind: PExpr("x", at(c.expression()))});
			case KindJsxElement | KindJsxSelfClosingElement | KindJsxFragment: out.push(parse(c));
			case _: f.fail(c, "unsupported TSX child");
		}
		return out;
	}

	function attributes(attrs:Node):Array<PAttr> {
		var out:Array<PAttr> = [];
		for (a in attrs.properties()) switch a.kind {
			case KindJsxAttribute:
				var name = a.name().kind == KindJsxNamespacedName ? a.name().namespace().text + ":" + a.name().name().text : a.name().text;
				var init = a.initializer();
				var where = at(a);
				if (init == null) out.push({name: name, value: AFlag, at: where});
				else if (init.kind == KindStringLiteral) out.push({name: name, value: AStatic(init.text), at: where});
				else if (init.kind == KindJsxExpression && init.expression() == null) continue;
				else if (init.kind == KindJsxExpression) out.push({name: name, value: AExpr("x", at(init.expression())), at: where});
				else out.push({name: name, value: AExpr("x", at(init)), at: where});
			case KindJsxSpreadAttribute:
				out.push({name: "...", value: ASpread("x", at(a.expression())), at: at(a)});
			case _:
		}
		return out;
	}

	// an element's name: the renderer's (lower case, or namespaced), a component (capitalized, dotted)
	function tagOf(t:Node):String return switch t.kind {
		case KindJsxNamespacedName: t.namespace().text + ":" + t.name().text;
		case KindIdentifier: t.text;
		case KindPropertyAccessExpression: tagOf(t.expression()) + "." + t.name().text;
		case KindThisKeyword: "this";
		case _: f.fail(t, "unsupported element name");
	}

	// ---- facts the planner asks

	// whether evaluating a TypeScript expression may read a signal (3.3): a
	// call, a new of what reads, a property read through a get accessor (the
	// program's, or a Haxe property's); not inside a function or a literal of its own
	public function mayRead(n:Node):Bool {
		return switch n.kind {
			case KindArrowFunction | KindFunctionExpression | KindClassExpression | KindJsxElement | KindJsxSelfClosingElement | KindJsxFragment: false;
			case KindCallExpression | KindTaggedTemplateExpression: true;
			case KindNewExpression: Lambda.exists(n.arguments() ?? [], mayRead);
			case KindPropertyAccessExpression: mayRead(n.expression()) || getter(n);
			case _:
				var r = false;
				for (c in n.children()) if (!r && mayRead(c)) r = true;
				r;
		}
	}

	function getter(n:Node):Bool {
		var name = n.name();
		if (name != null && name.symbol != null && getters.exists(name.symbol)) return true;
		var c = api.classOf(n.expression().tsType);
		if (c != null) {
			var m = manifest.cls(c.path);
			var member = m == null ? null : m.members.get(name.text);
			return member != null && member.get != null;
		}
		return false;
	}

	// an expression of constants, names, fields and operators (no call, function or markup)
	public static function simple(n:Node):Bool return switch n.kind {
		case KindNumericLiteral | KindStringLiteral | KindNoSubstitutionTemplateLiteral | KindTrueKeyword | KindFalseKeyword | KindNullKeyword | KindIdentifier: true;
		case KindPropertyAccessExpression: simple(n.expression());
		case KindElementAccessExpression: simple(n.expression()) && simple(n.argumentExpression());
		case KindParenthesizedExpression | KindAsExpression | KindNonNullExpression | KindSatisfiesExpression: simple(n.expression());
		case KindPrefixUnaryExpression: simple(n.operand());
		case KindBinaryExpression: simple(n.left()) && simple(n.right());
		case KindConditionalExpression: simple(n.condition()) && simple(n.whenTrue()) && simple(n.whenFalse());
		case _: false;
	}

	// a value of a type never reactive: a string, a number, a boolean
	public function plain(n:Node):Bool {
		if (!simple(n)) return false;
		var t = n.tsType;
		return f.types.isString(t) || f.types.isNumber(t) || f.types.isBoolean(t);
	}

	// a component's tag: its function (Pick's choice for renderer), its props that read, its children's renderer
	public function component(name:String, tag:Node, renderer:Null<String>, fail:String->Dynamic):Component<TsMarkup> {
		var t = tag.kind == KindJsxElement ? tag.openingElement().tagName() : tag.tagName();
		var found:Null<{c:MClass, m:MMember}> = null;
		switch t.kind {
			case KindIdentifier:
				switch api.of(t) {
					case FStatic(c, m): found = staticOf(c.path, m, t);
					case FClass(c): return fail('${c.name} is a class, not a component');
					case null:
				}
			case KindPropertyAccessExpression if (t.expression().kind == KindIdentifier):
				switch api.of(t.expression()) {
					case FClass(c): found = staticOf(c.path, t.name().text, t);
					case FStatic(_, _): return fail(name + " is not a component");
					case null:
				}
			case _:
		}
		if (found == null) {
			// (the program's function: its props' types say which read, whether its children are a function)
			var reads = [], childFunction = false;
			var decl = declarationOf(t);
			if (decl != null) {
				var ps = decl.parameters() ?? [];
				if (ps.length > 0 && ps[0].type() != null && ps[0].type().kind == KindTypeLiteral)
					for (m in ps[0].type().members()) if (m.kind == KindPropertySignature && m.name() != null) {
						if (api.namesRead(m.type())) reads.push(m.name().text);
						if (m.name().text == "children" && m.type() != null && m.type().kind == KindFunctionType) childFunction = true;
					}
			}
			return {callee: MScriptComponent(t), children: null, reads: reads, childFunction: childFunction};
		}
		var c = found.c, m = found.m;
		var props = propsOf(m.type);
		var pin = pinOf(c, m);
		if (renderer == Plan.ROOT) {
			if (pin != null && pin != renderer)
				fail("helder.view: <" + name + "> is " + pin + "'s markup, not a root's: a root (UiWindow.run's, Render.open's) holds roots (<Surface>) and components of no renderer");
		} else if (renderer != null) {
			var picked = pick(c, m, renderer, fail);
			c = picked.c;
			m = picked.m;
			props = propsOf(m.type);
			pin = pinOf(c, m);
			if (pin == Plan.ROOT) fail("helder.view: <" + name + "> is a root: UiWindow.run's or Render.open's content, not " + renderer + "'s markup");
			if (pin != null && pin != renderer) fail("helder.view: <" + name + "> is " + pin + "'s markup, not " + renderer + "'s");
		}
		var reads = [], children:Null<String> = null, childFunction = false;
		for (p in props) {
			if (p.name == "children") {
				switch HTypes.bare(p.t) {
					case HView(r): children = r;
					case HFn(_, _): childFunction = true;
					case _:
				}
			}
			if (HTypes.bare(p.t).match(HRead(_))) reads.push(p.name);
		}
		return {callee: MHaxeComponent(c, m), children: children, reads: reads, childFunction: childFunction};
	}

	function staticOf(path:String, field:String, at:Node):{c:MClass, m:MMember} {
		var c = manifest.cls(path);
		var m = c == null ? null : c.statics.get(field);
		if (m == null || m.kind != "method") return f.fail(at, path + "." + field + " is no component of helder's the manifest lists");
		return {c: c, m: m};
	}

	// (the function for renderer: the component itself, or its class's counterpart (@:renderer); none an error)
	function pick(c:MClass, m:MMember, renderer:String, fail:String->Dynamic):{c:MClass, m:MMember} {
		if (c.only == null || c.only.indexOf(renderer) >= 0) return {c: c, m: m};
		var other = c.other.get(renderer);
		var oc = other == null ? null : manifest.cls(other);
		var om = oc == null ? null : oc.statics.get(m.name);
		if (om != null) return {c: oc, m: om};
		return fail("helder.view: " + c.path + "." + m.name + " has no version for " + renderer + " (@:renderer names none)");
	}

	static function propsOf(t:HType):Array<HArg> return switch t {
		case HFn(args, _) if (args.length > 0): switch HTypes.bare(args[0].t) {
				case HAnon(fields): fields;
				case _: [];
			}
		case _: [];
	}

	// (the renderer a component's result pins it to: ViewOf<R>, a node of R)
	function pinOf(c:MClass, m:MMember):Null<String> return switch m.type {
		case HFn(_, ret): switch HTypes.bare(ret) {
				case HView(r): r;
				case HClass(path, _):
					var k = manifest.cls(path);
					k == null ? null : k.rendered;
				case _: null;
			}
		case _: null;
	}

	// (the program's function a tag names: in its module, or imported)
	function declarationOf(t:Node):Null<Node> {
		if (t.kind != KindIdentifier || t.symbol == null) return null;
		for (sf in f.src.files) for (n in sf.root.statements())
			if (n.kind == KindFunctionDeclaration && n.name() != null && n.name().symbol == t.symbol) return n;
		for (n in t.file.root.statements()) if (n.kind == KindImportDeclaration && n.importClause() != null && n.importClause().namedBindings() != null
			&& n.importClause().namedBindings().kind == KindNamedImports)
			for (spec in n.importClause().namedBindings().elements()) if (spec.name().text == t.text) {
				var target = f.src.resolve(n.moduleSpecifier());
				var exported = (spec.propertyName() ?? spec.name()).text;
				for (sf in f.src.files) if (sf.path == target) for (m in sf.root.statements())
					if (m.kind == KindFunctionDeclaration && m.name() != null && m.name().text == exported) return m;
			}
		return null;
	}

	// ---- lowering: where the literal is

	// a planned literal's value: its holes evaluated, its View made
	function value(e:TsMarkup, n:Node):Ex return switch e {
		case MView(v): view(v, n);
		case _: throw "TSHX004: a literal's plan is a View";
	}

	function view(v:Planned<TsMarkup>, n:Node):Ex {
		var holes = new Map<String, Local>(), names = [];
		for (h in v.holes) switch h {
			case MHoleDecl(name, e, factory):
				var x = holeValue(e);
				var l = b.local(name, Ir.typeOf(x));
				b.out.push(SSet(l, x));
				holes.set(name, l);
				names.push(name);
			case _:
		}
		var source = haxe.io.Path.withoutDirectory(n.file.path) + ":" + n.file.line(n.file.skipTrivia(n.pos));
		var parts:Ex = v.parts == null ? ENull(TRef(RAny)) : closure(partsSig(), holes, (args, refs) -> {
			var items = [for (part in v.parts) any(mountExpr(part, null, refs))];
			b.out.push(SReturn(b.temp(ENewArr(TRef(RAny), Vector.fromArrayCopy(items)))));
		});
		if (v.renderer == Plan.ROOT) return make(Plan.ROOT, null, 0, null, parts, source);
		if (v.renderer == null) {
			var key = HostId.of(n.file.path + ":" + n.index + ":" + v.at);
			agnostic.push({key: key, holes: names, body: v.body});
			var list = b.temp(ENewArr(TRef(RAny), Vector.fromArrayCopy([for (name in names) any(ELocal(holes.get(name)))])));
			return make(null, null, key, list, parts, source);
		}
		var r = renderer(v.renderer, n);
		// (values the mount would evaluate where it runs, the program's: evaluated here)
		var body = lift(v.body, holes);
		var sig = mountSig();
		var mount = closure(sig, holes, (args, refs) -> mountBody(body, r, args, refs, false));
		return make(v.renderer, mount, 0, null, parts, source);
	}

	function renderer(path:String, n:Node):MRenderer {
		var r = manifest.renderers.get(path);
		if (r == null) return f.fail(n, "markup for " + path + ", a renderer the program does not reach (its manifest: helder's classes its declaration files name)");
		return r;
	}

	// new View(renderer, mount, key, holes, parts, source)
	function make(renderer:Null<String>, mount:Null<Ex>, key:Int, holes:Null<Ex>, parts:Ex, source:String):Ex {
		var ci = bridge.classInfo("helder.view.View");
		var ctor = bridge.fn("helder_view_View_new");
		var o = b.temp(ENewObj(ci));
		var id = renderer == null ? 0 : HostId.of(renderer);
		var args = [o, EInt(id), mount ?? ENull(ctor.args[2].ty), EInt(key), holes ?? ENull(ctor.args[4].ty), parts, EStr(source)];
		b.out.push(SExpr(ECall(ctor, Vector.fromArrayCopy([for (i in 0...args.length) b.coerce(args[i], ctor.args[i].ty)]))));
		return any(o);
	}

	function mountSig():SigInfo return switch bridge.fn("helder_view_View_new").args[2].ty {
		case TRef(RClos(s)): s;
		case t: throw "TSHX004: View's mount is no function: " + t;
	}

	function partsSig():SigInfo return switch bridge.fn("helder_view_View_new").args[5].ty {
		case TRef(RClos(s)): s;
		case t: throw "TSHX004: View's parts is no function: " + t;
	}

	// a closure of signature s capturing the holes (refs: their values inside)
	function closure(s:SigInfo, holes:Map<String, Local>, build:(Array<Local>, Map<String, Ex>) -> Void):Ex {
		var names = [for (k in holes.keys()) k];
		names.sort(Reflect.compare);
		var fi = Builder.func(f.p, "markup" + serial++, s.ret);
		fi.args = [new Local(0, "closure", TRef(RAny))].concat([for (i in 0...s.args.length) new Local(i + 1, "a" + i, s.args[i])]);
		var li = new LambdaInfo(f.p.lambdas.length, s, Vector.fromArrayCopy([for (k in names) holes.get(k)]), fi);
		f.p.lambdas.push(li);
		fi.lambda = li;
		var outer = f.b;
		f.b = new Builder(f.p, fi);
		var refs = new Map<String, Ex>();
		for (i in 0...names.length) refs.set(names[i], b.temp(ECapture(li, i, ELocal(fi.args[0]))));
		build(fi.args.slice(1), refs);
		if (s.ret == TVoid) b.out.push(SReturn(null));
		b.finish();
		f.b = outer;
		return b.temp(ENewClos(li, Vector.fromArrayCopy([for (k in names) ELocal(holes.get(k))])));
	}

	// (a mount's values of the program's (its factories, an attribute's
	// expression it sets): holes of their own, evaluated where the literal is)
	function lift(body:Array<TsMarkup>, holes:Map<String, Local>):Array<TsMarkup> {
		function walk(m:TsMarkup):TsMarkup return switch m {
			case MFactory(_, _, _, _, _) | MThunk(_) | MHandler(_) | MView(_): hoist(m, holes);
			case MCode(n, _) if (!literalCode(n)): hoist(m, holes);
			case MCall(of, name, args): MCall(of, name, [for (a in args) walk(a)]);
			case MDeclare(name, e): MDeclare(name, walk(e));
			case MArray(items): MArray([for (i in items) walk(i)]);
			case MPartRef(el, ref): MPartRef(walk(el), walk(ref));
			case MKeyScope(name, key): MKeyScope(name, walk(key));
			case MCallValue(x): MCallValue(walk(x));
			case _: m;
		}
		return [for (s in body) walk(s)];
	}

	function hoist(m:TsMarkup, holes:Map<String, Local>):TsMarkup {
		var x = holeValue(m);
		var name = "__x" + serial++;
		var l = b.local(name, Ir.typeOf(x));
		b.out.push(SSet(l, x));
		holes.set(name, l);
		return MHoleRef(name);
	}

	static function literalCode(n:Node):Bool return n.kind == KindNumericLiteral || n.kind == KindStringLiteral;

	// a hole's value, where the literal is: a Haxe value (the program's, made Haxe's), a factory a closure
	function holeValue(e:TsMarkup):Ex return switch e {
		case MCode(_, _) | MString(_) | MBool(_) | MNull | MView(_): any(bridge.call(bridge.interop("toHaxe"), [any(script(e))]));
		case MThunk(inner):
			any(bridge.adapter(arrow(() -> any(script(inner))), f.p.sig([], TRef(RAny)), [], HDynamic, f.where()));
		case MHandler(inner):
			any(bridge.adapter(script(inner), f.p.sig([TRef(RAny)], TVoid), [{name: "event", opt: false, t: HDynamic}], HVoid, f.where()));
		case MFactory(c, props, content, agnostic, at):
			bridge.adapter(arrow(() -> any(factoryCall(c, props, content, agnostic, nodes[at]))), f.p.sig([], TRef(RAny)), [], HDynamic, f.where());
		case _: throw "TSHX004: unexpected hole " + e;
	}

	// a value as the program's: its expression's, a literal's View, a thunk's function
	function script(e:TsMarkup):Ex return switch e {
		case MCode(n, renderer):
			if (renderer != null) mark(n, renderer);
			f.expr(n);
		case MString(s): EStr(s);
		case MBool(v): ECast(TBool, EInt(v ? 1 : 0));
		case MNull: ENull(TRef(RAny));
		case MView(v): view(v, nodes.length > 0 ? nodes[v.at] : null);
		case MThunk(inner): arrow(() -> any(script(inner)));
		case _: throw "TSHX004: unexpected value " + e;
	}

	// () => value, the program's function (its bindings captured as an arrow's)
	function arrow(value:() -> Ex):Ex {
		var r = f.lambda(null, [], true, false, fi -> b.out.push(SReturn(value())));
		return b.runtime("libFunction", [r.clos, EInt(r.arity), ECast(TBool, EInt(0)), EInt(1), EStr("")]);
	}

	// (the literals in a hole's expression: for its literal's renderer, as Haxe's markup in a hole is)
	function mark(n:Node, renderer:String) {
		if (n.kind == KindJsxElement || n.kind == KindJsxSelfClosingElement || n.kind == KindJsxFragment) {
			if (!placed.exists(n)) placed.set(n, renderer);
			return;
		}
		for (c in n.children()) mark(c, renderer);
	}

	// a component called: its props, its content (children), by its function's types
	function factoryCall(c:Component<TsMarkup>, props:Array<{name:String, value:TsMarkup, at:Int}>, content:Null<TsMarkup>, agnostic:Bool, at:Node):Ex {
		var given = new Map<String, Ex>(), order = [];
		for (p in props) {
			given.set(p.name, script(p.value));
			order.push(p.name);
		}
		if (content != null) {
			given.set("children", script(content));
			order.push("children");
		}
		return switch c.callee {
			case MHaxeComponent(cls, m):
				var where = f.where();
				function callOf(cls:MClass, m:MMember):Ex {
					var s = bridge.props(propsOf(m.type), given, where);
					return bridge.callStatic(cls, m, [s], where, true);
				}
				if (!agnostic || cls.only == null) callOf(cls, m) else {
					// (Pick.call: the function for the renderer mounting it, Render.pass)
					var pass = b.temp(EGlobal(bridge.global("helder_view_Render_pass"), TI32));
					var l = b.local("component", TRef(RAny));
					var cases:Array<{id:Int, cls:MClass, m:MMember}> = [for (r in cls.only) {id: HostId.of(r), cls: cls, m: m}];
					for (r => other in cls.other) {
						var oc = manifest.cls(other);
						if (oc != null && oc.statics.exists(m.name)) cases.push({id: HostId.of(r), cls: oc, m: oc.statics.get(m.name)});
					}
					var otherwise = b.block(() -> b.out.push(SSet(l, any(bridge.call(bridge.interop("fail"), [EStr("helder.view: " + cls.path + "." + m.name + " has no version for this renderer")])))));
					var chain = otherwise;
					var k = cases.length;
					while (k-- > 0) {
						var x = cases[k];
						var then = b.block(() -> b.out.push(SSet(l, any(callOf(x.cls, x.m)))));
						chain = Vector.fromArrayCopy([SIf(EBin(Eq, pass, EInt(x.id)), then, chain)]);
					}
					for (s in chain) b.out.push(s);
					ELocal(l);
				}
			case MScriptComponent(tag):
				// (a prop that reads given a constant: a function giving it)
				if (c.reads != null) for (r in c.reads) if (given.exists(r)) given.set(r, bridge.call(bridge.interop("readFunction"), [any(given.get(r))]));
				var fn = b.temp(any(f.expr(tag)));
				var o = b.runtime("libObject", [f.pack([for (k in order) EStr(k)]), f.pack([for (k in order) given.get(k)])]);
				f.apply(fn, f.pack([o]));
			case _: throw "TSHX004: unexpected callee";
		}
	}

	// ---- lowering: the mount, on Haxe values

	// a mount's statements for renderer r: (parent, before, out) its arguments, refs the holes' values
	function mountBody(body:Array<TsMarkup>, r:MRenderer, args:Array<Local>, refs:Map<String, Ex>, late:Bool) {
		var node = TRef(nodeOf(r));
		var vars = new Map<String, Ex>();
		vars.set("__p", b.temp(ECast(node, b.coerce(ELocal(args[0]), TRef(RAny)))));
		vars.set("__b", b.temp(ECast(node, b.coerce(ELocal(args[1]), TRef(RAny)))));
		vars.set("__o", b.temp(ECast(TRef(RArr(node)), b.coerce(ELocal(args[2]), TRef(RAny)))));
		var ctx = {r: r, vars: vars, refs: refs, late: late};
		for (s in body) mountStmt(s, ctx);
	}

	function nodeOf(r:MRenderer):RefTy {
		var ci = r.node == null ? null : bridge.classInfo(r.node);
		return ci == null ? RAny : RObj(ci);
	}

	function mountStmt(s:TsMarkup, ctx:MountContext) switch s {
		case MDeclare(name, e):
			var x = mountExpr(e, ctx, ctx.refs);
			var l = b.local(name, Ir.typeOf(x));
			b.out.push(SSet(l, x));
			ctx.vars.set(name, ELocal(l));
		case MPartRef(el, ref):
			var r = b.temp(any(mountExpr(ref, ctx, ctx.refs)));
			var e = mountExpr(el, ctx, ctx.refs);
			b.out.push(SIf(ENot(EBin(RefEq, r, ENull(TRef(RAny)))), b.block(() -> bridge.call(bridge.interop("apply1"), [r, any(part(e, ctx))])), new Vector(0)));
		case _:
			mountExpr(s, ctx, ctx.refs);
	}

	function mountExpr(e:TsMarkup, ctx:Null<MountContext>, refs:Map<String, Ex>):Ex return switch e {
		case MIdent(name):
			var v = ctx == null ? null : ctx.vars.get(name);
			if (v == null) throw "TSHX004: markup's " + name + " is not declared";
			v;
		case MString(s): EStr(s);
		case MBool(v): ECast(TBool, EInt(v ? 1 : 0));
		case MNull: ENull(TRef(RAny));
		case MHoleRef(name):
			var v = refs.get(name);
			if (v == null) throw "TSHX004: markup's hole " + name + " is not captured";
			v;
		case MCode(n, _) if (n.kind == KindNumericLiteral): b.temp(EBox(TF64, EF64(Std.parseFloat(n.text))));
		case MCode(n, _) if (n.kind == KindStringLiteral): EStr(n.text);
		case MArray(items): b.temp(ENewArr(TRef(RAny), Vector.fromArrayCopy([for (i in items) any(mountExpr(i, ctx, refs))])));
		case MCall(of, name, args): mountCall(of, name, [for (a in args) mountExpr(a, ctx, refs)], args, ctx);
		case MKeyScope(name, key): bridge.call(bridge.interop("keyScope"), [EStr(name), any(mountExpr(key, ctx, refs))]);
		case MCallValue(fh):
			var s = f.p.sig([], TRef(RAny));
			b.temp(ECallClos(s, b.coerce(mountExpr(fh, ctx, refs), TRef(RClos(s))), new Vector(0)));
		case _: throw "TSHX004: unexpected markup in a mount: " + e;
	}

	// (a neutral element's part: itself, or its renderer's part)
	function part(e:Ex, ctx:MountContext):Ex return ctx.r.native || ctx.r.functions.get("part") != "function" ? e : bridge.call(host(ctx.r, "part"), [e]);

	function host(r:MRenderer, name:String):FuncInfo return bridge.fn(ident(r.path) + "_" + name);

	function runtime(r:MRenderer, name:String):FuncInfo return bridge.fn(ident(r.runtime) + "_" + name);

	static function ident(path:String):String return path.split(".").join("_");

	// a call of the renderer's (Host), its runtime's (Runtime) or its neutral
	// elements' (Neutral), as MarkupMacro.forRenderer makes them: a literal
	// name's property set by the renderer's setter for it (Renders' setter),
	// a neutral element by the renderer's neutral functions or as its own
	function mountCall(of:Callee, name:String, args:Array<Ex>, raw:Array<TsMarkup>, ctx:MountContext):Ex {
		var r = ctx.r;
		switch of {
			case Host:
				if (name == "setProperty" && r.functions.get("setProperty") == "macro") return setProperty(r, args, raw, ctx);
				return hostCall(r, name, args, ctx);
			case Runtime:
				if (name == "prop" && r.setters != null) switch raw[1] {
					case MString(s): return bridge.call(runtime(r, "propWith"), [args[0], args[1], args[2], setter(r, s)]);
					case _:
				}
				if (name == "ref" && !bridge.hasFn(ident(r.runtime) + "_ref")) return bridge.call(bridge.interop("apply1"), [any(args[1]), any(args[0])]);
				if (name == "componentIn" && !bridge.hasFn(ident(r.runtime) + "_componentIn")) return bridge.call(runtime(r, "component"), args.slice(1));
				return bridge.call(runtime(r, name), args);
			case Neutral:
				if (!r.neutral && !r.native) {
					var m = "markup: " + r.path + " realises no neutral elements (view, text, view:button...)";
					if (ctx.late) return bridge.call(bridge.interop("fail"), [EStr(m)]);
					throw "TSHX001: " + m;
				}
				if (r.neutral) return switch name {
					case "element": hostCall(r, "neutralElement", args, ctx);
					case "property": hostCall(r, "neutralProperty", args, ctx);
					case "listen": hostCall(r, "neutralListen", args, ctx);
					case "part": hostCall(r, "part", args, ctx);
					case _: throw "TSHX001: " + r.path + "'s neutral " + name + " is not supported from TypeScript";
				}
				return switch name {
					case "element": hostCall(r, "createElement", [args[0]], ctx);
					case "property":
						r.functions.get("setProperty") == "macro" ? setProperty(r, [args[0], args[2], args[3]], [raw[0], raw[2], raw[3]], ctx) : hostCall(r, "setProperty", [args[0], args[2], args[3]], ctx);
					case "prop":
						switch raw[2] {
							case MString(s) if (r.setters != null): bridge.call(runtime(r, "propWith"), [args[0], args[2], args[3], setter(r, s)]);
							case _: bridge.call(runtime(r, "prop"), [args[0], args[2], args[3]]);
						}
					case "listen": hostCall(r, "listen", [args[0], args[2], args[3]], ctx);
					case "part": args[0];
					case _: throw "TSHX004: markup's neutral " + name;
				}
		}
	}

	function hostCall(r:MRenderer, name:String, args:Array<Ex>, ctx:MountContext):Ex {
		var kind = r.functions.get(name);
		if (kind != "function") {
			var m = "markup: " + r.path + "." + name + (kind == "macro" ? " is a macro, which a TypeScript program's markup cannot call" : " is not a function of the renderer");
			if (ctx.late) return bridge.call(bridge.interop("fail"), [EStr(m)]);
			throw "TSHX001: " + m;
		}
		return bridge.call(host(r, name), args);
	}

	// (setProperty a macro: the renderer's setter for the literal name, Renders' setter)
	function setProperty(r:MRenderer, args:Array<Ex>, raw:Array<TsMarkup>, ctx:MountContext):Ex {
		var name = switch raw[1] {
			case MString(s): s;
			case _: null;
		}
		var fn = name == null ? r.setters?.fallback : r.setter(name);
		if (fn == null) return hostCall(r, "setProperty", args, ctx);
		return bridge.call(bridge.fn(ident(fn)), args);
	}

	function setter(r:MRenderer, name:String):Ex {
		var fn = r.setter(name);
		if (fn == null) throw "TSHX004: " + r.path + " has no setter for " + name;
		return bridge.staticClosure(ident(fn));
	}

	function any(e:Ex):Ex return b.coerce(e, TRef(RAny));

	// ---- the agnostic literals' code, for each renderer: ViewRuntime's late, set at the start

	public function install():Array<Stmt> {
		if (agnostic.length == 0) return [];
		var paths = [for (k in manifest.renderers.keys()) k];
		paths.sort(Reflect.compare);
		return f.b.block(() -> {
			for (path in paths) {
				var r = manifest.renderers.get(path);
				var g = bridge.global(ident(r.runtime) + "_late");
				if (g == null) continue;
				var t = f.p.globals[g].ty;
				var s = switch t {
					case TRef(RClos(s)): s;
					case _: continue;
				}
				var prev = b.local("late", t);
				b.out.push(SSet(prev, EGlobal(g, t)));
				var fi = Builder.func(f.p, "late" + serial++, s.ret);
				fi.args = [new Local(0, "closure", TRef(RAny))].concat([for (i in 0...s.args.length) new Local(i + 1, "a" + i, s.args[i])]);
				var li = new LambdaInfo(f.p.lambdas.length, s, Vector.fromArrayCopy([prev]), fi);
				f.p.lambdas.push(li);
				fi.lambda = li;
				var outer = f.b;
				f.b = new Builder(f.p, fi);
				var before = b.temp(ECapture(li, 0, ELocal(fi.args[0])));
				var args = fi.args.slice(1);
				var holes = b.temp(ECast(TRef(RArr(TRef(RAny))), b.coerce(ELocal(args[1]), TRef(RAny))));
				var cases = [];
				for (l in agnostic) {
					var body = b.block(() -> {
						var refs = new Map<String, Ex>();
						for (k in 0...l.holes.length) refs.set(l.holes[k], b.temp(EArrGet(TRef(RAny), holes, EInt(k))));
						mountBody(l.body, r, args.slice(2), refs, true);
					});
					cases.push({values: Vector.fromArrayCopy([l.key]), body: body});
				}
				var fallback = b.block(() -> {
					var call = b.block(() -> b.out.push(SExpr(ECallClos(s, before, Vector.fromArrayCopy([for (a in args) ELocal(a)])))));
					var none = b.block(() -> bridge.call(bridge.interop("fail"), [EStr("helder.view: no code for this markup")]));
					b.out.push(SIf(EBin(RefEq, before, ENull(t)), none, call));
				});
				// (by key: a chain of tests, the IR the frontend writes)
				var chain = fallback;
				var k = cases.length;
				while (k-- > 0) chain = Vector.fromArrayCopy([SIf(EBin(Eq, ELocal(args[0]), EInt(cases[k].values[0])), cases[k].body, chain)]);
				for (x in chain) b.out.push(x);
				b.out.push(SReturn(null));
				b.finish();
				f.b = outer;
				b.out.push(SSetGlobal(g, ENewClos(li, Vector.fromArrayCopy([ELocal(prev)]))));
			}
		}).toArray();
	}
}

typedef MountContext = {r:MRenderer, vars:Map<String, Ex>, refs:Map<String, Ex>, late:Bool};

// A renderer's identity at run time (HostMacro.id: FNV-1a of its class path, 31 bits, never 0).
class HostId {
	public static function of(path:String):Int {
		var h = 0x811c9dc5;
		for (k in 0...path.length) h = (h ^ StringTools.fastCodeAt(path, k)) * 0x01000193;
		h &= 0x7fffffff;
		return h == 0 ? 1 : h;
	}
}

// The planner's Target for TSX: facts from the manifest and TypeScript's
// types, code as TsMarkup (Tsx lowers it).
class TsTarget implements Target<TsMarkup> {
	final tsx:Tsx;
	final root:Node;

	public function new(tsx:Tsx, root:Node) {
		this.tsx = tsx;
		this.root = root;
	}

	function nodeAt(where:Null<Where>):Node return where == null ? root : tsx.nodes[where.at];

	public function error(message:String, where:Null<Where>):Dynamic return @:privateAccess tsx.f.fail(nodeAt(where), message);

	public function elements(renderer:String):Null<Array<String>> {
		var r = @:privateAccess tsx.manifest.renderers.get(renderer);
		return r == null ? null : r.elements;
	}

	public function code(code:String, at:Int, renderer:Null<String>, required:Bool):Null<TsMarkup> {
		if (code == "") {
			if (required) error("markup: an empty expression", {at: at, length: 1});
			return null;
		}
		return MCode(tsx.nodes[at], renderer);
	}

	public function isLiteral(e:TsMarkup):Bool return switch e {
		case MCode(n, _): n.kind == KindNumericLiteral || n.kind == KindStringLiteral;
		case _: false;
	}

	public function isPlain(e:TsMarkup):Bool return switch e {
		case MCode(n, _): tsx.plain(n);
		case _: false;
	}

	public function mayRead(e:TsMarkup):Bool return switch e {
		case MCode(n, _): tsx.mayRead(n);
		case _: false;
	}

	public function thunk(e:TsMarkup):TsMarkup return MThunk(e);

	public function isFunction(e:TsMarkup):Bool return switch e {
		case MCode(n, _):
			var s = n;
			while (s.kind == KindParenthesizedExpression) s = s.expression();
			s.kind == KindArrowFunction || s.kind == KindFunctionExpression;
		case _: false;
	}

	// (tsgo checked it against the declarations' JSX types: a function of the event or of none)
	public function handler(e:TsMarkup, name:String, renderer:Null<String>, neutral:Bool, where:Where):TsMarkup return MHandler(e);

	public function devKeys():Bool return tsx.dev;

	public function component(name:String, at:Int, renderer:Null<String>):Component<TsMarkup>
		return tsx.component(name, tsx.nodes[at], renderer, m -> error(m, {at: at, length: name.length}));

	public function ident(name:String):TsMarkup return MIdent(name);

	public function string(s:String, ?where:Where):TsMarkup return MString(s);

	public function bool(v:Bool, ?where:Where):TsMarkup return MBool(v);

	public function nil():TsMarkup return MNull;

	public function isNull(e:TsMarkup):Bool return e.match(MNull);

	public function anyArray(items:Array<TsMarkup>):TsMarkup return MArray(items);

	public function declare(name:String, e:TsMarkup, where:Null<Where>):TsMarkup return MDeclare(name, e);

	public function call(of:Callee, name:String, args:Array<TsMarkup>, where:Null<Where>):TsMarkup return MCall(of, name, args);

	public function holeDecl(name:String, e:TsMarkup, factory:Bool):TsMarkup return MHoleDecl(name, e, factory);

	public function holeRef(name:String, e:TsMarkup):TsMarkup return MHoleRef(name);

	public function callValue(f:TsMarkup):TsMarkup return MCallValue(f);

	public function partRef(element:TsMarkup, ref:TsMarkup, where:Where):TsMarkup return MPartRef(element, ref);

	public function keyScope(name:String, key:TsMarkup):TsMarkup return MKeyScope(name, key);

	public function factory(c:Component<TsMarkup>, props:Array<{name:String, value:TsMarkup, at:Int}>, content:Null<TsMarkup>, at:Int, agnostic:Bool):TsMarkup
		return MFactory(c, props, content, agnostic, at);

	public function view(v:Planned<TsMarkup>):TsMarkup return MView(v);
}
