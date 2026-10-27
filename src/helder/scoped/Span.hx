package helder.scoped;

// A run of bytes in scoped memory as a value: its address and length, in
// locals or in a struct's field, with no header. What a list of words, the
// keys of a table or the tokens of a parse keep (a Slice is a header on the
// scope's stack; a million of them would be a million headers). Indexes are
// checked against the length. It views memory it does not own: it is valid
// while what it was taken from is, and the checker keeps it out of the GC
// heap as it does a Slice.
@:build(helder.scoped.Value.build())
class Span {
	var at:Int;
	var length:Int;

	public static inline function of(s:Str):Span
		return new Span(s.data(), s.length);

	public static inline function ofSlice(s:Slice<U8>):Span
		return new Span(s.data(), s.length);

	public inline function get(i:Int):Int {
		if (i < 0 || i >= length)
			Memory.outOfRange(i, length);
		return Memory.getU8(at + i);
	}

	// the bytes pos .. pos + n - 1
	public inline function sub(pos:Int, n:Int):Span {
		if (pos < 0 || n < 0 || pos > length - n)
			Memory.outOfRange(pos + n, length);
		return new Span(at + pos, n);
	}

	public inline function equals(o:Span):Bool
		return length == o.length && Memory.compare(at, o.at, length) == 0;

	// FNV-1a, as Str.hash
	public inline function hash():Int {
		var h:haxe.Int32 = 0x811C9DC5;
		for (i in 0...length)
			h = (h ^ Memory.getU8(at + i)) * 0x01000193;
		return h;
	}

	public inline function toString():String
		return Memory.string(at, length);
}
