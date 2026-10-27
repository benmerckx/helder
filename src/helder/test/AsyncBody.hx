package helder.test;

import haxe.coro.Coroutine;
import helder.async.Async;
import helder.test.Runner;

// A coroutine as a test's step, on helder.async's loop with a timeout (a
// class of its own: only programs with async tests link helder.async).
// Natively and on Eval the loop runs until the step is done; in the
// browser's loop (wasm32-wasi) the step is launched and the page's event
// loop turns it, the runner going on when it is done.
class AsyncBody {
	public static function of(f:Coroutine<() -> Void>):Body
		return Coro((seconds, done) -> {
			var t = Async.launch(_ -> {
				try {
					Async.timeout(seconds, _ -> f());
				} catch (e:TimeoutException) {
					Runner.timedOut(seconds);
				}
				null;
			});
			t.onCompletion((_, e) -> done(e));
			#if (hxmc.target == "wasm32-wasi")
			helder.async.Loop.current().run();
			#else
			var finished = false;
			t.onCompletion((_, _) -> finished = true);
			helder.async.Loop.current().runUntil(() -> finished);
			#end
		});
}
