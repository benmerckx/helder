package async;

import haxe.Exception;
import haxe.exceptions.CancellationException;
import helder.async.*;
import helder.async.Async.TimeoutException;
import helder.test.Test;

// helder.async's tasks, cancellation, errors and timers (AsyncTest.hx has
// the loop and the I/O): `bun run helder test tests/async`. The tests of
// Async.run itself are plain, the others coroutines on the runner's loop.
function tests() {
	describe("tasks", () -> {
		test("run returns the body's result", () -> equals(Async.run(_ -> 7), 7));
		test("children run concurrently", async(() -> {
			var log = [];
			var r = Async.scope(task -> {
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
				log.push("main");
				a.await() + b.await();
			});
			equals(r, 3);
			equals(log, ["main", "b", "a"]);
		}));
		test("all, in order", async(() -> {
			var all = Async.scope(task -> Async.all([for (i in 0...5) task.async(_ -> {
				Async.delay(0.01 * (5 - i));
				i * i;
			})]));
			equals(all, [0, 1, 4, 9, 16]);
		}));
		test("run waits for the children it did not await", () -> {
			var childDone = false;
			Async.run(task -> {
				task.async(_ -> {
					Async.delay(0.02);
					childDone = true;
				});
				0;
			});
			assert(childDone);
		});
		test("awaitChildren", async(() -> {
			var n = Async.scope(task -> {
				var count = 0;
				for (i in 0...3)
					task.async(_ -> {
						Async.delay(0.01);
						count++;
					});
				task.awaitChildren();
				count;
			});
			equals(n, 3);
		}));
		test("scope", async(() -> {
			var nested = Async.scope(s -> {
				var x = s.async(_ -> {
					Async.yield();
					5;
				});
				x.await() * 2;
			});
			equals(nested, 10);
		}));
		test("launch: runs when the loop turns", () -> {
			var t = Async.launch(_ -> {
				Async.delay(0.01);
				"launched";
			});
			assert(t.isActive());
			Loop.current().runUntil(() -> !t.isActive());
			equals(t.get(), "launched");
		});
		test("the context has the task", async(() -> assert(Async.context().get(Node.key) != null)));
	});

	describe("cancellation", () -> {
		test("a cancelled child", async(() -> {
			var log = [];
			Async.scope(task -> {
				var a = task.async(_ -> {
					try Async.delay(10) catch (e:CancellationException) {
						log.push("a cancelled");
						throw e;
					}
					log.push("a not cancelled");
				});
				Async.delay(0.01);
				a.cancel();
				try a.await() catch (e:CancellationException) log.push("await threw");
			});
			equals(log, ["a cancelled", "await threw"]);
		}));
		test("reaches children and grandchildren", () -> {
			var deep = 0;
			var t0 = haxe.Timer.stamp();
			var root = Async.launch(task -> {
				task.async(c -> {
					c.async(_ -> try Async.delay(10) catch (e:CancellationException) {
						deep++;
						throw e;
					});
					try Async.delay(10) catch (e:CancellationException) {
						deep++;
						throw e;
					}
				});
				Async.delay(10);
			});
			var l = Loop.current();
			l.turn(0);
			root.cancel();
			l.runUntil(() -> !root.isActive());
			equals(deep, 2);
			assert(root.getError() is CancellationException, "the root's error: a cancellation");
			assert(haxe.Timer.stamp() - t0 < 1, "cancelled timers do not keep the loop");
			assert(!l.alive(), "nothing left after a cancellation");
		});
		test("no child starts in a cancelled task", () -> {
			var ran = false;
			var p = Async.launch(task -> {
				task.cancel();
				task.async(_ -> ran = true);
				Async.delay(1);
			});
			Loop.current().runUntil(() -> !p.isActive());
			assert(!ran);
		});
		test("a child's cancellation leaves its parent alone", async(() -> {
			equals(Async.scope(task -> {
				var c = task.async(_ -> Async.delay(10));
				Async.yield();
				c.cancel();
				Async.delay(0.01);
				"parent fine";
			}), "parent fine");
		}));
	});

	describe("errors", () -> {
		test("run throws the body's error", () -> {
			var e:Exception = throws(() -> Async.run(_ -> {
				Async.delay(0.01);
				throw new Exception("boom");
			}));
			equals(e?.message, "boom");
		});
		test("a child's error becomes the parent's and cancels its siblings", async(() -> {
			var siblingCancelled = false;
			var e:Exception = throwsAsync(() -> Async.scope(task -> {
				task.async(_ -> try Async.delay(10) catch (c:CancellationException) {
					siblingCancelled = true;
					throw c;
				});
				task.async(_ -> {
					Async.delay(0.01);
					throw new Exception("child failed");
				});
				Async.delay(10);
				"not here";
			}));
			equals(e?.message, "child failed");
			assert(siblingCancelled);
		}));
		test("a scope's error caught by its caller", async(() -> {
			var r = try Async.scope(s -> {
				s.async(_ -> throw new Exception("inner"));
				Async.delay(10);
				"no";
			}) catch (e:Exception) "caught " + e.message;
			equals(r, "caught inner");
		}));
		test("await throws the child's error, and so does its parent", async(() -> {
			var inner = "";
			var outer:Exception = throwsAsync(() -> Async.scope(task -> {
				var t = task.async(_ -> {
					throw new Exception("x");
					0;
				});
				try t.await() catch (e:Exception) inner = e.message;
				Async.delay(1);
			}));
			equals(inner + outer?.message, "xx");
		}));
		// (tests/async/rep/CatchThenCall.hx)
		test("a caught error stays caught", async(() -> {
			try Async.timeout(0.01, _ -> Async.delay(1)) catch (e:TimeoutException) {}
			Async.context();
			Async.suspend(c -> c.resume(1, null));
			assert(true);
		}));
	});

	describe("timers", () -> {
		test("delay", async(() -> {
			var t0 = haxe.Timer.stamp();
			Async.delay(0.05);
			var dt = haxe.Timer.stamp() - t0;
			assert(dt >= 0.045 && dt < 0.5, 'delay(0.05): $dt');
		}));
		test("timeout", async(() -> {
			var r = try Async.timeout(0.02, _ -> {
				Async.delay(10);
				"slow";
			}) catch (e:TimeoutException) "timed out";
			equals(r, "timed out");
			equals(Async.timeout(1, _ -> {
				Async.delay(0.01);
				"fast";
			}), "fast");
		}));
		test("the timeout's timer closed", () -> {
			Async.run(_ -> Async.timeout(1, _ -> Async.delay(0.01)));
			assert(!Loop.current().alive());
		});
		test("yield interleaves", async(() -> {
			var log = [];
			Async.scope(task -> {
				task.async(_ -> for (i in 0...3) {
					log.push("a" + i);
					Async.yield();
				});
				task.async(_ -> for (i in 0...3) {
					log.push("b" + i);
					Async.yield();
				});
				0;
			});
			equals(log.join(","), "a0,b0,a1,b1,a2,b2");
		}));
		test("a lock, in order of arrival", async(() -> {
			var order = [];
			Async.scope(task -> {
				var lock = new Lock();
				for (i in 0...3)
					task.async(_ -> {
						lock.acquire();
						order.push(i);
						Async.delay(0.005);
						order.push(i);
						lock.release();
					});
				0;
			});
			equals(order.join(""), "001122");
		}));
	});
}
