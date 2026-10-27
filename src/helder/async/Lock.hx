package helder.async;

import haxe.coro.IContinuation;

// One coroutine at a time between acquire and release (in order of arrival):
// writes of whole messages to a socket several tasks send on.
class Lock {
	var held = false;
	final waiting:Array<IContinuation<Any>> = [];

	public function new() {}

	@:coroutine public function acquire():Void {
		if (!held) {
			held = true;
			return;
		}
		var waiting = waiting;
		Async.suspendCancellable(cont -> {
			waiting.push(cont);
			return _ -> waiting.remove(cont);
		});
	}

	// (the next waiter holds it now: resumed at once, so that no cancellation
	// comes between)
	public function release() {
		var next = waiting.shift();
		if (next == null) held = false else next.resume(null, null);
	}
}
