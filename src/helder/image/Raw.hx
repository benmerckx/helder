package helder.image;

import haxe.io.Bytes;

// Memory as PngCore reads and writes it: on hxmc an address (hxmc.unsafe's
// Ptr, Mem and LibC, inline: what an @:hxmc.unsafe function may call), so
// that the same code runs on the GC heap's Bytes (an address taken at the
// call, before which nothing collects) and on off-heap buffers in a job;
// elsewhere (Eval, JavaScript) Bytes and an offset. Little-endian.
#if (target.name == "hxmc")
abstract Raw(hxmc.unsafe.Ptr) {
	inline function new(p:hxmc.unsafe.Ptr)
		this = p;

	@:from public static inline function ofPtr<T>(p:hxmc.unsafe.Ptr<T>):Raw
		return new Raw(cast p);

	@:to public inline function ptr():hxmc.unsafe.Ptr
		return this;

	// a Bytes' data: valid until the next GC point (take it in the call that uses it)
	public static inline function of(b:Bytes):Raw
		return new Raw(hxmc.unsafe.BytesPtr.of(b, 0, b.length));

	public static inline function malloc(n:Int):Raw
		return new Raw(hxmc.unsafe.LibC.malloc(n));

	public inline function free()
		hxmc.unsafe.LibC.free(this);

	public inline function isNull():Bool
		return this.isNull();

	public inline function add(n:Int):Raw
		return new Raw(this.add(n));

	public inline function u8(i:Int):Int
		return hxmc.unsafe.Mem.getU8(this, i);

	public inline function set8(i:Int, v:Int)
		hxmc.unsafe.Mem.setI8(this, i, v);

	public inline function i32(i:Int):Int
		return hxmc.unsafe.Mem.getI32(this, i);

	public inline function set32(i:Int, v:Int)
		hxmc.unsafe.Mem.setI32(this, i, v);

	// n bytes of src here (overlapping too)
	public inline function move(src:Raw, n:Int)
		hxmc.unsafe.LibC.memmove(this, src.ptr(), n);

	public inline function fill(v:Int, n:Int)
		hxmc.unsafe.LibC.memset(this, v, n);

	// n bytes from here into b
	public inline function copyTo(b:Bytes, n:Int)
		hxmc.unsafe.BytesPtr.copyIn(b, 0, this, n);
}
#else
abstract Raw(RawAt) {
	inline function new(r:RawAt)
		this = r;

	public static inline function of(b:Bytes):Raw
		return new Raw(new RawAt(b, 0));

	public static inline function malloc(n:Int):Raw
		return new Raw(new RawAt(Bytes.alloc(n), 0));

	public inline function free() {}

	public inline function isNull():Bool
		return this == null;

	public inline function add(n:Int):Raw
		return new Raw(new RawAt(this.b, this.o + n));

	public inline function u8(i:Int):Int
		return this.b.get(this.o + i);

	public inline function set8(i:Int, v:Int)
		this.b.set(this.o + i, v & 0xFF);

	public inline function i32(i:Int):Int
		return this.b.getInt32(this.o + i);

	public inline function set32(i:Int, v:Int)
		this.b.setInt32(this.o + i, v);

	public inline function move(src:Raw, n:Int)
		this.b.blit(this.o, src.at().b, src.at().o, n);

	public inline function fill(v:Int, n:Int)
		this.b.fill(this.o, n, v);

	public inline function copyTo(b:Bytes, n:Int)
		b.blit(0, this.b, this.o, n);

	inline function at():RawAt
		return this;
}

private class RawAt {
	public final b:Bytes;
	public final o:Int;

	public inline function new(b, o) {
		this.b = b;
		this.o = o;
	}
}
#end
