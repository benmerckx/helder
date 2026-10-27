package helder.async;

import haxe.Int64;
import haxe.coro.IContinuation;
import haxe.coro.context.Context;
import haxe.coro.dispatchers.Dispatcher;
import haxe.coro.dispatchers.IDispatchObject;
import haxe.coro.schedulers.IScheduler;
import haxe.coro.schedulers.ISchedulerHandle;
#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.Callback;
#end

// A thread's event loop: haxe.coro's Dispatcher and IScheduler for the
// coroutines of that thread. It runs what is dispatched to it (each
// continuation resumed here, never on another thread), timers, and what
// waits on I/O (Io: operations on sockets, pipes and processes) until nothing is left
// or stop(). `run` blocks; `turn(seconds)` runs what is ready and waits at
// most that long (0: not at all), for a loop driven by another one
// (App.run's frames). In the browser (wasm32-wasi) the page's event loop
// turns it: run returns at once, and a turn comes when something is
// dispatched, a timer is due or a fetch is done (src/helder/async/imports.mjs).
//
//   var loop = Loop.current();
//   loop.schedule(500, cont);    // haxe.coro's scheduler: cont resumed in 500 ms
//   while (loop.turn(0.01)) {}   // or loop.run()
@:allow(helder.async)
class Loop extends Dispatcher implements IScheduler {
	#if target.threaded
	static final tls = new sys.thread.Tls<Loop>();
	#else
	static var only:Null<Loop>;
	#end

	// what is ready, in order: a ring
	var ready:Array<Null<IDispatchObject>> = [for (_ in 0...64) null];
	var head = 0;
	var count = 0;
	// timers: a binary heap by time, then by order of scheduling
	final timers:Array<Timer> = [];
	var live = 0;
	var order = 0;
	// I/O: operations submitted, completed (Io.Backend)
	public final io:Io.Backend;
	// conditions checked each turn (a fetch in the browser): true when done
	final checks:Array<Void->Bool> = [];
	// other threads' posts (Loop.post) and how many sources may still post
	#if target.threaded
	final inbox:Array<Void->Void> = [];
	final lock = new sys.thread.Mutex();
	#end
	var held = 0;
	var stopped = false;
	var turning = false;

	function new() {
		io = Io.Backends.create(this);
	}

	// this thread's loop (made the first time)
	public static function current():Loop {
		#if target.threaded
		var l = tls.value;
		if (l == null) tls.value = l = new Loop();
		return l;
		#else
		return only ??= new Loop();
		#end
	}

	// the context of a coroutine started on this loop
	public function context():Context
		return Context.create(this);

	function get_scheduler():IScheduler
		return this;

	public function dispatch(obj:IDispatchObject) {
		if (count == ready.length) {
			var n = [for (_ in 0...count * 2) null];
			for (i in 0...count)
				n[i] = ready[(head + i) % ready.length];
			ready = n;
			head = 0;
		}
		ready[(head + count) % ready.length] = obj;
		count++;
		#if (hxmc.target == "wasm32-wasi")
		if (!turning) Web.wake(0);
		#end
	}

	// in ms; the continuation resumed through its own dispatcher
	public function schedule<T>(ms:Int64, cont:IContinuation<T>):ISchedulerHandle
		return at(haxe.Timer.stamp() + Int64.toInt(ms) / 1000, cast cont);

	public function now():Int64
		return Int64.fromFloat(haxe.Timer.stamp() * 1000);

	// a timer due at `time` (seconds of haxe.Timer.stamp), resuming cont
	public function at(time:Float, cont:IContinuation<Any>):Timer {
		var t = new Timer(this, time, order++, cont);
		timers.push(t);
		up(timers.length - 1);
		live++;
		#if (hxmc.target == "wasm32-wasi")
		if (!turning) Web.wake(Math.max(0, time - haxe.Timer.stamp()));
		#end
		return t;
	}

	// from any thread: f runs on this loop's thread (between hold and release,
	// the loop waits for posts, polling them at least every 10 ms)
	public function post(f:Void->Void) {
		#if target.threaded
		lock.acquire();
		inbox.push(f);
		lock.release();
		#else
		dispatch(new Call(f));
		#end
	}

	// (a source of posts started, ended: this thread only)
	public function hold()
		held++;

	public function release()
		held--;

	// f called each turn until it returns true (keeps the loop alive meanwhile)
	public function check(f:Void->Bool)
		checks.push(f);

	public function stop()
		stopped = true;

	// whether anything is left: ready, a timer, a wait on I/O, a check or a source of posts
	public function alive():Bool
		return count > 0 || live > 0 || io.pending() > 0 || checks.length > 0 || held > 0;

	// until nothing is left or stop() (the browser: returns at once, the page turns the loop)
	public function run() {
		stopped = false;
		#if (hxmc.target == "wasm32-wasi")
		Web.start(Callback.addr(webTurn));
		#else
		while (!stopped && turn(-1)) {}
		#end
	}

	// until done() or nothing is left; false: nothing was left
	public function runUntil(done:Void->Bool):Bool {
		stopped = false;
		while (!done()) {
			if (stopped || !turn(-1)) return done();
		}
		return true;
	}

	// what is ready runs, then due timers; then a wait for I/O (or the next
	// timer) of at most `seconds` (-1: as long as needed, 0: none) unless
	// something is ready; whether anything is left
	public function turn(seconds:Float):Bool {
		turning = true;
		drain();
		var now = haxe.Timer.stamp();
		fire(now);
		var wait = count > 0 ? 0.0 : seconds;
		if (live > 0 && wait != 0) {
			var next = Math.max(0, timers[0].time - now);
			if (wait < 0 || next < wait) wait = next;
		}
		#if target.threaded
		if (held > 0 && (wait < 0 || wait > 0.01)) wait = 0.01;
		#end
		#if (hxmc.target != "wasm32-wasi")
		if (checks.length > 0 && (wait < 0 || wait > 0.01)) wait = 0.01;
		#end
		if (io.pending() > 0) io.poll(wait);
		else if (wait > 0) Sys.sleep(wait);
		else if (wait < 0 && !alive()) {
			turning = false;
			return false;
		}
		posts();
		var i = 0;
		while (i < checks.length) {
			if (checks[i]()) checks.splice(i, 1) else i++;
		}
		fire(haxe.Timer.stamp());
		drain();
		turning = false;
		return alive();
	}

	#if (hxmc.target == "wasm32-wasi")
	// a turn the page runs: the seconds until the next one is wanted (-1: none)
	@:hxmc.callback static function webTurn():Float {
		var l = current();
		var go = l.turn(0) && !l.stopped;
		Sys.stdout().flush();
		if (!go) return -1;
		if (l.count > 0) return 0;
		return l.live > 0 ? Math.max(0, l.timers[0].time - haxe.Timer.stamp()) : -1;
	}
	#end

	function drain() {
		while (count > 0) {
			var o = ready[head];
			ready[head] = null;
			head = (head + 1) % ready.length;
			count--;
			o.onDispatch();
		}
	}

	function posts() {
		#if target.threaded
		if (held == 0 && inbox.length == 0) return;
		lock.acquire();
		var fs = inbox.splice(0, inbox.length);
		lock.release();
		for (f in fs)
			f();
		#end
	}

	// the due timers' continuations dispatched (each through its own dispatcher)
	function fire(now:Float) {
		while (timers.length > 0 && timers[0].time <= now) {
			var t = pop();
			if (t.cont == null) continue;
			t.fired = true;
			live--;
			var d = t.cont.context.get(Dispatcher);
			(d ?? this).dispatch(t);
		}
	}

	@:allow(helder.async.Timer) function cancelled()
		live--;

	function pop():Timer {
		var top = timers[0];
		var last = timers.pop();
		if (timers.length > 0) {
			timers[0] = last;
			down(0);
		}
		return top;
	}

	inline function less(a:Timer, b:Timer):Bool
		return a.time < b.time || (a.time == b.time && a.seq < b.seq);

	function up(i:Int) {
		var t = timers[i];
		while (i > 0) {
			var p = (i - 1) >> 1;
			if (!less(t, timers[p])) break;
			timers[i] = timers[p];
			i = p;
		}
		timers[i] = t;
	}

	function down(i:Int) {
		var n = timers.length, t = timers[i];
		while (true) {
			var c = 2 * i + 1;
			if (c >= n) break;
			if (c + 1 < n && less(timers[c + 1], timers[c])) c++;
			if (!less(timers[c], t)) break;
			timers[i] = timers[c];
			i = c;
		}
		timers[i] = t;
	}
}

// a scheduled resumption: close() cancels it
@:allow(helder.async.Loop)
class Timer implements ISchedulerHandle implements IDispatchObject {
	final loop:Loop;
	public final time:Float;
	final seq:Int;
	var cont:Null<IContinuation<Any>>;
	var fired = false;

	function new(loop, time, seq, cont) {
		this.loop = loop;
		this.time = time;
		this.seq = seq;
		this.cont = cont;
	}

	public function close() {
		if (cont == null || fired) return;
		cont = null;
		loop.cancelled();
	}

	public function onDispatch() {
		var c = cont;
		if (c == null) return;
		cont = null;
		c.resume(null, null);
	}
}

private class Call implements IDispatchObject {
	final f:Void->Void;

	public function new(f)
		this.f = f;

	public function onDispatch()
		f();
}
