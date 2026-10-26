package hxmc.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import hxmc.scoped.Scoped.isScoped;

using haxe.macro.Tools;
using Lambda;
#end

// The checker: a scoped value never reaches the GC heap, where it could
// outlive its scope. `--macro hxmc.scoped.Check.enable()` runs it after
// typing (extraParams.hxml does when the package is a -lib). An error for:
//
// - a field or static of a class, or of an anonymous structure, holding a
//   scoped value (a struct's own fields are its memory, not the heap's);
// - a scoped value inside a GC type: Array<Slice<Int>>, Null<Str>, a Map's
//   values, a type parameter of a class;
// - a closure capturing a local that holds a scoped value;
// - a scoped value given to Dynamic, Any or a type parameter (a call's
//   argument, an assignment, a variable, a return).
//
// - in a loop of a @:scoped function (its iterations are scopes), a value
//   made in the iteration assigned to a variable declared outside the loop:
//   its memory is freed when the next iteration starts (a variable from
//   outside, or an element or field of one, may be assigned).
//
// What it does not check (hxmc's checker did, on its IR, through calls):
// lifetimes across functions beyond these rules. `-D scoped_debug` catches
// the rest at run time for Slices, Grows and Strs.
class Check {
	#if macro
	public static function enable()
		Context.onAfterTyping(check);

	static var reported = new Map<String, Bool>();

	// (once per position: inlining repeats a local)
	static function report(msg:String, pos:Position) {
		var key = Std.string(pos) + msg;
		if (reported.exists(key))
			return;
		reported.set(key, true);
		Context.reportError(msg, pos);
	}

	static function check(types:Array<ModuleType>) {
		for (t in types)
			switch t {
				case TClassDecl(_.get() => c):
					if (c.pack.length >= 2 && c.pack[0] == "hxmc" && c.pack[1] == "scoped")
						continue;
					var impl = c.kind.match(KAbstractImpl(_));
					for (f in c.fields.get().concat(c.statics.get()))
						checkField(f, impl);
					if (c.constructor != null)
						checkField(c.constructor.get(), impl);
				default:
			}
	}

	static function checkField(f:ClassField, impl:Bool) {
		switch f.kind {
			case FVar(_, _) if (!impl && (isScoped(f.type) || holds(f.type))):
				report('${f.name}: a field holding a scoped value (the GC heap would keep it past its scope)', f.pos);
			case FVar(_, _) if (holds(f.type)):
				report('${f.name}: a scoped value inside a GC type', f.pos);
			default:
		}
		var e = f.expr();
		if (e != null)
			switch e.expr {
				// (the field's own function: its body is not a closure)
				case TFunction(fn): walk(fn.expr, null);
				default: walk(e, null);
			}
	}

	// a scoped value inside a GC type (not the type itself)
	static function holds(t:Type):Bool {
		return switch t {
			case TMono(r): r.get() != null && holds(r.get());
			case TLazy(f): holds(f());
			case TType(_.get() => td, params): holds(td.type.applyTypeParameters(td.params, params));
			// (the package's own classes: inline iterators, which do not escape)
			case TInst(_.get() => {pack: ["hxmc", "scoped"]}, _): false;
			case TInst(_, params): params.exists(p -> isScoped(p) || holds(p));
			case TEnum(_, params): params.exists(p -> isScoped(p) || holds(p));
			case TAbstract(_, params) if (isScoped(t)): false;
			// (the package's own views: locals of the Scoped macro's loops)
			case TAbstract(_.get() => {pack: ["hxmc", "scoped"]}, _): false;
			case TAbstract(_, params): params.exists(p -> isScoped(p) || holds(p));
			case TAnonymous(_.get() => a): a.fields.exists(f -> isScoped(f.type) || holds(f.type));
			case TFun(_, _) | TDynamic(_): false;
			default: false;
		}
	}

	// a type that loses track of what it holds
	static function opaque(t:Type):Bool {
		return switch t {
			case TMono(r): r.get() != null && opaque(r.get());
			case TLazy(f): opaque(f());
			case TDynamic(_): true;
			case TType(_.get() => td, params): opaque(td.type.applyTypeParameters(td.params, params));
			case TAbstract(_.get() => {pack: [], name: "Any"}, _): true;
			case TAbstract(_.get() => {pack: [], name: "Null"}, [p]): opaque(p);
			case TInst(_.get() => {kind: KTypeParameter(_)}, _): true;
			default: false;
		}
	}

	static function into(target:Type, e:TypedExpr) {
		if (isScoped(e.t) && opaque(target))
			report('a scoped value given to ${target.toString()} (it could outlive its scope there)', e.pos);
	}

	// locals: those of the closure being walked (null: not in a closure)
	static function walk(e:TypedExpr, locals:Null<Map<Int, Bool>>) {
		switch e.expr {
			case TFunction(fn):
				var inner = new Map<Int, Bool>();
				for (a in fn.args)
					inner.set(a.v.id, true);
				walk(fn.expr, inner);
				return;
			case TVar(v, init):
				if (locals != null)
					locals.set(v.id, true);
				if (holds(v.t))
					report('${v.name}: a scoped value inside a GC type', e.pos);
				if (init != null)
					into(v.t, init);
			case TLocal(v):
				if (locals != null && !locals.exists(v.id) && isScoped(v.t))
					report('${v.name}: a scoped value captured by a closure', e.pos);
			case TBlock(_) if (scopedLoop(e)):
				loopEscapes(e);
			case TCall(f, args):
				switch f.t.follow() {
					case TFun(params, _):
						for (i in 0...args.length)
							if (i < params.length)
								into(params[i].t, args[i]);
					default:
				}
			case TBinop(OpAssign, l, r):
				into(l.t, r);
			case TArrayDecl(values):
				for (v in values)
					if (isScoped(v.t))
						report('a scoped value in an Array', v.pos);
			case TObjectDecl(fields):
				for (f in fields)
					if (isScoped(f.expr.t))
						report('${f.name}: a scoped value in an anonymous structure', f.expr.pos);
			case TNew(_.get() => cl, params, _):
				if (cl.pack.join(".") != "hxmc.scoped" && params.exists(p -> isScoped(p) || holds(p)))
					report('a scoped value inside a GC type', e.pos);
			case TCast(inner, null) if (opaque(e.t)):
				into(e.t, inner);
			default:
		}
		e.iter(x -> walk(x, locals));
	}

	// an iteration of a loop the Scoped macro made a scope of: its body starts
	// with `var __iteration = Memory.restore(...)` (a loop over a constant range is
	// unrolled while typing: its iterations are such blocks one after another)
	static function scopedLoop(body:TypedExpr):Bool {
		return switch body.expr {
			case TBlock(el) if (el.length > 0):
				switch el[0].expr {
					case TVar({name: "__iteration"}, _): true;
					default: false;
				}
			default: false;
		}
	}

	// assignments, in the loop's body, of values made in an iteration to
	// variables declared outside the loop
	static function loopEscapes(body:TypedExpr) {
		var inside = new Map<Int, Bool>();
		function declared(e:TypedExpr) {
			switch e.expr {
				case TVar(v, _): inside.set(v.id, true);
				case TFunction(_): return;
				default:
			}
			e.iter(declared);
		}
		declared(body);
		// (a value that lives outside the iteration: a variable from outside,
		// or an element, field or reference of one)
		function outside(e:TypedExpr):Bool {
			return switch e.expr {
				case TLocal(v): !inside.exists(v.id);
				case TConst(TNull): true;
				case TParenthesis(x) | TCast(x, _) | TMeta(_, x): outside(x);
				case TField(x, _): outside(x);
				case TArray(x, _): outside(x);
				case TCall({expr: TField(_, FStatic(_.get() => {pack: ["hxmc", "scoped"]}, _.get() => m))}, args)
					if (args.length > 0 && (m.name == "ref" || StringTools.startsWith(m.name, "get"))):
					outside(args[0]);
				default: false;
			}
		}
		function find(e:TypedExpr) {
			switch e.expr {
				case TBinop(OpAssign, {expr: TLocal(v)}, r) if (!inside.exists(v.id) && isScoped(v.t) && !outside(r)):
					report('${v.name}: a value made in a loop iteration kept in a variable from outside the loop (its memory is freed when the next iteration starts)', e.pos);
				case TFunction(_):
					return;
				default:
			}
			e.iter(find);
		}
		find(body);
	}
	#end
}
