package hxmc.scoped;

import hxmc.scoped.Memory.*;

// A grow-only array in scoped memory. Its elements live in a buffer it
// claims for itself, so growing it never moves anything else, and a
// reference to an element (`ref(i)`, `add()`) stays valid as long as the
// Grow does. It is freed with the scope that made it, all at once.
//
// The value is the address of its header (buffer, length, stride), so a
// Grow is passed by reference. Element types as for Slice. Scope.grow(T)
// makes one.
@:using(hxmc.scoped.Grow.GrowAnyOps, hxmc.scoped.Grow.GrowBoolOps, hxmc.scoped.Grow.GrowFloatOps, hxmc.scoped.Grow.GrowIntOps, hxmc.scoped.Grow.GrowU8Ops)
abstract Grow<T>(Addr) to Addr {
	static inline var BUFFER = 0;
	static inline var LEN = 4;
	static inline var STRIDE = 8;
	static inline var MAGIC = 12;
	static inline var HEADER = 16;

	inline function new(h:Addr)
		this = h;

	// an empty Grow of elements of `stride` bytes, in the current scope
	public static function make<T>(stride:Int):Grow<T> {
		var h = Memory.alloc(HEADER);
		setI32(h, Memory.claim());
		setI32(h + STRIDE, stride);
		setI32(h + MAGIC, Header.MAGIC);
		return new Grow(h);
	}

	public var length(get, never):Int;

	inline function get_length():Int
		return getI32(Header.check(this, MAGIC) + LEN);

	@:noCompletion public inline function stride():Int
		return getI32(this + STRIDE);

	@:noCompletion public inline function base():Addr
		return getI32(Header.check(this, MAGIC)) << SHIFT;

	// a new element at the end, zeroed: its address
	@:noCompletion public inline function add():Addr {
		var a = room();
		Memory.zero(a, stride());
		return a;
	}

	// a new element at the end, not zeroed (for pushes, which write all of it)
	@:noCompletion public inline function room():Addr {
		var n = length, k = stride();
		var b = getI32(this);
		var end = (n + 1) * k;
		if (end > Memory.capacity(b))
			Memory.reserve(b, end);
		setI32(this + LEN, n + 1);
		return (b << SHIFT) + n * k;
	}

	@:noCompletion public inline function at(i:Int, k:Int):Int {
		var n = length;
		if (i < 0 || i >= n)
			outOfRange(i, n);
		return base() + i * k;
	}

	// (U8 converts to Int: its accessors come first, the first one that fits is taken)
	@:arrayAccess @:impl static inline function getByte(g:Grow<U8>, i:Int):U8
		return getU8(g.at(i, 1));

	@:arrayAccess @:impl static inline function setByte(g:Grow<U8>, i:Int, v:U8):U8 {
		setU8(g.at(i, 1), v);
		return v;
	}

	@:arrayAccess @:impl static inline function getInt(g:Grow<Int>, i:Int):Int
		return getI32(g.at(i, 4));

	@:arrayAccess @:impl static inline function setInt(g:Grow<Int>, i:Int, v:Int):Int {
		setI32(g.at(i, 4), v);
		return v;
	}

	@:arrayAccess @:impl static inline function getFloat(g:Grow<Float>, i:Int):Float
		return getF64(g.at(i, 8));

	@:arrayAccess @:impl static inline function setFloat(g:Grow<Float>, i:Int, v:Float):Float {
		setF64(g.at(i, 8), v);
		return v;
	}

	@:arrayAccess @:impl static inline function getBool(g:Grow<Bool>, i:Int):Bool
		return getU8(g.at(i, 1)) != 0;

	@:arrayAccess @:impl static inline function setBool(g:Grow<Bool>, i:Int, v:Bool):Bool {
		setU8(g.at(i, 1), v ? 1 : 0);
		return v;
	}

	@:arrayAccess inline function getStruct(i:Int):T
		return cast at(i, stride());

	@:arrayAccess inline function setStruct(i:Int, v:T):T {
		var k = stride();
		copy(at(i, k), cast v, k);
		return v;
	}

	// a reference to element i
	public inline function ref(i:Int):Ref<T>
		return cast at(i, stride());

	// drops the elements from n on (n <= length)
	public function truncate(n:Int) {
		if (n < 0 || n > length)
			outOfRange(n, length);
		setI32(this + LEN, n);
	}

	// the elements so far, as a view (valid until the Grow ends; growing it
	// later does not move them)
	public inline function slice():Slice<T>
		return Slice.view(base(), length, stride());
}

// (the elements' kinds: the last one listed in @:using is tried first)
class GrowIntOps {
	public static inline function push(g:Grow<Int>, v:Int):Int {
		setI32(g.room(), v);
		return g.length;
	}

	public static inline function iterator(g:Grow<Int>):Slice.SliceIntIterator
		return new Slice.SliceIntIterator(g.base(), g.length);
}

class GrowFloatOps {
	public static inline function push(g:Grow<Float>, v:Float):Int {
		setF64(g.room(), v);
		return g.length;
	}

	public static inline function iterator(g:Grow<Float>):Slice.SliceFloatIterator
		return new Slice.SliceFloatIterator(g.base(), g.length);
}

class GrowBoolOps {
	public static inline function push(g:Grow<Bool>, v:Bool):Int {
		setU8(g.room(), v ? 1 : 0);
		return g.length;
	}
}

class GrowU8Ops {
	public static inline function push(g:Grow<U8>, v:U8):Int {
		setU8(g.room(), v);
		return g.length;
	}

	public static inline function iterator(g:Grow<U8>):Slice.SliceU8Iterator
		return new Slice.SliceU8Iterator(g.base(), g.length);
}

class GrowAnyOps {
	// appends a copy of the struct v
	public static inline function push<T>(g:Grow<T>, v:T):Int {
		copy(g.room(), cast v, g.stride());
		return g.length;
	}

	// appends a zeroed struct: the new element, in place
	public static inline function next<T>(g:Grow<T>):T
		return cast g.add();

	public static inline function iterator<T>(g:Grow<T>):Slice.SliceStructIterator<T>
		return new Slice.SliceStructIterator(g.base(), g.length, g.stride());
}
