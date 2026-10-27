import helder.async.*;

// helder.async's costs: tasks started and awaited, timers, switches between
// two tasks through the loop (yield), a lock passed around. Prints each per
// second.
class AsyncBench {
	static function main() {
		var n = Std.parseInt(Sys.args()[0] ?? "") ?? 100000;
		bench("tasks started and awaited", n, () -> Async.run(task -> {
			var ts = [for (i in 0...n) task.async(_ -> i)];
			var s = 0;
			for (t in ts)
				s += t.await();
			s;
		}));
		bench("timers (delay, in 1000 tasks)", n, () -> Async.run(task -> {
			for (k in 0...1000)
				task.async(_ -> for (i in 0...Std.int(n / 1000))
					Async.delay(0));
			0;
		}));
		bench("switches (yield, 2 tasks)", n, () -> Async.run(task -> {
			for (k in 0...2)
				task.async(_ -> for (i in 0...Std.int(n / 2))
					Async.yield());
			0;
		}));
		bench("raw timers (Loop.schedule, no coroutine)", n, () -> {
			var l = Loop.current(), c = new Count(l);
			for (i in 0...n)
				l.schedule(0, c);
			l.run();
			c.n;
		});
	}

	static function bench(what:String, n:Int, f:Void->Dynamic) {
		var t0 = haxe.Timer.stamp();
		f();
		var dt = haxe.Timer.stamp() - t0;
		Sys.println('$what: ${Math.round(n / dt)}/s (${Math.round(dt * 1000)} ms for $n)');
	}
}

class Count implements haxe.coro.IContinuation<Any> {
	public var context(get, never):haxe.coro.context.Context;
	public var n = 0;

	final ctx:haxe.coro.context.Context;

	public function new(l:Loop)
		ctx = l.context();

	function get_context()
		return ctx;

	public function resume(_:Any, _:haxe.Exception)
		n++;
}
