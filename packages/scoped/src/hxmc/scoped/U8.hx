package hxmc.scoped;

// A byte as an element type (Slice<U8>, Grow<U8>, a struct's field): stored in
// one byte, read as an Int from 0 to 255. (Conversions by functions, not
// `from Int to Int`: with those, Slice<U8> and Slice<Int> would unify and an
// accessor of one could be picked for the other.)
abstract U8(Int) {
	@:from static inline function ofInt(v:Int):U8
		return cast v;

	@:to inline function toInt():Int
		return this;
}
