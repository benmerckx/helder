package helder.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import helder.scoped.Scoped.isScoped;

using haxe.macro.Tools;
using Lambda;
#end

// The checker: a scoped value never reaches the GC heap, where it could
// outlive its scope. `--macro helder.scoped.Check.enable()` runs it after
// typing (opt-in: a build that uses scoped adds it). An error for:
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
		var std = stdRoots();
		for (t in types)
			switch t {
				case TClassDecl(_.get() => c):
					if (c.pack.length >= 2 && c.pack[0] == "helder" && c.pack[1] == "scoped")
						continue;
					// (the standard library's classes cannot name a scoped type: what
					// they are given is checked where it is given; 40% of the time)
					var file = haxe.io.Path.normalize(sys.FileSystem.absolutePath(Context.getPosInfos(c.pos).file));
					if (std.exists(r -> StringTools.startsWith(file, r)))
						continue;
					var impl = c.kind.match(KAbstractImpl(_));
					for (f in c.fields.get().concat(c.statics.get()))
						checkField(f, impl);
					if (c.constructor != null)
						checkField(c.constructor.get(), impl);
				default:
			}
	}

	// (the class paths holding a standard library: Std.hx at their root)
	static function stdRoots():Array<String>
		return [
			for (cp in Context.getClassPath())
				if (cp != "" && sys.FileSystem.exists(haxe.io.Path.join([cp, "Std.hx"])))
					haxe.io.Path.addTrailingSlash(haxe.io.Path.normalize(sys.FileSystem.absolutePath(cp)))
		];

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

	// a scoped value inside a GC type (not the type itself); a typedef met
	// twice inside itself (a recursive one: typedef Tree = {children:Array<Tree>})
	// holds nothing more below that. (Types by their Refs' paths: get() makes
	// the whole type again on every call.)
	static function holds(t:Type, ?seen:Array<String>):Bool {
		function inside(p:Type)
			return isScoped(p) || holds(p, seen);
		return switch t {
			case TMono(r): r.get() != null && holds(r.get(), seen);
			case TLazy(f): holds(f(), seen);
			case TType(td, params):
				var key = td.toString();
				if (seen == null) seen = [];
				if (seen.filter(k -> k == key).length >= 2) return false;
				seen.push(key);
				var d = td.get();
				var r = holds(d.type.applyTypeParameters(d.params, params), seen);
				seen.pop();
				r;
			case TInst(_, []) | TEnum(_, []) | TAbstract(_, []): false;
			// (the package's own classes: inline iterators, which do not escape)
			case TInst(c, _) if (StringTools.startsWith(c.toString(), "helder.scoped.")): false;
			case TInst(_, params): params.exists(inside);
			case TEnum(_, params): params.exists(inside);
			case TAbstract(_, params) if (isScoped(t)): false;
			// (the package's own views: locals of the Scoped macro's loops)
			case TAbstract(a, _) if (StringTools.startsWith(a.toString(), "helder.scoped.")): false;
			case TAbstract(_, params): params.exists(inside);
			case TAnonymous(_.get() => a): a.fields.exists(f -> inside(f.type));
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
				if (cl.pack.join(".") != "helder.scoped" && params.exists(p -> isScoped(p) || holds(p)))
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

	// whether a function's body may allocate in the scope (no body: it may)
	static function bodyAllocates(f:ClassField):Bool {
		var e = f.expr();
		return switch e {
			case null: true;
			case {expr: TFunction(fn)}: Loops.mayAllocate(fn.expr);
			default: true;
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
		function readsOutside(e:TypedExpr):Bool {
			var ok = true;
			function walk(x:TypedExpr) {
				switch x.expr {
					case TLocal(v) if (inside.exists(v.id) && isScoped(v.t)):
						ok = false;
					default:
				}
				if (ok)
					x.iter(walk);
			}
			walk(e);
			return ok;
		}
		// (a value that lives outside the iteration: a variable from outside,
		// or an element, field or reference of one, or an element added to a
		// Grow from outside: it lives as long as the Grow)
		function outside(e:TypedExpr):Bool {
			return switch e.expr {
				case TLocal(v): !inside.exists(v.id);
				case TConst(TNull): true;
				case TParenthesis(x) | TCast(x, _) | TMeta(_, x): outside(x);
				case TField(x, _): outside(x);
				case TArray(x, _): outside(x);
				// (what allocates nothing in the scope can only give memory that
				// exists already: a Grow's new element, an element of a slice; it
				// is outside when every scoped value it reads is)
				case TBlock(_): !Loops.mayAllocate(e) && readsOutside(e);
				case TCall({expr: TField(_, FStatic(_, _.get() => f))}, args) if (!bodyAllocates(f)):
					args.foreach(a -> !isScoped(a.t) || outside(a));
				case TCall({expr: TField(_, FStatic(_.get() => {pack: ["helder", "scoped"]}, _.get() => m))}, args)
					if (args.length > 0 && (m.name == "ref" || StringTools.startsWith(m.name, "get") || ["next", "nextAny", "add", "room", "reserve", "at"].contains(m.name))):
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
