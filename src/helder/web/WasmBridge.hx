package helder.web;

#if (target.name == "hxmc" && !macro)
import haxe.io.Bytes;
import hxmc.I64;
import hxmc.unsafe.*;

// The imports of the module "hxmc_web" (src/helder/web/imports.mjs)
@:hxmc.c @:hxmc.lib("hxmc_web") extern class WebImports {
	// fn (a @:hxmc.callback's address) is name, for JavaScript (host.web.exports)
	static function define(name:CString, fn:Ptr):Void;
}

// The module's side of Exports (wasm32-wasi): the wrappers the macro makes
// call these. Bytes and strings cross through blocks of the C heap (they
// do not move): JavaScript allocates one for an argument (__alloc), copies
// the bytes in, frees it after the call (__free); a result is a block of
// its length (Int32) then its bytes, which JavaScript reads and frees (0:
// null).
class WasmBridge {
	static var started = false;

	// __alloc and __free, once
	public static function start() {
		if (started) return;
		started = true;
		define("__alloc", Callback.addr(WasmBridge.alloc));
		define("__free", Callback.addr(WasmBridge.free));
	}

	public static function define(name:String, fn:Ptr)
		Arena.scoped(a -> WebImports.define(a.cstring(name), fn));

	@:hxmc.callback static function alloc(n:Int):Int
		return LibC.malloc((n : I64)).toI64().toInt();

	@:hxmc.callback static function free(p:Int):Void
		LibC.free(Ptr.ofI64((p : I64)));

	// the n bytes at p, copied
	public static function bytesIn(p:Int, n:Int):Bytes {
		var b = Bytes.alloc(n);
		BytesPtr.copyIn(b, 0, Ptr.ofI64((p : I64)), n);
		return b;
	}

	// b in a new block (its length, its bytes); 0 for null
	public static function bytesOut(b:Null<Bytes>):Int {
		if (b == null) return 0;
		var n = b.length;
		var p = LibC.malloc(((n + 4) : I64));
		Mem.setI32(p, 0, n);
		copy(p.add(4), BytesPtr.of(b, 0, n), n);
		return p.toI64().toInt();
	}

	public static function stringOut(s:Null<String>):Int
		return s == null ? 0 : bytesOut(Bytes.ofString(s));

	@:hxmc.noGc static function copy(dst:Ptr, src:Ptr, n:Int)
		LibC.memcpy(dst, src, (n : I64));
}
#end
