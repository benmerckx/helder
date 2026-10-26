package hxmc.scoped;

// A 32-bit float as an element type (Slice<F32>, Grow<F32>, a struct's or a
// value's field): stored in 4 bytes, read as a Float. A Float written to one
// is rounded to f32 when stored; arithmetic is the target's Float. (Half the
// memory of a Float: for data a loop streams through.)
abstract F32(Float) {
	@:from static inline function ofFloat(v:Float):F32
		return cast v;

	@:to inline function toFloat():Float
		return this;
}
