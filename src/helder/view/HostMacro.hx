package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;

// The program's renderers and the runtime made for each.
//
// Renderers are named by defines: -D helder.view.renderer=<class> and any
// -D helder.view.renderer.<name>=<class> (each package its own: -lib
// helder.ui sets helder.view.renderer.ui), ordered by define name; each is a
// class implementing Renders<N>, its functions checked once. ViewRuntime is
// written against Host and HostNode, placeholders: its build macro keeps
// its fields and makes ViewRuntime itself the first renderer's runtime;
// instance(i) defines ViewRuntime_<i> for the others, the same fields with
// Host, HostNode, ViewRuntime and INDEX replaced. Markup compiles each literal
// once per renderer, so that a subtree's calls go straight to the renderer
// that owns it.
class HostMacro {
	static final REQUIRED = [
		"createElement", "createText", "createMarker", "setText", "holdsText", "setProperty", "setStyle", "listen", "insert", "remove", "parentOf",
		"arrange", "isNode"
	];

	static var list:Null<Array<{path:String, node:ComplexType, type:Type, setter:Bool, neutral:Bool, native:Bool}>> = null;
	static var template:Null<Array<Field>> = null;

	// the renderers: their class paths and node types
	public static function renderers():Array<{path:String, node:ComplexType, type:Type, setter:Bool, neutral:Bool, native:Bool}> {
		if (list != null) return list;
		var names = [];
		for (k => v in Context.getDefines())
			if (k == "helder.view.renderer" || StringTools.startsWith(k, "helder.view.renderer.")) names.push({key: k, path: v});
		names.sort((a, b) -> a.key == "helder.view.renderer" ? -1 : b.key == "helder.view.renderer" ? 1 : Reflect.compare(a.key, b.key));
		var seen = new Map<String, Bool>();
		list = [];
		for (n in names) {
			if (seen.exists(n.path) || n.path == "" || n.path == "1") continue;
			seen.set(n.path, true);
			list.push(check(n.path));
		}
		if (list.length == 0)
			Context.fatalError("helder.view: no renderer: name one with -D helder.view.renderer.<name>=<class> (-lib helder sets ui's)",
				Context.currentPos());
		return list;
	}

	// a renderer's class checked against the contract, its node type
	static function check(path:String):{path:String, node:ComplexType, type:Type, setter:Bool, neutral:Bool, native:Bool} {
		var c = switch Context.getType(path) {
			case TInst(c, _): c.get();
			case _: Context.fatalError('helder.view: the renderer $path is not a class', Context.currentPos());
		}
		var have = [for (f in c.statics.get()) f.name => true];
		var missing = [for (r in REQUIRED) if (!have.exists(r)) r];
		if (missing.length > 0) Context.fatalError('helder.view: the renderer $path lacks ' + missing.join(", ") + " (helder.view.Renders)", c.pos);
		for (i in c.interfaces)
			if (i.t.toString() == "helder.view.Renders") return {path: path, node: Context.toComplexType(i.params[0]), type: i.params[0], setter: have.exists("setter"),
					neutral: have.exists("neutralElement"), native: have.exists("neutralNative")};
		return Context.fatalError('helder.view: the renderer $path does not implement helder.view.Renders<Node>', c.pos);
	}

	// the index of the renderer whose nodes t is (a subclass of), else -1
	public static function rendererOf(t:Type):Int {
		var rs = renderers();
		for (i in 0...rs.length)
			if (Context.unify(t, rs[i].type)) return i;
		return -1;
	}

	// the runtime class of renderer i, as a path
	public static function runtime(i:Int):Array<String> {
		if (i == 0) return ["helder", "view", "ViewRuntime"];
		var name = 'ViewRuntime_$i';
		try {
			Context.getType('helder.view.$name');
		} catch (_:Dynamic) {
			// (its build macro run: its fields asked for)
			switch Context.getType("helder.view.ViewRuntime") {
				case TInst(c, _): c.get().statics.get();
				case _:
			}
			if (template == null) Context.fatalError("helder.view: the runtime's fields are not known (a cached build?)", Context.currentPos());
			Context.defineType({
				pack: ["helder", "view"],
				name: name,
				pos: Context.currentPos(),
				meta: [{name: ":noCompletion", pos: Context.currentPos()}],
				kind: TDClass(),
				fields: [for (f in template) subst(f, i)]
			});
		}
		return ["helder", "view", name];
	}

	// whether renderer i has the optional setter (Renders)
	public static function hasSetter(i:Int):Bool
		return renderers()[i].setter;

	// whether renderer i realises the neutral elements its own way (neutralElement, neutralProperty,
	// neutralSetter, neutralListen, part: a page's renderer), else as its own elements (ui's)
	public static function hasNeutral(i:Int):Bool
		return renderers()[i].neutral;

	// whether renderer i's own elements are the neutral ones (neutralNative: ui's)
	public static function isNeutralNative(i:Int):Bool
		return renderers()[i].native;

	public static function rendererPath(i:Int):Array<String>
		return renderers()[i].path.split(".");

	// ViewRuntime's build macro: its fields kept, made the first renderer's
	public static function build():Array<Field> {
		template = Context.getBuildFields();
		return [for (f in template) subst(f, 0)];
	}

	// a field with Host, HostNode, ViewRuntime and INDEX those of renderer i
	static function subst(f:Field, i:Int):Field
		return new Subst(renderers()[i].node, rendererPath(i), runtime0Name(i), i).field(f);

	static function runtime0Name(i:Int):String
		return i == 0 ? "ViewRuntime" : 'ViewRuntime_$i';
}

// (a field's copy for one renderer)
private class Subst {
	final node:ComplexType;
	final host:Array<String>;
	final self:String;
	final i:Int;

	public function new(node, host, self, i) {
		this.node = node;
		this.host = host;
		this.self = self;
		this.i = i;
	}

	function ct(t:Null<ComplexType>):Null<ComplexType>
		return t == null ? null : switch t {
			case TPath({pack: [], name: "HostNode", params: null | []}): node;
			case TPath(p):
				TPath({pack: p.pack, name: p.name == "ViewRuntime" && p.pack.length == 0 ? self : p.name, sub: p.sub,
					params: p.params == null ? null : [for (x in p.params) switch x {
						case TPType(t): TPType(ct(t));
						case TPExpr(e): TPExpr(ex(e));
					}]});
			case TFunction(args, ret): TFunction([for (a in args) ct(a)], ct(ret));
			case TAnonymous(fs): TAnonymous([for (f in fs) field(f)]);
			case TParent(t): TParent(ct(t));
			case TOptional(t): TOptional(ct(t));
			case TNamed(n, t): TNamed(n, ct(t));
			case _: t;
		}

	function fn(f:Function):Function
		return {
			args: [for (a in f.args) {name: a.name, opt: a.opt, type: ct(a.type), value: a.value == null ? null : ex(a.value), meta: a.meta}],
			ret: ct(f.ret),
			expr: f.expr == null ? null : ex(f.expr),
			params: f.params
		};

	function ex(e:Expr):Expr
		return switch e.expr {
			case EConst(CIdent("Host")): macro @:pos(e.pos) $p{host};
			case EConst(CIdent("ViewRuntime")): macro @:pos(e.pos) $i{self};
			case EConst(CIdent("INDEX")): macro @:pos(e.pos) $v{i};
			case EVars(vs): {expr: EVars([for (v in vs) {name: v.name, type: ct(v.type), expr: v.expr == null ? null : ex(v.expr), isFinal: v.isFinal}]), pos: e.pos};
			case ENew(t, args): {expr: ENew({pack: t.pack, name: t.name, sub: t.sub, params: t.params}, [for (a in args) ex(a)]), pos: e.pos};
			case ECast(x, t): {expr: ECast(ex(x), ct(t)), pos: e.pos};
			case ECheckType(x, t): {expr: ECheckType(ex(x), ct(t)), pos: e.pos};
			case EFunction(k, f): {expr: EFunction(k, fn(f)), pos: e.pos};
			case ETry(x, cs): {expr: ETry(ex(x), [for (c in cs) {name: c.name, type: ct(c.type), expr: ex(c.expr)}]), pos: e.pos};
			case _: e.map(ex);
		}

	public function field(f:Field):Field
		return {
			name: f.name,
			doc: f.doc,
			access: f.access,
			pos: f.pos,
			meta: f.meta,
			kind: switch f.kind {
				case FVar(t, e): FVar(ct(t), e == null ? null : ex(e));
				case FProp(g, s, t, e): FProp(g, s, ct(t), e == null ? null : ex(e));
				case FFun(f): FFun(fn(f));
			}
		};
}
#end
