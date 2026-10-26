package hxmc.scoped;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;

using haxe.macro.Tools;
#end

// The current scope: what Scope.slice, Scope.grow, Str.of and `new` of a
// struct allocate in. Scopes are marks (Memory): `@:scoped` functions get
// theirs from the Scoped build macro, and `Scope.run` makes one around a
// function anywhere else.
class Scope {
	// a mark: what is allocated after it is freed by exit(mark)
	public static inline function enter():Int
		return Memory.enter();

	public static inline function exit(mark:Int)
		Memory.exit(mark);

	// frees what was allocated since mark, which stays (a loop's iteration)
	public static inline function rewind(mark:Int)
		Memory.rewind(mark);

	// f in a scope of its own, freed when f returns or throws. f's result
	// may not be a scoped value (it would be freed with the scope).
	public static function run<R>(f:() -> R):R {
		var mark = enter();
		try {
			var r = f();
			exit(mark);
			return r;
		} catch (e:haxe.Exception) {
			exit(mark);
			throw e;
		}
	}

	// the bytes of scoped memory in use (not counting Grows' elements), and
	// the Grows live
	public static inline function used():Int
		return Memory.used();

	public static inline function grows():Int
		return Memory.grows();

	// n zeroed elements of T in the current scope:
	// `var ps = Scope.slice(Particle, 100);`
	public static macro function slice(type:Expr, n:Expr):Expr {
		var ct = complexType(type);
		var size = sizeOf(type);
		return macro(hxmc.scoped.Slice.alloc($n, $size) : hxmc.scoped.Slice<$ct>);
	}

	// an empty Grow of T in the current scope: `var g = Scope.grow(Int);`
	public static macro function grow(type:Expr):Expr {
		var ct = complexType(type);
		var size = sizeOf(type);
		return macro(hxmc.scoped.Grow.make($size) : hxmc.scoped.Grow<$ct>);
	}

	// the size in bytes of one T
	public static macro function size(type:Expr):Expr
		return sizeOf(type);

	#if macro
	static function complexType(type:Expr):ComplexType {
		var path = type.toString();
		var parts = path.split(".");
		var name = parts.pop();
		return TPath({pack: parts, name: name});
	}

	static function sizeOf(type:Expr):Expr {
		return switch type.toString() {
			case "Int": macro 4;
			case "Float": macro 8;
			case "Bool" | "U8" | "hxmc.scoped.U8": macro 1;
			default: macro $type.SIZE;
		}
	}
	#end
}
