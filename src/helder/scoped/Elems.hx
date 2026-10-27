package helder.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.Tools;
#end

// Struct elements of Grows and writers with their size a constant: next()
// zeroes a new element with a few stores, push(v) copies one with loads and
// stores, where the generic code reads the stride from the header and calls
// memset or memmove. (A struct's size is its Struct.build metadata; for an
// element type not known here, the generic code.)
class Elems {
	#if macro
	// the size of a struct element type, or null
	public static function structSize(t:Type):Null<Int> {
		return switch t.follow() {
			case TAbstract(_.get() => a, _) if (a.meta.has(":structLayout")):
				switch a.meta.extract(":structLayout")[0].params[0].expr {
					case EConst(CInt(v)): Std.parseInt(v);
					default: null;
				}
			default: null;
		}
	}

	// the element type of a Grow or GrowWriter expression
	static function element(e:Expr):Null<Type> {
		return switch Context.follow(Context.typeof(e)) {
			case TAbstract(_.get() => {pack: ["helder", "scoped"], name: "Grow" | "GrowWriter"}, [t]): t;
			default: null;
		}
	}

	// (the largest size done with stores rather than a call)
	static inline var INLINE = 64;

	// stores of zero over n bytes at the address in local `a`
	static function zeroes(a:Expr, n:Int):Array<Expr> {
		var out = [], k = 0;
		while (k + 4 <= n) {
			out.push(macro helder.scoped.Memory.setI32($a + $v{k}, 0));
			k += 4;
		}
		while (k < n) {
			out.push(macro helder.scoped.Memory.setU8($a + $v{k}, 0));
			k++;
		}
		return out;
	}

	// copies of n bytes from local `s` to local `d`
	static function copies(d:Expr, s:Expr, n:Int):Array<Expr> {
		var out = [], k = 0;
		while (k + 4 <= n) {
			out.push(macro helder.scoped.Memory.setI32($d + $v{k}, helder.scoped.Memory.getI32($s + $v{k})));
			k += 4;
		}
		while (k < n) {
			out.push(macro helder.scoped.Memory.setU8($d + $v{k}, helder.scoped.Memory.getU8($s + $v{k})));
			k++;
		}
		return out;
	}

	public static function next(g:Expr):Expr {
		var t = element(g);
		var size = t == null ? null : structSize(t);
		if (size == null)
			return macro ($g).nextAny();
		var ct = Context.toComplexType(t);
		var body = size <= INLINE ? zeroes(macro __a, size) : [macro helder.scoped.Memory.zero(__a, $v{size})];
		return macro {
			var __a:Int = ($g).room($v{size});
			$b{body};
			(cast __a : $ct);
		};
	}

	public static function push(g:Expr, v:Expr):Expr {
		var t = element(g);
		var size = t == null ? null : structSize(t);
		if (size == null)
			return macro ($g).pushAny($v);
		var body = size <= INLINE ? copies(macro __d, macro __s, size) : [macro helder.scoped.Memory.copy(__d, __s, $v{size})];
		return macro {
			var __s:Int = cast $v;
			var __g = $g;
			var __d:Int = __g.room($v{size});
			$b{body};
			__g.length;
		};
	}
	#end
}
