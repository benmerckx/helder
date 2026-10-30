package helder.async;

import haxe.io.Bytes;
#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.*;
#end

// A file's bytes, awaited: in the browser a fetch of its URL (relative to the
// page; cancelling the coroutine aborts it), natively the file read at once.
// helder.os.Fetch's, as a coroutine. progress, if given, is told the
// bytes received and how many there will be (0 while that is not known):
// in the browser as they arrive (at most every 50 ms), and once all are
// here.
//
//   var level = Fetch.bytes("levels/2.glb");
//   var map = Fetch.bytes("maps/big.bin", (loaded, total) -> trace(loaded / total));
class Fetch {
	@:coroutine public static function bytes(path:String, ?progress:(loaded:Int, total:Int) -> Void):Bytes {
		#if (hxmc.target == "wasm32-wasi")
		var h = fetched(path, progress);
		// (taken straight into the Bytes: no copy in between, no GC point)
		var n = Web.fetch_length(h);
		var b = Bytes.alloc(n);
		take(h, b, n);
		if (progress != null) progress(n, n);
		return b;
		#else
		var b = try sys.io.File.getBytes(path) catch (e:Dynamic) throw new haxe.Exception('fetch $path failed: $e');
		if (progress != null) progress(b.length, b.length);
		return b;
		#end
	}

	#if (hxmc.target == "wasm32-wasi")
	@:hxmc.unsafe static function take(h:Int, b:Bytes, n:Int)
		Web.fetch_take(h, BytesPtr.of(b, 0, n));

	// the same, in a buffer off the collected heap (the caller frees it): a
	// large file (an image to decode as a job) never on the collected heap
	@:coroutine public static function buffer(path:String, ?progress:(loaded:Int, total:Int) -> Void):IoBuffer {
		var h = fetched(path, progress);
		var n = Web.fetch_length(h);
		var b = IoBuffer.alloc(n);
		Web.fetch_take(h, b.ptr);
		if (progress != null) progress(n, n);
		return b;
	}

	// (the fetch's handle, its body here)
	@:coroutine static function fetched(path:String, progress:Null<(loaded:Int, total:Int) -> Void>):Int {
		var h = Arena.scopedValue(a -> Web.fetch_start(a.cstring(path)));
		var told = 0;
		var ok = Async.suspendCancellable(cont -> {
			var done = false;
			Async.loopOf(cont.context).check(() -> {
				if (done) return true;
				var s = Web.fetch_state(h);
				if (s == 0) {
					if (progress != null) {
						var n = Web.fetch_loaded(h);
						if (n != told) {
							told = n;
							progress(n, Web.fetch_total(h));
						}
					}
					return false;
				}
				done = true;
				cont.resume(s == 1, null);
				return true;
			});
			return _ -> if (!done) {
				done = true;
				Web.fetch_free(h);
			};
		});
		if (!ok) {
			Web.fetch_free(h);
			throw new haxe.Exception('fetch $path failed');
		}
		return h;
	}
	#end
}
