package helder.scoped;

import haxe.ds.Vector;
import haxe.io.Bytes;

// The buffers of scoped memory and typed access to them, one
// implementation per target family (Memory keeps the scopes). An address is
// the buffer in its top bits and the offset in the low 26 (Addr); an access
// cannot reach outside the buffers (checked, or by construction), and every
// access is
// aligned to its size (alloc's 8-byte alignment and the structs' natural
// layout keep it).
//
// - hxmc native: one reserved range for all of them, read and written by the
//   code generator's intrinsics at base + address, with no table and no
//   check (every address lies inside it).
// - hxmc wasm32: malloc'ed buffers in a table, each access checked; growing
//   reallocates (offsets do not change).
// - JavaScript: one ArrayBuffer holding every buffer at its address, with
//   Int32Array, Float64Array and Uint8Array views over it (V8 reads those far
//   faster than a DataView): an access is a typed array's at the address.
// - HashLink: one hl.Bytes holding every buffer at its address, as on
//   JavaScript; an access checks its buffer.
// - the JVM: haxe.io.Bytes, read through java.nio.ByteBuffer views.
// - the other targets: haxe.io.Bytes.
#if (target.name == "hxmc" && !hxmc.wasm_gc && !(hxmc.target == "wasm32-wasi"))
import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

class Store {
	static inline var SHIFT = Memory.SHIFT;
	static inline var MASK = Memory.MASK;

	// Native: one reservation of 32 regions of 64 MB, so an address is an
	// offset from one base, with no table and no check: every Addr is below
	// 2^31, inside it. The runtime's reservation (hxmc.rt.Os: mmap with
	// MAP_NORESERVE, VirtualAlloc with pages committed as touched) does not
	// count against the commit limit; malloc if it fails. The buffers'
	// lengths are raw memory too, so allocating touches no GC object (a job
	// in a safe region allocates: tests/bench/results/jobs.md).
	static var base:Ptr;
	static var lens:Ptr;

	public static function init(n:Int) {
		var bytes = (n : I64) << SHIFT;
		base = hxmc.rt.Os.reserve(bytes);
		if (base.isNull())
			base = LibC.malloc(bytes);
		if (base.isNull())
			Memory.fail("out of memory");
		lens = LibC.malloc((n * 4 : I64));
		if (lens.isNull())
			Memory.fail("out of memory");
		LibC.memset(lens, 0, (n * 4 : I64));
	}

	// the buffers there are room for
	public static inline function buffers():Int
		return Memory.BUFFERS;

	public static inline function exists(i:Int):Bool
		return capacity(i) > 0;

	// (a buffer's whole region at once: its pages are committed when touched,
	// and nothing reads memory it has not written, so nothing is zeroed here)
	public static function make(i:Int, cap:Int)
		Mem.setI32(lens, i * 4, MASK + 1);

	public static function grow(i:Int, cap:Int, keep:Int)
		Mem.setI32(lens, i * 4, MASK + 1);

	public static inline function capacity(i:Int):Int
		return Mem.getI32(lens, i * 4);

	public static inline function getI32(a:Int):Int
		return Mem.getI32(base, a);

	public static inline function setI32(a:Int, v:Int)
		Mem.setI32(base, a, v);

	public static inline function getF64(a:Int):Float
		return Mem.getF64(base, a);

	public static inline function setF64(a:Int, v:Float)
		Mem.setF64(base, a, v);

	public static inline function getF32(a:Int):Float
		return Mem.getF32(base, a);

	public static inline function setF32(a:Int, v:Float)
		Mem.setF32(base, a, v);

	public static inline function getU8(a:Int):Int
		return Mem.getU8(base, a);

	public static inline function setU8(a:Int, v:Int)
		Mem.setI8(base, a, v);

	public static function fill(a:Int, n:Int, v:Int)
		if (n > 0)
			LibC.memset(base.add(a), v, (n : I64));

	public static function copy(dst:Int, src:Int, n:Int)
		if (n > 0)
			LibC.memmove(base.add(dst), base.add(src), (n : I64));

	public static inline function compare(a:Int, b:Int, n:Int):Int
		return n <= 0 ? 0 : LibC.memcmp(base.add(a), base.add(b), (n : I64));

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
#elseif (target.name == "hxmc" && !hxmc.wasm_gc)
// (wasm32: a table of malloc'ed buffers, each access checked: a reservation
// there would grow the linear memory. The table is raw memory, 16 bytes a
// buffer: its pointer, then its length; an access reads both, with no
// Vector's bounds checks: twice as fast as Vectors, which it was)
import hxmc.I64;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

class Store {
	static inline var SHIFT = Memory.SHIFT;
	static inline var MASK = Memory.MASK;

	static var table:Ptr;

	public static function init(n:Int) {
		table = LibC.malloc((n * 16 : I64));
		if (table.isNull())
			Memory.fail("out of memory");
		LibC.memset(table, 0, (n * 16 : I64));
	}

	// the buffers there are room for
	public static inline function buffers():Int
		return Memory.BUFFERS;

	public static inline function exists(i:Int):Bool
		return capacity(i) > 0;

	public static function make(i:Int, cap:Int) {
		var p = LibC.malloc((cap : I64));
		if (p.isNull())
			Memory.fail("out of memory");
		Mem.setPtr(table, i * 16, p);
		Mem.setI32(table, i * 16 + 8, cap);
	}

	// buffer i made cap bytes long, its first `keep` bytes kept
	public static function grow(i:Int, cap:Int, keep:Int) {
		var p = LibC.realloc(Mem.getPtr(table, i * 16), (cap : I64));
		if (p.isNull())
			Memory.fail("out of memory");
		Mem.setPtr(table, i * 16, p);
		Mem.setI32(table, i * 16 + 8, cap);
	}

	public static inline function capacity(i:Int):Int
		return Mem.getI32(table, i * 16 + 8);

	static inline function buffer(a:Int):Ptr
		return Mem.getPtr(table, (a >>> SHIFT) * 16);

	static inline function at(a:Int, n:Int):Int {
		var o = a & MASK;
		if (o + n > capacity(a >>> SHIFT))
			Memory.outside(a);
		return o;
	}

	public static inline function getI32(a:Int):Int
		return Mem.getI32(buffer(a), at(a, 4));

	public static inline function setI32(a:Int, v:Int)
		Mem.setI32(buffer(a), at(a, 4), v);

	public static inline function getF64(a:Int):Float
		return Mem.getF64(buffer(a), at(a, 8));

	public static inline function setF64(a:Int, v:Float)
		Mem.setF64(buffer(a), at(a, 8), v);

	public static inline function getF32(a:Int):Float
		return Mem.getF32(buffer(a), at(a, 4));

	public static inline function setF32(a:Int, v:Float)
		Mem.setF32(buffer(a), at(a, 4), v);

	public static inline function getU8(a:Int):Int
		return Mem.getU8(buffer(a), at(a, 1));

	public static inline function setU8(a:Int, v:Int)
		Mem.setI8(buffer(a), at(a, 1), v);

	public static function fill(a:Int, n:Int, v:Int)
		if (n > 0)
			LibC.memset(buffer(a).add(at(a, n)), v, (n : I64));

	public static function copy(dst:Int, src:Int, n:Int)
		if (n > 0)
			LibC.memmove(buffer(dst).add(at(dst, n)), buffer(src).add(at(src, n)), (n : I64));

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
#elseif js
// (JavaScript: every buffer in one ArrayBuffer, at its address: its pages
// are not committed until touched, so 2 GB costs nothing until used, and an
// access is a typed array's at the address itself, with no table, no mask
// and no check: it cannot reach outside the ArrayBuffer. A host that will
// not make 2 GB gets half, and so on: fewer buffers. JavaScript's threads,
// workers, have memories of their own.)
class Store {
	static inline var SHIFT = Memory.SHIFT;

	static var i32:js.lib.Int32Array;
	static var f64:js.lib.Float64Array;
	static var f32:js.lib.Float32Array;
	static var u8:js.lib.Uint8Array;
	static var lens:Vector<Int>;
	static var count = 0;

	public static function init(n:Int) {
		var size = n;
		var mem:js.lib.ArrayBuffer = null;
		while (mem == null && size >= 2) {
			try
				mem = new js.lib.ArrayBuffer(js.Syntax.code("{0} * {1}", size, 1 << SHIFT))
			catch (e:Dynamic)
				size >>= 1;
		}
		if (mem == null)
			Memory.fail("out of memory");
		count = size;
		i32 = new js.lib.Int32Array(mem);
		f64 = new js.lib.Float64Array(mem);
		f32 = new js.lib.Float32Array(mem);
		u8 = new js.lib.Uint8Array(mem);
		lens = new Vector(n);
		for (i in 0...n)
			lens[i] = 0;
	}

	// the buffers there are room for
	public static inline function buffers():Int
		return count;

	public static inline function exists(i:Int):Bool
		return lens[i] > 0;

	// (a buffer's whole region at once, as natively)
	public static function make(i:Int, cap:Int)
		lens[i] = 1 << SHIFT;

	public static function grow(i:Int, cap:Int, keep:Int)
		lens[i] = 1 << SHIFT;

	public static inline function capacity(i:Int):Int
		return lens[i];

	public static inline function getI32(a:Int):Int
		return i32[a >> 2];

	public static inline function setI32(a:Int, v:Int)
		i32[a >> 2] = v;

	public static inline function getF64(a:Int):Float
		return f64[a >> 3];

	public static inline function setF64(a:Int, v:Float)
		f64[a >> 3] = v;

	public static inline function getF32(a:Int):Float
		return f32[a >> 2];

	public static inline function setF32(a:Int, v:Float)
		f32[a >> 2] = v;

	public static inline function getU8(a:Int):Int
		return u8[a];

	public static inline function setU8(a:Int, v:Int)
		u8[a] = v;

	public static function fill(a:Int, n:Int, v:Int) {
		// (an allocation's zeroing, small and aligned: stores beat a call)
		if (v == 0 && n <= 128 && (a | n) & 7 == 0) {
			var k = a >> 3, end = (a + n) >> 3;
			while (k < end)
				f64[k++] = 0;
		} else if (n > 0)
			u8.fill(v, a, a + n);
	}

	public static function copy(dst:Int, src:Int, n:Int)
		if (n > 0)
			u8.copyWithin(dst, src, src + n);

	public static function string(a:Int, n:Int):String
		return haxe.io.Bytes.ofData(u8.slice(a, a + n).buffer).getString(0, n);

	public static function write(a:Int, b:Bytes, pos:Int, n:Int)
		u8.set(new js.lib.Uint8Array(b.getData(), pos, n), a);
}
#elseif hl
// (HashLink: every buffer in one hl.Bytes, at its address, as on
// JavaScript: a large block's pages are not committed until touched. 31
// buffers, an Int's worth, and 8 bytes past the last, so an access checks
// its buffer only: a shift and a compare.)
class Store {
	static inline var SHIFT = Memory.SHIFT;

	static var mem:hl.Bytes;
	static var lens:Vector<Int>;
	static var count = 0;

	public static function init(n:Int) {
		var size = n - 1;
		while (mem == null && size >= 2) {
			mem = new hl.Bytes((size << SHIFT) + 8);
			if (mem == null)
				size >>= 1;
		}
		if (mem == null)
			Memory.fail("out of memory");
		count = size;
		lens = new Vector(n);
		for (i in 0...n)
			lens[i] = 0;
	}

	// the buffers there are room for
	public static inline function buffers():Int
		return count;

	public static inline function exists(i:Int):Bool
		return lens[i] > 0;

	// (a buffer's whole region at once, as natively)
	public static function make(i:Int, cap:Int)
		lens[i] = 1 << SHIFT;

	public static function grow(i:Int, cap:Int, keep:Int)
		lens[i] = 1 << SHIFT;

	public static inline function capacity(i:Int):Int
		return lens[i];

	static inline function at(a:Int):Int {
		if (a >>> SHIFT >= count)
			Memory.outside(a);
		return a;
	}

	public static inline function getI32(a:Int):Int
		return mem.getI32(at(a));

	public static inline function setI32(a:Int, v:Int)
		mem.setI32(at(a), v);

	public static inline function getF64(a:Int):Float
		return mem.getF64(at(a));

	public static inline function setF64(a:Int, v:Float)
		mem.setF64(at(a), v);

	public static inline function getF32(a:Int):Float
		return mem.getF32(at(a));

	public static inline function setF32(a:Int, v:Float)
		mem.setF32(at(a), v);

	public static inline function getU8(a:Int):Int
		return mem.getUI8(at(a));

	public static inline function setU8(a:Int, v:Int)
		mem.setUI8(at(a), v);

	// (n: within the buffer, which its callers check)
	public static function fill(a:Int, n:Int, v:Int)
		if (n > 0)
			mem.fill(at(a), n, v);

	public static function copy(dst:Int, src:Int, n:Int)
		if (n > 0)
			mem.blit(at(dst), mem, at(src), n);

	public static function string(a:Int, n:Int):String {
		var b = Bytes.alloc(n);
		@:privateAccess b.b.blit(0, mem, at(a), n);
		return b.getString(0, n);
	}

	public static function write(a:Int, b:Bytes, pos:Int, n:Int)
		mem.blit(at(a), @:privateAccess b.b, pos, n);
}
#else
#if jvm
// (the JVM: java.nio.ByteBuffer over each buffer's byte[], whose getDouble
// and getInt are intrinsics, where haxe.io.Bytes assembles bytes; Haxe 5
// has no java.nio externs, so the few used are declared here)
@:native("java.nio.ByteBuffer") private extern class JByteBuffer {
	static function wrap(a:haxe.io.BytesData):JByteBuffer;
	function order(o:JByteOrder):JByteBuffer;
	function getDouble(i:Int):Float;
	function putDouble(i:Int, v:Float):JByteBuffer;
	function getFloat(i:Int):Single;
	function putFloat(i:Int, v:Single):JByteBuffer;
	function getInt(i:Int):Int;
	function putInt(i:Int, v:Int):JByteBuffer;
}

@:native("java.nio.ByteOrder") private extern class JByteOrder {
	static var LITTLE_ENDIAN:JByteOrder;
}
#end

class Store {
	static inline var SHIFT = Memory.SHIFT;
	static inline var MASK = Memory.MASK;

	static var bufs:Vector<Bytes>;
	#if jvm
	static var bb:Vector<JByteBuffer>;
	#end

	public static function init(n:Int) {
		bufs = new Vector(n);
		for (i in 0...n)
			bufs[i] = null;
		#if jvm
		bb = new Vector(n);
		#end
	}

	// the buffers there are room for
	public static inline function buffers():Int
		return Memory.BUFFERS;

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
		#if jvm
		bb[i] = JByteBuffer.wrap(b.getData()).order(JByteOrder.LITTLE_ENDIAN);
		#end
	}

	public static inline function capacity(i:Int):Int
		return bufs[i].length;

	#if jvm
	public static inline function getI32(a:Int):Int
		return bb[a >>> SHIFT].getInt(a & MASK);

	public static inline function setI32(a:Int, v:Int)
		bb[a >>> SHIFT].putInt(a & MASK, v);

	public static inline function getF64(a:Int):Float
		return bb[a >>> SHIFT].getDouble(a & MASK);

	public static inline function setF64(a:Int, v:Float)
		bb[a >>> SHIFT].putDouble(a & MASK, v);

	public static inline function getF32(a:Int):Float
		return bb[a >>> SHIFT].getFloat(a & MASK);

	public static inline function setF32(a:Int, v:Float)
		bb[a >>> SHIFT].putFloat(a & MASK, v);

	public static inline function getU8(a:Int):Int
		return bufs[a >>> SHIFT].get(a & MASK);

	public static inline function setU8(a:Int, v:Int)
		bufs[a >>> SHIFT].set(a & MASK, v & 0xFF);
	#else
	public static inline function getI32(a:Int):Int
		return bufs[a >>> SHIFT].getInt32(a & MASK);

	public static inline function setI32(a:Int, v:Int)
		bufs[a >>> SHIFT].setInt32(a & MASK, v);

	public static inline function getF64(a:Int):Float
		return bufs[a >>> SHIFT].getDouble(a & MASK);

	public static inline function setF64(a:Int, v:Float)
		bufs[a >>> SHIFT].setDouble(a & MASK, v);

	public static inline function getF32(a:Int):Float
		return bufs[a >>> SHIFT].getFloat(a & MASK);

	public static inline function setF32(a:Int, v:Float)
		bufs[a >>> SHIFT].setFloat(a & MASK, v);

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
