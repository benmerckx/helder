package hxmc.scoped;

// A byte as an element type (Slice<U8>, Grow<U8>, a struct's field): stored in
// one byte, read as an Int from 0 to 255; arithmetic and comparisons work as
// on that Int (`b * 2`, `c >= '0'.code`). (Conversions by functions, not
// `from Int to Int`: with those, Slice<U8> and Slice<Int> would unify and an
// accessor of one could be picked for the other.)
abstract U8(Int) {
	@:from static inline function ofInt(v:Int):U8
		return cast v;

	@:to inline function toInt():Int
		return this;

	// (arithmetic and comparisons with Ints and U8s, as Ints)
	@:op(A + B) @:commutative static inline function addI(a:U8, b:Int):Int
		return (a : Int) + b;

	@:op(A + B) static inline function addU(a:U8, b:U8):Int
		return (a : Int) + (b : Int);

	@:op(A - B) static inline function subI(a:U8, b:Int):Int
		return (a : Int) - b;

	@:op(A - B) static inline function subR(a:Int, b:U8):Int
		return a - (b : Int);

	@:op(A - B) static inline function subU(a:U8, b:U8):Int
		return (a : Int) - (b : Int);

	@:op(A * B) @:commutative static inline function mulI(a:U8, b:Int):Int
		return (a : Int) * b;

	@:op(A * B) static inline function mulU(a:U8, b:U8):Int
		return (a : Int) * (b : Int);

	@:op(A & B) @:commutative static inline function andI(a:U8, b:Int):Int
		return (a : Int) & b;

	@:op(A & B) static inline function andU(a:U8, b:U8):Int
		return (a : Int) & (b : Int);

	@:op(A | B) @:commutative static inline function orI(a:U8, b:Int):Int
		return (a : Int) | b;

	@:op(A | B) static inline function orU(a:U8, b:U8):Int
		return (a : Int) | (b : Int);

	@:op(A ^ B) @:commutative static inline function xorI(a:U8, b:Int):Int
		return (a : Int) ^ b;

	@:op(A ^ B) static inline function xorU(a:U8, b:U8):Int
		return (a : Int) ^ (b : Int);

	@:op(A % B) static inline function modI(a:U8, b:Int):Int
		return (a : Int) % b;

	@:op(A % B) static inline function modR(a:Int, b:U8):Int
		return a % (b : Int);

	@:op(A % B) static inline function modU(a:U8, b:U8):Int
		return (a : Int) % (b : Int);

	@:op(A << B) static inline function shlI(a:U8, b:Int):Int
		return (a : Int) << b;

	@:op(A << B) static inline function shlR(a:Int, b:U8):Int
		return a << (b : Int);

	@:op(A << B) static inline function shlU(a:U8, b:U8):Int
		return (a : Int) << (b : Int);

	@:op(A >> B) static inline function shrI(a:U8, b:Int):Int
		return (a : Int) >> b;

	@:op(A >> B) static inline function shrR(a:Int, b:U8):Int
		return a >> (b : Int);

	@:op(A >> B) static inline function shrU(a:U8, b:U8):Int
		return (a : Int) >> (b : Int);

	@:op(A >>> B) static inline function ushrI(a:U8, b:Int):Int
		return (a : Int) >>> b;

	@:op(A >>> B) static inline function ushrR(a:Int, b:U8):Int
		return a >>> (b : Int);

	@:op(A >>> B) static inline function ushrU(a:U8, b:U8):Int
		return (a : Int) >>> (b : Int);

	@:op(A == B) @:commutative static inline function eqI(a:U8, b:Int):Bool
		return (a : Int) == b;

	@:op(A == B) static inline function eqU(a:U8, b:U8):Bool
		return (a : Int) == (b : Int);

	@:op(A != B) @:commutative static inline function neI(a:U8, b:Int):Bool
		return (a : Int) != b;

	@:op(A != B) static inline function neU(a:U8, b:U8):Bool
		return (a : Int) != (b : Int);

	@:op(A < B) static inline function ltI(a:U8, b:Int):Bool
		return (a : Int) < b;

	@:op(A < B) static inline function ltR(a:Int, b:U8):Bool
		return a < (b : Int);

	@:op(A < B) static inline function ltU(a:U8, b:U8):Bool
		return (a : Int) < (b : Int);

	@:op(A > B) static inline function gtI(a:U8, b:Int):Bool
		return (a : Int) > b;

	@:op(A > B) static inline function gtR(a:Int, b:U8):Bool
		return a > (b : Int);

	@:op(A > B) static inline function gtU(a:U8, b:U8):Bool
		return (a : Int) > (b : Int);

	@:op(A <= B) static inline function leI(a:U8, b:Int):Bool
		return (a : Int) <= b;

	@:op(A <= B) static inline function leR(a:Int, b:U8):Bool
		return a <= (b : Int);

	@:op(A <= B) static inline function leU(a:U8, b:U8):Bool
		return (a : Int) <= (b : Int);

	@:op(A >= B) static inline function geI(a:U8, b:Int):Bool
		return (a : Int) >= b;

	@:op(A >= B) static inline function geR(a:Int, b:U8):Bool
		return a >= (b : Int);

	@:op(A >= B) static inline function geU(a:U8, b:U8):Bool
		return (a : Int) >= (b : Int);
}
