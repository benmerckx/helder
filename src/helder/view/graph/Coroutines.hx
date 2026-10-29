package helder.view.graph;

import haxe.coro.Coroutine;

// How a coroutine computation starts (DESIGN.md 2, Holds): helder.async
// registers it (Loop's module, when linked), so that the graph needs no
// loop. The body runs now, inside the computation (its reads up to the
// first suspension tracked), as a task; ok or fail its completion; the
// function returned cancels the task and those under it.
class Coroutines {
	public static var start:Null<(body:Coroutine<Void->Dynamic>, ok:Dynamic->Void, fail:Dynamic->Void) -> (Void->Void)> = null;
}

// (a coroutine computation's Awaitable: started when made)
@:allow(helder.view.graph)
class CoroutineRun<T> implements Awaitable<T> {
	final later = new Awaitable.Later<T>();
	final stop:Void->Void;

	function new(body:Coroutine<Void->Dynamic>) {
		if (Coroutines.start == null) throw new Owner.GraphError("a coroutine computation needs helder.async (its loop runs the coroutine)");
		stop = Coroutines.start(body, v -> later.resolve(v), e -> later.reject(e));
	}

	public function onAnswer(value:T->Void, error:Dynamic->Void)
		later.onAnswer(value, error);

	public function cancel() {
		later.cancel();
		stop();
	}
}
