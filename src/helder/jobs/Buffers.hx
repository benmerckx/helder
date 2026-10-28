package helder.jobs;

import hxmc.unsafe.LibC;
import hxmc.unsafe.Mem;
import hxmc.unsafe.Ptr;

// IoBuffers made without a GC point (an IoBuffer's own alloc throws when
// out of memory): its layout, hxmc.unsafe.IoBuffer's (a 16-byte header whose
// second word is a NativeArray<Byte>'s, then the bytes)
class Buffers {
	public static inline var HEADER = 16;

	// an IoBuffer of n bytes, not zeroed (nil when out of memory)
	@:hxmc.unsafe public static function alloc(n:Int):Ptr {
		if (n < 0) return Ptr.nil();
		var p = LibC.malloc(HEADER + n);
		if (p.isNull()) return p;
		header(p, n);
		return p;
	}

	// (its length set: n bytes, no more than it has)
	@:hxmc.unsafe public static function header(p:Ptr, n:Int) {
		var words = (n + 7) >> 3;
		Mem.setI64(p, 0, 0);
		Mem.setI16(p, 8, hxmc.rt.Types.T_BYTES);
		Mem.setI16(p, 10, words < 0xFFFF ? words : 0xFFFF);
		Mem.setI32(p, 12, n);
	}
}
