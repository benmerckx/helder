package hxmc.scoped;

import hxmc.scoped.Memory.*;

// A grow-only array in scoped memory. Its elements live in a buffer it
// claims for itself, so growing it never moves anything else, and a
// reference to an element (`ref(i)`, `add()`) stays valid as long as the
// Grow does. It is freed with the scope that made it, all at once.
//
// The value is the address of its header (buffer, length, stride, capacity), so a
// Grow is passed by reference. Element types as for Slice. Scope.grow(T)
// makes one.
@:using(hxmc.scoped.Grow.GrowAnyOps, hxmc.scoped.Grow.GrowBoolOps, hxmc.scoped.Grow.GrowFloatOps, hxmc.scoped.Grow.GrowIntOps, hxmc.scoped.Grow.GrowU8Ops, hxmc.scoped.Grow.GrowF32Ops)
abstract Grow<T>(Addr) to Addr {
	static inline var BUFFER = 0;
	@:noCompletion public static inline var LEN = 4;
	static inline var STRIDE = 8;
	static inline var MAGIC = 12;
	// (the buffer's capacity, kept here: a push reads only its own header)
	@:noCompletion public static inline var CAP = 16;
	static inline var HEADER = 24;

	inline function new(h:Addr)
		this = h;

	// an empty Grow of elements of `stride` bytes, in the current scope
	public static function make<T>(stride:Int):Grow<T> {
		var h = Memory.alloc(HEADER);
		var b = Memory.claim();
		setI32(h, b);
		setI32(h + STRIDE, stride);
		setI32(h + CAP, Memory.capacity(b));
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
		var a = room(stride());
		Memory.zero(a, stride());
		return a;
	}

	// a new element at the end, not zeroed (for pushes, which write all of it)
	@:noCompletion public inline function room(k:Int):Addr {
		var n = length;
		var b = getI32(this);
		var end = (n + 1) * k;
		if (end > getI32(this + CAP)) {
			Memory.reserve(b, end);
			setI32(this + CAP, Memory.capacity(b));
		}
		setI32(this + LEN, n + 1);
		return (b << SHIFT) + n * k;
	}

	// the address of bytes i .. i + n - 1, checked against the length (for
	// multi-byte reads of a byte array)
	@:noCompletion public inline function atBytes(i:Int, n:Int):Int {
		var len = length;
		if (i < 0 || i > len - n)
			outOfRange(i, len);
		return base() + i;
	}

	@:noCompletion public inline function at(i:Int, k:Int):Int {
		var n = length;
		if (i < 0 || i >= n)
			outOfRange(i, n);
		return base() + i * k;
	}

	@:arrayAccess @:impl static inline function getF32(g:Grow<F32>, i:Int):Float
		return Memory.getF32(g.at(i, 4));

	@:arrayAccess @:impl static inline function setF32(g:Grow<F32>, i:Int, x:Float):Float {
		Memory.setF32(g.at(i, 4), x);
		return x;
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

	// a writer appending to this Grow with its length, capacity and buffer in
	// locals: `var w = g.writer(); w.push(x);` reads nothing from memory per
	// push (a compare, the element's store and the length's). Push through
	// it alone while it is in use: it does not see another's pushes.
	public inline function writer():GrowWriter<T>
		return new GrowWriter(new Grow<T>(this));

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
		setI32(g.room(4), v);
		return g.length;
	}

	public static inline function iterator(g:Grow<Int>):Slice.SliceIntIterator
		return new Slice.SliceIntIterator(g.base(), g.length);
}

class GrowFloatOps {
	public static inline function push(g:Grow<Float>, v:Float):Int {
		setF64(g.room(8), v);
		return g.length;
	}

	public static inline function iterator(g:Grow<Float>):Slice.SliceFloatIterator
		return new Slice.SliceFloatIterator(g.base(), g.length);
}

class GrowBoolOps {
	public static inline function push(g:Grow<Bool>, v:Bool):Int {
		setU8(g.room(1), v ? 1 : 0);
		return g.length;
	}
}

class GrowF32Ops {
	public static inline function push(g:Grow<F32>, v:Float):Int {
		Memory.setF32(g.room(4), v);
		return g.length;
	}

	public static inline function iterator(g:Grow<F32>):Slice.SliceF32Iterator
		return new Slice.SliceF32Iterator(g.base(), g.length);
}

class GrowU8Ops {
	public static inline function push(g:Grow<U8>, v:U8):Int {
		setU8(g.room(1), v);
		return g.length;
	}

	// a little-endian Int at byte offset i (checked: i + size <= length)
	public static inline function getI32At(g:Grow<U8>, i:Int):Int
		return Memory.getI32U(g.atBytes(i, 4));

	public static inline function getU16At(g:Grow<U8>, i:Int):Int
		return Memory.getU16(g.atBytes(i, 2));

	public static inline function getI16At(g:Grow<U8>, i:Int):Int
		return Memory.getI16(g.atBytes(i, 2));

	public static inline function iterator(g:Grow<U8>):Slice.SliceU8Iterator
		return new Slice.SliceU8Iterator(g.base(), g.length);
}

class GrowAnyOps {
	// appends a copy of the struct v (its size a constant: Elems)
	public static macro function push(g:haxe.macro.Expr, v:haxe.macro.Expr):haxe.macro.Expr
		return Elems.push(g, v);

	// appends a zeroed struct: the new element, in place
	public static macro function next(g:haxe.macro.Expr):haxe.macro.Expr
		return Elems.next(g);

	// (the same with the size read from the header: an element type not known
	// where it is called)
	@:noCompletion public static inline function pushAny<T>(g:Grow<T>, v:T):Int {
		copy(g.room(g.stride()), cast v, g.stride());
		return g.length;
	}

	@:noCompletion public static inline function nextAny<T>(g:Grow<T>):T
		return cast g.add();

	public static inline function iterator<T>(g:Grow<T>):Slice.SliceStructIterator<T>
		return new Slice.SliceStructIterator(g.base(), g.length, g.stride());
}

// Grow.writer(): a Grow's length, capacity (in bytes) and buffer in locals
// (Haxe's inline constructors keep the writer out of the heap).
@:using(hxmc.scoped.Grow.GrowWriterAnyOps, hxmc.scoped.Grow.GrowWriterBoolOps, hxmc.scoped.Grow.GrowWriterFloatOps, hxmc.scoped.Grow.GrowWriterIntOps, hxmc.scoped.Grow.GrowWriterU8Ops, hxmc.scoped.Grow.GrowWriterF32Ops)
abstract GrowWriter<T>(GrowWriterData) {
	public inline function new(g:Grow<T>) {
		var h:Int = cast g;
		var b = getI32(h);
		this = new GrowWriterData(h, b << SHIFT, g.length, getI32(h + Grow.CAP), b);
	}

	// the Grow written to
	public var grow(get, never):Grow<T>;

	inline function get_grow():Grow<T>
		return cast this.g;

	public var length(get, never):Int;

	inline function get_length():Int
		return this.n;

	// room for one more element of k bytes: its address
	@:noCompletion public inline function room(k:Int):Addr {
		var at = this.n * k;
		if (at + k > this.cap)
			this.cap = more(this.g, this.buffer, at + k);
		this.n++;
		setI32(this.g + Grow.LEN, this.n);
		return this.base + at;
	}

	// room for `count` more elements of k bytes: the address of the first
	@:noCompletion public inline function reserve(count:Int, k:Int):Addr {
		var at = this.n * k, end = (this.n + count) * k;
		if (end > this.cap)
			this.cap = more(this.g, this.buffer, end);
		this.n += count;
		setI32(this.g + Grow.LEN, this.n);
		return this.base + at;
	}

	// (cold: the buffer made larger, the header's capacity updated; it
	// allocates nothing in the scope: Loops.iteration)
	@:noAlloc static function more(g:Int, b:Int, end:Int):Int {
		Memory.reserve(b, end);
		var cap = Memory.capacity(b);
		setI32(g + Grow.CAP, cap);
		return cap;
	}
}

@:noCompletion class GrowWriterData {
	public final g:Int;
	public final base:Int;
	public var n:Int;
	public var cap:Int;
	public final buffer:Int;

	public inline function new(g:Int, base:Int, n:Int, cap:Int, buffer:Int) {
		this.g = g;
		this.base = base;
		this.n = n;
		this.cap = cap;
		this.buffer = buffer;
	}
}

class GrowWriterIntOps {
	public static inline function push(w:GrowWriter<Int>, v:Int):Int {
		setI32(w.room(4), v);
		return w.length;
	}
}

class GrowWriterFloatOps {
	public static inline function push(w:GrowWriter<Float>, v:Float):Int {
		setF64(w.room(8), v);
		return w.length;
	}
}

class GrowWriterBoolOps {
	public static inline function push(w:GrowWriter<Bool>, v:Bool):Int {
		setU8(w.room(1), v ? 1 : 0);
		return w.length;
	}
}

class GrowWriterF32Ops {
	public static inline function push(w:GrowWriter<F32>, v:Float):Int {
		Memory.setF32(w.room(4), v);
		return w.length;
	}
}

class GrowWriterU8Ops {
	public static inline function push(w:GrowWriter<U8>, v:U8):Int {
		setU8(w.room(1), v);
		return w.length;
	}

	// n bytes from src at once (one capacity check, one copy)
	public static inline function addBytes(w:GrowWriter<U8>, src:Addr, n:Int)
		copy(w.reserve(n, 1), src, n);

	public static inline function addStr(w:GrowWriter<U8>, s:Str)
		addBytes(w, s.data(), s.length);

	public static inline function addSlice(w:GrowWriter<U8>, s:Slice<U8>)
		addBytes(w, s.data(), s.length);

	// a String's UTF-8 bytes; a literal's are known here, written with a few
	// stores after one capacity check
	public static macro function addString(w:haxe.macro.Expr, s:haxe.macro.Expr):haxe.macro.Expr {
		switch s.expr {
			case EConst(CString(text, _)):
				var b = haxe.io.Bytes.ofString(text);
				var out = [macro var __a:Int = __w.reserve($v{b.length}, 1)];
				var k = 0;
				while (k + 4 <= b.length) {
					out.push(macro hxmc.scoped.Memory.setI32U(__a + $v{k}, $v{b.getInt32(k)}));
					k += 4;
				}
				while (k < b.length) {
					out.push(macro hxmc.scoped.Memory.setU8(__a + $v{k}, $v{b.get(k)}));
					k++;
				}
				return macro {
					var __w = $w;
					$b{out};
				};
			default:
				return macro hxmc.scoped.Grow.GrowWriterU8Ops.addStringRuntime($w, $s);
		}
	}

	@:noCompletion public static function addStringRuntime(w:GrowWriter<U8>, s:String) {
		var b = haxe.io.Bytes.ofString(s);
		var a = w.reserve(b.length, 1);
		Memory.write(a, b, 0, b.length);
	}

	// a little-endian 32- or 16-bit Int, at any byte position
	public static inline function pushI32(w:GrowWriter<U8>, v:Int)
		Memory.setI32U(w.reserve(4, 1), v);

	public static inline function pushI16(w:GrowWriter<U8>, v:Int)
		Memory.setI16(w.reserve(2, 1), v);
}

class GrowWriterAnyOps {
	// appends a copy of the struct v (its size a constant: Elems)
	public static macro function push(w:haxe.macro.Expr, v:haxe.macro.Expr):haxe.macro.Expr
		return Elems.push(w, v);

	// appends a zeroed struct: the new element, in place
	public static macro function next(w:haxe.macro.Expr):haxe.macro.Expr
		return Elems.next(w);

	@:noCompletion public static inline function pushAny<T>(w:GrowWriter<T>, v:T):Int {
		var k = w.grow.stride();
		copy(w.room(k), cast v, k);
		return w.length;
	}

	@:noCompletion public static inline function nextAny<T>(w:GrowWriter<T>):T {
		var k = w.grow.stride();
		var a = w.room(k);
		Memory.zero(a, k);
		return cast a;
	}
}
