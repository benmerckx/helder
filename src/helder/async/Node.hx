package helder.async;

import haxe.Exception;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.cancellation.ICancellationToken;
import haxe.coro.context.Context;
import haxe.coro.context.IElement;
import haxe.coro.context.Key;
import haxe.coro.dispatchers.Dispatcher;
import haxe.exceptions.CancellationException;

// a task's body: a coroutine given its task, to start children with
typedef Body<T> = Coroutine<(task:Node) -> T>;

// A node of the task tree (hxcoro's ICoroNode): its children run on the same
// loop, it is done once its body and all its children are, cancelling it
// cancels them, and a child's error (other than a cancellation) cancels it
// and becomes its own. It is the CancellationToken of its body's context
// (haxe.coro's), and its Node element (`Node.key`).
@:allow(helder.async)
class Node implements ICancellationToken implements IElement<Node> {
	public static final key = new Key<Node>("helder.async.Node");

	public var context(get, never):Context;
	public var cancellationException(get, never):Null<CancellationException>;

	final parent:Null<Node>;
	final loop:Loop;
	var ctx:Context;
	// (an error that is not a cancellation, as a token's cancellation)
	var cause:Null<CancellationException>;
	var error:Null<Exception>;
	// the active children; whether the body is over; whether the task is
	var kids:Array<Node> = [];
	// (where this one is in its parent's kids)
	var index = -1;
	var finished = false;
	var done = false;
	// a child's error cancels this one (async), or only its awaiter's (scope, timeout)
	final reports:Bool;
	var callbacks:Null<Array<Null<ICancellationCallback>>>;
	var childWaiter:Null<IContinuation<Any>>;

	function new(parent:Null<Node>, context:Context, reports:Bool) {
		this.parent = parent;
		this.reports = reports;
		var d = context.get(Dispatcher);
		loop = d is Loop ? cast d : Loop.current();
		ctx = context.clone().with(this).set(CancellationToken.key, this);
		if (ctx.get(Dispatcher) == null) ctx = ctx.clone().with(loop);
		if (parent != null) {
			index = parent.kids.length;
			parent.kids.push(this);
		}
	}

	inline function get_context():Context
		return ctx;

	public function getKey()
		return key;

	// a child task, started on the loop (after the current task suspends)
	public function async<T>(body:Body<T>):Task<T> {
		var t = new Task<T>(this, ctx, body, true);
		loop.dispatch(t);
		return t;
	}

	// until every current child is done
	@:coroutine public function awaitChildren():Void {
		if (kids.length == 0) return;
		Async.suspend(cont -> childWaiter = cont);
	}

	// cancels this task and its children (a CancellationException in their awaits)
	public function cancel(?cause:CancellationException) {
		if (done || error != null) return;
		fail(cause ?? new CancellationException());
	}

	public function cancelChildren(?cause:CancellationException) {
		cause ??= new CancellationException();
		for (k in kids.copy())
			k.cancel(cause);
	}

	// whether the task still runs (its body or its children)
	public function isActive():Bool
		return !done;

	public function isCancelling():Bool
		return error != null;

	function get_cancellationException():Null<CancellationException> {
		if (error == null) return null;
		if (error is CancellationException) return cast error;
		return cause ??= new CancellationException();
	}

	public function onCancellationRequested(cb:ICancellationCallback):ICancellationHandle {
		var c = cancellationException;
		if (c != null) {
			cb.onCancellation(c);
			return NoHandle.instance;
		}
		callbacks ??= [];
		callbacks.push(cb);
		return new Registration(this, cb);
	}

	@:allow(helder.async) function unregister(cb:ICancellationCallback) {
		if (callbacks != null) {
			var i = callbacks.indexOf(cb);
			if (i >= 0) {
				callbacks[i] = callbacks[callbacks.length - 1];
				callbacks.pop();
			}
		}
	}

	function fail(e:Exception) {
		if (error != null) return;
		error = e;
		var c = cancellationException;
		var cbs = callbacks;
		callbacks = null;
		if (cbs != null) for (cb in cbs)
			if (cb != null) cb.onCancellation(c);
		cancelChildren(new CancellationException());
		check();
	}

	function childDone(k:Node) {
		var last = kids.pop();
		if (last != k) {
			kids[k.index] = last;
			last.index = k.index;
		}
		if (k.reports && k.error != null && !(k.error is CancellationException)) fail(k.error);
		if (kids.length == 0 && childWaiter != null) {
			var w = childWaiter;
			childWaiter = null;
			Async.resumeLater(w, null, null);
		}
		check();
	}

	function check() {
		if (done || !finished || kids.length > 0) return;
		done = true;
		completed();
		if (parent != null) parent.childDone(this);
	}

	function completed() {}
}

private class Registration implements ICancellationHandle {
	final scope:Node;
	final cb:ICancellationCallback;

	public function new(scope, cb) {
		this.scope = scope;
		this.cb = cb;
	}

	public function close()
		scope.unregister(cb);
}

private class NoHandle implements ICancellationHandle {
	public static final instance = new NoHandle();

	function new() {}

	public function close() {}
}
