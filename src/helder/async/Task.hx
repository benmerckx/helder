package helder.async;

import haxe.Exception;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CancellationException;
import helder.async.Node.Body;

// A task: a Node with a result, awaited (hxcoro's ICoroTask). Made by
// Node.async, Async.launch, Async.run.
class Task<T> extends Node implements IContinuation<T> implements IDispatchObject {
	final body:Null<Body<T>>;
	var result:Null<T>;
	var awaiters:Null<Array<IContinuation<T>>>;
	var observers:Null<Array<(result:Null<T>, error:Null<Exception>) -> Void>>;
	var started = false;

	@:allow(helder.async) function new(parent:Null<Node>, context:Context, body:Null<Body<T>>, reports:Bool) {
		super(parent, context, reports);
		this.body = body;
	}

	// its result, or its error thrown (a CancellationException when it was cancelled)
	@:coroutine public function await():T {
		if (done) {
			if (error != null) throw error;
			return result;
		}
		return Async.suspendCancellable(cont -> {
			awaiters ??= [];
			awaiters.push(cont);
			return _ -> awaiters?.remove(cont);
		});
	}

	// its result once done (null before, or when it failed)
	public function get():Null<T>
		return result;

	public function getError():Null<Exception>
		return error;

	// f(result, error) once done (at once if it is)
	public function onCompletion(f:(result:Null<T>, error:Null<Exception>) -> Void) {
		if (done) f(result, error) else {
			observers ??= [];
			observers.push(f);
		}
	}

	// (dispatched: the body starts, unless the parent is cancelling)
	public function onDispatch() {
		if (started) return;
		started = true;
		if (parent != null && parent.error != null && error == null) error = new CancellationException();
		if (error != null || body == null) {
			finished = true;
			check();
			return;
		}
		body(this, this);
	}

	// (the body's completion)
	public function resume(result:Null<T>, error:Null<Exception>) {
		finished = true;
		if (error != null) fail(error) else this.result = result;
		check();
	}

	override function completed() {
		if (error != null) result = null;
		var aw = awaiters, ob = observers;
		awaiters = null;
		observers = null;
		// (awaiters are suspensions, which dispatch themselves: resumed now, before
		// the parent hears of an error and cancels them)
		if (aw != null) for (a in aw)
			a.resume(result, error);
		if (ob != null) for (f in ob)
			f(result, error);
		// (an error nobody hears of)
		if (parent == null && aw == null && ob == null && error != null && !(error is CancellationException))
			Async.unhandled(error);
	}
}

