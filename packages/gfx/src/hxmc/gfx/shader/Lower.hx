package hxmc.gfx.shader;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import hxmc.gfx.shader.Ir;

using haxe.macro.Tools;

// The shader macro's middle: a shader class's stages, from Haxe's typed AST
// (typed without inlining, Macro.typeClass, so that the math types' and
// ShaderMath's calls stay calls) to the IR. What a shader may contain:
// Float, Int and Bool, the math types, @:structInit classes of those,
// Texture2D parameters (passed on, or read by sample);
// locals, assignments to them, if, while, for over an Int range, return,
// break and continue; calls to ShaderMath, the math types' operators and
// swizzles, a few of Math's functions, Std.int, and the static functions of
// other shader classes (Shaders), none recursive. Anything else (allocation,
// closures, Dynamic, strings, arrays, fields of other types) is a compile
// error at its position, as are the stage interface's mismatches.
// Expressions with statements inside (blocks, the operands Haxe stores in
// temporaries) put those statements before the statement that uses them:
// shader code has no side effects but assignments, so that order is safe.
class Lower {
	static final SHADER_PACK = "hxmc.gfx.shader";

	final structs = new Map<String, SStruct>();
	final building = new Map<String, Bool>();
	final functions = new Map<String, SFunction>();
	final active:Array<String> = [];
	final globals = new Map<String, Bool>();
	// each function's locals, renamed at the end if a global took their name
	final vars = new Map<SFunction, Array<SVar>>();

	// the function being lowered
	var fn:SFunction;
	var locals:Map<Int, SVar>;
	var names:Map<String, Bool>;
	var temps = 0;

	public function new() {}

	public function program(c:ClassType):SProgram {
		var vcf = stageField(c, ":vertex"), fcf = stageField(c, ":fragment");
		var vf = func(c, vcf, vcf.pos), ff = func(c, fcf, fcf.pos);
		// the interface: a vertex of attributes in, the varyings out, one of them the position
		if (vf.params.length == 0) error('@:vertex ${vcf.name} takes no vertex', vcf.pos);
		var input = switch vf.params[0].type {
			case TStruct(s): s;
			case t: error('@:vertex ${vcf.name}: the vertex is a ${name(t)}, not a @:structInit class', vcf.pos);
		}
		for (f in input.fields)
			switch f.type {
				case TFloat | TVec(_):
				case t: error('@:vertex ${vcf.name}: ${input.path}.${f.field} is a ${name(t)}: vertex attributes are Float, Vec2, Vec3 or Vec4', vcf.pos);
			}
		var varyings = switch vf.ret {
			case TStruct(s): s;
			case t: error('@:vertex ${vcf.name} returns a ${name(t)}, not a @:structInit class of varyings', vcf.pos);
		}
		var positions = 0;
		for (f in varyings.fields)
			switch f.type {
				case TVec(4) if (f.position): positions++;
				case t if (f.position): error('@:vertex ${vcf.name}: the @:position ${varyings.path}.${f.field} is a ${name(t)}, not a Vec4', vcf.pos);
				case TFloat | TVec(_):
				case t: error('@:vertex ${vcf.name}: the varying ${varyings.path}.${f.field} is a ${name(t)}: varyings are Float, Vec2, Vec3 or Vec4', vcf.pos);
			}
		if (positions != 1) error('@:vertex ${vcf.name}: ${varyings.path} needs exactly one @:position field (it has $positions)', vcf.pos);
		if (ff.params.length == 0 || !same(ff.params[0].type, vf.ret))
			error('stage interface mismatch: @:fragment ${fcf.name} takes ' + (ff.params.length == 0 ? "nothing" : name(ff.params[0].type))
				+ ', but @:vertex ${vcf.name} returns ${name(vf.ret)}', fcf.pos);
		if (!same(ff.ret, TVec(4))) error('@:fragment ${fcf.name} returns a ${name(ff.ret)}, not a Vec4 (the colour)', fcf.pos);
		// resources: the further parameters, uniform blocks (a slot per struct)
		// and textures (a slot per name), slots in order of appearance
		var uniforms:Array<SUniform> = [], textures:Array<STexture> = [];
		function resources(f:SFunction, cf:ClassField):Array<SResource>
			return [
				for (p in f.params.slice(1)) {
					var slot = uniforms.length + textures.length;
					switch p.type {
						case TStruct(s):
							var u = Lambda.find(uniforms, u -> u.struct == s);
							if (u == null) {
								u = std140(s, slot, cf.pos);
								uniforms.push(u);
							}
							RUniform(u);
						case TTexture:
							var t = Lambda.find(textures, t -> t.name == p.name);
							if (t == null) {
								t = new STexture(p.name, slot);
								textures.push(t);
							}
							RTexture(t);
						case t: error('${cf.name}: the parameter ${p.name} is a ${name(t)}, not a uniform block (a @:structInit class) or a Texture2D', cf.pos);
					}
				}
			];
		var vr = resources(vf, vcf), fr = resources(ff, fcf);
		if (uniforms.length + textures.length > MAX_SLOTS) error('more than $MAX_SLOTS uniform blocks and textures', vcf.pos);
		// (a local may not hide a global of the same name)
		for (f => vs in vars)
			for (v in vs)
				if (globals.exists(v.name)) v.name = unique(v.name, n -> !globals.exists(n) && !Lambda.exists(vs, w -> w.name == n));
		return new SProgram(entry(Vertex, vf, input, vr), entry(Fragment, ff, varyings, fr), uniforms, textures);
	}

	function stageField(c:ClassType, meta:String):ClassField {
		var fs = [for (f in c.statics.get()) if (f.meta.has(meta)) f];
		if (fs.length == 0) error('${c.name} has no @$meta function', c.pos);
		if (fs.length > 1) error('${c.name} has more than one @$meta function', fs[1].pos);
		return fs[0];
	}

	// the stage's function and what it reaches, in declaration order
	function entry(stage:SStage, f:SFunction, input:SStruct, resources:Array<SResource>):SEntry {
		var fs:Array<SFunction> = [], ss:Array<SStruct> = [];
		function ty(t:SType)
			switch t {
				case TStruct(s) if (!ss.contains(s)):
					for (f in s.fields)
						ty(f.type);
					ss.push(s);
				case _:
			}
		function visit(f:SFunction) {
			if (fs.contains(f)) return;
			for (p in f.params)
				ty(p.type);
			ty(f.ret);
			function e(x:SExpr) {
				ty(x.t);
				switch x.e {
					case EField(a, _) | ESwizzle(a, _) | EColumn(a, _) | EUnop(_, a) | EConvert(a): e(a);
					case EBinop(_, a, b):
						e(a);
						e(b);
					case ECond(c, a, b):
						e(c);
						e(a);
						e(b);
					case ENew(args) | EBuiltin(_, args): for (a in args) e(a);
					case ECall(g, args):
						for (a in args)
							e(a);
						visit(g);
					case EFloat(_) | EInt(_) | EBool(_) | ELocal(_):
				}
			}
			function s(st:SStmt)
				switch st {
					case SDecl(v, init):
						ty(v.type);
						if (init != null) e(init);
					case SAssign(_, _, x) | SEval(x): e(x);
					case SIf(c, a, b):
						e(c);
						for (x in a)
							s(x);
						if (b != null) for (x in b)
							s(x);
					case SWhile(c, body):
						e(c);
						for (x in body)
							s(x);
					case SReturn(x): if (x != null) e(x);
					case SBreak | SContinue:
				}
			for (st in f.body)
				s(st);
			fs.push(f);
		}
		visit(f);
		for (r in resources)
			switch r {
				case RUniform(u): ty(TStruct(u.struct));
				case RTexture(_):
			}
		return new SEntry(stage, f, input, resources, ss, fs);
	}

	// std140 (and WGSL's uniform layout, the same for these types)
	function std140(s:SStruct, binding:Int, pos:Position):SUniform {
		var off = 0, offsets = [];
		for (f in s.fields) {
			var size = 0, align = 0;
			switch f.type {
				case TFloat | TInt:
					size = align = 4;
				case TVec(n):
					size = 4 * n;
					align = n == 2 ? 8 : 16;
				case TMat4:
					size = 64;
					align = 16;
				case t: error('the uniform ${s.path}.${f.field} is a ${name(t)}: uniforms are Float, Int, vectors and Mat4', pos);
			}
			off = (off + align - 1) & ~(align - 1);
			offsets.push(off);
			off += size;
		}
		return new SUniform(s, binding, offsets, (off + 15) & ~15);
	}

	// --- functions ---

	function func(c:ClassType, cf:ClassField, pos:Position):SFunction {
		var key = path(c) + "." + cf.name;
		var f = functions.get(key);
		if (f != null) return f;
		if (active.contains(key))
			error("recursion: " + active.slice(active.indexOf(key)).concat([key]).join(" -> ") + " (shader functions cannot recurse)", pos);
		var te = Macro.typedFunction(c, cf.name);
		if (te == null)
			error('${path(c)}.${cf.name} is not a shader function (shader code calls the static functions of classes that implement hxmc.gfx.shader.Shaders)',
				pos);
		var tf = switch te.expr {
			case TFunction(tf): tf;
			case _: error('${cf.name} is not a function', cf.pos);
		}
		if (cf.params.length > 0) error('${cf.name}: a shader function has no type parameters', cf.pos);
		active.push(key);
		var saved = {fn: fn, locals: locals, names: names};
		locals = new Map();
		names = new Map();
		var vs = [];
		var params = [for (a in tf.args) declare(a.v, cf.pos, vs)];
		f = new SFunction(global(cf.name), params, type(tf.t, cf.pos));
		if (f.ret == TTexture) error('${cf.name}: a texture is not a result (pass the parameter on)', cf.pos);
		fn = f;
		vars.set(f, vs);
		var body = [];
		stmt(tf.expr, body);
		f.body = body;
		fn = saved.fn;
		locals = saved.locals;
		names = saved.names;
		active.pop();
		functions.set(key, f);
		return f;
	}

	function declare(v:TVar, pos:Position, ?list:Array<SVar>):SVar {
		var t = type(v.t, pos);
		if (t == TVoid) error('${v.name} has no value', pos);
		// (a texture: a parameter, its sampler <name>_smp next to it where the language has one)
		if (t == TTexture && list == null) error('${v.name}: a texture is a parameter, not a local', pos);
		var s = new SVar(unique(sanitize(v.name), n -> !names.exists(n) && (t != TTexture || !names.exists(n + "_smp"))), t);
		names.set(s.name, true);
		if (t == TTexture) names.set(s.name + "_smp", true);
		locals.set(v.id, s);
		(list != null ? list : vars.get(fn)).push(s);
		return s;
	}

	function temp(t:SType):SVar {
		var s = new SVar(unique("t" + temps++, n -> !names.exists(n)), t);
		names.set(s.name, true);
		vars.get(fn).push(s);
		return s;
	}

	// --- types ---

	function type(t:Type, pos:Position):SType {
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
					case _: error('${t.toString()} is not a shader type (Float, Int, Bool, Vec2, Vec3, Vec4, Mat4 and @:structInit classes of them)', pos);
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
					case _: TStruct(struct(c, pos));
				}
			case TDynamic(_): error('Dynamic is not a shader type', pos);
			case _: error('${t.toString()} is not a shader type (Float, Int, Bool, Vec2, Vec3, Vec4, Mat4 and @:structInit classes of them)', pos);
		}
	}

	function struct(c:ClassType, pos:Position):SStruct {
		var key = path(c);
		var s = structs.get(key);
		if (s != null) return s;
		if (c.isExtern || c.isInterface || c.superClass != null || c.params.length > 0 || !c.meta.has(":structInit"))
			error('$key is not a shader type (a struct is a @:structInit class of Float, Int, Bool, vectors, matrices and structs, without a superclass)',
				pos);
		if (building.exists(key)) error('$key contains itself', c.pos);
		building.set(key, true);
		var fields:Array<SField> = [];
		for (f in c.fields.get())
			switch f.kind {
				case FVar(AccNormal | AccNo, AccNormal | AccNo | AccNever | AccCtor):
					fields.push({
						name: unique(sanitize(f.name), n -> !Lambda.exists(fields, g -> g.name == n)),
						field: f.name,
						type: type(f.type, f.pos),
						position: f.meta.has(":position")
					});
					if (fields[fields.length - 1].type == TTexture) error('$key.${f.name}: a texture is not a struct field (it is a parameter)', f.pos);
				case FVar(_, _): error('$key.${f.name}: a property is not a struct field', f.pos);
				case FMethod(_):
			}
		if (fields.length == 0) error('$key has no fields', c.pos);
		building.remove(key);
		s = new SStruct(global(c.name), key, fields);
		structs.set(key, s);
		return s;
	}

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
					case ECall(_):
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
				if (v.t != TFloat && v.t != TInt) error('-: a ${name(v.t)}', e.pos);
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
				{e: ENew([for (i in 0...args.length) coerce(expr(args[i], out), s.fields[i].type, args[i].pos)]), t: t};
			case TField(x, FInstance(c, _, cf)): field(x, c.get(), cf.get(), e, out);
			case TField(_, FStatic(c, cf)): constant(c.get(), cf.get(), e);
			case TField(_, _): error("this field access is not supported in a shader", e.pos);
			case TObjectDecl(_): error("an anonymous object is not a shader value (a @:structInit class is)", e.pos);
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
				if (t != TFloat && t != TInt) error('${name(x.t)} ${op} ${name(y.t)} is not a shader operation', e.pos);
				if (op == OpMod && t == TFloat) error("% on Float is not supported in a shader", e.pos);
				{e: EBinop(binop(op, e.pos), coerce(x, t, a.pos), coerce(y, t, b.pos)), t: t};
			case OpEq | OpNotEq | OpLt | OpLte | OpGt | OpGte:
				var w = x.t == TFloat || y.t == TFloat ? TFloat : x.t;
				if (!(w == TFloat || w == TInt || (w == TBool && (op == OpEq || op == OpNotEq))))
					error('${name(x.t)} and ${name(y.t)} cannot be compared in a shader', e.pos);
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
						case TVec(n) if (name != "reflect" && name != "cross"):
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
		if (same(x.t, t)) return x;
		return switch [x.t, t] {
			case [TInt, TFloat]:
				switch x.e {
					case EInt(i): {e: EFloat(i), t: TFloat};
					case _: {e: EConvert(x), t: TFloat};
				}
			case _: error('${name(x.t)} where a ${name(t)} is needed', pos);
		}
	}

	static function one(t:SType):SExpr
		return t == TFloat ? {e: EFloat(1), t: TFloat} : {e: EInt(1), t: TInt};

	static function not(x:SExpr):SExpr
		return {e: EUnop(Not, x), t: TBool};

	static function local(v:SVar):SExpr
		return {e: ELocal(v), t: v.type};

	public static function same(a:SType, b:SType):Bool
		return switch [a, b] {
			case [TVec(n), TVec(m)]: n == m;
			case [TStruct(s), TStruct(r)]: s == r;
			case _: a == b;
		}

	public static function name(t:SType):String
		return switch t {
			case TVoid: "Void";
			case TBool: "Bool";
			case TInt: "Int";
			case TFloat: "Float";
			case TVec(n): 'Vec$n';
			case TMat4: "Mat4";
			case TTexture: "Texture2D";
			case TStruct(s): s.path;
		}

	static function path(c:ClassType):String
		return c.pack.concat([c.name]).join(".");

	// a struct's or function's name: not one of the entry points' either
	// (main, main0, i, r, o, s, StageIn, StageOut; in_*, v_*, out_*, u_*, make_*, tex_*, smp_*)
	function global(n:String):String {
		var s = unique(sanitize(n), n -> !globals.exists(n) && !ENTRY.match(n));
		globals.set(s, true);
		return s;
	}

	// the name, or with _2, _3, ... until free; never reserved
	static function unique(n:String, free:String->Bool):String {
		var s = n, k = 1;
		while (!free(s) || reserved(s))
			s = n + "_" + ++k;
		return s;
	}

	// an identifier every language takes: letters, digits and single
	// underscores, starting with a letter
	static function sanitize(n:String):String {
		var s = ~/[^A-Za-z0-9_]/g.replace(n, "_");
		s = ~/_+/g.replace(s, "_");
		while (StringTools.startsWith(s, "_"))
			s = s.substr(1);
		if (s == "" || ~/^[0-9]/.match(s)) s = "t" + s;
		return s;
	}

	static final ENTRY = ~/^(main|main0|i|r|o|s|StageIn|StageOut|(in|v|out|u|make|tex|smp)_.*)$/;
	static inline var MAX_SLOTS = 16;
	static var RESERVED:Map<String, Bool>;

	// the keywords and builtins of GLSL ES 3.00, WGSL, MSL (C++) and HLSL
	static function reserved(n:String):Bool {
		if (RESERVED == null) {
			RESERVED = new Map();
			for (w in ("attribute const uniform varying layout centroid flat smooth noperspective patch sample break continue do for while switch case default "
				+ "if else subroutine in out inout float double int void bool true false invariant precise discard return mat2 mat3 mat4 mat2x2 mat2x3 "
				+ "mat2x4 mat3x2 mat3x3 mat3x4 mat4x2 mat4x3 mat4x4 vec2 vec3 vec4 ivec2 ivec3 ivec4 bvec2 bvec3 bvec4 uint uvec2 uvec3 uvec4 lowp mediump "
				+ "highp precision sampler2D sampler3D samplerCube struct common partition active asm class union enum typedef template this resource "
				+ "goto inline noinline public static extern external interface long short half fixed unsigned superp input output filter sizeof cast "
				+ "namespace using texture sampler gl_Position gl_FragCoord "
				+ "fn let var alias override bitcast enable requires diagnostic loop continuing fallthrough f16 f32 i32 u32 vec2f vec3f vec4f vec2i "
				+ "vec3i vec4i mat4x4f array atomic ptr private storage workgroup function read write read_write select module "
				+ "auto catch char const_cast constexpr decltype delete dynamic_cast explicit export friend mutable new noexcept nullptr operator protected "
				+ "register reinterpret_cast signed static_assert static_cast thread throw try typeid typename virtual volatile wchar_t device constant "
				+ "threadgroup kernel vertex fragment packed_float3 float2 float3 float4 float4x4 half2 half3 half4 int2 int3 int4 uint2 uint3 uint4 metal "
				+ "cbuffer tbuffer row_major column_major packoffset nointerpolation linear point line triangle lineadj triangleadj vector matrix string "
				+ "technique pass compile dword min16float min16int SV_Position SV_Target TEXCOORD bool2 bool3 bool4 float1 groupshared "
				+ "abs sign floor ceil fract frac sqrt inversesqrt inverseSqrt rsqrt sin cos tan exp log min max pow step mix lerp clamp smoothstep dot "
				+ "length distance normalize reflect cross mul saturate mod atan atan2 any all transpose determinant").split(" "))
				RESERVED.set(w, true);
		}
		return RESERVED.exists(n) || StringTools.startsWith(n, "gl_");
	}

	static function error(msg:String, pos:Position):Dynamic
		return Context.error("shader: " + msg, pos);
}
#end
