package helder.jobs;

import haxe.io.Bytes;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// The bytes a sendable value crosses as (Sendable's codec: a GC job's
// input and result, a channel's messages): written into an IoBuffer, read
// from one. Little-endian; a String as UTF-8. An IoBuffer moves: natively
// its address, in a browser's worker its bytes (the sender's freed).
class Writer {
	var buf:Ptr;
	var cap:Int;
	public var pos(default, null) = 0;

	public function new() {
		cap = 64;
		buf = Buffers.alloc(cap);
		if (buf.isNull()) throw new JobError(-1, "out of memory");
	}

	// room for n more bytes: their address
	public function reserve(n:Int):Ptr {
		if (pos + n > cap) {
			var c = cap * 2;
			while (c < pos + n)
				c *= 2;
			var b = Buffers.alloc(c);
			if (b.isNull()) throw new JobError(-1, "out of memory (" + c + " bytes)");
			LibC.memcpy(b.add(Buffers.HEADER), buf.add(Buffers.HEADER), pos);
			LibC.free(buf);
			buf = b;
			cap = c;
		}
		var p = buf.add(Buffers.HEADER + pos);
		pos += n;
		return p;
	}

	public inline function int(v:Int)
		Mem.setI32(reserve(4), 0, v);

	public inline function float(v:Float)
		Mem.setF64(reserve(8), 0, v);

	public inline function bool(v:Bool)
		Mem.setI8(reserve(1), 0, v ? 1 : 0);

	public inline function int64(v:haxe.Int64) {
		var p = reserve(8);
		Mem.setI32(p, 0, v.low);
		Mem.setI32(p, 4, v.high);
	}

	public function string(s:Null<String>) {
		if (s == null) {
			int(-1);
			return;
		}
		bytes(Bytes.ofString(s));
	}

	// (copied)
	public function bytes(b:Null<Bytes>) {
		if (b == null) {
			int(-1);
			return;
		}
		int(b.length);
		if (b.length > 0) {
			copyIn(reserve(b.length), b);
		}
	}

	static function copyIn(p:Ptr, b:Bytes) {
		// (the address of b's data used at once: a fast call)
		LibC.memcpy(p, hxmc.unsafe.BytesPtr.of(b, 0, b.length), b.length);
	}

	// (moved: natively its address, in a browser's worker its bytes, freed)
	public function buffer(b:IoBuffer) {
		var p:Ptr = cast b;
		if (p.isNull()) {
			int(-1);
			return;
		}
		#if (hxmc.target == "wasm32-wasi")
		int(b.length);
		LibC.memcpy(reserve(b.length), b.ptr, b.length);
		b.free();
		#else
		int(0);
		var q = reserve(8);
		Mem.setPtr(q, 0, p);
		#end
	}

	// the bytes written (the writer is done)
	public function done():IoBuffer {
		var b = buf;
		Buffers.header(b, pos);
		buf = Ptr.nil();
		return cast b;
	}
}

class Reader {
	final buf:IoBuffer;
	var pos = 0;

	public function new(buf:IoBuffer)
		this.buf = buf;

	// n bytes on: their address
	public function at(n:Int):Ptr {
		if (pos + n > buf.length) throw new JobError(-1, "a message ends early");
		var p = buf.ptr.add(pos);
		pos += n;
		return p;
	}

	public inline function int():Int
		return Mem.getI32(at(4), 0);

	public inline function float():Float
		return Mem.getF64(at(8), 0);

	public inline function bool():Bool
		return Mem.getU8(at(1), 0) != 0;

	public inline function int64():haxe.Int64 {
		var p = at(8);
		return haxe.Int64.make(Mem.getI32(p, 4), Mem.getI32(p, 0));
	}

	public function string():Null<String> {
		var b = bytes();
		return b == null ? null : b.toString();
	}

	public function bytes():Null<Bytes> {
		var n = int();
		if (n < 0) return null;
		var b = Bytes.alloc(n);
		if (n > 0) hxmc.unsafe.BytesPtr.copyIn(b, 0, at(n), n);
		return b;
	}

	public function buffer():IoBuffer {
		var n = int();
		if (n < 0) return cast Ptr.nil();
		#if (hxmc.target == "wasm32-wasi")
		var b = IoBuffer.alloc(n);
		LibC.memcpy(b.ptr, at(n), n);
		return b;
		#else
		return cast Mem.getPtr(at(8), 0);
		#end
	}
}
