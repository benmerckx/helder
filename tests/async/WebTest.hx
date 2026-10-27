import haxe.Exception;
import haxe.exceptions.CancellationException;
import helder.async.*;
import helder.async.Async.TimeoutException;

// helder.async in the browser's loop (wasm32-wasi, run by browser.mjs with
// src/helder/async/imports.mjs: tests/async/web.mjs, under node): main
// returns at once and the page's event loop turns the loop; timers, tasks,
// cancellation, a timeout, fetches. Prints "ok" and the number of checks,
// exits 1 on a failure.
class WebTest {
	static var checks = 0;
	static var failures = 0;

	static function eq<T>(got:T, want:T, what:String) {
		checks++;
		if (got != want) {
			failures++;
			Sys.println('FAIL $what: got $got, want $want');
		}
	}

	static function main() {
		var t0 = haxe.Timer.stamp();
		Async.main(task -> {
			eq(haxe.Timer.stamp() - t0 < 0.5, true, "main returned before the body ran");
			var log = [];
			var a = task.async(_ -> {
				Async.delay(0.03);
				log.push("a");
				1;
			});
			var b = task.async(_ -> {
				Async.delay(0.01);
				log.push("b");
				2;
			});
			eq(a.await() + b.await(), 3, "two tasks");
			eq(log.join(","), "b,a", "in the order of their timers");
			var s = haxe.Timer.stamp();
			Async.delay(0.05);
			var dt = haxe.Timer.stamp() - s;
			eq(dt >= 0.045 && dt < 0.5, true, 'delay(0.05): $dt');
			var c = task.async(_ -> try {
				Async.delay(10);
				"no";
			} catch (e:CancellationException) "cancelled");
			Async.yield();
			c.cancel();
			eq(try c.await() catch (e:CancellationException) "await threw", "await threw", "cancellation");
			eq(try Async.timeout(0.02, _ -> {
				Async.delay(10);
				"slow";
			}) catch (e:TimeoutException) "timed out", "timed out", "timeout");
			eq(Fetch.bytes("hello.txt").toString(), "hello from the page\n", "fetch");
			eq(try {
				Fetch.bytes("missing.txt");
				"found";
			} catch (e:Exception) "failed", "failed", "a fetch that fails");
			var both = Async.all([task.async(_ -> Fetch.bytes("hello.txt").length), task.async(_ -> {
				Async.delay(0.01);
				7;
			})]);
			eq(both.join(","), "20,7", "a fetch and a timer at once");
			Sys.println(failures == 0 ? 'ok ($checks checks)' : '$failures of $checks checks failed');
			Sys.exit(failures == 0 ? 0 : 1);
		});
	}
}
