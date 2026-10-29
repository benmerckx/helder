package helder.pack;

import haxe.io.Bytes;

// Random bytes from the system's source, for keys (the Android debug key's
// scalar and its certificate's serial: helder.pack.android.DebugKey):
// Windows' BCryptGenRandom (the system's preferred generator), elsewhere
// /dev/urandom (Linux's and macOS's; hxmc's static Linux runtime links no
// getrandom or getentropy). Never a weaker fallback: without a source it
// throws.
class Entropy {
	public static function bytes(n:Int):Bytes {
		#if (target.name == "hxmc")
		// (Mem.os() is the target's: the other branch is not compiled in)
		if (hxmc.unsafe.Mem.os() == 2) {
			var out = Bytes.alloc(n);
			var ok = hxmc.unsafe.Arena.scopedValue(a -> {
				var p = a.alloc(n < 1 ? 1 : n, 1);
				// (BCRYPT_USE_SYSTEM_PREFERRED_RNG: no algorithm handle; STATUS_SUCCESS is 0)
				var r = Bcrypt.BCryptGenRandom(hxmc.unsafe.Ptr.nil(), p, n, 2);
				if (r == 0) hxmc.unsafe.BytesPtr.copyIn(out, 0, p, n);
				r == 0;
			});
			if (ok) return out;
			throw "no random source: BCryptGenRandom failed";
		}
		if (hxmc.unsafe.Mem.os() == 3) throw "no random source on wasm32-wasi";
		#end
		var f = try sys.io.File.read("/dev/urandom", true) catch (_:Dynamic) throw "no random source: no /dev/urandom";
		var b = try f.read(n) catch (e:Dynamic) {
			f.close();
			throw "no random source: /dev/urandom: " + e;
		}
		f.close();
		if (b.length != n) throw "no random source: /dev/urandom gave " + b.length + " bytes";
		return b;
	}
}

#if (target.name == "hxmc")
@:hxmc.c @:hxmc.lib("bcrypt") private extern class Bcrypt {
	static function BCryptGenRandom(alg:hxmc.unsafe.Ptr, buf:hxmc.unsafe.Ptr, n:Int, flags:Int):Int;
}
#end
