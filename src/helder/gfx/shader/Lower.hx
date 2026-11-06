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

	public function finish()
		names.unhide(vars);

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
		var te = Context.withOptions({allowInlining: false}, () -> Context.typeExpr({expr: EFunction(FAnonymous, f), pos: e.pos}));
		var tf = switch strip(te).expr {
			case TFunction(tf): tf;
			case _: throw "lowerStage";
		}
		if (varyings == null) varyings = tf.t;
		stageTypes.set(name, te.t);
		return lower("<stage>." + name, name, tf, e.pos);
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

	function lower(key:String, name:String, tf:TFunc, pos:Position):SFunction {
		active.push(key);
		var saved = {fn: fn, locals: locals, names: localNames};
		locals = new Map();
		localNames = new Map();
		var vs = [];
		var params = [for (a in tf.args) declare(a.v, pos, vs)];
		var f = new SFunction(names.global(name), params, type(tf.t, pos));
		if (f.ret == TTexture) error('$name: a texture is not a result (pass the parameter on)', pos);
		fn = f;
		vars.set(f, vs);
		var body = [];
		stmt(tf.expr, body);
		f.body = body;
		fn = saved.fn;
		locals = saved.locals;
		localNames = saved.names;
		active.pop();
		functions.set(key, f);
		return f;
	}

	function declare(v:TVar, pos:Position, ?list:Array<SVar>):SVar {
		var t = type(v.t, pos);
		if (t == TVoid) error('${v.name} has no value', pos);
		// (a texture: a parameter, its sampler <name>_smp next to it where the language has one)
		if (t == TTexture && list == null) error('${v.name}: a texture is a parameter, not a local', pos);
		var s = new SVar(Names.unique(Names.sanitize(v.name), n -> !localNames.exists(n) && (t != TTexture || !localNames.exists(n + "_smp"))), t);
		localNames.set(s.name, true);
		if (t == TTexture) localNames.set(s.name + "_smp", true);
		locals.set(v.id, s);
		(list != null ? list : vars.get(fn)).push(s);
		return s;
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
				var key = "{" + [for (f in sortedFields(a)) f.name + ":" + f.type.toString()].join(",") + "}";
				var s = anonStruct(key, "S" + anonymous, a, pos);
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

	function anonStruct(key:String, name:String, a:AnonType, pos:Position):SStruct {
		var s = structs.get(key);
		if (s != null) return s;
		if (name == "S" + anonymous) anonymous++;
		return fields(key, name, [
			for (f in sortedFields(a))
				switch f.kind {
					case FVar(_, _): f;
					case FMethod(_): error('$key.${f.name}: a method is not a struct field', f.pos);
				}
		], pos);
	}

	function fields(key:String, name:String, cfs:Array<ClassField>, pos:Position):SStruct {
		if (building.exists(key)) error('$key contains itself', pos);
		building.set(key, true);
		var fields:Array<SField> = [];
		for (f in cfs) {
			fields.push({
				name: Names.unique(Names.sanitize(f.name), n -> !Lambda.exists(fields, g -> g.name == n)),
				field: f.name,
				type: type(f.type, f.pos),
				position: false
			});
			if (fields[fields.length - 1].type == TTexture) error('$key.${f.name}: a texture is not a struct field (it is a parameter)', f.pos);
		}
		if (fields.length == 0) error('$key has no fields', pos);
		building.remove(key);
		var s = new SStruct(names.global(name), key, fields);
		structs.set(key, s);
		return s;
	}

	// a struct's value from its fields' (position(x): that field is the clip-space position)
	function build(s:SStruct, args:Array<TypedExpr>, out:Array<SStmt>):SExpr {
		var xs = [];
		for (i in 0...args.length) {
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
				for (x in el)
					stmt(x, out);
			case TMeta(_, x) | TParenthesis(x):
				stmt(x, out);
			case TVar(v, {expr: TUnop(op = OpIncrement | OpDecrement, true, {expr: TLocal(i)})}) if (locals.exists(i.id)):
				// var v = i++ (Haxe's for loops): no temporary
				var s = declare(v, e.pos), i = target({expr: TLocal(i), t: v.t, pos: e.pos});
				out.push(SDecl(s, local(i)));
				out.push(SAssign(i, op == OpIncrement ? Add : Sub, one(i.type)));
			case TVar(v, init):
				var p = init == null ? null : positionArg(init);
				if (p != null) {
					positionLocals.set(v.id, true);
					init = p;
				}
				var x = init == null ? null : expr(init, out);
				var s = declare(v, e.pos);
				out.push(SDecl(s, x == null ? null : coerce(x, s.type, init.pos)));
			case TIf(c, a, b):
				out.push(SIf(coerce(expr(c, out), TBool, c.pos), block(a), b == null ? null : block(b)));
			case TWhile(c, body, true):
				var pre = [];
				var x = coerce(expr(c, pre), TBool, c.pos);
				if (pre.length == 0) out.push(SWhile(x, block(body))) else
					out.push(SWhile({e: EBool(true), t: TBool}, pre.concat([SIf(not(x), [SBreak], null)]).concat(block(body))));
			case TWhile(_, _, false):
				error("do-while is not supported in a shader (use while)", e.pos);
			case TFor(v, it, body):
				switch it.expr {
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
			case TLocal(v):
				var s = locals.get(v.id);
				if (s == null) error('${v.name} is not a local of this function (a closure?)', e.pos);
				local(s);
			case TParenthesis(x) | TMeta(_, x): expr(x, out);
			case TCast(x, null): coerce(expr(x, out), type(e.t, e.pos), e.pos);
			case TCast(_, _): error("a checked cast is not supported in a shader", e.pos);
			case TBlock([]): error("an empty block has no value", e.pos);
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
			case TUnop(OpNot, false, x): {e: EUnop(Not, coerce(expr(x, out), TBool, x.pos)), t: TBool};
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
			case TField(x, FInstance(c, _, cf)): field(x, c.get(), cf.get(), e, out);
			case TField(_, FStatic(c, cf)): constant(c.get(), cf.get(), e);
			case TField(_, _): error("this field access is not supported in a shader", e.pos);
			case TObjectDecl(fs):
				// (a struct of a typedef: its fields by name, in the struct's order)
				var s = switch type(e.t, e.pos) {
					case TStruct(s): s;
					case _: error("an anonymous object is not a shader value (a struct is)", e.pos);
				}
				var args = [
					for (f in s.fields) {
						var given = Lambda.find(fs, x -> x.name == f.field);
						if (given == null) error('${s.path}: the field ${f.field} is not given', e.pos);
						given.expr;
					}
				];
				if (fs.length != s.fields.length) error('${s.path} is built with all its fields, no others', e.pos);
				build(s, args, out);
			case TArrayDecl(_) | TArray(_, _): error("arrays are not supported in a shader (yet)", e.pos);
			case TFunction(_): error("a closure is not supported in a shader", e.pos);
			case TSwitch(_, _, _): error("switch is not supported in a shader (yet)", e.pos);
			case TTry(_, _) | TThrow(_): error("exceptions are not supported in a shader", e.pos);
			case TTypeExpr(_): error("a type is not a shader value", e.pos);
			case _: error("not supported in a shader", e.pos);
		}
	}

	function binary(op:Binop, a:TypedExpr, b:TypedExpr, e:TypedExpr, out:Array<SStmt>):SExpr {
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
		var t = type(e.t, e.pos);
		var o = expr(x, out);
		return switch o.t {
			case TVec(_): {e: ESwizzle(o, cf.name), t: t};
			case TMat4: {e: EColumn(o, Std.parseInt(cf.name.substr(1))), t: t};
			case TStruct(s):
				var f = Lambda.find(s.fields, f -> f.field == cf.name);
				if (f == null) error('${s.path} has no field ${cf.name}', e.pos);
				{e: EField(o, f.name), t: t};
			case _: error('the field ${cf.name} of ${c.name} is not a shader value', e.pos);
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
			case _: error('${path(c)}.${cf.name} is not a constant (shader code reads static constants only: a final or inline var of a literal)', e.pos);
		}
	}

	function call(f:TypedExpr, args:Array<TypedExpr>, e:TypedExpr, out:Array<SStmt>):SExpr {
		var t = type(e.t, e.pos);
		var c:ClassType, cf:ClassField;
		switch f.expr {
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
				case "sqrt" | "sin" | "cos" | "tan" | "exp" | "log" | "abs" | "pow" | "min" | "max": {e: EBuiltin(cf.name, xs), t: t};
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
#end
