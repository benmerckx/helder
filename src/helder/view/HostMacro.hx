package helder.view;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;

typedef RendererInfo = {
	path:String,
	node:ComplexType,
	type:Type,
	setter:Bool,
	neutral:Bool,
	native:Bool,
	// its elements when it lists them (@:elements), else null: any name
	elements:Null<Array<String>>,
	// its identity at run time (Render.idOf)
	id:Int,
	// its runtime's class name
	runtime:String
};

// The program's renderers and the runtime made for each.
//
// No defines: a renderer is a class implementing Renders<N>, its functions
// checked when first named, and it is reached when markup is compiled for
// it or content is mounted into its nodes (MarkupMacro, Render). Each
// reached renderer gets a runtime, ViewRuntime_<path> (ViewRuntime's fields,
// kept by its build macro, with Host, HostNode, ViewRuntime, INDEX and NAME
// replaced). A literal whose renderer is not known where it is (agnostic)
// leaves a template in its class's metadata (:helder.late, so that a cached
// module keeps it); after typing, a class per reached renderer
// (Late_<path>_<hash of its code>) holds every such literal's code for it, a switch on its
// key, which its __init__ hands to the renderer's runtime (ViewRuntime's
// late); a later callback's new literals another, falling back to it.
// helder.view names no renderer: node types name theirs (@:rendered(R) on a
// class: it and its subclasses are R's nodes), views pinned to one are
// ViewOf<R>.
class HostMacro {
	static final REQUIRED = [
		"createElement", "createText", "createMarker", "setText", "holdsText", "setProperty", "setStyle", "listen", "insert", "remove", "parentOf",
		"arrange", "isNode"
	];

	// (the renderers checked, by class path; those reached, in order)
	static var infos = new Map<String, RendererInfo>();
	static var reached:Array<String> = [];
	// (ViewRuntime's fields: kept across a compilation server's builds, ViewRuntime's module may be cached)
	@:persistent static var template:Null<Array<Field>> = null;

	// a renderer's class checked against the contract (path: its class path)
	public static function info(path:String):RendererInfo {
		var i = infos.get(path);
		if (i != null) return i;
		var c = switch Context.getType(path) {
			case TInst(c, _): c.get();
			case _: Context.fatalError('helder.view: the renderer $path is not a class', Context.currentPos());
		}
		var have = [for (f in c.statics.get()) f.name => true];
		var missing = [for (r in REQUIRED) if (!have.exists(r)) r];
		if (missing.length > 0) Context.fatalError('helder.view: the renderer $path lacks ' + missing.join(", ") + " (helder.view.Renders)", c.pos);
		var full = c.pack.concat([c.name]).join(".");
		for (it in c.interfaces)
			if (it.t.toString() == "helder.view.Renders") {
				var els = c.meta.extract(":elements");
				i = {
					path: full,
					node: Context.toComplexType(it.params[0]),
					type: it.params[0],
					setter: have.exists("setter"),
					neutral: have.exists("neutralElement"),
					native: have.exists("neutralNative"),
					elements: els.length == 0 ? null : [for (e in els[0].params) switch e.expr {
						case EConst(CString(s, _)): s;
						case _: Context.fatalError("helder.view: @:elements lists strings", e.pos);
					}],
					id: id(full),
					runtime: "ViewRuntime_" + mangle(full)
				};
				infos.set(path, i);
				infos.set(full, i);
				return i;
			}
		return Context.fatalError('helder.view: the renderer $path does not implement helder.view.Renders<Node>', c.pos);
	}

	// a renderer's identity at run time: a hash of its class path (FNV-1a, 31 bits; never 0)
	public static function id(path:String):Int {
		var h = 0x811c9dc5;
		for (k in 0...path.length)
			h = (h ^ StringTools.fastCodeAt(path, k)) * 0x01000193;
		h &= 0x7fffffff;
		return h == 0 ? 1 : h;
	}

	static function mangle(path:String):String
		return path.split(".").join("_");

	// renderer path reached: its runtime made, the late code made for it after typing
	public static function reach(path:String):RendererInfo {
		var i = info(path);
		if (reached.indexOf(i.path) < 0) {
			reached.push(i.path);
			hook();
		}
		return i;
	}

	// the renderer whose nodes t is: its class's (or a superclass's) @:rendered, else a
	// reached renderer's node type it unifies with; null when none
	public static function rendererOf(t:Type):Null<String> {
		var r = rendered(t);
		if (r != null) return r;
		for (p in reached)
			if (Context.unify(t, infos.get(p).type)) return p;
		return null;
	}

	// (@:rendered(R) on t's class or a superclass: R's path)
	public static function rendered(t:Type):Null<String> {
		var c = switch Context.follow(t) {
			case TInst(c, _): c.get();
			case TAbstract(_.get() => {name: "Null", pack: []}, [p]): return rendered(p);
			case _: return null;
		}
		while (c != null) {
			var m = c.meta.extract(":rendered");
			if (m.length > 0 && m[0].params != null && m[0].params.length > 0) return resolve(m[0].params[0]);
			c = c.superClass == null ? null : c.superClass.t.get();
		}
		return null;
	}

	// a class named in metadata, by its full path
	public static function resolve(e:Expr):String {
		var name = e.toString();
		return try switch Context.getType(name) {
			case TInst(c, _): c.get().pack.concat([c.get().name]).join(".");
			case _: name;
		} catch (_:Dynamic) name;
	}

	// ViewOf<R> (through Null and typedefs): R's path, else null
	public static function viewOf(t:Null<Type>):Null<String> {
		if (t == null) return null;
		return switch t {
			case TAbstract(_.get() => {pack: ["helder", "view"], name: "ViewOf"}, [r]): switch Context.follow(r) {
					case TInst(c, _): c.get().pack.concat([c.get().name]).join(".");
					case _: null;
				}
			case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): viewOf(p);
			case TType(_.get() => d, ps): viewOf(Context.follow(t, true));
			case TMono(m) if (m.get() != null): viewOf(m.get());
			case TLazy(f): viewOf(f());
			case _: null;
		}
	}

	// the renderer a function returning t is pinned to: ViewOf<R>, or a type whose class is @:rendered(R)
	public static function pinOf(t:Null<Type>):Null<String> {
		if (t == null) return null;
		var v = viewOf(t);
		return v != null ? v : switch Context.follow(t) {
			case TMono(_) | TDynamic(_): null;
			case _: rendered(t);
		}
	}

	// the runtime class of renderer path (reached), as a path
	public static function runtime(path:String):Array<String> {
		var i = reach(path);
		try {
			Context.getType('helder.view.${i.runtime}');
		} catch (_:Dynamic) {
			if (template == null)
				// (its build macro run: its fields asked for)
				switch Context.getType("helder.view.ViewRuntime") {
					case TInst(c, _): c.get().statics.get();
					case _:
				}
			if (template == null) Context.fatalError("helder.view: the runtime's fields are not known (a cached build: build again)", Context.currentPos());
			Context.defineType({
				pack: ["helder", "view"],
				name: i.runtime,
				pos: Context.currentPos(),
				meta: [{name: ":noCompletion", pos: Context.currentPos()}],
				kind: TDClass(),
				fields: [for (f in template) subst(f, i)]
			});
		}
		return ["helder", "view", i.runtime];
	}

	// ViewRuntime's build macro: its fields kept as the template, none of its own
	public static function build():Array<Field> {
		template = Context.getBuildFields();
		return [];
	}

	// a field with Host, HostNode, ViewRuntime, INDEX and NAME those of renderer i
	static function subst(f:Field, i:RendererInfo):Field
		return new Subst(i.node, i.path.split("."), i.runtime, i.id, i.path).field(f);

	// --- after typing: the agnostic literals' code for each reached renderer

	static var hooked = false;
	// (the templates seen, each once; per renderer, those its code was made for; the classes made)
	static final literals:Array<{key:Int, holes:Expr, body:Expr, only:Expr, pos:Position}> = [];
	static final seen = new Map<Int, Bool>();
	static final done = new Map<String, Map<Int, Bool>>();

	static function hook() {
		if (hooked) return;
		hooked = true;
		Context.onAfterTyping(late);
	}

	// (each callback: the templates of the types given, cached modules' too;
	// a renderer's code for those it has none of yet in a class of their own,
	// whose mount falls back to the one set before it: a literal typed while
	// the code is made, or a renderer reached then, still gets code)
	static function late(types:Array<ModuleType>) {
		for (t in types)
			switch t {
				case TClassDecl(c):
					for (m in c.get().meta.extract(":helder.late")) {
						var key = switch m.params[0].expr {
							case EConst(CInt(s)): Std.parseInt(s);
							case _: continue;
						}
						if (seen.exists(key)) continue;
						seen.set(key, true);
						literals.push({key: key, holes: m.params[1], body: m.params[2], only: m.params[3], pos: m.pos});
					}
				case _:
			}
		for (path in reached.copy()) {
			var mine = done.get(path);
			if (mine == null) done.set(path, mine = new Map());
			var i = infos.get(path), n = i.node;
			var cases:Array<Case> = [], sig = new StringBuf();
			for (l in literals) {
				if (mine.exists(l.key)) continue;
				mine.set(l.key, true);
				sig.add(l.key + ":" + l.holes.toString() + l.body.toString() + l.only.toString() + ";");
				var only = switch l.only.expr {
					case EArrayDecl(a): [for (x in a) switch x.expr {
							case EConst(CString(s, _)): s;
							case _: "";
						}];
					case _: [];
				}
				var body = switch l.body.expr {
					case EBlock(es): es;
					case _: [l.body];
				}
				var code = only.length > 0 && only.indexOf(path) < 0 ? [macro @:pos(l.pos) throw $v{"helder.view: this markup is not for " + path + " (@:renderer)"}] : MarkupMacro.forRenderer(body,
					path, true);
				var decls = switch l.holes.expr {
					case EBlock(vs): [
							for (k in 0...vs.length)
								switch vs[k].expr {
									case EVars([v]): {expr: EVars([{name: v.name, type: v.type, expr: macro cast __h[$v{k}], isFinal: false}]), pos: vs[k].pos};
									case _: vs[k];
								}
						];
					case _: [];
				}
				cases.push({values: [macro $v{l.key}], expr: macro @:pos(l.pos) $b{decls.concat(code)}});
			}
			if (cases.length == 0) continue;
			var rt = runtime(path);
			var sw = {
				expr: ESwitch(macro __key, cases, macro if (prev != null) prev(__key, __h, __p, __b, __o) else throw "helder.view: no code for this markup (" + __key + ")"),
				pos: Context.currentPos()
			};
			// (named by its code: a module of that name, from hxmc's module cache
			// or made already when hxmc's custom target runs the callbacks again
			// with our statics anew, is this one)
			var name = "Late_" + mangle(path) + "_" + StringTools.hex(id(sig.toString()));
			if (Lambda.exists(types, t -> switch t {
				case TClassDecl(c): c.get().pack.join(".") == "helder.view" && c.get().name == name;
				case _: false;
			})) continue;
			try Context.defineType({
				pack: ["helder", "view"],
				name: name,
				pos: Context.currentPos(),
				meta: [{name: ":keep", pos: Context.currentPos()}, {name: ":noCompletion", pos: Context.currentPos()}],
				kind: TDClass(),
				fields: (macro class {
					static var prev:Null<(Int, Array<Any>, $n, Null<$n>, Null<Array<$n>>) -> Void>;

					static function __init__() {
						prev = $p{rt}.late;
						$p{rt}.late = mount;
					}

					static function mount(__key:Int, __h:Array<Any>, __p:$n, __b:Null<$n>, __o:Null<Array<$n>>):Void
						$sw;
				}).fields
			}) catch (e:haxe.macro.Expr.Error) if (!StringTools.startsWith(e.message, "Cannot redefine module")) throw e;
		}
	}
}

// (a field's copy for one renderer)
private class Subst {
	final node:ComplexType;
	final host:Array<String>;
	final self:String;
	final id:Int;
	final name:String;

	public function new(node, host, self, id, name) {
		this.node = node;
		this.host = host;
		this.self = self;
		this.id = id;
		this.name = name;
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
			case EConst(CIdent("INDEX")): macro @:pos(e.pos) $v{id};
			case EConst(CIdent("NAME")): macro @:pos(e.pos) $v{name};
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
