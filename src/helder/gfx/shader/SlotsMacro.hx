package helder.gfx.shader;

#if macro
import haxe.io.Bytes;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.definition.HaxeAdapter;
import helder.definition.Kernel;
import helder.gfx.shader.ShaderDefinition;

using haxe.macro.Tools;

// Slot objects in Haxe (Slots): slots(def) checks its argument and keeps
// it as it is (the CPU's object); with(overrides) notes the overrides
// (merged(base, id)); variant(options) finds the slots(...) call the object
// was made by (its module-level final's source, typed in its module's
// scope), applies the overrides on the way, runs the handler's variant
// (ShaderDefinition.variant, Lower its adapter) and builds the Shader
// (ShaderMacro.build) whose CPU stages call the object's stages with an
// object of the variant's slots and options.
class SlotsMacro {
	static final merges:Array<Expr> = [];
	static final sources = new Map<String, {node:KNode, scope:Scopes.Scope}>();

	public static function slots(def:Expr):Expr {
		var a = new HaxeAdapter("slots");
		SlotsDef.read(a.node(def), a);
		// (typed for its diagnostics; the CPU's stages are each variant's)
		Context.typeExpr(def);
		return macro new helder.gfx.shader.Slots();
	}

	public static function with(self:Expr, overrides:Expr):Expr {
		var id = merges.length;
		merges.push(overrides);
		return macro @:pos(Context.currentPos()) helder.gfx.shader.Slots.merged($self, $v{id});
	}

	public static function variant(self:Expr, options:Null<Expr>):Expr {
		var pos = Context.currentPos();
		var a = new HaxeAdapter("shader");
		var lower = new Lower();
		var r = resolve(Context.typeExpr(self), lower, a);
		var given = options == null || options.expr.match(EConst(CIdent("null"))) ? null : a.node(options);
		var out = new ShaderDefinition().variant(r.def, given, lower, pos);
		return build(r, r.def.values(given, a), out, lower);
	}

	// a variant's Shader, its CPU stages static functions of their own (hxmc
	// calls a function of struct values by its exact type, not through a
	// structure's field): the object's stages, typed in its module's scope
	// (a module of their own with its imports), m.options.<name> the
	// variant's values and m.<slot>(s, p) a call of the slot's function (a
	// default by its name; an override, from the caller's module, a static
	// of a module made with the caller's imports; one whose parameters are
	// not the stage's throws on the CPU: it runs on the GPU only)
	public static function build(r:Resolved, values:Map<String, KValue>, out:ShaderOutput, lower:Lower):Expr {
		var pos = Context.currentPos();
		var def = r.def;
		var vertexSource:Expr = def.vertex.source, fragmentSource:Expr = def.fragment.source;
		var vf = func(vertexSource), ff = func(fragmentSource);
		if (vf.args.length != 3 || ff.args.length != 3)
			Context.error("slots: the stages take their input, their parameters and the slot object (m.options, m.<slot>)", pos);
		var mt = typeOf(vf.args[2].type, r.scope, pos);
		var expected = switch mt.follow() {
			case TAnonymous(an): [for (f in an.get().fields) f.name => f.type];
			case t: Context.error('slots: the slot object\'s type is a structure of its options and slots, not ${t.toString()}', pos);
		}
		// the overrides written in the caller's module: statics of a module made with its imports
		var callerModule = Context.getLocalModule();
		var callerScope = Scopes.of(callerModule, Context.getPosInfos(pos).file);
		var overrides:Array<Field> = [];
		var calls = new Map<String, Expr>();
		var overridePack = callerModule.split(".");
		var overrideBase = overridePack.pop() + "_" + (Context.getLocalMethod() ?? "slots") + "_slots";
		var overridden = [];
		for (slot in def.slotOrder) {
			var node = def.slots.get(slot);
			var t = expected.get(slot);
			if (t == null) Context.error('slots: the slot object\'s type has no slot $slot', pos);
			if (r.defaults.get(slot) == node) {
				calls.set(slot, refExpr(node));
				continue;
			}
			switch node.value {
				case KFunction(k):
					var f = func(k.source);
					var g = Reflect.copy(f);
					g.args = [for (a in f.args) Reflect.copy(a)];
					switch t.follow() {
						case TFun(as, ret):
							if (g.args.length > 0 && g.args[0].type == null) g.args[0].type = as[0].t.toComplexType();
							if (g.ret == null) g.ret = ret.toComplexType();
						case _:
					}
					overrides.push({
						name: slot,
						access: [APublic, AStatic],
						kind: FFun(g),
						pos: (k.source : Expr).pos
					});
					overridden.push(slot);
				case _: calls.set(slot, refExpr(node));
			}
		}
		if (overrides.length > 0) {
			var cls:TypeDefinition = {
				pack: overridePack,
				name: overrideBase,
				pos: pos,
				kind: TDClass(),
				fields: overrides,
				meta: [{name: ":noCompletion", pos: pos}]
			};
			var name = overrideBase + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
			cls.name = name;
			define(overridePack.concat([name]).join("."), cls, callerScope);
			for (slot in overridden)
				calls.set(slot, macro $p{overridePack.concat([name, slot])});
		}
		// (a call of a slot whose parameters are not the stage's: the GPU's only)
		for (slot in def.slotOrder) {
			var t = expected.get(slot);
			var ct = t.toComplexType();
			var e = calls.get(slot);
			var ok = try {
				Context.typeExpr(macro($e : $ct));
				true;
			} catch (_:Dynamic) false;
			if (!ok) calls.set(slot, macro(function(s, p) return throw $v{'the slot $slot of this variant runs on the GPU only (its parameters are not the stage\'s)'} : $ct));
		}
		// the stages: the object's, the slot object read as constants and calls
		var pack = r.module.split(".");
		var base = pack.pop() + "_" + r.field + "_variant";
		function stage(f:Function, name:String):Field {
			var self = f.args[2].name;
			function map(e:Expr):Expr
				return switch e.expr {
					case EField({expr: EField({expr: EConst(CIdent(s))}, "options")}, o) if (s == self):
						switch values.get(o) {
							case KBool(b): macro @:pos(e.pos) $v{b};
							case KInt(i): macro @:pos(e.pos) $v{i};
							case KFloat(x): macro @:pos(e.pos) $v{x};
							case _: Context.error('slots: the slot object has no option $o', e.pos);
						}
					case ECall({expr: EField({expr: EConst(CIdent(s))}, slot)}, args) if (s == self):
						var c = calls.get(slot);
						if (c == null) Context.error('slots: the slot object has no slot $slot', e.pos);
						{expr: ECall(c, [for (a in args) map(a)]), pos: e.pos};
					case _: haxe.macro.ExprTools.map(e, map);
				}
			var g = Reflect.copy(f);
			g.args = [for (i in 0...2) Reflect.copy(f.args[i])];
			if (g.args[0].type == null) g.args[0].type = lower.haxeType(out.program.varyings).toComplexType();
			g.expr = map(f.expr);
			return {
				name: name,
				access: [APublic, AStatic],
				kind: FFun(g),
				pos: f.expr.pos
			};
		}
		var vfield = stage(vf, "vertex"), ffield = stage(ff, "fragment");
		var cls:TypeDefinition = {
			pack: pack,
			name: base,
			pos: pos,
			kind: TDClass(),
			fields: [vfield, ffield],
			meta: [{name: ":noCompletion", pos: pos}]
		};
		var name = base + "_" + haxe.crypto.Md5.encode(new haxe.macro.Printer().printTypeDefinition(cls)).substr(0, 8);
		cls.name = name;
		define(pack.concat([name]).join("."), cls, r.scope);
		var path = pack.concat([name]);
		function types(f:Function):{args:Array<ComplexType>, ret:ComplexType} {
			var ft = Context.typeof(macro $p{path.concat([f == vf ? "vertex" : "fragment"])});
			return switch ft.follow() {
				case TFun(as, ret): {args: [for (a in as) a.t.toComplexType()], ret: ret.toComplexType()};
				case _: throw "stage";
			}
		}
		var vt = types(vf), ft = types(ff);
		return ShaderMacro.build(out, lower, {
			vertex: macro $p{path.concat(["vertex"])},
			fragment: macro $p{path.concat(["fragment"])},
			vertexType: TFunction(vt.args, vt.ret),
			fragmentType: TFunction(ft.args, ft.ret)
		});
	}

	static function func(e:Expr):Function
		return switch e.expr {
			case EFunction(_, f): f;
			case _: Context.error("slots: a function", e.pos);
		}

	// a type written in a module's scope
	static function typeOf(ct:Null<ComplexType>, scope:Scopes.Scope, pos:Position):Type {
		if (ct == null) Context.error("slots: the stages' third parameter, the slot object, has its type written", pos);
		return Context.withImports(scope.imports, scope.usings, () -> Context.resolveType(ct, pos));
	}

	// a slot's function by its name (a module-level function: its typed reference)
	static function refExpr(node:KNode):Expr
		return switch node.value {
			case KRef(path): HaxeAdapter.refs.get(path).expr;
			case _: Context.error("slots: a slot's function", node.pos);
		}

	// a generated class in a module of its own, typed with a module's imports
	static function define(path:String, cls:TypeDefinition, scope:Scopes.Scope) {
		var exists = try Context.getType(path) != null catch (_:Dynamic) false;
		if (exists) return;
		var imports:Array<ImportExpr> = [];
		for (i in scope.imports) {
			var all = StringTools.endsWith(i, ".*");
			var parts = (all ? i.substr(0, i.length - 2) : i).split(" as ");
			var p = [for (n in StringTools.trim(parts[0]).split(".")) {name: n, pos: cls.pos}];
			imports.push({path: p, mode: all ? IAll : parts.length > 1 ? IAsName(StringTools.trim(parts[1])) : INormal});
		}
		var usings:Array<TypePath> = [
			for (u in scope.usings) {
				var ps = u.split(".");
				var n = ps.pop();
				{pack: ps, name: n};
			}
		];
		Context.defineModule(path, [cls], imports, usings);
	}

	// a slot object's expression: the slots(...) call it was made by (a
	// module-level final's), with(...)'s overrides applied
	public static function resolve(e:TypedExpr, lower:Lower, a:HaxeAdapter):Resolved {
		return switch e.expr {
			case TParenthesis(x) | TMeta(_, x) | TCast(x, null): resolve(x, lower, a);
			case TCall({expr: TField(_, FStatic(_, cf))}, [base, {expr: TConst(TInt(id))}]) if (cf.get().name == "merged"):
				var r = resolve(base, lower, a);
				{def: r.def.with(a.node(merges[id]), a), root: r.root, defaults: r.defaults, scope: r.scope, module: r.module, field: r.field};
			case TField(_, FStatic(c, cf)):
				var src = source(c.get(), cf.get(), a, e.pos);
				var def = SlotsDef.read(src.node, a);
				function scoped(n:KNode)
					switch n.value {
						case KFunction(k): lower.scopes.set(k.source, src.scope);
						case _:
					}
				lower.scopes.set(def.vertex.source, src.scope);
				lower.scopes.set(def.fragment.source, src.scope);
				for (s in def.slotOrder)
					scoped(def.slots.get(s));
				{def: def, root: e, defaults: def.slots, scope: src.scope, module: c.get().module, field: cf.get().name};
			case _: a.error("a slot object is a module-level final made by slots({...}) (or with(...) of one)", e.pos);
		}
	}

	// the argument of the slots(...) call a module-level final is made by, in its module's scope
	static function source(c:ClassType, cf:ClassField, a:HaxeAdapter, pos:Position):{node:KNode, scope:Scopes.Scope} {
		var key = c.module + "." + c.name + "." + cf.name;
		var cached = sources.get(key);
		if (cached != null) return cached;
		var info = Context.getPosInfos(cf.pos);
		var file = info.file;
		var bytes = Bytes.ofString(sys.io.File.getContent(file));
		var text = bytes.getString(info.min, bytes.length - info.min);
		var r = ~/\bslots\s*\(/;
		if (!r.match(text)) a.error('${cf.name} is not made by slots({...})', pos);
		var open = r.matchedPos().pos + r.matchedPos().len - 1;
		var close = matching(text, open);
		var at = info.min + Bytes.ofString(text.substr(0, open + 1)).length;
		var end = info.min + Bytes.ofString(text.substr(0, close)).length;
		var arg = Context.parseInlineString(bytes.getString(at, end - at), Context.makePosition({min: at, max: end, file: file}));
		var scope = Scopes.of(c.module, file);
		var node = Context.withImports(scope.imports, scope.usings, () -> a.node(arg));
		var out = {node: node, scope: scope};
		sources.set(key, out);
		return out;
	}

	// the index of the parenthesis closing the one at open (strings and comments skipped)
	static function matching(s:String, open:Int):Int {
		var depth = 0, i = open;
		while (i < s.length) {
			var c = s.charAt(i);
			if (c == "/" && s.charAt(i + 1) == "/") {
				i = s.indexOf("\n", i);
				if (i < 0) break;
				continue;
			}
			if (c == "/" && s.charAt(i + 1) == "*") {
				i = s.indexOf("*/", i) + 2;
				continue;
			}
			if (c == '"' || c == "'") {
				i++;
				while (i < s.length && s.charAt(i) != c) {
					if (s.charAt(i) == "\\") i++;
					i++;
				}
			} else if (c == "(" || c == "{" || c == "[") depth++;
			else if (c == ")" || c == "}" || c == "]") {
				depth--;
				if (depth == 0) return i;
			}
			i++;
		}
		return Context.error("slots: no end to slots(...)", Context.currentPos());
	}
}

typedef Resolved = {
	def:SlotsDef,
	// (the object the CPU's stages are: the slots(...) value)
	root:TypedExpr,
	// (the slots(...) call's own slots: a slot whose node is its default's is called by its name)
	defaults:Map<String, KNode>,
	// (the module the object is written in, its scope, its final's name)
	scope:Scopes.Scope,
	module:String,
	field:String
}
#end
