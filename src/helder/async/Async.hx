package helder.async;

import haxe.Exception;
import haxe.coro.BaseContinuation;
import haxe.coro.IContinuation;
import haxe.coro.SuspensionResult;
import haxe.coro.cancellation.CancellationToken;
import haxe.coro.cancellation.ICancellationCallback;
import haxe.coro.cancellation.ICancellationHandle;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.exceptions.CancellationException;
import helder.async.Node.Body;

// Coroutines on the thread's Loop: the entry points, timers, nested scopes,
// and suspension, the building block of the rest (hxcoro's Coro and
// CoroRun, by the same names, but times in seconds).
//
//   Async.run(task -> {
//     var a = task.async(_ -> { Async.delay(0.1); 1; });
//     var b = task.async(_ -> 2);
//     Async.timeout(1, _ -> a.await() + b.await());
//   });
class Async {
	// body as the root task of this thread's loop, run until it is done: its
	// result, or its error thrown (natively: in the browser it cannot wait, launch)
	public static function run<T>(body:Body<T>):T {
		var t = launch(body);
		var finished = false;
		t.onCompletion((_, _) -> finished = true);
		if (!Loop.current().runUntil(() -> finished))
			throw new Exception("helder.async: the loop ran out of work while the task waits");
		if (t.getError() != null) throw t.getError();
		return t.get();
	}

	// a program's main: run (in the browser launched, the page's event loop
	// turning the loop); an error printed, exit code 1
	public static function main(body:Body<Void>) {
		#if (hxmc.target == "wasm32-wasi")
		launch(body).onCompletion((_, e) -> if (e != null) fatal(e));
		Loop.current().run();
		#else
		try run(body) catch (e:Exception) fatal(e);
		#end
	}

	static function fatal(e:Exception) {
		if (Errors.report(e, "main")) return;
		Sys.stderr().writeString("error: " + e.details() + "\n");
		Sys.exit(1);
	}

	// body as a root task on this thread's loop, started when the loop turns
	public static function launch<T>(body:Body<T>, ?context:Context):Task<T> {
		var loop = Loop.current();
		var t = new Task<T>(null, context ?? loop.context(), body, false);
		loop.dispatch(t);
		return t;
	}

	// resumed after that many seconds (a CancellationException if cancelled first)
	@:coroutine public static function delay(seconds:Float):Void {
		suspendCancellable(cont -> {
			var t = loopOf(cont.context).at(haxe.Timer.stamp() + seconds, cont);
			return _ -> t.close();
		});
	}

	// resumed after what is ready and the next poll for I/O
	@:coroutine public static function yield():Void {
		delay(0);
	}

	// body in a task of its own, awaited with its children; an error in them
	// is thrown here (it cancels this task only if not caught)
	@:coroutine public static function scope<T>(body:Body<T>):T {
		return suspend(cont -> {
			var t = new Task<T>(cont.context.get(Node.key), cont.context, body, false);
			t.onCompletion((r, e) -> resumeLater(cont, r, e));
			t.loop.dispatch(t);
		});
	}

	// scope, cancelled after that many seconds: then a TimeoutException
	@:coroutine public static function timeout<T>(seconds:Float, body:Body<T>):T {
		return suspend(cont -> {
			var t = new Task<T>(cont.context.get(Node.key), cont.context, body, false);
			var e = new TimeoutException();
			var timer = t.loop.at(haxe.Timer.stamp() + seconds, new Call(cont.context, () -> t.cancel(e)));
			t.onCompletion((r, err) -> {
				timer.close();
				resumeLater(cont, r, err);
			});
			t.loop.dispatch(t);
		});
	}

	// each task's result, in order (the first error thrown: structured
	// concurrency cancels the others)
	@:coroutine public static function all<T>(tasks:Array<Task<T>>):Array<T> {
		var out = [];
		for (t in tasks)
			out.push(t.await());
		return out;
	}

	// the current coroutine's context
	@:coroutine(transformed)
	public static function context(completion:IContinuation<Any>):SuspensionResult<Context> {
		stale(completion);
		return SuspensionResult.withResult(completion.context);
	}

	// the current coroutine suspended until f's continuation is resumed (at
	// once if f resumes it; later through the loop)
	@:coroutine(transformed)
	public static function suspend<T>(completion:IContinuation<T>, f:IContinuation<T>->Void):SuspensionResult<T> {
		stale(completion);
		var s = new Suspension(completion);
		f(s);
		return s.resolve();
	}

	// suspend, also resumed by the context's cancellation (a
	// CancellationException), after the function f returned is called
	// (undoing what it started; null: nothing to undo)
	@:coroutine(transformed)
	public static function suspendCancellable<T>(completion:IContinuation<T>, f:IContinuation<T>->Null<CancellationException->Void>):SuspensionResult<T> {
		stale(completion);
		var token = completion.context.get(CancellationToken.key);
		var c = token?.cancellationException;
		if (c != null) return cast SuspensionResult.withError(c);
		var s = new Suspension(completion);
		s.undo = f(s);
		if (!s.done && token != null) s.handle = token.onCancellationRequested(s);
		return s.resolve();
	}

	// cont resumed on its loop, after what runs now (through its dispatcher)
	public static function resumeLater<T>(cont:IContinuation<T>, result:Null<T>, error:Null<Exception>) {
		var d = cont.context.get(Dispatcher);
		var r = new Resumption(cont, result, error);
		if (d != null) d.dispatch(r) else r.onDispatch();
	}

	// (the caller's error of an earlier resumption, which it caught, cleared:
	// the coroutine transform checks it again after a call that returns at
	// once, and would throw it a second time; tests/async/rep/CatchThenCall.hx)
	static inline function stale(c:IContinuation<Dynamic>)
		if (c is BaseContinuation) (cast c : BaseContinuation<Dynamic>).error = null;

	// the loop a context's coroutine resumes on
	public static function loopOf(c:Context):Loop {
		var d = c.get(Dispatcher);
		return d is Loop ? cast d : Loop.current();
	}

	@:allow(helder.async) static function unhandled(e:Exception)
		if (!Errors.report(e, "task")) Sys.stderr().writeString("helder.async: unhandled error in a task: " + e.details() + "\n");
}

// a cancellation because a time ran out (Async.timeout; hxcoro's TimeoutException)
class TimeoutException extends CancellationException {}

// a suspension's continuation: resumed once (by f, the loop or a cancellation)
@:allow(helder.async)
private class Suspension<T> implements IContinuation<T> implements IDispatchObject implements ICancellationCallback {
	public var context(get, never):Context;

	final completion:IContinuation<T>;
	var result:Null<T>;
	var error:Null<Exception>;
	var done = false;
	var suspended = false;
	var undo:Null<CancellationException->Void>;
	var handle:Null<ICancellationHandle>;

	public function new(completion) {
		this.completion = completion;
	}

	inline function get_context()
		return completion.context;

	public function resume(result:Null<T>, error:Null<Exception>) {
		if (done) return;
		done = true;
		this.result = result;
		this.error = error;
		undo = null;
		if (handle != null) handle.close();
		if (suspended) {
			var d = completion.context.get(Dispatcher);
			if (d != null) d.dispatch(this) else onDispatch();
		}
	}

	public function onCancellation(cause:CancellationException) {
		if (done) return;
		var u = undo;
		handle = null;
		resume(null, cause);
		if (u != null) u(cause);
	}

	public function onDispatch()
		completion.resume(result, error);

	function resolve():SuspensionResult<T> {
		if (!done) {
			suspended = true;
			return cast SuspensionResult.suspended;
		}
		if (error != null) return cast SuspensionResult.withError(error);
		return cast SuspensionResult.withResult(result);
	}
}

private class Resumption<T> implements IDispatchObject {
	final cont:IContinuation<T>;
	final result:Null<T>;
	final error:Null<Exception>;

	public function new(cont, result, error) {
		this.cont = cont;
		this.result = result;
		this.error = error;
	}

	public function onDispatch()
		cont.resume(result, error);
}

// a function as a continuation (a timer's)
private class Call implements IContinuation<Any> {
	public var context(get, never):Context;

	final ctx:Context;
	final f:Void->Void;

	public function new(ctx, f) {
		this.ctx = ctx;
		this.f = f;
	}

	inline function get_context()
		return ctx;

	public function resume(_:Any, _:Exception)
		f();
}
