package hxmc.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
using Lambda;
#end

// Scopes for functions, as hxmc's compiler made them for scoped code:
//
//   @:build(hxmc.scoped.Scoped.build())
//   class Physics {
//     @:scoped static function step(ps:Slice<Particle>, dt:Float) { ... }
//   }
//
// (`@:scoped` on the class: every function of it.)
//
// - A function marks its scope on entry and leaves it at every return, so
//   what it allocated is freed. A function whose result is a scoped value
//   does not: its memory, the result included, belongs to the caller's
//   scope. An unannotated return type counts as scoped when the function
//   returns a value.
// - Each loop's iteration is a scope: what an iteration allocated is freed
//   when the next starts, and after the loop.
// - An exception leaves the memory to the enclosing scope (a mark is left
//   with the marks around it), so nothing is freed early; `Scope.run` at the
//   entry points from ordinary code frees it there.
// - Loops over a slice: in `for (i in 0...s.length)`, where neither s nor i is
//   assigned, declared again or captured in the body, `s[i]` reads the
//   elements through a view (Loops.view: the data and stride in locals) with
//   no checks, i being in range by construction.
class Scoped {
	#if macro
	static var counter = 0;

	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var cls = Context.getLocalClass();
		var all = cls != null && cls.get().meta.has(":scoped");
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null && (all || f.meta.exists(m -> m.name == ":scoped"))):
					fn.expr = wrap(fn, f.pos);
				default:
			}
		return fields;
	}

	static function wrap(fn:Function, pos:Position):Expr {
		var keep = returnsScoped(fn, pos);
		var mark = "__scope" + counter++;
		var body = rewrite(fn.expr, keep ? null : mark);
		if (keep)
			return body;
		return macro @:pos(pos) {
			var $mark = hxmc.scoped.Scope.enter();
			$body;
			hxmc.scoped.Scope.exit($i{mark});
		};
	}

	// (mark: the function's, left at each return; null: kept for the caller)
	static function rewrite(e:Expr, mark:Null<String>):Expr {
		return switch e.expr {
			case EFunction(_, _):
				e;
			case EReturn(null) if (mark != null):
				macro @:pos(e.pos) {
					hxmc.scoped.Scope.exit($i{mark});
					return;
				};
			case EReturn(v) if (mark != null):
				var r = rewrite(v, mark);
				macro @:pos(e.pos) {
					var __result = $r;
					hxmc.scoped.Scope.exit($i{mark});
					return __result;
				};
			case EWhile(cond, body, normal):
				var l = "__loop" + counter++, c = "__claims" + counter++;
				var b = rewrite(body, mark);
				var loop = {expr: EWhile(rewrite(cond, mark), macro {hxmc.scoped.Memory.restore($i{l}, $i{c}); $b;}, normal), pos: e.pos};
				macro @:pos(e.pos) {
					var $l = hxmc.scoped.Memory.top(), $c = hxmc.scoped.Memory.claims();
					$loop;
					hxmc.scoped.Memory.restore($i{l}, $i{c});
				};
			case EFor(it, body):
				var l = "__loop" + counter++, c = "__claims" + counter++;
				var view = sliceLoop(it, body);
				if (view != null)
					body = view.body;
				var b = rewrite(body, mark);
				var loop = {expr: EFor(rewrite(it, mark), macro {hxmc.scoped.Memory.restore($i{l}, $i{c}); $b;}), pos: e.pos};
				var out = macro @:pos(e.pos) {
					var $l = hxmc.scoped.Memory.top(), $c = hxmc.scoped.Memory.claims();
					$loop;
					hxmc.scoped.Memory.restore($i{l}, $i{c});
				};
				if (view == null)
					out;
				else {
					var vn = view.name, vs = view.slice;
					macro @:pos(e.pos) {
						var $vn = hxmc.scoped.Loops.view($i{vs});
						$out;
					};
				}
			default:
				e.map(x -> rewrite(x, mark));
		}
	}

	// `for (i in 0...s.length)` whose body uses s[i] and neither assigns,
	// declares nor captures s or i: the body with s[i] read through a view
	static function sliceLoop(it:Expr, body:Expr):Null<{name:String, slice:String, body:Expr}> {
		var i:String, s:String;
		switch it.expr {
			case EBinop(OpIn, {expr: EConst(CIdent(iv))}, {expr: EBinop(OpInterval, {expr: EConst(CInt("0", _))}, {expr: EField({expr: EConst(CIdent(sv))}, "length", _)})}):
				i = iv;
				s = sv;
			default:
				return null;
		}
		var safe = true, used = false;
		function names(e:Expr):Bool
			return switch e.expr {
				case EConst(CIdent(n)): n == i || n == s;
				default: false;
			}
		function mentions(e:Expr):Bool {
			var found = false;
			function find(x:Expr)
				switch x.expr {
					case EConst(CIdent(n)) if (n == i || n == s): found = true;
					default: x.iter(find);
				}
			find(e);
			return found;
		}
		function check(e:Expr) {
			switch e.expr {
				case EBinop(OpAssign | OpAssignOp(_), l, _) if (names(l)):
					safe = false;
				case EUnop(OpIncrement | OpDecrement, _, x) if (names(x)):
					safe = false;
				case EVars(vs):
					for (v in vs)
						if (v.name == i || v.name == s)
							safe = false;
				case EFunction(_, _):
					if (mentions(e))
						safe = false;
					return;
				case EArray({expr: EConst(CIdent(a))}, {expr: EConst(CIdent(b))}) if (a == s && b == i):
					used = true;
				default:
			}
			e.iter(check);
		}
		check(body);
		if (!safe || !used)
			return null;
		var name = "__view" + counter++;
		function replace(e:Expr):Expr
			return switch e.expr {
				case EArray({expr: EConst(CIdent(a))}, {expr: EConst(CIdent(b))}) if (a == s && b == i):
					{expr: EArray(macro $i{name}, macro $i{i}), pos: e.pos};
				case EFunction(_, _): e;
				default: e.map(replace);
			}
		return {name: name, slice: s, body: replace(body)};
	}

	static function returnsScoped(fn:Function, pos:Position):Bool {
		if (fn.ret == null)
			return returnsValue(fn.expr);
		switch fn.ret {
			case TPath({pack: [], name: "Void" | "Int" | "Float" | "Bool" | "String" | "Dynamic"}):
				return false;
			default:
		}
		return try isScoped(Context.resolveType(fn.ret, pos)) catch (_:Dynamic) true;
	}

	static function returnsValue(e:Expr):Bool {
		var found = false;
		function walk(e:Expr)
			switch e.expr {
				case EFunction(_, _):
				case EReturn(v) if (v != null): found = true;
				default: e.iter(walk);
			}
		walk(e);
		return found;
	}

	// an abstract over hxmc.scoped.Addr (Slice, Grow, Str, Ref, the structs)
	public static function isScoped(t:Type):Bool {
		return switch t {
			case TMono(r): r.get() != null && isScoped(r.get());
			case TLazy(f): isScoped(f());
			case TType(_.get() => td, params): isScoped(td.type.applyTypeParameters(td.params, params));
			case TAbstract(_.get() => a, _):
				switch a.type {
					case TAbstract(_.get() => {pack: ["hxmc", "scoped"], name: "Addr"}, _): true;
					default: false;
				}
			default: false;
		}
	}
	#end
}
