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
// (App.run's frames: Driven). In the browser (wasm32-wasi) the page's event
// loop turns it from its making on: run returns at once, and a turn comes
// when something is dispatched, a timer is due or a fetch is done
// (src/helder/async/imports.mjs), with or without frames.
//
//   var loop = Loop.current();
//   loop.schedule(500, cont);    // haxe.coro's scheduler: cont resumed in 500 ms
//   while (loop.turn(0.01)) {}   // or loop.run()
@:allow(helder.async)
class Loop extends Dispatcher implements IScheduler implements Driven {
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
	// (the browser: in a turn the page runs, which asks for the next itself;
	// in another (App.run's frames) a dispatch or a timer asks the page)
	var paged = false;
	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	// (POSIX: a pipe a post writes a byte to, the backend polling its read end,
	// made when a source of posts is first held; elsewhere waits are at most
	// 10 ms while one is)
	var wakeRead = -1;
	var wakeWrite = -1;
	var woken = false;
	#end

	function new() {
		io = Io.Backends.create(this);
		if (Driven.MainLoop.main == null) Driven.MainLoop.main = this;
		#if (hxmc.target == "wasm32-wasi")
		Web.start(Callback.addr(webTurn));
		#end
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
		if (!paged) Web.wake(0);
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
		if (!paged) Web.wake(Math.max(0, time - haxe.Timer.stamp()));
		#end
		return t;
	}

	// from any thread: f runs on this loop's thread (between hold and release,
	// the loop waits for posts, polling them at least every 10 ms)
	public function post(f:Void->Void) {
		#if target.threaded
		lock.acquire();
		inbox.push(f);
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var w = woken ? -1 : wakeWrite;
		if (w >= 0) woken = true;
		#end
		lock.release();
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (w >= 0) Wake.write(w);
		#end
		#else
		dispatch(new Call(f));
		#end
	}

	// (a source of posts started, ended: this thread only)
	public function hold() {
		held++;
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (wakeRead < 0 && !Io.Handle.WINDOWS) {
			var fds = Wake.pipe();
			if (fds >= 0) {
				wakeRead = fds & 0xFFFF;
				wakeWrite = fds >>> 16;
			}
		}
		#end
	}

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
		drain();
		var now = haxe.Timer.stamp();
		fire(now);
		var wait = count > 0 ? 0.0 : seconds;
		if (live > 0 && wait != 0) {
			var next = Math.max(0, timers[0].time - now);
			if (wait < 0 || next < wait) wait = next;
		}
		#if target.threaded
		if (held > 0 && !wakes() && (wait < 0 || wait > 0.01)) wait = 0.01;
		// (posted already: at once)
		if (inbox.length > 0) wait = 0;
		#end
		#if (hxmc.target != "wasm32-wasi")
		if (checks.length > 0 && (wait < 0 || wait > 0.01)) wait = 0.01;
		#end
		if (wait < 0 && !alive()) {
			return false;
		}
		if (io.pending() > 0 || (held > 0 && wakes())) io.poll(wait, -1);
		else if (wait > 0) Sys.sleep(wait);
		posts();
		var i = 0;
		while (i < checks.length) {
			if (checks[i]()) checks.splice(i, 1) else i++;
		}
		fire(haxe.Timer.stamp());
		drain();
		return alive();
	}

	// (Driven) a wait for I/O, posts or fd, at most seconds and the next
	// timer; nothing runs
	public function wait(seconds:Float, fd:Int) {
		var now = haxe.Timer.stamp();
		if (count > 0 || (live > 0 && timers[0].time <= now)) return;
		#if target.threaded
		if (inbox.length > 0) return;
		#end
		if (live > 0) {
			var next = timers[0].time - now;
			if (seconds < 0 || next < seconds) seconds = next;
		}
		#if target.threaded
		if (held > 0 && !wakes() && (seconds < 0 || seconds > 0.01)) seconds = 0.01;
		#end
		if (checks.length > 0 && (seconds < 0 || seconds > 0.01)) seconds = 0.01;
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (io.pending() > 0 || (held > 0 && wakes()) || fd >= 0) {
			io.poll(seconds, fd);
			return;
		}
		#end
		if (seconds > 0) Sys.sleep(seconds);
	}

	// (Driven) seconds bounded by what the loop waits for
	public function bound(seconds:Float):Float {
		if (count > 0) return 0;
		if (live > 0) {
			var next = Math.max(0, timers[0].time - haxe.Timer.stamp());
			if (seconds < 0 || next < seconds) seconds = next;
		}
		if ((io.pending() > 0 || held > 0 || checks.length > 0) && (seconds < 0 || seconds > 0.01)) seconds = 0.01;
		return seconds;
	}

	// (posts wake the backend's poll)
	inline function wakes():Bool
		return #if (target.name == "hxmc" && hxmc.target != "wasm32-wasi") wakeRead >= 0 #else false #end;

	#if (hxmc.target == "wasm32-wasi")
	// a turn the page runs: the seconds until the next one is wanted (-1: none)
	@:hxmc.callback static function webTurn():Float {
		var l = current();
		l.paged = true;
		var go = l.turn(0) && !l.stopped;
		l.paged = false;
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
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (woken) {
			woken = false;
			Wake.drain(wakeRead);
		}
		#end
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

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (the wake pipe: non-blocking, not inherited by children)
private class Wake {
	// both ends, read | write << 16; -1 on a failure
	@:hxmc.unsafe public static function pipe():Int {
		var fds = hxmc.unsafe.Mem.stack(8);
		if (hxmc.unsafe.Posix.pipe(fds) != 0) return -1;
		var r = hxmc.unsafe.Mem.getI32(fds, 0), w = hxmc.unsafe.Mem.getI32(fds, 4);
		flags(r);
		flags(w);
		return r | (w << 16);
	}

	// (F_SETFL O_NONBLOCK: Linux's 0x800, the BSDs' 4; F_SETFD FD_CLOEXEC)
	@:hxmc.unsafe static function flags(fd:Int) {
		hxmc.unsafe.Posix.fcntl(fd, 4, hxmc.unsafe.Mem.os() == 1 ? 4 : 0x800);
		hxmc.unsafe.Posix.fcntl(fd, 2, 1);
	}

	@:hxmc.unsafe public static function write(fd:Int) {
		var b = hxmc.unsafe.Mem.stack(8);
		hxmc.unsafe.Mem.setI8(b, 0, 1);
		hxmc.unsafe.Posix.write(fd, b, 1);
	}

	@:hxmc.unsafe public static function drain(fd:Int) {
		var b = hxmc.unsafe.Mem.stack(64);
		while (hxmc.unsafe.Posix.read(fd, b, 64) > 0) {}
	}
}
#end
