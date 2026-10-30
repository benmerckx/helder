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
		var n = Web.fetch_length(h);
		var b = Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			Web.fetch_take(h, p);
			BytesPtr.copyIn(b, 0, p, n);
		});
		if (progress != null) progress(n, n);
		return b;
		#else
		var b = try sys.io.File.getBytes(path) catch (e:Dynamic) throw new haxe.Exception('fetch $path failed: $e');
		if (progress != null) progress(b.length, b.length);
		return b;
		#end
	}
}
