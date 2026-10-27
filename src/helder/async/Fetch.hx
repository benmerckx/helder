package helder.async;

import haxe.io.Bytes;
#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.*;
#end

// A file's bytes, awaited: in the browser a fetch of its URL (relative to the
// page; cancelling the coroutine aborts it), natively the file read at once.
// helder.os.Fetch's, as a coroutine.
//
//   var level = Fetch.bytes("levels/2.glb");
class Fetch {
	@:coroutine public static function bytes(path:String):Bytes {
		#if (hxmc.target == "wasm32-wasi")
		var h = Arena.scopedValue(a -> Web.fetch_start(a.cstring(path)));
		var ok = Async.suspendCancellable(cont -> {
			var done = false;
			Async.loopOf(cont.context).check(() -> {
				if (done) return true;
				var s = Web.fetch_state(h);
				if (s == 0) return false;
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
		return b;
		#else
		return try sys.io.File.getBytes(path) catch (e:Dynamic) throw new haxe.Exception('fetch $path failed: $e');
		#end
	}
}
