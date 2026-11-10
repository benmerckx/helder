package helder.gfx.shader;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.definition.Kernel;
import helder.gfx.shader.Ir;
import helder.gfx.shader.ShaderDefinition;

using haxe.macro.Tools;

// The shader definition's Haxe adapter (ShaderAdapter): a stage's function
// (shader({vertex, fragment})'s, as written) and the functions it calls,
// from Haxe's typed AST to the IR. Each is typed again without inlining
// (Context.withOptions), so that the math types' and ShaderMath's calls
// stay calls: a stage at the definition (in its caller's imports), any
// other function from its own source (Sources), in its module's imports.
// What a shader may contain: Float, Int and Bool, the math types, structs
// of those (@:structInit classes, typedefs of anonymous structures),
// Texture2D parameters (passed on, or read by sample); locals, assignments
// to them, if, while, for over an Int range, return, break and continue;
// calls to ShaderMath, the math types' operators and swizzles, a few of
// Math's functions, Std.int, and static or module-level functions, none
// recursive; position(v) around the clip-space position where the vertex
// stage's varyings are built. Anything else (allocation, closures,
// Dynamic, strings, arrays, fields of other types) is a compile error at
// its position. Expressions with statements inside (blocks, the operands
// Haxe stores in temporaries) put those statements before the statement
// that uses them: shader code has no side effects but assignments, so that
// order is safe.
class Lower implements ShaderAdapter {
	static final SHADER_PACK = "helder.gfx.shader";

	final structs = new Map<String, SStruct>();
	final building = new Map<String, Bool>();
	final functions = new Map<String, SFunction>();
	final active:Array<String> = [];
	final names = new Names();
	// each function's locals, renamed at the end if a global took their name
	final vars = new Map<SFunction, Array<SVar>>();
	// the vertex stage's result, for a fragment stage's first parameter given without a type
	var varyings:Null<Type>;
	var anonymous = 0;
	// each struct's Haxe type (the generated writers' parameters)
	final haxeTypes = new Map<SStruct, Type>();
	// locals holding a position(...) (Haxe's temporaries of a struct's fields)
	final positionLocals = new Map<Int, Bool>();
	// the stage's object of parameters (its fields are its parameters: p.frame)
	var paramsObject:Null<{id:Int, name:String, fields:Map<String, SVar>}>;
	// a slot object's variant (useSlots): its options and slots; the stage's
	// third parameter (the object: -1 none); the slots lowered; the loop
	// variables of unrolled loops (constants)
	var slots:Null<SlotsUse>;
	var slotsSelf = -1;
	// what is being lowered (a uniform's value is read in a stage)
	var kind = Plain;
	// the uniforms the stages read (uniform(...)'s values, ShaderMath.uniform):
	// one block of them, Uniforms, a field each in the order first read; the
	// constants' typed references (the CPU's writer reads them)
	public var uniformBlock(default, null):Null<SStruct>;
	public final uniformRefs:Array<{field:String, expr:Expr, type:ComplexType}> = [];
	final slotFunctions = new Map<String, SFunction>();
	final constants = new Map<Int, SExpr>();
	// the static finals of vectors and the like read (valueOf: null, not one)
	final values = new Map<String, Null<SExpr>>();
	// the module scopes a slot object's functions are typed in (its own module's imports: Scopes)
	public final scopes = new Map<Expr, Scopes.Scope>();

	// the function being lowered
	var fn:SFunction;
	var locals:Map<Int, SVar>;
	var localNames:Map<String, Bool>;
	var temps = 0;

	public function new() {}

	public function error(message:String, pos:KPos):Dynamic
		return Context.error("shader: " + message, pos);

	public function defined(name:String):Null<String>
		return Context.definedValue(name);

	public function finish() {
		names.unhide(vars);
		if (uniformBlock != null)
			haxeTypes.set(uniformBlock, haxe.macro.ComplexTypeTools.toType(TAnonymous([
				for (r in uniformRefs)
					{name: r.field, kind: FVar(r.type), pos: Context.currentPos()}
			])));
	}

	public function uniforms():Null<SStruct>
		return uniformBlock;

	public function useSlots(use:SlotsUse)
		slots = use;

	// an expression typed without inlining, in its scope (a slot object's
	// module's imports, else the definition's caller's)
	function typeIn(source:Expr, e:Expr):TypedExpr {
		var scope = scopes.get(source);
		function typed()
			return Context.withOptions({allowInlining: false}, () -> Context.typeExpr(e));
		return scope == null ? typed() : Context.withImports(scope.imports, scope.usings, typed);
	}

	public function haxeType(s:SStruct):Type
		return haxeTypes.get(s);

	// the stages' function types (vs, fs: as the CPU calls them)
	public final stageTypes = new Map<String, Type>();

	// --- functions ---

	public function lowerStage(k:KFunction, name:String):SFunction {
		var e:Expr = k.source;
		var f = switch e.expr {
			case EFunction(_, f): f;
			case _: throw "lowerStage";
		}
		// (the fragment stage's varyings, when not written: the vertex stage's result)
		if (varyings != null && f.args.length > 0 && f.args[0].type == null) {
			var ct = Context.toComplexType(varyings);
			f = Reflect.copy(f);
			f.args = [Reflect.copy(f.args[0])].concat(f.args.slice(1));
			f.args[0].type = ct;
		}
		var te = typeIn(e, {expr: EFunction(FAnonymous, f), pos: e.pos});
		var tf = switch strip(te).expr {
			case TFunction(tf): tf;
			case _: throw "lowerStage";
		}
		if (varyings == null) varyings = tf.t;
		stageTypes.set(name, te.t);
		return lower("<stage>." + name, name, tf, e.pos, Stage);
	}

	// a static or module-level function called by shader code
	function func(c:ClassType, cf:ClassField, pos:Position):SFunction {
		var key = path(c) + "." + cf.name;
		var f = functions.get(key);
		if (f != null) return f;
		if (active.contains(key))
			error("recursion: " + active.slice(active.indexOf(key)).concat([key]).join(" -> ") + " (shader functions cannot recurse)", pos);
		if (cf.params.length > 0) error('${cf.name}: a shader function has no type parameters', cf.pos);
		var te = Sources.typed(c, cf);
		if (te == null) error('${display(c, cf)} has no source a shader can compile (a static or module-level function written in Haxe)', pos);
		var tf = switch strip(te).expr {
			case TFunction(tf): tf;
			case _: error('${cf.name} is not a function', cf.pos);
		}
		return lower(key, cf.name, tf, cf.pos);
	}

	function lower(key:String, name:String, tf:TFunc, pos:Position, kind = Plain):SFunction {
		active.push(key);
		var saved = {fn: fn, locals: locals, names: localNames, object: paramsObject, self: slotsSelf, kind: this.kind};
		this.kind = kind;
		locals = new Map();
		localNames = new Map();
		paramsObject = null;
		slotsSelf = -1;
		var vs = [];
		var params = [], fields = [];
		var stage = kind != Plain;
		var count = tf.args.length;
		// (a slot object's stage: its third parameter the object, m.options.x and m.color(s, p))
		if (kind == Stage && slots != null && count == 3) {
			slotsSelf = tf.args[2].v.id;
			count = 2;
		}
		if (stage && count > 2)
			error('a ${kind == Slot ? "slot" : "stage"} takes its input and one object of parameters ({frame: Frame, image: Texture2D}), not ${count - 1}', pos);
		for (i in 0...count) {
			var v = tf.args[i].v;
			if (!stage || i == 0) {
				params.push(declare(v, pos, vs));
				continue;
			}
			// (a stage's object of parameters: its fields the parameters, in order)
			var a = anonOf(v.t);
			if (a == null) error('${v.name}: a stage\'s parameters are an object of uniform blocks and textures ({frame: Frame, image: Texture2D}), not a ${v.t.toString()}', pos);
			paramsObject = {id: v.id, name: v.name, fields: new Map()};
			for (f in sortedFields(a)) {
				var optional = f.meta.has(":optional");
				var s = declareNamed(f.name, type(optional ? unNull(f.type) : f.type, f.pos), f.pos, vs, true);
				s.optional = optional;
				paramsObject.fields.set(f.name, s);
				params.push(s);
				fields.push(f.name);
			}
		}
		var f = new SFunction(names.global(name), params, type(tf.t, pos));
		f.fields = fields;
		if (f.ret == TTexture) error('$name: a texture is not a result (pass the parameter on)', pos);
		fn = f;
		vars.set(f, vs);
		var body = [];
		stmt(tf.expr, body);
		f.body = body;
		fn = saved.fn;
		locals = saved.locals;
		localNames = saved.names;
		paramsObject = saved.object;
		slotsSelf = saved.self;
		this.kind = saved.kind;
		active.pop();
		functions.set(key, f);
		return f;
	}

	function declare(v:TVar, pos:Position, ?list:Array<SVar>):SVar {
		var s = declareNamed(v.name, type(v.t, pos), pos, list ?? vars.get(fn), list != null);
		locals.set(v.id, s);
		return s;
	}

	function declareNamed(name:String, t:SType, pos:Position, list:Array<SVar>, param:Bool):SVar {
		if (t == TVoid) error('$name has no value', pos);
		// (a texture: a parameter, its sampler <name>_smp next to it where the language has one)
		if (t == TTexture && !param) error('$name: a texture is a parameter, not a local', pos);
		var s = new SVar(Names.unique(Names.sanitize(name), n -> !localNames.exists(n) && (t != TTexture || !localNames.exists(n + "_smp"))), t);
		localNames.set(s.name, true);
		if (t == TTexture) localNames.set(s.name + "_smp", true);
		list.push(s);
		return s;
	}

	// (an optional field's type: T of Null<T>)
	static function unNull(t:Type):Type
		return switch t {
			case TAbstract(a, [u]) if (a.get().name == "Null" && a.get().pack.length == 0): u;
			case TType(td, []) if (td.get().name == "Null"): unNull(td.get().type);
			case _: t;
		}

	// (an anonymous structure's fields, through typedefs)
	static function anonOf(t:Type):Null<AnonType>
		return switch t {
			case TType(td, []): anonOf(td.get().type);
			case TMono(r) if (r.get() != null): anonOf(r.get());
			case TLazy(f): anonOf(f());
			case TAnonymous(a): a.get();
			case _: null;
		}

	function temp(t:SType):SVar {
		var s = new SVar(Names.unique("t" + temps++, n -> !localNames.exists(n)), t);
		localNames.set(s.name, true);
		vars.get(fn).push(s);
		return s;
	}

	// --- types ---

	function type(t:Type, pos:Position):SType {
		// (a typedef of an anonymous structure: a struct of its name)
		var named = namedStruct(t, pos);
		if (named != null) {
			if (!haxeTypes.exists(named)) haxeTypes.set(named, t);
			return TStruct(named);
		}
		return switch t.follow() {
			case TAbstract(a, params):
				var a = a.get();
				switch [a.pack.join("."), a.name] {
					case ["", "Float"]: TFloat;
					case ["", "Int"]: TInt;
					case ["", "Bool"]: TBool;
					case ["", "Void"]: TVoid;
					case [SHADER_PACK, "Vec2"]: TVec(2);
					case [SHADER_PACK, "Vec3"]: TVec(3);
					case [SHADER_PACK, "Vec4"]: TVec(4);
					case [SHADER_PACK, "Mat4"]: TMat4;
					case ["", "Null"]: error('${t.toString()}: a nullable type is not a shader type', pos);
					case _: error('${t.toString()} is not a shader type (Float, Int, Bool, Vec2, Vec3, Vec4, Mat4 and structs of them)', pos);
				}
			case TInst(_.get() => {pack: [], name: "Array"}, [_]):
				error('${t.toString()}: an array is a uniform block\'s field (@:length(8) var lights:Array<Vec4>), read by index there', pos);
			case TInst(c, []):
				// (the math types' representations, as `this` of their methods)
				var c = c.get();
				switch [c.pack.join("."), c.name] {
					case [SHADER_PACK, "Vec2Data"]: TVec(2);
					case [SHADER_PACK, "Vec3Data"]: TVec(3);
					case [SHADER_PACK, "Vec4Data"]: TVec(4);
					case [SHADER_PACK, "Mat4Data"]: TMat4;
					case [SHADER_PACK, "Texture2D"]: TTexture;
					case _:
						var s = struct(c, pos);
						if (!haxeTypes.exists(s)) haxeTypes.set(s, t.follow());
						TStruct(s);
				}
			case TAnonymous(a):
				// (an anonymous structure written out: a struct named after where it is first met)
				var a = a.get();
				var s = anonStruct(shape(a), "S" + anonymous, a, pos);
				if (!haxeTypes.exists(s)) haxeTypes.set(s, t.follow());
				TStruct(s);
			case TDynamic(_): error('Dynamic is not a shader type', pos);
			case _: error('${t.toString()} is not a shader type (Float, Int, Bool, Vec2, Vec3, Vec4, Mat4 and structs of them)', pos);
		}
	}

	function namedStruct(t:Type, pos:Position):Null<SStruct>
		return switch t {
			case TType(td, []):
				var d = td.get();
				switch d.type {
					case TAnonymous(a): anonStruct(d.pack.concat([d.name]).join("."), d.name, a.get(), pos);
					case u: namedStruct(u, pos);
				}
			case TMono(r) if (r.get() != null): namedStruct(r.get(), pos);
			case TLazy(f): namedStruct(f(), pos);
			case _: null;
		}

	static function sortedFields(a:AnonType):Array<ClassField> {
		var fs = a.fields.copy();
		fs.sort((x, y) -> Context.getPosInfos(x.pos).min - Context.getPosInfos(y.pos).min);
		return fs;
	}

	function struct(c:ClassType, pos:Position):SStruct {
		var key = path(c);
		var s = structs.get(key);
		if (s != null) return s;
		if (c.isExtern || c.isInterface || c.superClass != null || c.params.length > 0 || !c.meta.has(":structInit"))
			error('$key is not a shader type (a struct is a @:structInit class or a typedef of an anonymous structure, of Float, Int, Bool, vectors, matrices and structs, without a superclass)',
				pos);
		return fields(key, c.name, [
			for (f in c.fields.get())
				switch f.kind {
					case FVar(AccNormal | AccNo, AccNormal | AccNo | AccNever | AccCtor): f;
					case FVar(_, _): error('$key.${f.name}: a property is not a struct field', f.pos);
					case FMethod(_): continue;
				}
		], c.pos);
	}

	// (an anonymous structure's fields: a literal of a typedef's has the typedef's struct)
	static function shape(a:AnonType):String {
		var fs = [for (f in a.fields) f.name + ":" + f.type.toString()];
		fs.sort(Reflect.compare);
		return "{" + fs.join(",") + "}";
	}

	function anonStruct(key:String, name:String, a:AnonType, pos:Position):SStruct {
		var s = structs.get(key) ?? structs.get(shape(a));
		if (s != null) return s;
		if (name == "S" + anonymous) anonymous++;
		s = fields(key, name, [
			for (f in sortedFields(a))
				switch f.kind {
					case FVar(_, _): f;
					case FMethod(_): error('$key.${f.name}: a method is not a struct field', f.pos);
				}
		], pos);
		structs.set(shape(a), s);
		return s;
	}

	function fields(key:String, name:String, cfs:Array<ClassField>, pos:Position):SStruct {
		if (building.exists(key)) error('$key contains itself', pos);
		building.set(key, true);
		var fields:Array<SField> = [];
		for (f in cfs) {
			var optional = f.meta.has(":optional");
			fields.push({
				name: Names.unique(Names.sanitize(f.name), n -> !Lambda.exists(fields, g -> g.name == n)),
				field: f.name,
				type: fieldType(key, f, optional ? unNull(f.type) : f.type),
				position: false,
				optional: optional
			});
			if (fields[fields.length - 1].type == TTexture) error('$key.${f.name}: a texture is not a struct field (it is a parameter)', f.pos);
		}
		if (fields.length == 0) error('$key has no fields', pos);
		building.remove(key);
		var s = new SStruct(names.global(name), key, fields);
		structs.set(key, s);
		return s;
	}

	// a field's type: an Array<Vec4> or Array<Mat4> of @:length(n) an array
	function fieldType(key:String, f:ClassField, t:Type):SType {
		var element = switch t.follow() {
			case TInst(_.get() => {pack: [], name: "Array"}, [e]): e;
			case _: return type(t, f.pos);
		}
		var m = f.meta.extract(":length");
		var n = m.length == 1 && m[0].params.length == 1 ? switch m[0].params[0].expr {
			case EConst(CInt(s)): Std.parseInt(s);
			case _: 0;
		} : 0;
		if (n < 1) error('$key.${f.name}: an array field has a length, @:length(n) (a literal above 0)', f.pos);
		var e = type(element, f.pos);
		if (e != TMat4 && !e.match(TVec(4))) error('$key.${f.name}: an array is of Vec4 or Mat4 (std140 pads the others to 16 bytes: pack them in Vec4s)', f.pos);
		return TArray(e, n);
	}

	// a struct's value from its fields' (position(x): that field is the clip-space position)
	function build(s:SStruct, args:Array<Null<TypedExpr>>, out:Array<SStmt>):SExpr {
		var xs = [];
		for (i in 0...args.length) {
			// (an optional field left out: zero)
			if (args[i] == null) {
				xs.push(Names.zero(s.fields[i].type));
				continue;
			}
			var x = args[i], p = positionArg(x);
			if (p != null) {
				s.fields[i].position = true;
				x = p;
			} else switch strip(x).expr {
				case TLocal(v) if (positionLocals.exists(v.id)): s.fields[i].position = true;
				case _:
			}
			xs.push(coerce(expr(x, out), s.fields[i].type, x.pos));
		}
		return {e: ENew(xs), t: TStruct(s)};
	}

	// position(x)'s x
	static function positionArg(e:TypedExpr):Null<TypedExpr>
		return switch e.expr {
			case TParenthesis(x) | TMeta(_, x) | TCast(x, null): positionArg(x);
			case TCall({expr: TField(_, FStatic(c, cf))}, [x]) if (cf.get().name == "position" && path(c.get()) == SHADER_PACK + ".ShaderMath"): x;
			case _: null;
		}

	static function strip(e:TypedExpr):TypedExpr
		return switch e.expr {
			case TParenthesis(x) | TMeta(_, x): strip(x);
			case _: e;
		}

	static function display(c:ClassType, cf:ClassField):String
		return StringTools.endsWith(c.name, "_Fields_") ? c.module + "." + cf.name : path(c) + "." + cf.name;

	// --- statements ---

	function block(e:TypedExpr):Array<SStmt> {
		var out = [];
		stmt(e, out);
		return out;
	}

	function stmt(e:TypedExpr, out:Array<SStmt>) {
		switch e.expr {
			case TBlock(el):
				var i = 0;
				while (i < el.length) {
					// (a variant's loop over constants, as Haxe's typer writes a for over a...b: unrolled)
					if (slots != null && i + 2 < el.length && unrolled(el[i], el[i + 1], el[i + 2], out)) {
						i += 3;
						continue;
					}
					stmt(el[i], out);
					i++;
				}
			case TMeta(_, x) | TParenthesis(x):
				stmt(x, out);
			case TVar(v, {expr: TUnop(op = OpIncrement | OpDecrement, true, {expr: TLocal(i)})}) if (locals.exists(i.id)):
				// var v = i++ (Haxe's for loops): no temporary
				var s = declare(v, e.pos), i = target({expr: TLocal(i), t: v.t, pos: e.pos});
				out.push(SDecl(s, local(i)));
				out.push(SAssign(i, op == OpIncrement ? Add : Sub, one(i.type)));
			case TVar(v, init):
				// (a typedef's struct first, as written: named after it, not after its value's literal)
				namedStruct(v.t, e.pos);
				var p = init == null ? null : positionArg(init);
				if (p != null) {
					positionLocals.set(v.id, true);
					init = p;
				}
				var x = init == null ? null : expr(init, out);
				var s = declare(v, e.pos);
				out.push(SDecl(s, x == null ? null : coerce(x, s.type, init.pos)));
			case TIf(c, a, b):
				var x = coerce(expr(c, out), TBool, c.pos);
				// (a variant's test of a constant: the branch it takes alone)
				switch x.e {
					case EBool(k) if (slots != null):
						if (k) stmt(a, out) else if (b != null) stmt(b, out);
					case _:
						out.push(SIf(x, block(a), b == null ? null : block(b)));
				}
			case TWhile(c, body, true):
				var pre = [];
				var x = coerce(expr(c, pre), TBool, c.pos);
				if (pre.length == 0) out.push(SWhile(x, block(body))) else
					out.push(SWhile({e: EBool(true), t: TBool}, pre.concat([SIf(not(x), [SBreak], null)]).concat(block(body))));
			case TWhile(_, _, false):
				error("do-while is not supported in a shader (use while)", e.pos);
			case TFor(v, it, body):
				switch it.expr {
					case TBinop(OpInterval, a, b) if (slots != null && constantRange(a, b) != null):
						// (a variant's loop over constants: unrolled, its variable a constant in each copy)
						var r = constantRange(a, b);
						if (breaks(body)) error("a loop a variant unrolls has no break or continue", e.pos);
						for (k in r.from...r.to) {
							constants.set(v.id, {e: EInt(k), t: TInt});
							stmt(body, out);
						}
						constants.remove(v.id);
					case TBinop(OpInterval, a, b):
						// var i = a, end = b; while (i < end) { var v = i; i++; body }
						var i = temp(TInt), end = temp(TInt);
						out.push(SDecl(i, coerce(expr(a, out), TInt, a.pos)));
						out.push(SDecl(end, coerce(expr(b, out), TInt, b.pos)));
						i.assigned = true;
						var s = declare(v, e.pos);
						var inner = [SDecl(s, local(i)), SAssign(i, Add, {e: EInt(1), t: TInt})];
						stmt(body, inner);
						out.push(SWhile({e: EBinop(Lt, local(i), local(end)), t: TBool}, inner));
					case _: error("for loops in a shader run over an Int range (a...b)", it.pos);
				}
			case TReturn(x):
				out.push(SReturn(x == null ? null : coerce(expr(x, out), fn.ret, x.pos)));
			case TBreak:
				out.push(SBreak);
			case TContinue:
				out.push(SContinue);
			case TBinop(OpAssign | OpAssignOp(_), _, _):
				assign(e, out);
			case TUnop(op = OpIncrement | OpDecrement, _, x):
				var v = target(x);
				out.push(SAssign(v, op == OpIncrement ? Add : Sub, one(v.type)));
			case _:
				var x = expr(e, out);
				switch x.e {
					case ECall(_) | EBuiltin("discard", _):
						out.push(SEval(x));
					case _:
				}
		}
	}

	function assign(e:TypedExpr, out:Array<SStmt>):SVar {
		return switch e.expr {
			case TBinop(OpAssign, l, r):
				var v = target(l);
				out.push(SAssign(v, null, coerce(expr(r, out), v.type, r.pos)));
				v;
			case TBinop(OpAssignOp(op), l, r):
				var v = target(l);
				var o = binop(op, e.pos);
				if (o == Mod && v.type == TFloat) error("% on Float is not supported in a shader", e.pos);
				out.push(SAssign(v, o, coerce(expr(r, out), v.type == TFloat ? TFloat : v.type, r.pos)));
				v;
			case _: throw "assign";
		}
	}

	// a local as the target of an assignment
	function target(e:TypedExpr):SVar {
		return switch e.expr {
			case TLocal(v):
				var s = locals.get(v.id);
				if (s == null) error('${v.name} is not a local of this function', e.pos);
				if (s.type == TTexture) error('${v.name}: a texture parameter is not assigned', e.pos);
				s.assigned = true;
				s;
			case TParenthesis(x) | TMeta(_, x): target(x);
			case TField(_, _): error("shader values are immutable: assign to a local, not to a field", e.pos);
			case _: error("shader code assigns to locals only", e.pos);
		}
	}

	// --- expressions ---

	function expr(e:TypedExpr, out:Array<SStmt>):SExpr {
		return switch e.expr {
			case TConst(TInt(i)): {e: EInt(i), t: TInt};
			case TConst(TFloat(s)):
				var f = Std.parseFloat(s);
				if (!Math.isFinite(f)) error('$s is not a finite number', e.pos);
				{e: EFloat(f), t: TFloat};
			case TConst(TBool(b)): {e: EBool(b), t: TBool};
			case TConst(TString(_)): error("a String is not a shader value", e.pos);
			case TConst(TNull): error("null is not a shader value", e.pos);
			case TConst(TThis | TSuper): error("a shader function is static: no this", e.pos);
			case TLocal(v) if (constants.exists(v.id)): constants.get(v.id);
			case TLocal(v) if (v.id == slotsSelf):
				error('${v.name}, the slot object, is read as ${v.name}.options.<name> and called as ${v.name}.<slot>(s, p): it is no shader value', e.pos);
			case TLocal(v):
				if (paramsObject != null && v.id == paramsObject.id)
					error('${v.name}, the stage\'s parameters, is read by its fields (${v.name}.name): it is no shader value', e.pos);
				var s = locals.get(v.id);
				if (s == null) error('${v.name} is not a local of this function (a closure?)', e.pos);
				local(s);
			case TParenthesis(x) | TMeta(_, x): expr(x, out);
			case TCast(x, null): coerce(expr(x, out), type(e.t, e.pos), e.pos);
			case TCast(_, _): error("a checked cast is not supported in a shader", e.pos);
			case TBlock([]): error("an empty block has no value", e.pos);
			// (a commutative operator with its operands swapped, 2 * v: Haxe keeps them
			// in temporaries for their order, which shader code has no need of)
			case TBlock([{expr: TVar(a, ea)}, {expr: TVar(b, eb)}, {expr: TCall(f, [{expr: TLocal(x)}, {expr: TLocal(y)}])}])
				if (a.name == "lhs" && b.name == "rhs" && x.id == b.id && y.id == a.id && ea != null && eb != null):
				call(f, [eb, ea], e, out);
			case TBlock(el):
				for (i in 0...el.length - 1)
					stmt(el[i], out);
				expr(el[el.length - 1], out);
			case TVar(_, _) | TWhile(_, _, _) | TFor(_, _, _) | TReturn(_) | TBreak | TContinue:
				error("a statement where a value is needed", e.pos);
			case TBinop(OpAssign | OpAssignOp(_), _, _): local(assign(e, out));
			case TBinop(op, a, b): binary(op, a, b, e, out);
			case TUnop(OpNeg, false, x):
				var v = expr(x, out);
				if (v.t != TFloat && v.t != TInt) error('-: a ${Names.typeName(v.t)}', e.pos);
				{e: EUnop(Neg, v), t: v.t};
			case TUnop(OpNot, false, x):
				var v = coerce(expr(x, out), TBool, x.pos);
				switch v.e {
					case EBool(k) if (slots != null): {e: EBool(!k), t: TBool};
					case _: {e: EUnop(Not, v), t: TBool};
				}
			case TUnop(OpNegBits, false, x): {e: EUnop(BitNot, coerce(expr(x, out), TInt, x.pos)), t: TInt};
			case TUnop(op = OpIncrement | OpDecrement, postfix, x):
				// the value before (x++) or after (++x)
				var v = target(x);
				var before = postfix ? temp(v.type) : null;
				if (postfix) out.push(SDecl(before, local(v)));
				out.push(SAssign(v, op == OpIncrement ? Add : Sub, one(v.type)));
				local(postfix ? before : v);
			case TUnop(_, _, _): error("not supported in a shader", e.pos);
			case TIf(c, a, b) if (b != null):
				var t = type(e.t, e.pos);
				if (t == TTexture) error("a texture is chosen by no condition (pass the parameter on)", e.pos);
				var cond = coerce(expr(c, out), TBool, c.pos);
				// (a variant's choice by a constant: the branch it takes alone)
				switch cond.e {
					case EBool(k) if (slots != null): return coerce(expr(k ? a : b, out), t, e.pos);
					case _:
				}
				var pa = [], pb = [];
				var x = coerce(expr(a, pa), t, a.pos), y = coerce(expr(b, pb), t, b.pos);
				if (pa.length == 0 && pb.length == 0) {e: ECond(cond, x, y), t: t} else {
					var tmp = temp(t);
					tmp.assigned = true;
					out.push(SDecl(tmp, null));
					out.push(SIf(cond, pa.concat([SAssign(tmp, null, x)]), pb.concat([SAssign(tmp, null, y)])));
					local(tmp);
				}
			case TCall(f, args): call(f, args, e, out);
			case TNew(c, _, args):
				var t = type(e.t, e.pos);
				var s = switch t {
					case TStruct(s): s;
					case _: error('new ${c.get().name}: allocation is not supported in a shader', e.pos);
				}
				if (args.length != s.fields.length)
					error('new ${s.path}: a shader struct is built by its @:structInit constructor, all fields given', e.pos);
				build(s, args, out);
			// (Uniform<T>, @:generic: Uniform_<T's path>)
			case TField(x, FInstance(c, _, cf)) if (cf.get().name == "value" && c.get().pack.join(".") == SHADER_PACK
				&& (c.get().name == "Uniform" || StringTools.startsWith(c.get().name, "Uniform_"))):
				uniformRead(x, e);
			case TField(x, FInstance(c, _, cf)): field(x, c.get(), cf.get(), e, out);
			case TField(x, FAnon(cf)):
				switch strip(x).expr {
					case TLocal(v) if (paramsObject != null && v.id == paramsObject.id): local(paramsObject.fields.get(cf.get().name));
					case TField({expr: TLocal(v)}, FAnon(o)) if (v.id == slotsSelf && o.get().name == "options"): option(cf.get().name, e);
					case TLocal(v) if (v.id == slotsSelf): error('${v.name}.${cf.get().name}: the slot object is read as ${v.name}.options.<name> and called as ${v.name}.<slot>(s, p)', e.pos);
					case _: field(x, null, cf.get(), e, out);
				}
			case TField(_, FStatic(c, cf)): constant(c.get(), cf.get(), e);
			case TField(_, _): error("this field access is not supported in a shader", e.pos);
			case TObjectDecl(fs):
				// (a struct of a typedef: its fields by name, in the struct's order)
				var s = switch type(e.t, e.pos) {
					case TStruct(s): s;
					case _: error("an anonymous object is not a shader value (a struct is)", e.pos);
				}
				var args:Array<Null<TypedExpr>> = [
					for (f in s.fields) {
						var given = Lambda.find(fs, x -> x.name == f.field);
						if (given == null && !f.optional) error('${s.path}: the field ${f.field} is not given', e.pos);
						given == null ? null : given.expr;
					}
				];
				if (fs.length != args.filter(x -> x != null).length) error('${s.path} is built with all its fields, no others', e.pos);
				build(s, args, out);
			case TArray(a, i):
				var o = expr(a, out), k = coerce(expr(i, out), TInt, i.pos);
				switch [o.t, k.e] {
					case [TArray(_, n), EInt(j)] if (j < 0 || j >= n): error('$j is outside the array (0 to ${n - 1})', i.pos);
					case [TArray(t, _), _]: {e: EIndex(o, k), t: t};
					case _: error('a ${Names.typeName(o.t)} is not indexed in a shader', e.pos);
				}
			case TArrayDecl(_): error("arrays are not supported in a shader but as a uniform block's field (@:length(n) var lights:Array<Vec4>)", e.pos);
			case TFunction(_): error("a closure is not supported in a shader", e.pos);
			case TSwitch(_, _, _): error("switch is not supported in a shader (yet)", e.pos);
			case TTry(_, _) | TThrow(_): error("exceptions are not supported in a shader", e.pos);
			case TTypeExpr(_): error("a type is not a shader value", e.pos);
			case _: error("not supported in a shader", e.pos);
		}
	}

	function binary(op:Binop, a:TypedExpr, b:TypedExpr, e:TypedExpr, out:Array<SStmt>):SExpr {
		var r = binaryOf(op, a, b, e, out);
		return slots != null ? Fold.expr(r) : r;
	}

	function binaryOf(op:Binop, a:TypedExpr, b:TypedExpr, e:TypedExpr, out:Array<SStmt>):SExpr {
		var t = type(e.t, e.pos);
		var x = expr(a, out), y = expr(b, out);
		return switch op {
			case OpAdd | OpSub | OpMult | OpDiv | OpMod:
				if (t != TFloat && t != TInt) error('${Names.typeName(x.t)} ${op} ${Names.typeName(y.t)} is not a shader operation', e.pos);
				if (op == OpMod && t == TFloat) error("% on Float is not supported in a shader", e.pos);
				{e: EBinop(binop(op, e.pos), coerce(x, t, a.pos), coerce(y, t, b.pos)), t: t};
			case OpEq | OpNotEq | OpLt | OpLte | OpGt | OpGte:
				var w = x.t == TFloat || y.t == TFloat ? TFloat : x.t;
				if (!(w == TFloat || w == TInt || (w == TBool && (op == OpEq || op == OpNotEq))))
					error('${Names.typeName(x.t)} and ${Names.typeName(y.t)} cannot be compared in a shader', e.pos);
				{e: EBinop(binop(op, e.pos), coerce(x, w, a.pos), coerce(y, w, b.pos)), t: TBool};
			case OpBoolAnd | OpBoolOr:
				{e: EBinop(op == OpBoolAnd ? And : Or, coerce(x, TBool, a.pos), coerce(y, TBool, b.pos)), t: TBool};
			case OpAnd | OpOr | OpXor | OpShl | OpShr:
				{e: EBinop(binop(op, e.pos), coerce(x, TInt, a.pos), coerce(y, TInt, b.pos)), t: TInt};
			case _: error('$op is not supported in a shader', e.pos);
		}
	}

	function binop(op:Binop, pos:Position):SBinop
		return switch op {
			case OpAdd: Add;
			case OpSub: Sub;
			case OpMult: Mul;
			case OpDiv: Div;
			case OpMod: Mod;
			case OpEq: Eq;
			case OpNotEq: Ne;
			case OpLt: Lt;
			case OpLte: Le;
			case OpGt: Gt;
			case OpGte: Ge;
			case OpAnd: BitAnd;
			case OpOr: BitOr;
			case OpXor: BitXor;
			case OpShl: Shl;
			case OpShr: Shr;
			case _: error('$op is not supported in a shader', pos);
		}

	function field(x:TypedExpr, c:ClassType, cf:ClassField, e:TypedExpr, out:Array<SStmt>):SExpr {
		var o = expr(x, out);
		return switch o.t {
			case TVec(_): {e: ESwizzle(o, cf.name), t: type(e.t, e.pos)};
			case TMat4: {e: EColumn(o, Std.parseInt(cf.name.substr(1))), t: type(e.t, e.pos)};
			case TStruct(s):
				var f = Lambda.find(s.fields, f -> f.field == cf.name);
				if (f == null) error('${s.path} has no field ${cf.name}', e.pos);
				{e: EField(o, f.name), t: f.type};
			case _: error('the field ${cf.name} of ${c == null ? Names.typeName(o.t) : c.name} is not a shader value', e.pos);
		}
	}

	// a static variable: a constant
	function constant(c:ClassType, cf:ClassField, e:TypedExpr):SExpr {
		if (path(c) == "Math" && cf.name == "PI") return {e: EFloat(Math.PI), t: TFloat};
		var v = switch cf.kind {
			case FVar(_, AccNever | AccInline | AccCtor) if (cf.expr() != null): cf.expr();
			case _: null;
		}
		var t = type(e.t, e.pos);
		function strip(x:TypedExpr):TypedExpr
			return switch x.expr {
				case TParenthesis(y) | TMeta(_, y) | TCast(y, null): strip(y);
				case _: x;
			}
		return switch v == null ? null : strip(v).expr {
			case TConst(TInt(i)): coerce({e: EInt(i), t: TInt}, t, e.pos);
			case TConst(TFloat(s)): {e: EFloat(Std.parseFloat(s)), t: TFloat};
			case TConst(TBool(b)): {e: EBool(b), t: TBool};
			case TUnop(OpNeg, false, {expr: TConst(TInt(i))}): coerce({e: EInt(-i), t: TInt}, t, e.pos);
			case TUnop(OpNeg, false, {expr: TConst(TFloat(s))}): {e: EFloat(-Std.parseFloat(s)), t: TFloat};
			case _:
				var x = valueOf(c, cf);
				if (x == null || !Names.same(x.t, t))
					error('${path(c)}.${cf.name} is not a constant (shader code reads static constants only: a final or inline var of a literal, or of vec3(...) and the like of literals)', e.pos);
				x;
		}
	}

	// a static final of literals through builtins and operators (vec3(0.2,
	// 0.3, 0.9), mat4(1)): its value, printed where it is read
	function valueOf(c:ClassType, cf:ClassField):Null<SExpr> {
		var key = path(c) + "." + cf.name;
		if (values.exists(key)) return values.get(key);
		var te = Sources.value(c, cf);
		var scratch = [];
		var x = te == null ? null : expr(te, scratch);
		if (x != null && (scratch.length > 0 || !literal(x))) x = null;
		values.set(key, x);
		return x;
	}

	static function literal(x:SExpr):Bool
		return switch x.e {
			case EFloat(_) | EInt(_) | EBool(_): true;
			case ENew(xs): Lambda.foreach(xs, literal);
			case EBuiltin(name, xs): name != "sample" && name != "sampleLevel" && name != "discard" && Lambda.foreach(xs, literal);
			case EUnop(_, a) | ESwizzle(a, _) | EColumn(a, _) | EConvert(a): literal(a);
			case EBinop(_, a, b): literal(a) && literal(b);
			case ECond(c, a, b): literal(c) && literal(a) && literal(b);
			case _: false;
		}

	function call(f:TypedExpr, args:Array<TypedExpr>, e:TypedExpr, out:Array<SStmt>):SExpr {
		var t = type(e.t, e.pos);
		var c:ClassType, cf:ClassField;
		switch strip(f).expr {
			case TField({expr: TLocal(v)}, FAnon(slot)) if (v.id == slotsSelf):
				return slotCall(slot.get(), args, e, out);
			case TField(_, FStatic(cr, cfr)):
				c = cr.get();
				cf = cfr.get();
			case TField(_, FInstance(_, _, cfr)):
				error('${cfr.get().name}: a method call is not supported in a shader (shader functions are static)', e.pos);
			case _:
				error("this call is not supported in a shader", e.pos);
		}
		var argTypes = switch cf.type.follow() {
			case TFun(as, _): [for (a in as) a.t];
			case _: [for (a in args) a.t];
		}
		function lowered():Array<SExpr>
			return [for (i in 0...args.length) coerce(expr(args[i], out), type(argTypes[i], args[i].pos), args[i].pos)];
		var p = path(c);
		if (p == SHADER_PACK + ".ShaderMath") {
			if (cf.name == "position") error("position(...) marks a field of the varyings where the vertex stage builds them ({clip: position(...), ...})", e.pos);
			var xs = lowered();
			return switch cf.name {
				case "vec2" | "vec3" | "vec4": {e: ENew(xs), t: t};
				case "mat4" if (xs.length == 4): {e: ENew(xs), t: t};
				case "mat4":
					// the diagonal
					var s = xs[0];
					switch s.e {
						case EFloat(_) | ELocal(_):
						case _:
							var tmp = temp(TFloat);
							out.push(SDecl(tmp, s));
							s = local(tmp);
					}
					var z = {e: EFloat(0), t: TFloat};
					{e: ENew([for (i in 0...4) {e: ENew([for (j in 0...4) i == j ? s : z]), t: TVec(4)}]), t: t};
				case name:
					// (a Float bound or weight of a vector function: a vector, as WGSL wants it)
					switch t {
						case TVec(n) if (name != "reflect" && name != "cross" && name != "sampleLevel"):
							xs = [for (x in xs) x.t == TFloat ? {e: ENew([x]), t: t} : x];
						case _:
					}
					{e: EBuiltin(name, xs), t: t};
			}
		}
		switch c.kind {
			case KAbstractImpl(a) if (a.get().pack.join(".") == SHADER_PACK):
				var xs = lowered();
				var name = cf.name;
				if (name == "_new") return {e: ENew(xs), t: t};
				if (StringTools.startsWith(name, "get_")) return {e: ESwizzle(xs[0], name.substr(4)), t: t};
				var op = switch name {
					case "add" | "adds": Add;
					case "sub" | "subs" | "ssub": Sub;
					case "mul" | "scale" | "mulVec" | "mulMat": Mul;
					case "div" | "divs" | "sdiv": Div;
					case "neg": return {e: EUnop(Neg, xs[0]), t: t};
					case _: error('${a.get().name}.$name is not supported in a shader', e.pos);
				}
				return {e: EBinop(op, xs[0], xs[1]), t: t};
			case _:
		}
		if (p == "Math") {
			var xs = lowered();
			return switch cf.name {
				case "sqrt" | "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "atan2" | "exp" | "log" | "abs" | "pow" | "min" | "max": {e: EBuiltin(cf.name, xs), t: t};
				case "ffloor": {e: EBuiltin("floor", xs), t: t};
				case "fceil": {e: EBuiltin("ceil", xs), t: t};
				case "floor" | "ceil": {e: EConvert({e: EBuiltin(cf.name, xs), t: TFloat}), t: TInt};
				case _: error('Math.${cf.name} is not supported in a shader', e.pos);
			}
		}
		if (p == "Std" && cf.name == "int") return {e: EConvert(coerce(expr(args[0], out), TFloat, args[0].pos)), t: TInt};
		var g = func(c, cf, e.pos);
		var xs = [for (i in 0...args.length) coerce(expr(args[i], out), g.params[i].type, args[i].pos)];
		return {e: ECall(g, xs), t: g.ret};
	}

	// --- uniform(...)'s values ---

	// <uniform>.value: its field of the stage's Uniforms block
	function uniformRead(x:TypedExpr, e:TypedExpr):SExpr {
		var ref = strip(x);
		var name = switch ref.expr {
			case TField(_, FStatic(c, cf)) if (cf.get().kind.match(FVar(_, AccNever | AccCtor))): cf.get().name;
			case _: error("a uniform is a module-level final made by uniform(value): its value is read as <final>.value", e.pos);
		}
		if (kind != Stage) error('$name.value: a uniform is read in a stage (its value passed on to the functions it calls)', e.pos);
		var t = type(e.t, e.pos);
		switch t {
			case TFloat | TInt | TVec(_) | TMat4:
			case _: error('$name: a uniform is a Float, an Int, a vector or a Mat4, not a ${Names.typeName(t)}', e.pos);
		}
		var key = haxe.macro.TypedExprTools.toString(ref);
		if (uniformBlock == null) uniformBlock = new SStruct(names.global("Uniforms"), "Uniforms", []);
		var f = Lambda.find(uniformBlock.fields, f -> f.field == name);
		if (f == null) {
			f = {
				name: Names.unique(Names.sanitize(name), n -> !Lambda.exists(uniformBlock.fields, g -> g.name == n)),
				field: name,
				type: t,
				position: false
			};
			uniformBlock.fields.push(f);
			uniformRefs.push({field: name, expr: Context.storeTypedExpr(ref), type: Context.toComplexType(e.t)});
		}
		return {e: EField(local(stageParam("uniforms", TStruct(uniformBlock), e.pos)), f.name), t: t};
	}

	// --- slot objects' variants ---

	// m.options.<name>: the variant's value
	function option(name:String, e:TypedExpr):SExpr {
		var v = slots.options.get(name);
		if (v == null) error('the slot object has no option $name', e.pos);
		var t = type(e.t, e.pos);
		return switch [v, t] {
			case [KBool(b), TBool]: {e: EBool(b), t: TBool};
			case [KInt(i), TInt]: {e: EInt(i), t: TInt};
			case [KFloat(f), TInt] if (Math.ffloor(f) == f): {e: EInt(Std.int(f)), t: TInt};
			case [KInt(i), TFloat]: {e: EFloat(i), t: TFloat};
			case [KFloat(f), TFloat]: {e: EFloat(f), t: TFloat};
			case _: error('the option $name is a ${Names.typeName(t)}, not ${new KNode(v, null).describe()}', e.pos);
		}
	}

	// var g = a; var g1 = b; while (g < g1) { var k = g++; body }, a and b
	// constants: the body once for each k, k a constant in each
	function unrolled(first:TypedExpr, second:TypedExpr, loop:TypedExpr, out:Array<SStmt>):Bool {
		switch [first.expr, second.expr, strip(loop).expr] {
			case [TVar(g, a), TVar(g1, b), TWhile({expr: TBinop(OpLt, {expr: TLocal(x)}, {expr: TLocal(y)})}, {expr: TBlock(body)}, true)]
				if (a != null && b != null && x.id == g.id && y.id == g1.id && body.length > 0):
				var k = switch body[0].expr {
					case TVar(k, {expr: TUnop(OpIncrement, true, {expr: TLocal(z)})}) if (z.id == g.id): k;
					case _: return false;
				}
				var r = constantRange(a, b);
				if (r == null) return false;
				var rest = body.slice(1);
				for (x in rest)
					if (breaks(x)) error("a loop a variant unrolls has no break or continue", x.pos);
				for (n in r.from...r.to) {
					constants.set(k.id, {e: EInt(n), t: TInt});
					for (x in rest)
						stmt(x, out);
				}
				constants.remove(k.id);
				return true;
			case _:
				return false;
		}
	}

	// a loop's bounds, when both are constants
	function constantRange(a:TypedExpr, b:TypedExpr):Null<{from:Int, to:Int}> {
		var scratch = [];
		var x = Fold.expr(expr(a, scratch)), y = Fold.expr(expr(b, scratch));
		return switch [x.e, y.e] {
			case [EInt(i), EInt(j)] if (scratch.length == 0): {from: i, to: j};
			case _: null;
		}
	}

	static function breaks(e:TypedExpr):Bool {
		var found = false;
		function visit(x:TypedExpr)
			switch x.expr {
				case TBreak | TContinue: found = true;
				case TWhile(_, _, _) | TFor(_, _, _) | TFunction(_):
				case _: haxe.macro.TypedExprTools.iter(x, visit);
			}
		visit(e);
		return found;
	}

	// m.<slot>(s, p): the slot's function (the override's, else the
	// default's), its input s; its own parameters the stage's of the same
	// names, the others joining the stage's
	function slotCall(field:ClassField, args:Array<TypedExpr>, e:TypedExpr, out:Array<SStmt>):SExpr {
		var name = field.name;
		var node = slots.slots.get(name);
		if (node == null) error('the slot object has no slot $name', e.pos);
		if (args.length == 0 || args.length > 2) error('a slot is called with its input and the stage\'s parameters: m.$name(s, p)', e.pos);
		var g = slotFunctions.get(name);
		if (g == null) {
			g = switch node.value {
				case KFunction(k):
					var source:Expr = k.source;
					var f = switch source.expr {
						case EFunction(_, f): f;
						case _: throw "slot";
					}
					// (its input's type, when not written: what the stage passes)
					if (f.args.length > 0 && f.args[0].type == null) {
						f = Reflect.copy(f);
						f.args = [Reflect.copy(f.args[0])].concat(f.args.slice(1));
						f.args[0].type = Context.toComplexType(switch field.type.follow() {
							case TFun(as, _) if (as.length > 0): as[0].t;
							case _: args[0].t;
						});
					}
					if (f.args.length > 1 && f.args[1].type == null) error('the slot $name: its parameters\' type is written ({time: Float})', source.pos);
					var te = typeIn(source, {expr: EFunction(FAnonymous, f), pos: source.pos});
					switch strip(te).expr {
						case TFunction(tf): lower("<slot>." + name, name, tf, source.pos, Slot);
						case _: throw "slot";
					}
				case KRef(ref):
					var r = helder.definition.HaxeAdapter.refs.get(ref);
					if (r == null) error('the slot $name, $ref, is not a function', node.pos);
					var te = Sources.typed(r.c, r.cf);
					if (te == null) error('${display(r.c, r.cf)} has no source a shader can compile (a static or module-level function written in Haxe)', node.pos);
					switch strip(te).expr {
						case TFunction(tf): lower(path(r.c) + "." + r.cf.name, r.cf.name, tf, r.cf.pos, Slot);
						case _: error('the slot $name is not a function', node.pos);
					}
				case _: error('the slot $name is a function, not ${node.describe()}', node.pos);
			}
			slotFunctions.set(name, g);
		}
		if (g.params.length == 0) error('the slot $name takes no input', e.pos);
		var xs = [coerce(expr(args[0], out), g.params[0].type, args[0].pos)];
		for (i in 0...g.fields.length)
			xs.push(local(stageParam(g.fields[i], g.params[i + 1].type, e.pos)));
		var want = type(e.t, e.pos);
		if (!Names.same(g.ret, want)) error('the slot $name returns a ${Names.typeName(g.ret)}, where a ${Names.typeName(want)} is needed', e.pos);
		return {e: ECall(g, xs), t: g.ret};
	}

	// the stage's parameter of a name (a slot's: made one when the stage has none of it)
	function stageParam(name:String, t:SType, pos:Position):SVar {
		if (paramsObject == null) paramsObject = {id: -1, name: "p", fields: new Map()};
		var s = paramsObject.fields.get(name);
		if (s != null) {
			if (!Names.same(s.type, t)) error('the parameter $name is a ${Names.typeName(s.type)} in the stage, a ${Names.typeName(t)} in a slot', pos);
			return s;
		}
		s = declareNamed(name, t, pos, vars.get(fn), true);
		paramsObject.fields.set(name, s);
		fn.params.push(s);
		fn.fields.push(name);
		return s;
	}

	// --- helpers ---

	function coerce(x:SExpr, t:SType, pos:Position):SExpr {
		if (Names.same(x.t, t)) return x;
		return switch [x.t, t] {
			case [TInt, TFloat]:
				switch x.e {
					case EInt(i): {e: EFloat(i), t: TFloat};
					case _: {e: EConvert(x), t: TFloat};
				}
			case _: error('${Names.typeName(x.t)} where a ${Names.typeName(t)} is needed', pos);
		}
	}

	static function one(t:SType):SExpr
		return t == TFloat ? {e: EFloat(1), t: TFloat} : {e: EInt(1), t: TInt};

	static function not(x:SExpr):SExpr
		return {e: EUnop(Not, x), t: TBool};

	static function local(v:SVar):SExpr
		return {e: ELocal(v), t: v.type};

	static function path(c:ClassType):String
		return c.pack.concat([c.name]).join(".");
}

// what a function is lowered as: a plain function, a stage (its object of
// parameters flattened, a slot object's third parameter), a slot
enum abstract LowerKind(Int) {
	var Plain;
	var Stage;
	var Slot;
}
#end
