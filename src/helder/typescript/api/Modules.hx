package helder.typescript.api;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

// helder's TypeScript modules as Haxe declares them: a module is a class
// (its package's `TypeScript`) whose metadata names what it exports:
//
//   @:typescript("helder/view", "index.d.ts")          // the module, its declarations' file (beside the class)
//   @:typescript.classes(helder.view.Render, ...)        // classes: their public members (those marked
//                                                        // @:typescript when some are), @:noCompletion ones aside
//   @:typescript.functions(signal = helder.view.graph.Graph.signalValue, ...)
//                                                        // a class's static as a function of the module
//   @:typescript.types(helder.view.graph.Signal, ...)   // abstracts (interfaces, unions) and opaque classes
//   @:typescript.imports("helder/view")                  // modules whose types it names
//   @:typescript.jsx(neutral)                            // its part of JSX: the neutral elements (ui's events)
//   @:typescript.renderers(helder.web.StaticRenderer)    // renderers its markup reaches its types do not name
//   @:build(helder.typescript.api.Manifest.build())      // its manifest, made when it is typed
//
// A program's own Haxe classes are declared the same way (tests/view's
// TestTypeScript). The manifest (Manifest) and the declarations
// (Declarations) read them.
class Modules {
	// the modules their declaration classes declare
	public static function of(paths:Array<String>):Api {
		var api = new Api();
		for (p in paths) {
			var c = switch Context.getType(p) {
				case TInst(c, _): c.get();
				case _: Context.fatalError('helder.typescript: $p is not a class', Context.currentPos());
			}
			if (!c.meta.has(":typescript")) Context.fatalError('helder.typescript: $p declares no module (@:typescript)', c.pos);
			module(api, c);
		}
		return api;
	}

	// a module from its declaration class, its classes added to api
	public static function module(api:Api, c:ClassType):ApiModule {
		var m = c.meta.extract(":typescript")[0];
		var params = m.params == null ? [] : [for (e in m.params) string(e)];
		var mod = new ApiModule(params[0], params.length > 1 ? params[1] : "index.d.ts", typePath(c), haxe.io.Path.directory(Context.getPosInfos(c.pos).file));
		for (e in metaParams(c, ":typescript.classes")) {
			var path = haxe.macro.ExprTools.toString(e);
			mod.classes.push(api.add(path, Context.getType(path), null, mod));
		}
		for (e in metaParams(c, ":typescript.functions"))
			switch e.expr {
				case EBinop(OpAssign, {expr: EConst(CIdent(alias))}, target):
					var parts = haxe.macro.ExprTools.toString(target).split(".");
					var field = parts.pop(), path = parts.join(".");
					var cls = api.find(path);
					if (cls == null) cls = api.add(path, Context.getType(path), [], mod);
					if (cls.only != null && cls.only.indexOf(field) < 0) cls.only.push(field);
					if (mod.classes.indexOf(cls) < 0) mod.classes.push(cls);
					cls.refresh();
					mod.functions.push({alias: alias, cls: cls, field: field});
				case _:
					Context.error("helder.typescript: @:typescript.functions lists alias = pack.Class.member", e.pos);
			}
		for (e in metaParams(c, ":typescript.types"))
			mod.types.push(Context.getType(haxe.macro.ExprTools.toString(e)));
		for (e in metaParams(c, ":typescript.imports"))
			mod.imports.push(string(e));
		for (e in metaParams(c, ":typescript.jsx"))
			mod.jsx.push(haxe.macro.ExprTools.toString(e));
		for (e in metaParams(c, ":typescript.renderers"))
			mod.renderers.push(helder.view.HostMacro.resolve(e));
		api.modules.push(mod);
		return mod;
	}

	static function metaParams(c:ClassType, name:String):Array<Expr> {
		var out = [];
		for (m in c.meta.extract(name))
			if (m.params != null)
				for (p in m.params)
					out.push(p);
		return out;
	}

	static function string(e:Expr):String
		return switch e.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("helder.typescript: a string expected", e.pos);
		}

	// a class's Haxe type path (Module.Name when its module has another name)
	public static function typePath(c:ClassType):String {
		var last = c.module.split(".").pop();
		return last == c.name ? c.pack.concat([c.name]).join(".") : c.module + "." + c.name;
	}
}

// The classes a build's program reaches, and the modules declaring them.
class Api {
	public final classes:Array<ApiClass> = [];
	public final modules:Array<ApiModule> = [];

	public function new() {}

	public function find(path:String):Null<ApiClass> {
		for (c in classes)
			if (c.type == path) return c;
		return null;
	}

	// (only: the statics it declares, null: its public members)
	public function add(path:String, t:Type, only:Null<Array<String>>, module:Null<ApiModule>):ApiClass {
		var c = find(path);
		if (c != null) {
			if (only == null) c.only = null;
			c.refresh();
			return c;
		}
		var ref = switch t {
			case TInst(r, _): r;
			case _: Context.fatalError('helder.typescript: $path is not a class', Context.currentPos());
		}
		c = new ApiClass(path, ref, only, module);
		classes.push(c);
		return c;
	}

	// the renderers its classes reach: @:rendered classes among them, those
	// their types name (ViewOf<R>, a node of R), the ones given
	public function renderers(?more:Array<String>):Array<String> {
		var out:Array<String> = [];
		function add(r:Null<String>)
			if (r != null && r != helder.view.MarkupMacro.ROOT && out.indexOf(r) < 0) out.push(r);
		var t = new Manifest.Types();
		for (c in classes) {
			add(helder.view.HostMacro.rendered(TInst(c.ref, [])));
			for (f in c.statics.concat(c.members))
				t.of(f.type);
			if (c.ctor != null) t.of(c.ctor.type);
		}
		for (v in t.views)
			add(v);
		if (more != null)
			for (v in more)
				add(v);
		return out;
	}
}

class ApiModule {
	// its specifier ("helder/view"), its declarations' file name and directory, its declaration class
	public final name:String;
	public final file:String;
	public final decl:String;
	public final dir:String;
	public final classes:Array<ApiClass> = [];
	public final functions:Array<{alias:String, cls:ApiClass, field:String}> = [];
	public final types:Array<Type> = [];
	public final imports:Array<String> = [];
	public final jsx:Array<String> = [];
	public final renderers:Array<String> = [];

	public function new(name, file, decl, dir) {
		this.name = name;
		this.file = file;
		this.decl = decl;
		this.dir = dir;
	}
}

// A class of the API: the members a program can use
class ApiClass {
	// its class path (pack.Name), its Haxe type path (Module.Name when they differ)
	public final path:String;
	public final type:String;
	public final ref:Ref<ClassType>;
	public final module:Null<ApiModule>;
	public var cls(get, never):ClassType;
	public var only:Null<Array<String>>;
	public var statics:Array<ClassField> = [];
	public var members:Array<ClassField> = [];
	public var ctor:Null<ClassField> = null;

	public function new(type, ref, only, module) {
		this.type = type;
		this.ref = ref;
		this.only = only;
		this.module = module;
		var c = ref.get();
		path = c.pack.concat([c.name]).join(".");
		refresh();
	}

	function get_cls():ClassType
		return ref.get();

	// its members: the public ones (those marked @:typescript when some are,
	// @:noCompletion ones aside, in a module's class), or the statics listed
	public function refresh() {
		var c = ref.get();
		function pick(fields:Array<ClassField>):Array<ClassField> {
			if (only != null) return [for (f in fields) if (only.indexOf(f.name) >= 0) f];
			var pub = [for (f in fields) if (f.isPublic) f];
			if (module == null) return pub;
			var marked = [for (f in pub) if (f.meta.has(":typescript")) f];
			return marked.length > 0 ? marked : [for (f in pub) if (!f.meta.has(":noCompletion")) f];
		}
		var all = c.statics.get().concat(c.fields.get());
		var anyMarked = module != null && only == null && Lambda.exists(all, f -> f.isPublic && f.meta.has(":typescript"));
		statics = pick(c.statics.get());
		members = only != null ? [] : anyMarked ? [for (f in c.fields.get()) if (f.isPublic && f.meta.has(":typescript")) f] : pick(c.fields.get());
		if (anyMarked) statics = [for (f in c.statics.get()) if (f.isPublic && f.meta.has(":typescript")) f];
		ctor = only != null || c.constructor == null || !c.constructor.get().isPublic || c.isInterface
			|| (anyMarked && !c.constructor.get().meta.has(":typescript")) ? null : c.constructor.get();
	}
}
#end
