package hxmc.scoped;

// An address in scoped memory: the buffer in the top bits, the byte
// offset in that buffer in the low 26 (hxmc.scoped.Memory). Every scoped
// type (Slice, Grow, Str, Ref, the structs of Struct.build) is an abstract
// over it: that is what the checker and the scope macros recognize.
abstract Addr(Int) from Int to Int {
	public inline function add(bytes:Int):Addr
		return this + bytes;
}
