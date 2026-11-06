package helder.native;

// What helder/native's C calls (native.c, a definition: the lowering's
// Natives) do around a call where values cross: a string as a C string, a
// typed array's bytes in C's memory, and back. Addresses are numbers
// (doubles: an address of today's machines fits in their 53 bits), C's
// memory malloc's. A program calls them through helder/native (native.string,
// native.free...), the lowering for a call's arguments.
class Script {
	// s as a NUL-terminated UTF-8 string in C's memory (free it), 0 for null
	public static function cstring(s:Null<String>):Float {
		#if (target.name == "hxmc")
		if (s == null) return 0;
		var p = hxmc.unsafe.LibC.malloc((3 * s.length + 1 : hxmc.I64));
		hxmc.rt.MemRepr.utf8To(s, p);
		return address(p);
		#else
		return 0;
		#end
	}

	// the NUL-terminated UTF-8 string at an address, copied (null for 0)
	public static function string(at:Float):Null<String> {
		#if (target.name == "hxmc")
		if (at == 0) return null;
		var c:hxmc.unsafe.CString = cast pointer(at);
		return c.toString();
		#else
		return null;
		#end
	}

	// b's bytes copied into C's memory (free it with back), 0 for null
	public static function bytesIn(b:Null<haxe.io.Bytes>):Float {
		#if (target.name == "hxmc")
		if (b == null) return 0;
		var p = hxmc.unsafe.LibC.malloc(((b.length > 0 ? b.length : 1) : hxmc.I64));
		if (b.length > 0) hxmc.unsafe.LibC.memcpy(p, hxmc.unsafe.BytesPtr.of(b, 0, b.length), (b.length : hxmc.I64));
		return address(p);
		#else
		return 0;
		#end
	}

	// after the call: what C left at an address bytesIn made copied back into b, the memory freed
	public static function bytesBack(at:Float, b:Null<haxe.io.Bytes>) {
		#if (target.name == "hxmc")
		if (at == 0 || b == null) return;
		if (b.length > 0) hxmc.unsafe.BytesPtr.copyIn(b, 0, pointer(at), b.length);
		free(at);
		#end
	}

	// C's memory of malloc's (cstring's, bytesIn's, a C function's) freed
	public static function free(at:Float) {
		#if (target.name == "hxmc")
		if (at != 0) hxmc.unsafe.LibC.free(pointer(at));
		#end
	}

	// n bytes at an address, copied
	public static function bytesAt(at:Float, n:Int):haxe.io.Bytes {
		var b = haxe.io.Bytes.alloc(n);
		#if (target.name == "hxmc")
		if (n > 0 && at != 0) hxmc.unsafe.BytesPtr.copyIn(b, 0, pointer(at), n);
		#end
		return b;
	}

	#if (target.name == "hxmc")
	static function address(p:hxmc.unsafe.Ptr):Float {
		var v:haxe.Int64 = p.toI64();
		var lo = v.low;
		return v.high * 4294967296.0 + (lo < 0 ? lo + 4294967296.0 : lo);
	}

	static function pointer(at:Float):hxmc.unsafe.Ptr
		return hxmc.unsafe.Ptr.ofI64(haxe.Int64.fromFloat(at));
	#end
}
