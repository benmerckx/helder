package helder.typescript.api;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.typescript.api.Modules;

using haxe.macro.TypeTools;

// The manifest of helder's API for TypeScript programs (DESIGN.md 7.3),
// made from the Haxe types while the build is typed: for each module (a
// declaration class, Modules: helder.view.TypeScript...), its classes'
// members and their types, and the contracts of the renderers it reaches
// (@:rendered nodes and ViewOf<R> in its types, those it names in
// @:typescript.renderers). The lowering reads it instead of glue written
// per call site (helder.typescript.lower.Api); Declarations writes the .d.ts
// files from the same types.
//
// The declaration class's build macro (`build`): the manifest is its
// metadata (@:helder.manifest, JSON), and its __init__ names every function
// the manifest lists, under a condition never true (the class @:keep, its
// __init__ with it under -dce full): hxmc lowers what code names, from main
// and the classes' __init__s, so each is in the program's IR for the
// TypeScript lowering to call; the frontend drops those __init__s after, and
// what the program does not call is left out of the executable. Nothing in
// it depends on the program: a module typed once is cached as any (hxmc's
// module cache, a compilation server's), and a build adds only the
// declaration classes the program's declaration files name (`__module`).
//
// The format (version 1), one per module, merged by the frontend:
//
//   {version, module, classes: {path: Class}, renderers: {path: Renderer}, neutralEvents: {name: Type}}
//   Class: {ident (hxmc's symbol prefix), type (its Haxe type path), params, rendered (R or null),
//     limits ({only: [R], other: {R: class path}} or null: @:renderer), interface,
//     statics: {name: Member}, members: {name: Member}, ctor: Type (a function's) or null}
//   Member: {kind: "method" | "var" | "const", type: Type, value (a const's), get, set (accessors' names, or null),
//     readonly, mount (true: Render.render's kind, @:typescript.mount), neutral (@:neutral)}
//   Renderer: {id, node (its nodes' class path), runtime (its ViewRuntime_ class path), runtimeFunctions,
//     elements ([tag] or null), events ({name: Type} or null), neutral, native, markEnds,
//     functions (its statics: name -> "function" | "macro" | "const"), setters ({names: {attribute: function path},
//     prefixes: {prefix: function path}, fallback: function path} or null)}
//   Type: "Int" | "Float" | "Bool" | "String" | "Void" | "Dynamic" | {null: Type} | {array: Type}
//     | {fn: [{name, opt, t}], ret: Type} | {anon: [{name, opt, t}]} | {class: path, params: [Type]}
//     | {read: Type} | {view: R} | {abstract: path, params, under: Type, values ([String], an enum abstract's)}
//     | {enum: path} | {param: name}
class Manifest {
	// (the metadata it is on its module's declaration class)
	public static inline final META = ":helder.manifest";

	// a module's declaration class's build macro: its manifest, its keep
	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var local = Context.getLocalClass();
		var api = new Api();
		var m = Modules.module(api, local.get());
		var classes:Dynamic = {};
		var keep:Array<Expr> = [];
		var t = new Types();
		for (c in api.classes)
			Reflect.setField(classes, c.path, describe(c, t, keep));
		var renderers:Dynamic = {};
		for (r in api.renderers(t.views.concat(m.renderers)))
			Reflect.setField(renderers, r, renderer(r, t, keep));
		// (what the TypeScript lowering builds itself: Views, its runtime's helpers)
		keep.push(macro keep.push(helder.view.View.new));
		keep.push(macro keep.push(helder.view.Render.pass));
		switch Context.getType("helder.typescript.js.Interop") {
			case TInst(c, _):
				for (f in c.get().statics.get())
					if (f.isPublic && f.kind.match(FMethod(MethNormal | MethInline)) && f.params.length == 0 && f.name != "keeping") {
						var n = f.name;
						keep.push(macro keep.push(helder.typescript.js.Interop.$n));
					}
			case _:
		}
		var json = haxe.Json.stringify({
			version: 1,
			module: m.name,
			classes: classes,
			renderers: renderers,
			neutralEvents: events(helder.view.MarkupMacro.NEUTRAL_EVENTS, t)
		});
		var pos = Context.currentPos();
		local.get().meta.add(META, [macro $v{json}], pos);
		local.get().meta.add(":keep", [], pos);
		fields = fields.concat((macro class {
			static function __init__()
				if (helder.typescript.js.Interop.keeping()) {
					var keep:Array<Dynamic> = [];
					$b{keep};
				}
		}).fields);
		return fields;
	}

	// a class's members, and the keep's expressions naming them
	static function describe(c:ApiClass, t:Types, keep:Array<Expr>):Dynamic {
		var cls = c.cls;
		var tpath = c.type.split(".");
		var statics:Dynamic = {}, members:Dynamic = {};
		for (f in c.statics) {
			var m = member(f, t);
			if (m == null) continue;
			Reflect.setField(statics, f.name, m);
			var n = f.name;
			if (m.kind != "const" && m.mount != true) keep.push(macro keep.push(@:privateAccess $p{tpath}.$n));
		}
		var self:ComplexType = TPath({
			pack: cls.pack,
			name: cls.module.split(".").pop(),
			sub: cls.module.split(".").pop() == cls.name ? null : cls.name,
			params: [for (_ in cls.params) TPType(macro :Dynamic)]
		});
		var any = false;
		for (f in c.members) {
			var m = member(f, t);
			if (m == null) continue;
			Reflect.setField(members, f.name, m);
			var n = f.name;
			if (m.kind == "method" || m.get != null) {
				keep.push(macro keep.push(@:privateAccess o.$n));
				any = true;
			}
			if (m.set != null) {
				keep.push(macro @:privateAccess o.$n = null);
				any = true;
			}
		}
		if (any) keep.unshift(macro var o:$self = null);
		var ctor:Dynamic = null;
		if (c.ctor != null) {
			ctor = t.of(c.ctor.type);
			keep.push(macro keep.push(@:privateAccess $p{tpath}.new));
		}
		var rendered = helder.view.HostMacro.rendered(TInst(c.ref, []));
		if (rendered != null) t.views.push(rendered);
		var limits = helder.view.MarkupMacro.limits(cls.meta);
		return {
			ident: cls.pack.concat([cls.name]).join("_"),
			type: c.type,
			params: [for (p in cls.params) p.name],
			rendered: rendered,
			limits: limits == null ? null : {
				only: limits.only,
				other: {
					var o:Dynamic = {};
					for (r => e in limits.other)
						Reflect.setField(o, r, helder.view.HostMacro.resolve(e));
					o;
				}
			},
			"interface": cls.isInterface,
			statics: statics,
			members: members,
			ctor: ctor
		};
	}

	// a field as the manifest lists it (null: one a program cannot reach, a macro)
	static function member(f:ClassField, t:Types):Dynamic {
		return switch f.kind {
			case FMethod(MethMacro): f.meta.has(":typescript.mount") ? {kind: "method", type: t.of(f.type), mount: true} : null;
			case FMethod(_) if (f.isExtern || f.overloads.get().length > 0): null;
			case FMethod(_): {kind: "method", type: t.of(f.type), neutral: f.meta.has(":neutral")};
			case FVar(AccInline, _):
				var v = constant(f);
				v == null ? null : {kind: "const", type: t.of(f.type), value: v};
			case FVar(read, write):
				{
					kind: "var",
					type: t.of(f.type),
					get: read == AccCall ? "get_" + f.name : null,
					set: write == AccCall ? "set_" + f.name : null,
					readonly: write == AccNever || write == AccNo || write == AccCtor
				};
		}
	}

	// an inline var's value (a number, a string, a Bool)
	static function constant(f:ClassField):Dynamic {
		var e = try f.expr() catch (_:Dynamic) null;
		while (e != null)
			switch e.expr {
				case TConst(TInt(i)): return i;
				case TConst(TFloat(s)): return Std.parseFloat(s);
				case TConst(TString(s)): return s;
				case TConst(TBool(b)): return b;
				case TCast(x, null) | TParenthesis(x) | TMeta(_, x): e = x;
				case _: return null;
			}
		return null;
	}

	// an @:events structure's fields by name (null: no such type)
	static function events(path:Null<String>, t:Types):Dynamic {
		if (path == null) return null;
		var o:Dynamic = {};
		switch Context.follow(Context.getType(path)) {
			case TAnonymous(a):
				for (f in a.get().fields)
					Reflect.setField(o, f.name, t.of(f.type));
			case _:
				return null;
		}
		return o;
	}

	// a renderer's contract, and the keep's expressions naming its functions and its runtime's
	static function renderer(path:String, t:Types, keep:Array<Expr>):Dynamic {
		var info = helder.view.HostMacro.reach(path);
		var rt = helder.view.HostMacro.runtime(path);
		var cls = switch Context.getType(path) {
			case TInst(c, _): c.get();
			case _: throw "unreachable";
		}
		var hpath = path.split(".");
		var functions:Dynamic = {};
		for (f in cls.statics.get())
			switch f.kind {
				case FMethod(MethMacro):
					Reflect.setField(functions, f.name, "macro");
				case FMethod(_) if (!f.isExtern):
					Reflect.setField(functions, f.name, "function");
					var n = f.name;
					keep.push(macro keep.push(@:privateAccess $p{hpath}.$n));
				case FVar(AccInline, _):
					Reflect.setField(functions, f.name, "const");
				case _:
			}
		var runtimeFunctions = [];
		switch Context.getType(rt.join(".")) {
			case TInst(c, _):
				for (f in c.get().statics.get())
					switch f.kind {
						case FMethod(MethNormal | MethInline) if (f.isPublic):
							runtimeFunctions.push(f.name);
							var n = f.name;
							keep.push(macro keep.push(@:privateAccess $p{rt}.$n));
						case FVar(_, _) if (f.name == "late"):
							keep.push(macro keep.push($p{rt}.late));
						case _:
					}
			case _:
		}
		var node = switch Context.follow(info.type) {
			case TInst(c, _): c.get().pack.concat([c.get().name]).join(".");
			case _: null;
		}
		var setters:Dynamic = null;
		if (Reflect.field(functions, "setter") == "macro") {
			var names:Dynamic = {}, prefixes:Dynamic = {};
			var listed = Reflect.field(functions, "setterNames") == "macro" ? strings(macro $p{hpath}.setterNames()) : [];
			function fn(name:String):Null<String> {
				var e = macro @:privateAccess $p{hpath}.setter($v{name});
				var typed = try Context.typeExpr(e) catch (_:Dynamic) return null;
				var found:Null<String> = null;
				function visit(x:TypedExpr)
					switch x.expr {
						case TField(_, FStatic(c, cf)) if (found == null):
							var k = c.get();
							found = k.module + (k.module.split(".").pop() == k.name ? "" : "." + k.name) + "." + cf.get().name;
						case _:
							haxe.macro.TypedExprTools.iter(x, visit);
					}
				visit(typed);
				if (found != null) {
					var p = found.split(".");
					keep.push(macro keep.push(@:privateAccess $p{p}));
				}
				return found;
			}
			for (n in listed)
				if (StringTools.endsWith(n, "*")) Reflect.setField(prefixes, n.substr(0, n.length - 1), fn(n.substr(0, n.length - 1) + "x"));
				else Reflect.setField(names, n, fn(n));
			setters = {names: names, prefixes: prefixes, fallback: fn("helder-typescript-none")};
		}
		return {
			id: info.id,
			node: node,
			runtime: rt.join("."),
			runtimeFunctions: runtimeFunctions,
			elements: info.elements,
			events: events(info.events, t),
			neutral: info.neutral,
			native: info.native,
			markEnds: info.markEnds,
			functions: functions,
			setters: setters
		};
	}

	// (a macro's array of strings)
	static function strings(e:Expr):Array<String> {
		var typed = try Context.typeExpr(e) catch (_:Dynamic) return [];
		return switch typed.expr {
			case TArrayDecl(items): [for (i in items) switch i.expr {
					case TConst(TString(s)): s;
					case _: continue;
				}];
			case _: [];
		}
	}
}

// Haxe types as the manifest writes them (Manifest's format); the renderers
// they reach (ViewOf<R>) noted
class Types {
	public final views:Array<String> = [];

	var depth = 0;

	public function new() {}

	public function of(t:Type):Dynamic {
		if (depth > 12) return "Dynamic";
		depth++;
		var r = type(t);
		depth--;
		return r;
	}

	function type(t:Type):Dynamic {
		var v = helder.view.HostMacro.viewOf(t);
		if (v != null) {
			if (views.indexOf(v) < 0) views.push(v);
			return {view: v};
		}
		return switch t {
			case TMono(r): r.get() == null ? "Dynamic" : of(r.get());
			case TLazy(f): of(f());
			case TType(_.get() => {pack: [], name: "Null"}, [p]): {"null": of(p)};
			case TType(d, ps): of(d.get().type.applyTypeParameters(d.get().params, ps));
			case TAbstract(_.get() => a, ps):
				switch [a.pack.join("."), a.name] {
					case ["", "Int"]: "Int";
					case ["", "Float"]: "Float";
					case ["", "Bool"]: "Bool";
					case ["", "Void"]: "Void";
					case ["", "Any"]: "Dynamic";
					case ["", "Null"]: {"null": of(ps[0])};
					case ["helder.view.graph", "Read"]: {read: of(ps[0])};
					case _ if (a.meta.has(":coreType")): "Dynamic";
					case _:
						{
							"abstract": a.pack.concat([a.name]).join("."),
							params: [for (p in ps) of(p)],
							under: of(a.type.applyTypeParameters(a.params, ps)),
							values: a.meta.has(":enum") ? enumValues(a) : null
						};
				}
			case TInst(_.get() => c, ps):
				switch c.kind {
					case KTypeParameter(_): {param: c.name};
					case _ if (c.pack.length == 0 && c.name == "String"): "String";
					case _ if (c.pack.length == 0 && c.name == "Array"): {array: of(ps[0])};
					case _:
						var r = helder.view.HostMacro.rendered(t);
						if (r != null && views.indexOf(r) < 0) views.push(r);
						{"class": Modules.typePath(c), params: [for (p in ps) of(p)]};
				}
			case TFun(args, ret): {fn: [for (a in args) {name: a.name, opt: a.opt, t: of(a.t)}], ret: of(ret)};
			case TAnonymous(a): {anon: [for (f in a.get().fields) {name: f.name, opt: f.meta.has(":optional"), t: of(f.type)}]};
			case TEnum(e, _): {"enum": e.get().pack.concat([e.get().name]).join(".")};
			case TDynamic(_): "Dynamic";
		}
	}

	// an enum abstract's values (its constants', strings)
	public static function enumValues(a:AbstractType):Null<Array<String>> {
		if (a.impl == null) return null;
		var out = [];
		for (f in a.impl.get().statics.get())
			if (f.meta.has(":enum") || f.meta.has(":value")) {
				var e = try f.expr() catch (_:Dynamic) null;
				while (e != null)
					switch e.expr {
						case TConst(TString(s)):
							out.push(s);
							e = null;
						case TCast(x, _) | TParenthesis(x) | TMeta(_, x): e = x;
						case _: e = null;
					}
			}
		return out;
	}
}
#end
