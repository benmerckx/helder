package helder.async;

import haxe.io.Bytes;

// helder.async for code that has no coroutines (a TypeScript program,
// helder/async): each a task started now on this thread's loop, which
// TypeScript awaits as a promise (cancelling the promise cancels it).
class Tasks {
	// done after that many seconds
	public static function delay(seconds:Float):Task<Any>
		return Async.launch(@:coroutine function(_) {
			Async.delay(seconds);
			return null;
		});

	// a file's bytes: natively read, in the browser fetched (Fetch.bytes)
	public static function bytes(path:String):Task<Bytes>
		return Async.launch(@:coroutine function(_) return Fetch.bytes(path));
}
