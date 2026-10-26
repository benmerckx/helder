package hxmc.scoped;

import hxmc.scoped.Memory.*;

// A view of n elements of T in scoped memory, rooted at what it views (its
// scope, or the Grow it was taken from). The value is the address of a
// header in the scope that made the view (data, length, stride), so a Slice
// is one Int: copying one copies the view, not the elements.
//
// T is Int (4 bytes), Float (8), Bool and U8 (1), or a struct of
// Struct.build (stored in place: `s[i]` is the element itself, `s[i].x = 1`
// writes into the slice; `s[i] = p` copies p into it). Indexes are checked.
//
// Scope.slice(T, n) makes one (zeroed, in the current scope).
@:using(hxmc.scoped.Slice.SliceAnyOps, hxmc.scoped.Slice.SliceBoolOps, hxmc.scoped.Slice.SliceFloatOps, hxmc.scoped.Slice.SliceIntOps, hxmc.scoped.Slice.SliceU8Ops, hxmc.scoped.Slice.SliceF32Ops)
abstract Slice<T>(Addr) to Addr {
	static inline var DATA = 0;
	static inline var LEN = 4;
	static inline var STRIDE = 8;
	static inline var MAGIC = 12;
	static inline var HEADER = 16;

	inline function new(h:Addr)
		this = h;

	// n zeroed elements of `stride` bytes in the current scope
	public static function alloc<T>(n:Int, stride:Int):Slice<T> {
		if (n < 0)
			fail("negative length");
		return view(Memory.alloc(n * stride), n, stride);
	}

	// a view of n elements at data (the trusted layer's: Grow.slice, Str)
	@:noCompletion public static function view<T>(data:Addr, n:Int, stride:Int):Slice<T> {
		var h = Memory.alloc(HEADER);
		setI32(h, data);
		setI32(h + LEN, n);
		setI32(h + STRIDE, stride);
		setI32(h + MAGIC, Header.MAGIC);
		return new Slice(h);
	}

	public var length(get, never):Int;

	inline function get_length():Int
		return getI32(Header.check(this, MAGIC) + LEN);

	@:noCompletion public inline function data():Addr
		return getI32(Header.check(this, MAGIC));

	@:noCompletion public inline function stride():Int
		return getI32(this + STRIDE);

	// the address of element i (k: its size, a constant for scalars)
	// the address of bytes i .. i + n - 1, checked against the length (for
	// multi-byte reads of a byte array)
	@:noCompletion public inline function atBytes(i:Int, n:Int):Int {
		var len = length;
		if (i < 0 || i > len - n)
			outOfRange(i, len);
		return getI32(this) + i;
	}

	@:noCompletion public inline function at(i:Int, k:Int):Int {
		var n = length;
		if (i < 0 || i >= n)
			outOfRange(i, n);
		return getI32(this) + i * k;
	}

	@:arrayAccess @:impl static inline function getF32(s:Slice<F32>, i:Int):Float
		return Memory.getF32(s.at(i, 4));

	@:arrayAccess @:impl static inline function setF32(s:Slice<F32>, i:Int, x:Float):Float {
		Memory.setF32(s.at(i, 4), x);
		return x;
	}

	// (U8 converts to Int: its accessors come first, the first one that fits is taken)
	@:arrayAccess @:impl static inline function getByte(s:Slice<U8>, i:Int):U8
		return getU8(s.at(i, 1));

	@:arrayAccess @:impl static inline function setByte(s:Slice<U8>, i:Int, v:U8):U8 {
		setU8(s.at(i, 1), v);
		return v;
	}

	@:arrayAccess @:impl static inline function getInt(s:Slice<Int>, i:Int):Int
		return getI32(s.at(i, 4));

	@:arrayAccess @:impl static inline function setInt(s:Slice<Int>, i:Int, v:Int):Int {
		setI32(s.at(i, 4), v);
		return v;
	}

	@:arrayAccess @:impl static inline function getFloat(s:Slice<Float>, i:Int):Float
		return getF64(s.at(i, 8));

	@:arrayAccess @:impl static inline function setFloat(s:Slice<Float>, i:Int, v:Float):Float {
		setF64(s.at(i, 8), v);
		return v;
	}

	@:arrayAccess @:impl static inline function getBool(s:Slice<Bool>, i:Int):Bool
		return getU8(s.at(i, 1)) != 0;

	@:arrayAccess @:impl static inline function setBool(s:Slice<Bool>, i:Int, v:Bool):Bool {
		setU8(s.at(i, 1), v ? 1 : 0);
		return v;
	}

	// a struct element, in place
	@:arrayAccess inline function getStruct(i:Int):T
		return cast at(i, stride());

	// copies the struct v into element i
	@:arrayAccess inline function setStruct(i:Int, v:T):T {
		var k = stride();
		copy(at(i, k), cast v, k);
		return v;
	}

	// a reference to element i
	public inline function ref(i:Int):Ref<T>
		return cast at(i, stride());

	// the elements pos .. pos + len - 1, the same memory
	public function sub(pos:Int, len:Int):Slice<T> {
		if (pos < 0 || len < 0 || pos + len > length)
			outOfRange(pos + len, length);
		var k = stride();
		return view(data() + pos * k, len, k);
	}

	// copies n elements from src (at si) to this slice (at di); they may overlap
	public function blit(di:Int, src:Slice<T>, si:Int, n:Int) {
		var k = stride();
		if (n < 0 || di < 0 || si < 0 || di + n > length || si + n > src.length)
			outOfRange(di + n, length);
		copy(data() + di * k, src.data() + si * k, n * k);
	}
}

// (the elements' kinds: the last one listed in @:using is tried first)
class SliceIntOps {
	public static inline function iterator(s:Slice<Int>):SliceIntIterator
		return new SliceIntIterator(s.data(), s.length);

	public static function fill(s:Slice<Int>, v:Int)
		for (i in 0...s.length)
			s[i] = v;
}

class SliceFloatOps {
	public static inline function iterator(s:Slice<Float>):SliceFloatIterator
		return new SliceFloatIterator(s.data(), s.length);

	public static function fill(s:Slice<Float>, v:Float)
		for (i in 0...s.length)
			s[i] = v;
}

class SliceBoolOps {
	public static inline function iterator(s:Slice<Bool>):SliceBoolIterator
		return new SliceBoolIterator(s.data(), s.length);
}

class SliceU8Ops {
	public static inline function iterator(s:Slice<U8>):SliceU8Iterator
		return new SliceU8Iterator(s.data(), s.length);

	// a little-endian Int at byte offset i (checked: i + size <= length)
	public static inline function getI32At(s:Slice<U8>, i:Int):Int
		return Memory.getI32U(s.atBytes(i, 4));

	public static inline function setI32At(s:Slice<U8>, i:Int, v:Int)
		Memory.setI32U(s.atBytes(i, 4), v);

	public static inline function getU16At(s:Slice<U8>, i:Int):Int
		return Memory.getU16(s.atBytes(i, 2));

	public static inline function getI16At(s:Slice<U8>, i:Int):Int
		return Memory.getI16(s.atBytes(i, 2));

	public static inline function setI16At(s:Slice<U8>, i:Int, v:Int)
		Memory.setI16(s.atBytes(i, 2), v);
}

class SliceF32Ops {
	public static inline function iterator(s:Slice<F32>):SliceF32Iterator
		return new SliceF32Iterator(s.data(), s.length);
}

class SliceAnyOps {
	// the struct elements, in place
	public static inline function iterator<T>(s:Slice<T>):SliceStructIterator<T>
		return new SliceStructIterator(s.data(), s.length, s.stride());
}

// (inline constructors: Haxe's inliner makes their fields locals)
class SliceIntIterator {
	var a:Int;
	var end:Int;

	public inline function new(a:Int, n:Int) {
		this.a = a;
		end = a + 4 * n;
	}

	public inline function hasNext():Bool
		return a < end;

	public inline function next():Int {
		var v = getI32(a);
		a += 4;
		return v;
	}
}

class SliceFloatIterator {
	var a:Int;
	var end:Int;

	public inline function new(a:Int, n:Int) {
		this.a = a;
		end = a + 8 * n;
	}

	public inline function hasNext():Bool
		return a < end;

	public inline function next():Float {
		var v = getF64(a);
		a += 8;
		return v;
	}
}

class SliceBoolIterator {
	var a:Int;
	var end:Int;

	public inline function new(a:Int, n:Int) {
		this.a = a;
		end = a + n;
	}

	public inline function hasNext():Bool
		return a < end;

	public inline function next():Bool
		return getU8(a++) != 0;
}

class SliceF32Iterator {
	var a:Int;
	final end:Int;

	public inline function new(a:Int, n:Int) {
		this.a = a;
		end = a + n * 4;
	}

	public inline function hasNext():Bool
		return a < end;

	public inline function next():Float {
		var v = Memory.getF32(a);
		a += 4;
		return v;
	}
}

class SliceU8Iterator {
	var a:Int;
	var end:Int;

	public inline function new(a:Int, n:Int) {
		this.a = a;
		end = a + n;
	}

	public inline function hasNext():Bool
		return a < end;

	public inline function next():U8
		return getU8(a++);
}

class SliceStructIterator<T> {
	var a:Int;
	var end:Int;
	var k:Int;

	public inline function new(a:Int, n:Int, k:Int) {
		this.a = a;
		this.k = k;
		end = a + k * n;
	}

	public inline function hasNext():Bool
		return a < end;

	public inline function next():T {
		var v = a;
		a += k;
		return cast v;
	}
}

// A Slice's data and stride in locals: what the Scoped macro puts in place
// of `s` in `for (i in 0...s.length)` loops (Loops.view), so that `s[i]`
// reads no header and checks nothing. i is in range: the loop runs over the
// slice's own length, which never changes, and neither s nor i is assigned
// in the loop (the macro checks). Haxe's inline constructors keep it in
// locals, out of the heap, on every target.
@:noCompletion abstract SliceView<T>(SliceViewData) {
	public inline function new(s:Slice<T>)
		this = new SliceViewData(s.data(), s.stride(), 0);

	inline function at(i:Int, k:Int):Int
		return this.data + i * k;

	// (U8 converts to Int: its accessors come first, as Slice's)
	@:arrayAccess @:impl static inline function getF32(v:SliceView<F32>, i:Int):Float
		return Memory.getF32(v.at(i, 4));

	@:arrayAccess @:impl static inline function setF32(v:SliceView<F32>, i:Int, x:Float):Float {
		Memory.setF32(v.at(i, 4), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getByte(v:SliceView<U8>, i:Int):U8
		return getU8(v.at(i, 1));

	@:arrayAccess @:impl static inline function setByte(v:SliceView<U8>, i:Int, x:U8):U8 {
		setU8(v.at(i, 1), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getInt(v:SliceView<Int>, i:Int):Int
		return getI32(v.at(i, 4));

	@:arrayAccess @:impl static inline function setInt(v:SliceView<Int>, i:Int, x:Int):Int {
		setI32(v.at(i, 4), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getFloat(v:SliceView<Float>, i:Int):Float
		return getF64(v.at(i, 8));

	@:arrayAccess @:impl static inline function setFloat(v:SliceView<Float>, i:Int, x:Float):Float {
		setF64(v.at(i, 8), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getBool(v:SliceView<Bool>, i:Int):Bool
		return getU8(v.at(i, 1)) != 0;

	@:arrayAccess @:impl static inline function setBool(v:SliceView<Bool>, i:Int, x:Bool):Bool {
		setU8(v.at(i, 1), x ? 1 : 0);
		return x;
	}

	@:arrayAccess inline function getStruct(i:Int):T
		return cast at(i, this.stride);

	@:arrayAccess inline function setStruct(i:Int, x:T):T {
		copy(at(i, this.stride), cast x, this.stride);
		return x;
	}
}

// A Slice's data, length and stride in locals, with every index checked
// against the length: what the Scoped macro reads a slice through in a
// @:scoped function, from its declaration on, when the slice's variable is
// never assigned or captured (Loops.checked). The header is read once, not
// at each access. (A slice's header never changes.)
@:noCompletion abstract SliceChecked<T>(SliceViewData) {
	public inline function new(s:Slice<T>) {
		// (a null slice: a view of nothing, which fails at its first use)
		// (one constructor call: two in a conditional would not stay in locals)
		var none = (cast s : Int) == 0;
		this = new SliceViewData(none ? 0 : s.data(), none ? 0 : s.stride(), none ? 0 : s.length);
	}

	public var length(get, never):Int;

	inline function get_length():Int
		return this.len;

	inline function at(i:Int, k:Int):Int {
		if (i < 0 || i >= this.len)
			outOfRange(i, this.len);
		return this.data + i * k;
	}

	@:arrayAccess @:impl static inline function getF32(v:SliceChecked<F32>, i:Int):Float
		return Memory.getF32(v.at(i, 4));

	@:arrayAccess @:impl static inline function setF32(v:SliceChecked<F32>, i:Int, x:Float):Float {
		Memory.setF32(v.at(i, 4), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getByte(v:SliceChecked<U8>, i:Int):U8
		return getU8(v.at(i, 1));

	@:arrayAccess @:impl static inline function setByte(v:SliceChecked<U8>, i:Int, x:U8):U8 {
		setU8(v.at(i, 1), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getInt(v:SliceChecked<Int>, i:Int):Int
		return getI32(v.at(i, 4));

	@:arrayAccess @:impl static inline function setInt(v:SliceChecked<Int>, i:Int, x:Int):Int {
		setI32(v.at(i, 4), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getFloat(v:SliceChecked<Float>, i:Int):Float
		return getF64(v.at(i, 8));

	@:arrayAccess @:impl static inline function setFloat(v:SliceChecked<Float>, i:Int, x:Float):Float {
		setF64(v.at(i, 8), x);
		return x;
	}

	@:arrayAccess @:impl static inline function getBool(v:SliceChecked<Bool>, i:Int):Bool
		return getU8(v.at(i, 1)) != 0;

	@:arrayAccess @:impl static inline function setBool(v:SliceChecked<Bool>, i:Int, x:Bool):Bool {
		setU8(v.at(i, 1), x ? 1 : 0);
		return x;
	}

	@:arrayAccess inline function getStruct(i:Int):T
		return cast at(i, this.stride);

	@:arrayAccess inline function setStruct(i:Int, x:T):T {
		copy(at(i, this.stride), cast x, this.stride);
		return x;
	}
}

@:noCompletion class SliceViewData {
	public final data:Int;
	public final stride:Int;
	public final len:Int;

	public inline function new(data:Int, stride:Int, len:Int) {
		this.data = data;
		this.stride = stride;
		this.len = len;
	}
}
