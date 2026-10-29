package helder.view.graph;

// Async work a computation returns (DESIGN.md 2, Holds): its answer later
// (a value or an error, once), and a cancel when the run that asked is
// superseded or its owner disposed. helder.async's tasks, helder.asset's
// loads and TypeScript's promises are Awaitables; Later is one by hand.
interface Awaitable<T> {
	function onAnswer(value:T->Void, error:Dynamic->Void):Void;
	function cancel():Void;
}

// An Awaitable answered by hand.
class Later<T> implements Awaitable<T> {
	var ok:Null<T->Void> = null;
	var fail:Null<Dynamic->Void> = null;
	var answered = false;
	var value:Null<T> = null;
	var error:Dynamic = null;
	var failed = false;

	public var cancelled(default, null) = false;

	public function new() {}

	public function onAnswer(ok:T->Void, fail:Dynamic->Void) {
		this.ok = ok;
		this.fail = fail;
		if (answered) deliver();
	}

	public function cancel()
		cancelled = true;

	public function resolve(v:T) {
		if (answered) return;
		answered = true;
		value = v;
		deliver();
	}

	public function reject(e:Dynamic) {
		if (answered) return;
		answered = true;
		error = e;
		failed = true;
		deliver();
	}

	function deliver() {
		if (ok == null || cancelled) return;
		if (failed) fail(error) else ok(value);
	}
}

// (a read of a value not ready, inside the runtime: the computation stops there)
class NotReady extends haxe.Exception {
	public static final instance = new NotReady("a value read before it is ready");
}
