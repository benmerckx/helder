package hxmc.scoped;

import haxe.ds.Vector;
import haxe.io.Bytes;

// The 16 buffers of scoped memory and typed access to them, one
// implementation per target family (Memory keeps the scopes). An address is
// the buffer in its top four bits and the offset in the other 28 (Addr);
// every access is checked against the buffer's length, so a wrong address
// fails instead of reading or writing outside it, and every access is
// aligned to its size (alloc's 8-byte alignment and the structs' natural
// layout keep it).
//
// - hxmc (native, wasm32): malloc'ed memory, read and written by the code
//   generator's intrinsics; growing reallocates (offsets do not change).
// - JavaScript: an ArrayBuffer per buffer, with Int32Array, Float64Array and
//   Uint8Array views (V8 reads those far faster than a DataView). Not
//   checked here: a typed array cannot reach outside itself (a read past
//   its end is undefined), and the types check their indexes.
// - HashLink: haxe.io.Bytes, read through its hl.Bytes with one check here.
// - the other targets: haxe.io.Bytes.
#if (target.name == "hxmc" && !hxmc.wasm_gc)
import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

class Store {
	static inline var SHIFT = Memory.SHIFT;
	static inline var MASK = Memory.MASK;

	static var ptrs:Vector<Ptr>;
	static var lens:Vector<Int>;

	public static function init(n:Int) {
		ptrs = new Vector(n);
		lens = new Vector(n);
		for (i in 0...n) {
			ptrs[i] = Ptr.nil();
			lens[i] = 0;
		}
	}

	public static inline function exists(i:Int):Bool
		return lens[i] > 0;

	public static function make(i:Int, cap:Int) {
		var p = LibC.malloc((cap : I64));
		if (p.isNull())
			Memory.fail("out of memory");
		LibC.memset(p, 0, (cap : I64));
		ptrs[i] = p;
		lens[i] = cap;
	}

	// buffer i made cap bytes long, its first `keep` bytes kept
	public static function grow(i:Int, cap:Int, keep:Int) {
		var p = LibC.realloc(ptrs[i], (cap : I64));
		if (p.isNull())
			Memory.fail("out of memory");
		LibC.memset(p.add(lens[i]), 0, ((cap - lens[i]) : I64));
		ptrs[i] = p;
		lens[i] = cap;
	}

	public static inline function capacity(i:Int):Int
		return lens[i];

	static inline function at(a:Int, n:Int):Int {
		var o = a & MASK;
		if (o + n > lens[a >>> SHIFT])
			Memory.outside(a);
		return o;
	}

	public static inline function getI32(a:Int):Int
		return Mem.getI32(ptrs[a >>> SHIFT], at(a, 4));

	public static inline function setI32(a:Int, v:Int)
		Mem.setI32(ptrs[a >>> SHIFT], at(a, 4), v);

	public static inline function getF64(a:Int):Float
		return Mem.getF64(ptrs[a >>> SHIFT], at(a, 8));

	public static inline function setF64(a:Int, v:Float)
		Mem.setF64(ptrs[a >>> SHIFT], at(a, 8), v);

	public static inline function getU8(a:Int):Int
		return Mem.getU8(ptrs[a >>> SHIFT], at(a, 1));

	public static inline function setU8(a:Int, v:Int)
		Mem.setI8(ptrs[a >>> SHIFT], at(a, 1), v);

	public static function fill(a:Int, n:Int, v:Int)
		if (n > 0)
			LibC.memset(ptrs[a >>> SHIFT].add(at(a, n)), v, (n : I64));

	public static function copy(dst:Int, src:Int, n:Int)
		if (n > 0)
			LibC.memmove(ptrs[dst >>> SHIFT].add(at(dst, n)), ptrs[src >>> SHIFT].add(at(src, n)), (n : I64));

	public static function string(a:Int, n:Int):String {
		var b = Bytes.alloc(n);
		for (k in 0...n)
			b.set(k, getU8(a + k));
		return b.getString(0, n);
	}

	public static function write(a:Int, b:Bytes, pos:Int, n:Int)
		for (k in 0...n)
			setU8(a + k, b.get(pos + k));
}
#else
class Store {
	static inline var SHIFT = Memory.SHIFT;
	static inline var MASK = Memory.MASK;

	static var bufs:Vector<Bytes>;
	#if js
	static var i32:Vector<js.lib.Int32Array>;
	static var f64:Vector<js.lib.Float64Array>;
	static var u8:Vector<js.lib.Uint8Array>;
	#elseif hl
	static var raw:hl.NativeArray<hl.Bytes>;
	static var lens:hl.NativeArray<Int>;
	#end

	public static function init(n:Int) {
		bufs = new Vector(n);
		for (i in 0...n)
			bufs[i] = null;
		#if js
		i32 = new Vector(n);
		f64 = new Vector(n);
		u8 = new Vector(n);
		#elseif hl
		raw = new hl.NativeArray(n);
		lens = new hl.NativeArray(n);
		#end
	}

	public static inline function exists(i:Int):Bool
		return bufs[i] != null;

	public static function make(i:Int, cap:Int)
		set(i, Bytes.alloc(cap));

	public static function grow(i:Int, cap:Int, keep:Int) {
		var b = Bytes.alloc(cap);
		b.blit(0, bufs[i], 0, keep);
		set(i, b);
	}

	static function set(i:Int, b:Bytes) {
		bufs[i] = b;
		#if js
		var d = b.getData();
		i32[i] = new js.lib.Int32Array(d);
		f64[i] = new js.lib.Float64Array(d);
		u8[i] = new js.lib.Uint8Array(d);
		#elseif hl
		raw[i] = @:privateAccess b.b;
		lens[i] = b.length;
		#end
	}

	public static inline function capacity(i:Int):Int
		return #if hl lens[i] #else bufs[i].length #end;

	#if hl
	static inline function at(a:Int, n:Int):Int {
		var o = a & MASK;
		if (o + n > capacity(a >>> SHIFT))
			Memory.outside(a);
		return o;
	}
	#end

	#if js
	public static inline function getI32(a:Int):Int
		return i32[a >>> SHIFT][(a & MASK) >> 2];

	public static inline function setI32(a:Int, v:Int)
		i32[a >>> SHIFT][(a & MASK) >> 2] = v;

	public static inline function getF64(a:Int):Float
		return f64[a >>> SHIFT][(a & MASK) >> 3];

	public static inline function setF64(a:Int, v:Float)
		f64[a >>> SHIFT][(a & MASK) >> 3] = v;

	public static inline function getU8(a:Int):Int
		return u8[a >>> SHIFT][a & MASK];

	public static inline function setU8(a:Int, v:Int)
		u8[a >>> SHIFT][a & MASK] = v;
	#elseif hl
	public static inline function getI32(a:Int):Int
		return raw[a >>> SHIFT].getI32(at(a, 4));

	public static inline function setI32(a:Int, v:Int)
		raw[a >>> SHIFT].setI32(at(a, 4), v);

	public static inline function getF64(a:Int):Float
		return raw[a >>> SHIFT].getF64(at(a, 8));

	public static inline function setF64(a:Int, v:Float)
		raw[a >>> SHIFT].setF64(at(a, 8), v);

	public static inline function getU8(a:Int):Int
		return raw[a >>> SHIFT].getUI8(at(a, 1));

	public static inline function setU8(a:Int, v:Int)
		raw[a >>> SHIFT].setUI8(at(a, 1), v);
	#else
	public static inline function getI32(a:Int):Int
		return bufs[a >>> SHIFT].getInt32(a & MASK);

	public static inline function setI32(a:Int, v:Int)
		bufs[a >>> SHIFT].setInt32(a & MASK, v);

	public static inline function getF64(a:Int):Float
		return bufs[a >>> SHIFT].getDouble(a & MASK);

	public static inline function setF64(a:Int, v:Float)
		bufs[a >>> SHIFT].setDouble(a & MASK, v);

	public static inline function getU8(a:Int):Int
		return bufs[a >>> SHIFT].get(a & MASK);

	public static inline function setU8(a:Int, v:Int)
		bufs[a >>> SHIFT].set(a & MASK, v & 0xFF);
	#end

	public static function fill(a:Int, n:Int, v:Int)
		bufs[a >>> SHIFT].fill(a & MASK, n, v);

	public static function copy(dst:Int, src:Int, n:Int)
		bufs[dst >>> SHIFT].blit(dst & MASK, bufs[src >>> SHIFT], src & MASK, n);

	public static function string(a:Int, n:Int):String
		return bufs[a >>> SHIFT].getString(a & MASK, n);

	public static function write(a:Int, b:Bytes, pos:Int, n:Int)
		bufs[a >>> SHIFT].blit(a & MASK, b, pos, n);
}
#end
