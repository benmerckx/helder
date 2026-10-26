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
				var l = "__loop" + counter++;
				var b = rewrite(body, mark);
				var loop = {expr: EWhile(rewrite(cond, mark), macro {hxmc.scoped.Scope.rewind($i{l}); $b;}, normal), pos: e.pos};
				macro @:pos(e.pos) {
					var $l = hxmc.scoped.Scope.enter();
					$loop;
					hxmc.scoped.Scope.exit($i{l});
				};
			case EFor(it, body):
				var l = "__loop" + counter++;
				var b = rewrite(body, mark);
				var loop = {expr: EFor(rewrite(it, mark), macro {hxmc.scoped.Scope.rewind($i{l}); $b;}), pos: e.pos};
				macro @:pos(e.pos) {
					var $l = hxmc.scoped.Scope.enter();
					$loop;
					hxmc.scoped.Scope.exit($i{l});
				};
			default:
				e.map(x -> rewrite(x, mark));
		}
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
