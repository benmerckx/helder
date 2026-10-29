package view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Memo;
import helder.view.graph.Graph.*;
import view.graph.Kit;

// createMemo.test.ts "async compute" (the value side; isPending/latest are in
// Verdicts), async-cleanup-timing.test.ts, async-chain-supersession.test.ts,
// first-observer-stale-reader.test.ts
function tests() {
	afterEach(() -> flush());

	describe("async compute", () -> {
		test("should ignore equals on first async resolution without a seeded baseline", () -> {
			var load = new Later<Int>();
			var result:Dynamic = null;
			root(_ -> {
				var a = memo(() -> load, {equals: (_, _) -> true});
				var boundary = loadingBoundary(() -> (a() : Dynamic), () -> "loading");
				renderEffect(() -> result = boundary(), _ -> {});
			});
			flush();
			equals(result, "loading");
			load.resolve(1);
			flush();
			equals(result, 1);
		});

		// (F-7: the old frame's resources live until the transition that replaces it lands)
		test("should not auto-dispose zombie computed when it loses subscribers during transition", () -> {
			var route = signal("home");
			var zombieCleanup = new Spy();
			var load = new Later<String>();
			var asyncMemo:Null<Memo<String>> = null;
			root(_ -> {
				var parent = memo(() -> {
					var child = memo(() -> {
						onCleanup(zombieCleanup.fn0());
						"child";
					});
					if (route() != "home") asyncMemo = memo(() -> load);
					child;
				});
				renderEffect(() -> {
					parent();
					if (asyncMemo != null) asyncMemo();
					null;
				}, _ -> {});
				renderEffect(() -> {
					var component = parent();
					if (route() == "home") return component();
					"fallback";
				}, _ -> {});
			});
			flush();
			equals(zombieCleanup.calls, 0);
			route("profile");
			flush();
			equals(zombieCleanup.calls, 0);
			load.resolve("async");
			flush();
			equals(zombieCleanup.calls, 1);
		});

		test("should throw when reading uninitialized async computed outside reactive scope", () -> {
			var f = new Fetcher((v:Int) -> v);
			var a = root(_ -> {
				var a = memo(() -> f.fetch(42));
				renderEffect(() -> a(), _ -> {});
				a;
			});
			throws(() -> a());
			f.settle();
			equals(a(), 42);
		});

		test("should return stale value when reading re-pending async computed outside reactive scope", () -> {
			var f = new Fetcher((v:Int) -> v);
			var s = signal(1);
			var a = root(_ -> {
				var a = memo(() -> f.fetch(s()));
				renderEffect(() -> a(), _ -> {});
				a;
			});
			f.settle();
			equals(a(), 1);
			s(2);
			flush();
			equals(a(), 1);
			f.settle();
			equals(a(), 2);
		});

		test("diamond should not cause waterfalls on read", () -> {
			var s = signal(1);
			var spy = new Spy();
			var f1 = new Fetcher((v:Int) -> v), f2 = new Fetcher((v:Int) -> v);
			root(_ -> {
				var b = memo(() -> f1.fetch(s()));
				var c = memo(() -> f2.fetch(s()));
				effect(() -> [b(), c()], v -> spy.call(v[0], v[1]));
			});
			equals([f1.calls, f2.calls, spy.calls], [1, 1, 0]);
			f1.settle();
			f2.settle();
			equals([f1.calls, f2.calls, spy.calls], [1, 1, 1]);
			assert(spy.calledWith(1, 1));
			s(2);
			equals([f1.calls, f2.calls, spy.calls], [1, 1, 1]);
			flush();
			equals([f1.calls, f2.calls, spy.calls], [2, 2, 1]);
			f1.resolveAll();
			f2.resolveAll();
			flush();
			equals([f1.calls, f2.calls, spy.calls], [2, 2, 2]);
			assert(spy.calledWith(2, 2));
		});

		test("keeps shared downstream pending after one async source settles unchanged", () -> {
			var triggerA = signal(0), triggerB = signal(0), tick = signal(0);
			var nextA = 1, nextB = 1;
			var fa = new Fetcher((v:Int) -> v), fb = new Fetcher((v:Int) -> v);
			var a = memo(() -> {
				triggerA();
				fa.fetch(nextA);
			});
			var b = memo(() -> {
				triggerB();
				fb.fetch(nextB);
			});
			var shared = memo(() -> a() + b());
			var middle = memo(() -> shared() * 2);
			var downstream = memo(() -> {
				tick();
				middle();
			});
			var values:Array<Int> = [], pending:Array<Bool> = [];
			root(_ -> {
				renderEffect(() -> downstream(), v -> values.push(v));
				renderEffect(() -> isPending(() -> downstream()), v -> pending.push(v));
			});
			flush();
			equals(values, []);
			equals(pending, []);
			fa.resolveAll();
			flush();
			equals(values, []);
			equals(pending, []);
			fb.resolveAll();
			flush();
			equals(values, [4]);
			equals(pending, [false]);

			nextA = 1;
			nextB = 3;
			triggerA(1);
			triggerB(1);
			flush();
			equals(values, [4]);
			equals(pending, [false, true]);
			fa.resolveAll();
			flush();
			equals(values, [4]);
			equals(pending[pending.length - 1], true);
			assert(!pending.slice(2).contains(false));
			tick(1);
			flush();
			equals(values, [4]);
			equals(pending[pending.length - 1], true);
			assert(!pending.slice(2).contains(false));
			fb.resolveAll();
			flush();
			equals(values, [4, 8]);
			equals(pending[pending.length - 1], false);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("should waterfall when dependent on another async with shared source", () -> {
			var s = signal(1);
			var spy = new Spy();
			var calls1 = 0, calls2 = 0;
			var f = new Fetcher((v:Int) -> v);
			root(_ -> {
				var a:Memo<Int> = null;
				a = memo(() -> {
					calls1++;
					f.fetch(s());
				});
				var b = memo(() -> {
					calls2++;
					f.fetch(s() + a());
				});
				effect(() -> b(), v -> spy.call(v));
			});
			equals([calls1, calls2, spy.calls], [1, 1, 0]);
			f.settle();
			equals([calls1, calls2, spy.calls], [1, 2, 1]);
			assert(spy.calledWith(2));
			s(2);
			equals([calls1, calls2, spy.calls], [1, 2, 1]);
			flush();
			equals([calls1, calls2, spy.calls], [2, 3, 1]);
			f.settle();
			equals([calls1, calls2, spy.calls], [2, 4, 2]);
			assert(spy.calledWith(4));
		});

		test("should drop stale dependencies when an async memo suspends after untracked branching (#2695)", () -> {
			var count = signal(0);
			var runs = 0;
			var done = new Later<Bool>();
			root(_ -> {
				var shouldDoIt = memo(() -> count() % 2 > 0);
				var didIt = memo(() -> {
					if (!untrack(() -> shouldDoIt())) {
						shouldDoIt();
						return Kit.resolved(false);
					}
					runs++;
					done;
				});
				loadingBoundary(() -> didIt(), () -> false)();
			});
			equals(runs, 0);
			count(1);
			flush();
			equals(runs, 1);
			done.resolve(true);
			flush();
			count(2);
			flush();
			count(3);
			flush();
			equals(runs, 1);
		});

		test("error boundary fallback observes repeated async errors from the same source (#2701)", () -> {
			var count = signal(0);
			var requests:Array<Later<String>> = [];
			var view:Memo<String> = null;
			root(_ -> {
				var fetched = memo(() -> {
					count();
					var r = new Later<String>();
					requests.push(r);
					r;
				});
				view = errorBoundary(() -> loadingBoundary(() -> fetched(), () -> "loading")(), (e, _) -> 'error:${e()}');
			});
			equals(view(), "loading");
			requests[0].reject("Fetch error for 0");
			flush();
			equals(view(), "error:Fetch error for 0");
			count(1);
			flush();
			requests[1].reject("Fetch error for 1");
			flush();
			equals(view(), "error:Fetch error for 1");
		});

		test("async memo can wrap a pending async read", () -> {
			var gate = new Later<Int>();
			var f = new Fetcher((v:Int) -> v);
			var outer:Memo<Int> = null;
			var boundary:Memo<Dynamic> = null;
			root(_ -> {
				var inner = memo(() -> gate);
				outer = memo(() -> {
					var value = inner();
					f.fetch(value * 2);
				});
				boundary = loadingBoundary(() -> (outer() : Dynamic), () -> "loading");
			});
			equals(boundary(), "loading");
			gate.resolve(3);
			f.settle();
			equals(outer(), 6);
			equals(boundary(), 6);
			equals(isPending(() -> outer()), false);
		});
	});

	// async-cleanup-timing.test.ts (#4222): a frame's resources live until
	// something replaces it on screen (F-1, F-7)
	describe("async cleanup timing", () -> {
		function setup() {
			var log:Array<String> = [];
			var gates = new Map<String, Later<String>>();
			var q = signal("a");
			root(_ -> {
				var m = memo(() -> {
					var v = q();
					log.push("start " + v);
					onCleanup(() -> log.push("cleanup " + v));
					memo(() -> onCleanup(() -> log.push("child " + v)));
					var l = new Later<String>();
					gates.set(v, l);
					l;
				});
				effect(() -> m(), v -> log.push("show " + v), e -> log.push("error " + e));
			});
			flush();
			return {log: log, gates: gates, q: q};
		}

		test("a run that never committed is cleaned up when superseded; the committed one when the replacement lands", () -> {
			var s = setup();
			s.gates.get("a").resolve("A");
			flush();
			s.q("b");
			flush();
			s.q("c");
			flush();
			equals(s.log, ["start a", "show A", "start b", "child b", "cleanup b", "start c"]);
			s.log.resize(0);
			s.gates.get("c").resolve("C");
			flush();
			equals(s.log, ["child a", "cleanup a", "show C"]);
		});

		test("a rejected replacement retires the frame it replaces", () -> {
			var s = setup();
			s.gates.get("a").resolve("A");
			flush();
			s.q("b");
			flush();
			s.log.resize(0);
			s.gates.get("b").reject("B");
			flush();
			equals(s.log, ["child a", "cleanup a", "error B"]);
			s.log.resize(0);
			s.q("c");
			flush();
			equals(s.log, ["child b", "cleanup b", "start c"]);
			s.log.resize(0);
			s.gates.get("c").resolve("C");
			flush();
			equals(s.log, ["show C"]);
		});
	});

	// async-chain-supersession.test.ts: a second write while an async chain is in flight (F-1, F-2)
	describe("a second write while an async chain is in flight", () -> {
		// <Show keyed when={key()}>: the flow effect's compute owns the child, remade on each key
		function remount(key:Void->Any, children:Void->Void)
			renderEffect(() -> {
				key();
				children();
			}, _ -> {});

		test("#3373 the stale first-hop landing does not commit the newer signal value", () -> {
			var c = new Clock();
			var count = signal(0);
			root(_ -> {
				var a = memo(() -> c.delay(1000, count()));
				var b = memo(() -> c.delay(1000, a()));
				c.text(() -> '${count()} / ${b()}');
			});
			flush();
			c.advanceTo(2500);
			count(1);
			flush();
			c.advanceTo(4000);
			count(2);
			flush();
			c.advanceTo(9000);
			equals(c.log, ["0 / 0", "2 / 2"]);
		});

		test("the held first-hop answer reveals when the re-asked input lands unchanged", () -> {
			var c = new Clock();
			var count = signal(0);
			root(_ -> {
				var a = memo(() -> c.delay(1000, count() < 1 ? count() : 1));
				var b = memo(() -> c.delay(1000, a()));
				c.text(() -> '${count()} / ${b()}');
			});
			flush();
			c.advanceTo(2500);
			count(1);
			flush();
			c.advanceTo(4000);
			count(2);
			flush();
			c.advanceTo(9000);
			equals(c.log, ["0 / 0", "2 / 1"]);
			equals(c.when, [2000, 5000]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("#3376 isPending stays true across the stale first-hop landing", () -> {
			var c = new Clock();
			var count = signal(0);
			root(_ -> {
				var a = memo(() -> c.delay(400, count()));
				var b = memo(() -> c.delay(400, a()));
				c.text(() -> 'Pending: ${isPending(() -> b())}');
			});
			flush();
			c.advanceTo(1000);
			count(1);
			flush();
			c.advanceTo(1600);
			count(2);
			flush();
			c.advanceTo(5000);
			equals(c.log, ["Pending: false", "Pending: true", "Pending: false"]);
		});

		test("#3374 repeating the held write after remounting the reader publishes with the derived value", () -> {
			var c = new Clock();
			var count = signal(0), version = signal(1);
			root(_ -> {
				var details = memo(() -> c.delay(2000, count()));
				c.text(() -> 'Count: ${count()}');
				remount(() -> version(), () -> c.text(() -> 'Details: ${details()}'));
			});
			flush();
			c.advanceTo(2500);
			count(1);
			flush();
			c.advanceTo(3000);
			version(2);
			flush();
			c.advanceTo(3500);
			count(1);
			flush();
			c.advanceTo(9000);
			equals(c.frames(), ["0: Count: 0", "2000: Details: 0", "3000: Details: 0", "4500: Count: 1 | Details: 1"]);
		});

		test("#3373 x #3374: a reader remounted onto the stale first-hop flight holds on the re-asked input", () -> {
			var c = new Clock();
			var count = signal(0), version = signal(1);
			root(_ -> {
				var a = memo(() -> c.delay(1000, count()));
				var b = memo(() -> c.delay(1000, a()));
				c.text(() -> 'Count: ${count()}');
				remount(() -> version(), () -> c.text(() -> 'B: ${b()}'));
			});
			flush();
			c.advanceTo(2500);
			count(1);
			flush();
			c.advanceTo(4000);
			count(2);
			flush();
			c.advanceTo(4200);
			version(2);
			flush();
			c.advanceTo(9000);
			equals(c.frames(), ["0: Count: 0", "2000: B: 0", "4200: B: 0", "6000: B: 2 | Count: 2"]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("#3374 (two hops) the remounted reader holds through an intermediate memo", () -> {
			var c = new Clock();
			var count = signal(0), version = signal(1);
			root(_ -> {
				var details = memo(() -> c.delay(2000, count()));
				var shown = memo(() -> 'Details: ${details()}');
				c.text(() -> 'Count: ${count()}');
				remount(() -> version(), () -> c.text(() -> shown()));
			});
			flush();
			c.advanceTo(2500);
			count(1);
			flush();
			c.advanceTo(3000);
			version(2);
			flush();
			c.advanceTo(3500);
			count(1);
			flush();
			c.advanceTo(9000);
			equals(c.frames(), ["0: Count: 0", "2000: Details: 0", "4500: Count: 1 | Details: 1"]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});

	// first-observer-stale-reader.test.ts (#3458, A15 reveal corollary; F-2)
	describe("a stale reader that is a flight's first observer registers it", () -> {
		test("revealing a pending memo holds the transaction on it", () -> {
			var c = new Clock();
			var count = signal(0), show = signal(false);
			root(_ -> {
				var a = memo(() -> c.delay(1000, count()));
				var b = memo(() -> c.delay(2000, count()));
				c.text(() -> 'Count: ${count()}', false);
				c.text(() -> 'A: ${a()}', false);
				c.text(() -> 'B: ${show() ? Std.string(b()) : "hidden"}', false);
			});
			flush();
			c.advanceTo(3000);
			count(1);
			flush();
			c.advanceTo(3500);
			show(true);
			flush();
			c.advanceTo(9000);
			equals(c.frames(), ["0: B: hidden | Count: 0", "1000: A: 0", "3500: B: 0", "5000: A: 1 | B: 1 | Count: 1"]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});
}
