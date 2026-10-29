package view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Memo;
import helder.view.graph.Graph.*;
import view.graph.Kit;

// isPending and latest (F-6, F-9, F-10): createMemo.test.ts's verdict tests
// and its A8 describe, spec-async-semantics A16 and A19, latest-*.test.ts,
// isPending-held-sync-memo.test.ts, latest-isPending-consistency.test.ts (#3028)
function tests() {
	afterEach(() -> flush());

	// an async memo over a signal, a render effect keeping it observed
	function asyncTimesTen() {
		var f = new Fetcher((v:Int) -> v * 10);
		var x = signal(1);
		var a = root(_ -> {
			var a = memo(() -> f.fetch(x()));
			renderEffect(() -> a(), _ -> {});
			a;
		});
		return {f: f, x: x, a: a};
	}

	describe("createMemo: isPending and latest", () -> {
		test("should should show stale state with `isPending` in graph", () -> {
			var s = asyncTimesTen();
			s.f.settle();
			var b = memo(() -> isPending(() -> s.a()) ? "stale" : "not stale");
			equals(b(), "not stale");
			s.x(2);
			flush();
			equals(b(), "stale");
			s.f.settle();
			equals(b(), "not stale");
		});

		test("should should show stale state with `isPending` out of graph", () -> {
			var s = asyncTimesTen();
			equals(isPending(() -> s.a()), false);
			s.f.settle();
			equals(isPending(() -> s.a()), false);
			s.x(2);
			flush();
			equals(isPending(() -> s.a()), true);
			s.f.settle();
			equals(isPending(() -> s.a()), false);
		});

		test("should should show pending state in graph", () -> {
			var f = new Fetcher((v:Int) -> v);
			var s = signal(1);
			var res:Null<Int> = null;
			root(_ -> {
				var a = memo(() -> f.fetch(s()));
				renderEffect(() -> latest(() -> s()), v -> res = v);
				renderEffect(() -> a(), _ -> {});
			});
			f.settle();
			equals(res, 1);
			s(2);
			flush();
			equals(res, 2);
			f.settle();
			equals(res, 2);
		});

		test("should should show pending state outside of graph", () -> {
			var f = new Fetcher((v:Int) -> v);
			var s = signal(1);
			root(_ -> {
				var a = memo(() -> f.fetch(s()));
				renderEffect(() -> a(), _ -> {});
			});
			equals(latest(() -> s()), 1);
			f.settle();
			equals(latest(() -> s()), 1);
			s(2);
			flush();
			equals(latest(() -> s()), 2);
			f.settle();
			equals(latest(() -> s()), 2);
		});

		test("should track pending value changes for loading indicator pattern", () -> {
			var f = new Fetcher((v:Int) -> "D" + v);
			var id = signal(0);
			var data = memo(() -> f.fetch(id()));
			var spy = new Spy();
			root(_ -> {
				renderEffect(() -> data(), _ -> {});
				renderEffect(() -> latest(() -> id()), v -> spy.call(v));
			});
			f.settle();
			equals(spy.args[spy.args.length - 1][0], 0);
			id(1);
			flush();
			equals(spy.args[spy.args.length - 1][0], 1);
			f.settle();
			equals(spy.args[spy.args.length - 1][0], 1);
		});

		test("latest() on upstream vs downstream of async", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var syncMemo:Memo<Int> = null, asyncMemo:Memo<Int> = null;
			root(_ -> {
				syncMemo = memo(() -> x() * 2);
				asyncMemo = memo(() -> f.fetch(syncMemo()));
				renderEffect(() -> asyncMemo(), _ -> {});
			});
			f.settle();
			equals(syncMemo(), 2);
			equals(asyncMemo(), 20);
			x(2);
			flush();
			equals(latest(() -> x()), 2);
			equals(x(), 1);
			equals(latest(() -> syncMemo()), 4);
			equals(syncMemo(), 2);
			equals(latest(() -> asyncMemo()), 20);
			equals(asyncMemo(), 20);
			f.settle();
			equals(asyncMemo(), 40);
			equals(syncMemo(), 4);
			equals(x(), 2);
		});

		test("latest() on upstream signal during transition", () -> {
			var s = asyncTimesTen();
			s.f.settle();
			equals(s.a(), 10);
			s.x(2);
			flush();
			equals(latest(() -> s.x()), 2);
			equals(s.x(), 1);
			s.f.settle();
			equals(s.x(), 2);
			equals(latest(() -> s.x()), 2);
		});

		test("isPending and latest on upstream signal that triggers async memo", () -> {
			var s = asyncTimesTen();
			flush();
			equals(isPending(() -> s.x()), false);
			s.f.settle();
			s.x(2);
			flush();
			equals(isPending(() -> s.x()), true);
			equals(latest(() -> s.x()), 2);
			equals(s.x(), 1);
			equals(isPending(() -> s.a()), true);
			s.f.settle();
			equals(isPending(() -> s.x()), false);
			equals(isPending(() -> s.a()), false);
			equals(s.x(), 2);
			equals(latest(() -> s.x()), 2);
		});

		test("isPending sees the first async update for a writable memo signal", () -> {
			var f = new Fetcher((v:String) -> v);
			var list = signal(() -> ([] : Array<String>));
			var asyncMemo = root(_ -> {
				var m = memo(() -> f.fetch('async: ${list().length}'));
				renderEffect(() -> m(), _ -> {});
				m;
			});
			f.settle();
			equals(asyncMemo(), "async: 0");
			equals(isPending(() -> list().length), false);
			list(l -> l.concat(["123"]));
			flush();
			equals(isPending(() -> list().length), true);
			f.settle();
			equals(asyncMemo(), "async: 1");
			equals(isPending(() -> list().length), false);
			list(l -> l.concat(["456"]));
			flush();
			equals(isPending(() -> list().length), true);
		});

		test("isPending with chained async memos", () -> {
			var fa = new Fetcher((v:Int) -> v * 10), fb = new Fetcher((v:Int) -> v + 1);
			var x = signal(1);
			var a:Memo<Int> = null, b:Memo<Int> = null;
			root(_ -> {
				a = memo(() -> fa.fetch(x()));
				b = memo(() -> fb.fetch(a()));
				renderEffect(() -> b(), _ -> {});
			});
			fa.settle();
			fb.settle();
			equals(a(), 10);
			equals(b(), 11);
			x(2);
			flush();
			equals(isPending(() -> a()), true);
			equals(isPending(() -> b()), true);
			fa.settle();
			fb.settle();
			equals(a(), 20);
			equals(b(), 21);
			equals(isPending(() -> a()), false);
			equals(isPending(() -> b()), false);
		});

		test("isPending with sync memo depending on async memo", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var asyncMemo:Memo<Int> = null, syncMemo:Memo<Int> = null;
			root(_ -> {
				asyncMemo = memo(() -> f.fetch(x()));
				syncMemo = memo(() -> asyncMemo() + 1);
				renderEffect(() -> syncMemo(), _ -> {});
			});
			f.settle();
			equals(asyncMemo(), 10);
			equals(syncMemo(), 11);
			x(2);
			flush();
			equals(isPending(() -> asyncMemo()), true);
			equals(isPending(() -> syncMemo()), true);
			f.settle();
			equals(asyncMemo(), 20);
			equals(syncMemo(), 21);
			equals(isPending(() -> asyncMemo()), false);
			equals(isPending(() -> syncMemo()), false);
		});

		test("isPending full lifecycle - false to true to false", () -> {
			var s = asyncTimesTen();
			flush();
			equals(isPending(() -> s.a()), false);
			s.f.settle();
			equals(isPending(() -> s.a()), false);
			equals(s.a(), 10);
			s.x(2);
			flush();
			equals(isPending(() -> s.a()), true);
			equals(s.a(), 10);
			s.f.settle();
			equals(isPending(() -> s.a()), false);
			equals(s.a(), 20);
		});

		test("isPending participates in Loading during initial async", () -> {
			var gate = new Later<Int>();
			var a:Memo<Int> = null;
			var boundary:Memo<Dynamic> = null;
			root(_ -> {
				a = memo(() -> gate);
				boundary = loadingBoundary(() -> {
					var r:Dynamic = isPending(() -> a()) ? ("pending" : Dynamic) : (a() : Dynamic);
					r;
				}, () -> "loading");
			});
			equals(isPending(() -> a()), false);
			equals(boundary(), "loading");
			gate.resolve(1);
			flush();
			equals(boundary(), 1);
			equals(isPending(() -> a()), false);
		});

		test("isPending stays false for upstream-only initial reads", () -> {
			var id = signal(1);
			var boundary:Memo<Dynamic> = null;
			root(_ -> {
				var a = memo(() -> Kit.resolved(id() * 10));
				boundary = loadingBoundary(() -> (a() : Dynamic), () -> "loading");
			});
			equals(isPending(() -> id()), false);
			equals(boundary(), "loading");
			flush();
			equals(boundary(), 10);
			equals(isPending(() -> id()), false);
		});

		test("isPending returns true during revalidation", () -> {
			var s = asyncTimesTen();
			flush();
			s.f.settle();
			equals(s.a(), 10);
			equals(isPending(() -> s.a()), false);
			s.x(2);
			flush();
			equals(isPending(() -> s.a()), true);
			equals(s.a(), 10);
			s.f.settle();
			equals(s.a(), 20);
			equals(isPending(() -> s.a()), false);
		});

		test("isPending keeps old branches on stale pending status", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var a:Memo<Int> = null;
			var boundary:Memo<Dynamic> = null;
			root(_ -> {
				a = memo(() -> f.fetch(x()));
				boundary = loadingBoundary(() -> {
					var r:Dynamic = isPending(() -> a()) ? ("pending" : Dynamic) : (a() : Dynamic);
					r;
				}, () -> "loading");
			});
			equals(boundary(), "loading");
			f.settle();
			equals(boundary(), 10);
			x(2);
			flush();
			equals(boundary(), "pending");
			equals(a(), 10);
			f.settle();
			equals(boundary(), 20);
			equals(isPending(() -> a()), false);
		});

		test("isPending read inside reactive context (memo)", () -> {
			var s = asyncTimesTen();
			flush();
			s.f.settle();
			equals(s.a(), 10);
			var pendingValues:Array<Bool> = [];
			var pendingMemo = root(_ -> {
				var m = memo(() -> isPending(() -> s.a()));
				renderEffect(() -> m(), v -> pendingValues.push(v));
				m;
			});
			equals(pendingMemo(), false);
			s.x(2);
			flush();
			equals(pendingMemo(), true);
			assert(pendingValues.contains(true));
			s.f.settle();
			equals(pendingMemo(), false);
			equals(s.a(), 20);
		});

		test("latest read inside reactive context (memo)", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var asyncMemo:Memo<Int> = null, latestMemo:Memo<Int> = null;
			var values:Array<Int> = [];
			root(_ -> {
				asyncMemo = memo(() -> f.fetch(x()));
				latestMemo = memo(() -> latest(() -> asyncMemo()));
				renderEffect(() -> asyncMemo(), _ -> {});
				renderEffect(() -> latestMemo(), v -> values.push(v));
			});
			flush();
			f.settle();
			equals(asyncMemo(), 10);
			equals(latestMemo(), 10);
			x(2);
			flush();
			equals(latestMemo(), 10);
			f.settle();
			equals(asyncMemo(), 20);
			equals(latestMemo(), 20);
		});

		test("latest on upstream signal read inside reactive context", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var latestX:Memo<Int> = null;
			root(_ -> {
				var a = memo(() -> f.fetch(x()));
				latestX = memo(() -> latest(() -> x()));
				renderEffect(() -> a(), _ -> {});
			});
			flush();
			f.settle();
			equals(x(), 1);
			equals(latestX(), 1);
			x(2);
			flush();
			equals(x(), 1);
			equals(latestX(), 2);
			f.settle();
			equals(x(), 2);
			equals(latestX(), 2);
		});
	});

	// createMemo.test.ts: pairs as "isPending value" strings
	describe("isPending and latest with async upstream and downstream (A8: verdicts are per-channel)", () -> {
		function last<T>(a:Array<T>):T
			return a[a.length - 1];

		test("diagnostic: latest(signal) alone in render effect returns in-flight value", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var values:Array<Int> = [];
			root(_ -> {
				var a = memo(() -> f.fetch(x()));
				renderEffect(() -> a(), _ -> {});
				renderEffect(() -> latest(() -> x()), v -> values.push(v));
			});
			f.settle();
			equals(last(values), 1);
			x(2);
			flush();
			equals(last(values), 2);
			f.settle();
			equals(last(values), 2);
		});

		test("diagnostic: latest(x) combined with isPending(() => latest(x)) in same effect", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var pairs:Array<String> = [], latestOnly:Array<Int> = [], pendingOnly:Array<Bool> = [];
			root(_ -> {
				var a = memo(() -> f.fetch(x()));
				renderEffect(() -> a(), _ -> {});
				renderEffect(() -> '${isPending(() -> latest(() -> x()))} ${latest(() -> x())}', v -> pairs.push(v));
				renderEffect(() -> latest(() -> x()), v -> latestOnly.push(v));
				renderEffect(() -> isPending(() -> latest(() -> x())), v -> pendingOnly.push(v));
			});
			f.settle();
			equals(last(pairs), "false 1");
			equals(last(latestOnly), 1);
			equals(last(pendingOnly), false);
			x(2);
			flush();
			equals(last(latestOnly), 2);
			equals(last(pairs), "false 2");
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("latest(signal) with sync consumer - latest(signal) is never pending; the plain form reports the hold", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var pairs:Array<String> = [], pendingSignal:Array<Bool> = [];
			root(_ -> {
				var a = memo(() -> f.fetch(x()));
				renderEffect(() -> a(), _ -> {});
				renderEffect(() -> '${isPending(() -> latest(() -> x()))} ${latest(() -> x())}', v -> pairs.push(v));
				renderEffect(() -> isPending(() -> x()), v -> pendingSignal.push(v));
			});
			f.settle();
			equals(last(pendingSignal), false);
			equals(last(pairs), "false 1");
			x(2);
			flush();
			equals(last(pendingSignal), true);
			equals(last(pairs), "false 2");
			f.settle();
			equals(last(pendingSignal), false);
			equals(last(pairs), "false 2");
			equals(x(), 2);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		// (F-6: async derived from a display-ahead read holds its own lane)
		test("latest(signal) consumed by async memo - latest form stays settled; downstream async reports itself", () -> {
			var fMain = new Fetcher((v:Int) -> v * 10), fDetails = new Fetcher((v:Int) -> "details-" + v);
			var id = signal(1);
			var pairs:Array<String> = [], pendingValues:Array<Bool> = [], latestValues:Array<Int> = [], detailPairs:Array<String> = [];
			root(_ -> {
				var main = memo(() -> fMain.fetch(id()));
				var details = memo(() -> fDetails.fetch(latest(() -> id())));
				renderEffect(() -> main(), _ -> {});
				renderEffect(() -> details(), _ -> {});
				renderEffect(() -> '${isPending(() -> latest(() -> id()))} ${latest(() -> id())}', v -> pairs.push(v));
				renderEffect(() -> isPending(() -> latest(() -> id())), v -> pendingValues.push(v));
				renderEffect(() -> latest(() -> id()), v -> latestValues.push(v));
				renderEffect(() -> '${isPending(() -> details())} ${details()}', v -> detailPairs.push(v));
			});
			flush();
			fMain.resolveAll();
			flush();
			fDetails.resolveAll();
			flush();
			equals(last(pairs), "false 1");
			equals(last(pendingValues), false);
			equals(last(latestValues), 1);
			equals(last(detailPairs), "false details-1");
			id(2);
			flush();
			equals(last(pendingValues), false);
			equals(last(pairs), "false 1");
			fDetails.resolveAll();
			flush();
			equals(last(pairs), "false 2");
			equals(last(pendingValues), false);
			fMain.resolveAll();
			flush();
			equals(last(pairs), "false 2");
			equals(id(), 2);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("A10: single async - [isPending(x), x()] pairs update atomically", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var pairs:Array<String> = [];
			root(_ -> {
				var a = memo(() -> f.fetch(x()));
				renderEffect(() -> '${isPending(() -> a())} ${a()}', v -> pairs.push(v));
			});
			flush();
			f.settle();
			equals(last(pairs), "false 10");
			x(2);
			flush();
			equals(last(pairs), "true 10");
			f.settle();
			equals(last(pairs), "false 20");
			for (p in pairs)
				if (p.indexOf("true") == 0) equals(p, "true 10");
		});

		test("single async - [isPending(() => latest(x)), latest(x)] pairs update atomically", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var x = signal(1);
			var pairs:Array<String> = [];
			root(_ -> {
				var a = memo(() -> f.fetch(x()));
				renderEffect(() -> a(), _ -> {});
				renderEffect(() -> '${isPending(() -> latest(() -> a()))} ${latest(() -> a())}', v -> pairs.push(v));
			});
			flush();
			f.settle();
			equals(last(pairs), "false 10");
			x(2);
			flush();
			equals(last(pairs), "true 10");
			f.settle();
			equals(last(pairs), "false 20");
			for (p in pairs)
				if (p.indexOf("true") == 0) equals(p, "true 10");
		});

		test("chained async - each [isPending(x), x()] pair tracks its own resolution atomically", () -> {
			var fa = new Fetcher((v:Int) -> v * 10), fb = new Fetcher((v:Int) -> v + 1);
			var x = signal(1);
			var pairsA:Array<String> = [], pairsB:Array<String> = [];
			root(_ -> {
				var a = memo(() -> fa.fetch(x()));
				var b = memo(() -> fb.fetch(a()));
				renderEffect(() -> '${isPending(() -> a())} ${a()}', v -> pairsA.push(v));
				renderEffect(() -> '${isPending(() -> b())} ${b()}', v -> pairsB.push(v));
			});
			flush();
			fa.resolveAll();
			flush();
			fb.resolveAll();
			flush();
			equals(last(pairsA), "false 10");
			equals(last(pairsB), "false 11");
			x(2);
			flush();
			equals(last(pairsA), "true 10");
			equals(last(pairsB), "true 11");
			fa.resolveAll();
			flush();
			equals(last(pairsA), "true 10");
			equals(last(pairsB), "true 11");
			fb.resolveAll();
			flush();
			equals(last(pairsA), "false 20");
			equals(last(pairsB), "false 21");
		});

		test("chained async - [isPending(() => latest(x)), latest(x)] pairs track each node's own resolution", () -> {
			var fa = new Fetcher((v:Int) -> v * 10), fb = new Fetcher((v:Int) -> v + 1);
			var x = signal(1);
			var pairsA:Array<String> = [], pairsB:Array<String> = [];
			root(_ -> {
				var a = memo(() -> fa.fetch(x()));
				var b = memo(() -> fb.fetch(a()));
				renderEffect(() -> b(), _ -> {});
				renderEffect(() -> '${isPending(() -> latest(() -> a()))} ${latest(() -> a())}', v -> pairsA.push(v));
				renderEffect(() -> '${isPending(() -> latest(() -> b()))} ${latest(() -> b())}', v -> pairsB.push(v));
			});
			flush();
			fa.resolveAll();
			flush();
			fb.resolveAll();
			flush();
			equals(last(pairsA), "false 10");
			equals(last(pairsB), "false 11");
			x(2);
			flush();
			equals(last(pairsA), "true 10");
			equals(last(pairsB), "true 11");
			fa.resolveAll();
			flush();
			equals(last(pairsA), "false 20");
			equals(last(pairsB), "true 11");
			fb.resolveAll();
			flush();
			equals(last(pairsB), "false 21");
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("multiple independent async - [isPending(x), x()] pairs with progressive resolution", () -> {
			var fa = new Fetcher((v:Int) -> v * 10), fb = new Fetcher((v:Int) -> v * 100);
			var x = signal(1);
			var pairsA:Array<String> = [], pairsB:Array<String> = [];
			root(_ -> {
				var a = memo(() -> fa.fetch(x()));
				var b = memo(() -> fb.fetch(x()));
				renderEffect(() -> '${isPending(() -> a())} ${a()}', v -> pairsA.push(v));
				renderEffect(() -> '${isPending(() -> b())} ${b()}', v -> pairsB.push(v));
			});
			flush();
			fa.resolveAll();
			flush();
			fb.resolveAll();
			flush();
			equals(last(pairsA), "false 10");
			equals(last(pairsB), "false 100");
			x(2);
			flush();
			equals(last(pairsA), "true 10");
			equals(last(pairsB), "true 100");
			fb.resolveAll();
			flush();
			equals(last(pairsB), "true 100");
			equals(last(pairsA), "true 10");
			fa.resolveAll();
			flush();
			equals(last(pairsA), "false 20");
			equals(last(pairsB), "false 200");
		});

		test("multiple independent async - [isPending(() => latest(x)), latest(x)] pairs with progressive resolution", () -> {
			var fa = new Fetcher((v:Int) -> v * 10), fb = new Fetcher((v:Int) -> v * 100), fc = new Fetcher((v:Int) -> v * 1000);
			var x = signal(1);
			var pairsA:Array<String> = [], pairsB:Array<String> = [], pairsC:Array<String> = [];
			root(_ -> {
				var a = memo(() -> fa.fetch(x()));
				var b = memo(() -> fb.fetch(x()));
				var c = memo(() -> fc.fetch(x()));
				renderEffect(() -> a(), _ -> {});
				renderEffect(() -> b(), _ -> {});
				renderEffect(() -> c(), _ -> {});
				renderEffect(() -> '${isPending(() -> latest(() -> a()))} ${latest(() -> a())}', v -> pairsA.push(v));
				renderEffect(() -> '${isPending(() -> latest(() -> b()))} ${latest(() -> b())}', v -> pairsB.push(v));
				renderEffect(() -> '${isPending(() -> latest(() -> c()))} ${latest(() -> c())}', v -> pairsC.push(v));
			});
			flush();
			fa.resolveAll();
			flush();
			fb.resolveAll();
			flush();
			fc.resolveAll();
			flush();
			equals([last(pairsA), last(pairsB), last(pairsC)], ["false 10", "false 100", "false 1000"]);
			x(2);
			flush();
			equals([last(pairsA), last(pairsB), last(pairsC)], ["true 10", "true 100", "true 1000"]);
			fc.resolveAll();
			flush();
			equals([last(pairsA), last(pairsB), last(pairsC)], ["true 10", "true 100", "false 2000"]);
			fa.resolveAll();
			flush();
			equals([last(pairsA), last(pairsB)], ["false 20", "true 100"]);
			fb.resolveAll();
			flush();
			equals(last(pairsB), "false 200");
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});

	// spec-async-semantics.test.ts
	describe("A16: isPending never throws in untracked contexts", () -> {
		test("returns false when the thunk throws a real error", () -> {
			equals(isPending(() -> throw "boom"), false);
		});

		test("returns false for an uninitialized async source (initial load is not pending)", () -> {
			var f = new Fetcher((v:Int) -> v);
			var data = root(_ -> {
				var d = memo(() -> f.fetch(1));
				renderEffect(() -> d(), _ -> {});
				d;
			});
			flush();
			equals(isPending(() -> data()), false);
			f.resolveAll();
			flush();
			equals(isPending(() -> data()), false);
			equals(data(), 1);
		});

		test("tracked isPending of an uninitialized source participates in a loading boundary (B5a)", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var result:Dynamic = null;
			root(_ -> {
				var data = memo(() -> f.fetch(1));
				var pending = memo(() -> isPending(() -> data()));
				var boundary = loadingBoundary(() -> 'pending:${pending()}', () -> "loading");
				renderEffect(() -> result = boundary(), _ -> {});
			});
			flush();
			equals(result, "loading");
			f.resolveAll();
			flush();
			equals(result, "pending:false");
		});
	});

	describe("A19: isPending(x) = the observable value of x is not final", () -> {
		test("cause (i): a held trigger write is pending until commit, final at commit", () -> {
			var s = asyncTimesTen();
			s.f.settle();
			equals(isPending(() -> s.x()), false);
			s.x(2);
			flush();
			equals(s.x(), 1);
			equals(isPending(() -> s.x()), true);
			equals(isPending(() -> s.a()), true);
			s.f.resolveAll();
			flush();
			equals(s.x(), 2);
			equals(isPending(() -> s.x()), false);
			equals(isPending(() -> s.a()), false);
		});
	});

	// latest-async.test.ts (#2829)
	test("latest(asyncMemo) settles to the resolved value and re-reports pending on each refresh (#2829)", () -> {
		var f = new Fetcher((c:Int) -> 'AV$c');
		var count = signal(0);
		var latestLog:Array<String> = [], pendingLog:Array<Bool> = [];
		root(_ -> {
			var av = memo(() -> f.fetch(count()));
			renderEffect(() -> latest(() -> av()), v -> latestLog.push(v));
			renderEffect(() -> isPending(() -> latest(() -> av())), v -> pendingLog.push(v));
		});
		flush();
		equals(latestLog, []);
		f.resolveAll();
		flush();
		equals(latestLog[latestLog.length - 1], "AV0");
		equals(pendingLog[pendingLog.length - 1], false);
		for (n in 1...3) {
			count(n);
			flush();
			equals(pendingLog[pendingLog.length - 1], true);
			equals(latestLog[latestLog.length - 1], 'AV${n - 1}');
			f.resolveAll();
			flush();
			equals(latestLog[latestLog.length - 1], 'AV$n');
			equals(pendingLog[pendingLog.length - 1], false);
		}
		assert(!latestLog.contains(null));
	});

	// latest-created-inside-window.test.ts (#2926)
	describe("a memo created inside latest()", () -> {
		test("memo created inside a latest() window still links its dependencies (#2926)", () -> {
			var runs = 0;
			var g = signal(0, {equals: (_, _) -> false});
			var m = root(_ -> {
				var owner = getOwner();
				var lazy:Null<Memo<Int>> = null;
				() -> {
					if (lazy == null) lazy = runWithOwner(owner, () -> memo(() -> {
						runs++;
						g() + 1;
					}));
					lazy();
				};
			});
			equals(latest(m), 1);
			equals(runs, 1);
			g(0);
			flush();
			equals(latest(m), 1);
			equals(runs, 2);
			g(5);
			flush();
			equals(latest(m), 6);
			equals(runs, 3);
		});

		test("memo created directly inside latest(fn) links its dependencies (#2926)", () -> {
			var g = signal(1);
			var runs = 0;
			var m:Memo<Int> = null;
			var first = latest(() -> {
				m = root(_ -> memo(() -> {
					runs++;
					g() * 10;
				}));
				m();
			});
			equals(first, 10);
			equals(runs, 1);
			g(2);
			flush();
			equals(m(), 20);
			equals(runs, 2);
		});
	});

	// latest-lazy-companion-backfill.test.ts (#3041)
	describe("latest() first read during a held transition", () -> {
		function scene(warm:Bool) {
			var current:Later<String> = null;
			var seen:Array<String> = [];
			var query = signal("pikachu");
			root(_ -> {
				var pokemon = memo(() -> {
					query();
					current = new Later<String>();
				});
				if (warm) latest(() -> query());
				renderEffect(() -> isPending(() -> pokemon()) ? latest(() -> query()) : "idle:" + pokemon(), v -> seen.push(v));
			});
			flush();
			current.resolve("pikachu");
			flush();
			seen.resize(0);
			query("charizard");
			flush();
			return seen;
		}

		test("latest() first read during a held transition sees in-flight value (#3041)", () -> {
			equals(scene(false), ["charizard"]);
		});

		test("control: companion pre-warmed before transition", () -> {
			equals(scene(true), ["charizard"]);
		});
	});

	// latest-pending-probe-mid-flight.test.ts (#3166)
	test("a tracked latest(isPending()) probe created mid-flight sees the current flight (#3166)", () -> {
		var f = new Fetcher((v:Int) -> v);
		var id = signal(0);
		var source = root(_ -> {
			var s = memo(() -> {
				var current = id();
				f.fetch(current * 100);
			});
			renderEffect(() -> {
				try s() catch (e:Dynamic) {}
			}, _ -> {});
			s;
		});
		flush();
		f.resolveAll();
		flush();
		id(1);
		flush();
		equals(isPending(() -> source()), true);
		equals(latest(() -> isPending(() -> source())), true);
		var probe = root(_ -> memo(() -> latest(() -> isPending(() -> source()))));
		equals(probe(), true);
		f.resolveAll();
		flush();
		equals(probe(), false);
		id(2);
		flush();
		equals(probe(), true);
		f.resolveAll();
		flush();
		equals(probe(), false);
	});

	// latest-plain-write-purity.test.ts (#3009; F-10)
	describe("latest() and plain writes", () -> {
		test("latest(m) does not change what plain m() returns before the flush (#3009)", () -> {
			var count = signal(0);
			var m = root(_ -> memo(() -> latest(() -> count()) * 2));
			flush();
			count(4);
			equals(m(), 0);
			equals(latest(() -> m()), 0);
			equals(m(), 0);
			equals(latest(() -> m()), 0);
			equals(m(), 0);
			flush();
			equals(m(), 8);
			equals(latest(() -> m()), 8);
		});

		test("the flush commits and notifies effects after latest() probes (#3009)", () -> {
			var count = signal(0);
			var effectLog:Array<Int> = [];
			var m = root(_ -> {
				var m = memo(() -> latest(() -> count()) * 2);
				effect(() -> m(), v -> effectLog.push(v));
				m;
			});
			flush();
			equals(effectLog, [0]);
			count(4);
			equals(latest(() -> m()), 0);
			flush();
			equals(m(), 8);
			equals(latest(() -> m()), 8);
			equals(effectLog, [0, 8]);
			count(10);
			flush();
			equals(m(), 20);
			equals(effectLog, [0, 8, 20]);
		});

		test("chained memos over latest() stay pure (#3009)", () -> {
			var count = signal(1);
			var m:Memo<Int> = null, m2:Memo<Int> = null;
			root(_ -> {
				m = memo(() -> latest(() -> count()) * 2);
				m2 = memo(() -> m() + 1);
			});
			flush();
			equals(m2(), 3);
			count(5);
			equals(latest(() -> m2()), 3);
			equals(m(), 2);
			equals(m2(), 3);
			flush();
			equals(m(), 10);
			equals(m2(), 11);
			equals(latest(() -> m2()), 11);
		});

		test("an isPending probe on the same shape does not pollute committed reads (#3009)", () -> {
			var count = signal(0);
			var m = root(_ -> memo(() -> latest(() -> count()) * 2));
			flush();
			count(4);
			isPending(() -> m());
			equals(m(), 0);
			flush();
			equals(m(), 8);
		});
	});

	// latest-repeated-writes.test.ts (F-10)
	describe("latest() across repeated writes", () -> {
		test("latest(memo) reflects every flushed write, none of the unflushed ones", () -> {
			var s = signal(0);
			var m = root(_ -> memo(() -> s() * 2 + 1));
			flush();
			equals(m(), 1);
			s(1);
			equals(m(), 1);
			equals(latest(() -> m()), 1);
			flush();
			equals(latest(() -> m()), 3);
			equals(m(), 3);
			s(2);
			equals(latest(() -> m()), 3);
			flush();
			equals(latest(() -> m()), 5);
			s(3);
			equals(latest(() -> m()), 5);
			flush();
			equals(latest(() -> m()), 7);
			equals(m(), 7);
		});

		test("latest(memo) stays fresh across flushed writes when an effect keeps the shadow subscribed", () -> {
			var s = signal(0);
			var effectLog:Array<Int> = [];
			var m = root(_ -> {
				var m = memo(() -> s() * 2 + 1);
				effect(() -> latest(() -> m()), v -> effectLog.push(v));
				m;
			});
			flush();
			equals(effectLog, [1]);
			s(1);
			equals(latest(() -> m()), 1);
			flush();
			equals(latest(() -> m()), 3);
			s(2);
			equals(latest(() -> m()), 3);
			flush();
			equals(latest(() -> m()), 5);
			equals(m(), 5);
			equals(effectLog, [1, 3, 5]);
		});

		test("latest(signal) reflects each write once flushed", () -> {
			var s = signal(0);
			flush();
			s(1);
			equals(latest(() -> s()), 0);
			flush();
			equals(latest(() -> s()), 1);
			s(2);
			equals(latest(() -> s()), 1);
			flush();
			equals(latest(() -> s()), 2);
			equals(s(), 2);
		});

		test("two unflushed writes in one tick: latest() skips the intermediate, the flush lands the last", () -> {
			var s = signal(0);
			var m = root(_ -> memo(() -> s() * 2 + 1));
			flush();
			s(1);
			s(2);
			equals(latest(() -> s()), 0);
			equals(latest(() -> m()), 1);
			flush();
			equals(latest(() -> s()), 2);
			equals(latest(() -> m()), 5);
		});
	});

	// latest-unobserved-memo.test.ts (#2927)
	describe("latest() of an unobserved memo", () -> {
		function setup() {
			var runs = 0;
			var g = signal(0, {equals: (_, _) -> false});
			var m = root(_ -> memo(() -> {
				runs++;
				g() + 1;
			}));
			flush();
			return {m: m, write: () -> g(0), runs: () -> runs};
		}

		test("m(); latest(m); write — recomputes on every click (#2927 case A)", () -> {
			var s = setup();
			equals(s.runs(), 1);
			for (i in 2...6) {
				s.m();
				latest(() -> s.m());
				s.write();
				flush();
				equals(s.runs(), i);
			}
		});

		test("latest(m); m(); write — recomputes on every click (#2927 case B)", () -> {
			var s = setup();
			equals(s.runs(), 1);
			for (i in 2...6) {
				latest(() -> s.m());
				s.m();
				s.write();
				flush();
				equals(s.runs(), i);
			}
		});

		test("orderings stay consistent without explicit flushes (#2927)", () -> {
			var a = setup(), b = setup();
			for (i in 0...4) {
				a.m();
				latest(() -> a.m());
				a.write();
				latest(() -> b.m());
				b.m();
				b.write();
				equals(a.runs(), b.runs());
				equals(a.runs(), 1);
			}
			flush();
			equals(a.runs(), 2);
			equals(b.runs(), 2);
		});
	});

	// latest-probe-order-independence.test.ts (#3104)
	describe("latest-mode probe order independence (#3104)", () -> {
		function stage(withExternalLatestRead:Bool) {
			var count = signal(0);
			var m1 = memo(() -> latest(() -> isPending(() -> count())));
			equals(m1(), false);
			equals(isPending(() -> count()), false);
			count(v -> v + 1);
			var reads = [
				m1(),
				withExternalLatestRead ? latest(() -> m1()) : false,
				isPending(() -> count()),
				latest(() -> isPending(() -> count()))
			];
			flush();
			return {reads: reads, settled: [m1(), isPending(() -> count())]};
		}

		test("latest(() => isPending(x)) answers the same whether or not latest(m) was read before it", () -> {
			var withRead = stage(true), without = stage(false);
			equals(withRead.reads, [false, false, false, false]);
			equals(without.reads, [false, false, false, false]);
			equals(withRead.settled, [false, false]);
			equals(without.settled, [false, false]);
		});

		test("isPending inside a latest window survives subsequent flushes and stays coherent", () -> {
			var f = new Fetcher((v:Int) -> v * 2);
			var log:Array<String> = [];
			var a = signal(0);
			var dispose = root(d -> {
				var double = memo(() -> f.fetch(a()));
				renderEffect(() -> try (double() : Dynamic) catch (e:Dynamic) "THROWN", _ -> {});
				renderEffect(() -> 'plain=${isPending(() -> a())} latestP=${latest(() -> isPending(() -> a()))} latestPm=${latest(() -> isPending(() -> double()))}',
					v -> log.push(v));
				d;
			});
			flush();
			f.resolveAll();
			flush();
			equals(log[log.length - 1], "plain=false latestP=false latestPm=false");
			a(1);
			flush();
			equals(log[log.length - 1], "plain=true latestP=false latestPm=true");
			f.resolveAll();
			flush();
			equals(log[log.length - 1], "plain=false latestP=false latestPm=false");
			dispose();
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});

	// latest-derived-held-error-4106.test.ts (F-6, D-41)
	describe("a derivation of latest() over a held answer", () -> {
		function scene() {
			var request = new Later<Int>(), sibling = new Later<Int>();
			var round = signal(1);
			var log:Array<Dynamic> = [];
			var screen = {round: 0};
			var source:Memo<Int> = null, derived:Memo<Int> = null;
			root(_ -> {
				source = memo(() -> {
					round();
					request;
				});
				derived = memo(() -> latest(() -> source()));
				var slow = memo(() -> {
					round();
					sibling;
				});
				renderEffect(() -> {
					var r = round();
					slow();
					r;
				}, r -> screen.round = r);
				effect(() -> derived(), v -> log.push(v), e -> log.push(e));
			});
			flush();
			request.resolve(1);
			sibling.resolve(1);
			flush();
			equals(log, [1]);
			equals(screen.round, 1);
			request = new Later<Int>();
			sibling = new Later<Int>();
			round(2);
			flush();
			return {
				log: log,
				screen: screen,
				request: () -> request,
				sibling: () -> sibling,
				reads: () -> [
					Kit.attempt(() -> latest(() -> source())),
					Kit.attempt(() -> latest(() -> derived())),
					Kit.attempt(() -> derived()),
					Kit.attempt(() -> source())
				]
			};
		}

		test("a held value reaches a derivation of latest before the reveal", () -> {
			var s = scene();
			s.request().resolve(2);
			flush();
			equals(s.screen.round, 1);
			equals(s.reads(), [2, 2, 2, 1]);
			equals(s.log, [1, 2]);
			s.sibling().resolve(2);
			flush();
			equals(s.screen.round, 2);
			equals(s.reads(), [2, 2, 2, 2]);
			equals(s.log, [1, 2]);
		});

		test("a held error reaches a derivation of latest at the same point as a value", () -> {
			var s = scene();
			s.request().reject("boom");
			flush();
			equals(s.screen.round, 1);
			equals(s.reads(), ["boom", "boom", "boom", 1]);
			equals(s.log, [1, "boom"]);
			s.sibling().resolve(2);
			flush();
			equals(s.screen.round, 2);
			equals(s.reads(), ["boom", "boom", "boom", "boom"]);
			equals(s.log, [1, "boom"]);
		});

		test("a tracked latest of the derivation sees the held error when it would see a value", () -> {
			for (reject in [false, true]) {
				var request = new Later<Int>(), sibling = new Later<Int>();
				var round = signal(1);
				var log:Array<Dynamic> = [];
				var outer:Memo<Int> = null;
				root(_ -> {
					var source = memo(() -> {
						round();
						request;
					});
					var derived = memo(() -> latest(() -> source()));
					outer = memo(() -> latest(() -> derived()));
					var slow = memo(() -> {
						round();
						sibling;
					});
					renderEffect(() -> slow(), _ -> {});
					effect(() -> outer(), v -> log.push(v), e -> log.push(e));
				});
				flush();
				request.resolve(1);
				sibling.resolve(1);
				flush();
				request = new Later<Int>();
				sibling = new Later<Int>();
				round(2);
				flush();
				if (reject) request.reject("boom") else request.resolve(2);
				flush();
				var answer:Dynamic = reject ? "boom" : 2;
				equals([Kit.attempt(() -> outer()), Kit.attempt(() -> latest(() -> outer()))], [answer, answer]);
				equals(log, [1, answer]);
				sibling.resolve(2);
				flush();
				equals(log, [1, answer]);
			}
		});
	});

	// isPending-held-sync-memo.test.ts (#3413)
	test("isPending on a held sync memo: reports pending for the identity memo while the async memo holds the write", () -> {
		var f = new Fetcher((v:Int) -> v);
		var count = signal(0);
		var countPending:Null<Bool> = null, copyPending:Null<Bool> = null, copyShown:Null<Int> = null;
		root(_ -> {
			var copy = memo(() -> count());
			var details = memo(() -> f.fetch(copy()));
			renderEffect(() -> copy(), v -> copyShown = v);
			renderEffect(() -> details(), _ -> {});
			renderEffect(() -> isPending(() -> count()), v -> countPending = v);
			renderEffect(() -> isPending(() -> copy()), v -> copyPending = v);
		});
		f.settle();
		equals(([copyShown, countPending, copyPending] : Array<Dynamic>), ([0, false, false] : Array<Dynamic>));
		count(1);
		flush();
		equals(([copyShown, countPending, copyPending] : Array<Dynamic>), ([0, true, true] : Array<Dynamic>));
		f.settle();
		equals(([copyShown, countPending, copyPending] : Array<Dynamic>), ([1, false, false] : Array<Dynamic>));
	});

	// latest-held-till-flush.test.ts (F-10: a write is visible at its flush, to every channel)
	describe("latest() is held till flush", () -> {
		// a signal whose write is held by an async memo a render effect observes
		function heldSetup(initial:Int) {
			var f = new Fetcher((v:Int) -> v);
			var count = signal(initial);
			root(_ -> {
				var data = memo(() -> f.fetch(count()));
				renderEffect(() -> data(), _ -> {});
			});
			f.settle();
			equals(count(), initial);
			return count;
		}

		test("latest(signal): unflushed write invisible; visible after flush", () -> {
			var s = signal(0);
			flush();
			s(1);
			equals(latest(() -> s()), 0);
			equals(s(), 0);
			flush();
			equals(latest(() -> s()), 1);
			equals(s(), 1);
		});

		test("latest(memo): does not derive downstream pre-flush", () -> {
			var s = signal(0);
			var m = root(_ -> memo(() -> s() * 2 + 1));
			flush();
			equals(m(), 1);
			s(1);
			equals(latest(() -> m()), 1);
			equals(m(), 1);
			s(2);
			equals(latest(() -> m()), 1);
			flush();
			equals(m(), 5);
			equals(latest(() -> m()), 5);
		});

		test("flush() then latest() is read-your-own-writes under a held transition", () -> {
			var count = heldSetup(10);
			count(20);
			equals(latest(() -> count()), 10);
			flush();
			equals(count(), 10);
			equals(latest(() -> count()), 20);
		});

		test("a rewrite of a held node is invisible until its own flush (existing companion)", () -> {
			var count = heldSetup(10);
			count(20);
			flush();
			equals(latest(() -> count()), 20);
			count(30);
			equals(latest(() -> count()), 20);
			equals(count(), 10);
			flush();
			equals(latest(() -> count()), 30);
			equals(count(), 10);
		});

		test("a companion created after the rewrite agrees with one that existed before it", () -> {
			var count = heldSetup(10);
			count(20);
			flush();
			count(30);
			equals(latest(() -> count()), 20);
			flush();
			equals(latest(() -> count()), 30);
		});

		test("a companion created pre-flush on a node that was not held reads committed", () -> {
			var s = signal(10);
			flush();
			s(30);
			equals(latest(() -> s()), 10);
			flush();
			equals(latest(() -> s()), 30);
		});

		test("memo transparency: a getter and a memo wrapping latest() agree pre- and post-flush", () -> {
			var count = heldSetup(0);
			var getter = () -> latest(() -> count());
			var m = root(_ -> memo(() -> latest(() -> count())));
			flush();
			equals([getter(), m()], [0, 0]);
			count(1);
			equals([getter(), m()], [0, 0]);
			flush();
			equals([getter(), m()], [1, 1]);
			equals(count(), 0);
		});

		test("a tracked latest() reader created after an unflushed write still updates at flush", () -> {
			var s = signal(0);
			flush();
			s(1);
			var seen:Array<Int> = [];
			root(_ -> effect(() -> latest(() -> s()), v -> seen.push(v)));
			flush();
			equals(seen, [1]);
		});

		test("a tracked latest() reader created after an unflushed rewrite of a held node updates at flush", () -> {
			var count = heldSetup(10);
			count(20);
			flush();
			count(30);
			var m = root(_ -> memo(() -> latest(() -> count())));
			equals(m(), 20);
			flush();
			equals(m(), 30);
		});

		test("an effect over latest() created after an unflushed rewrite of a held node runs at flush (not parked with the hold)", () -> {
			var count = heldSetup(10);
			count(20);
			flush();
			count(30);
			var seen:Array<Int> = [];
			root(_ -> effect(() -> latest(() -> count()), v -> seen.push(v)));
			flush();
			equals(seen, [30]);
		});

		test("isPending() follows the same clock: false for an unflushed write, true once flushed and held", () -> {
			var count = heldSetup(10);
			equals(isPending(() -> count()), false);
			count(20);
			equals(isPending(() -> count()), false);
			flush();
			equals(isPending(() -> count()), true);
		});

		test("functional updaters still compose across unflushed writes", () -> {
			var s = signal(10);
			flush();
			s(v -> v + 1);
			s(v -> v + 1);
			equals(latest(() -> s()), 10);
			flush();
			equals(s(), 12);
		});

		test("latest(memo) reads the flushed held derivation, not a mid-tick one", () -> {
			var count = heldSetup(10);
			var double = root(_ -> memo(() -> count() * 2));
			flush();
			equals(latest(() -> double()), 20);
			count(20);
			equals(latest(() -> double()), 20);
			flush();
			equals(double(), 20);
			equals(latest(() -> double()), 40);
			equals(latest(() -> count()), 20);
		});
	});

	// latest-isPending-consistency.test.ts (#3028)
	describe("isPending wrapper memo over a signal with async downstream (#3028)", () -> {
		test("memo of bare isPending(a) flips true while downstream async is in flight", () -> {
			var f = new Fetcher((v:Int) -> v * 2);
			var a = signal(0);
			var pendingLog:Array<Bool> = [], doubleLog:Array<Int> = [];
			root(_ -> {
				var double = memo(() -> f.fetch(a()));
				var m = memo(() -> isPending(() -> a()));
				renderEffect(() -> double(), v -> doubleLog.push(v));
				renderEffect(() -> m(), v -> pendingLog.push(v));
			});
			flush();
			f.resolveAll();
			flush();
			equals(doubleLog, [0]);
			equals(pendingLog, [false]);
			a(1);
			flush();
			equals(pendingLog, [false, true]);
			f.resolveAll();
			flush();
			equals(doubleLog, [0, 2]);
			equals(pendingLog, [false, true, false]);
		});

		test("memo reading both a() and isPending(a) flips true (issue variant B)", () -> {
			var f = new Fetcher((v:Int) -> v * 2);
			var a = signal(0);
			var pendingLog:Array<Bool> = [];
			root(_ -> {
				var double = memo(() -> f.fetch(a()));
				renderEffect(() -> double(), _ -> {});
				var m = memo(() -> {
					a();
					isPending(() -> a());
				});
				renderEffect(() -> m(), v -> pendingLog.push(v));
			});
			flush();
			f.resolveAll();
			flush();
			equals(pendingLog, [false]);
			a(1);
			flush();
			equals(pendingLog, [false, true]);
			f.resolveAll();
			flush();
			equals(pendingLog, [false, true, false]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("control: memo reading double() too flips true (issue's workaround)", () -> {
			var f = new Fetcher((v:Int) -> v * 2);
			var a = signal(0);
			var pendingLog:Array<Bool> = [];
			root(_ -> {
				var double = memo(() -> f.fetch(a()));
				var m = memo(() -> {
					double();
					isPending(() -> a());
				});
				renderEffect(() -> try m() catch (e:Dynamic) false, v -> pendingLog.push(v));
			});
			flush();
			f.resolveAll();
			flush();
			a(1);
			flush();
			equals(pendingLog[pendingLog.length - 1], true);
			f.resolveAll();
			flush();
			equals(pendingLog[pendingLog.length - 1], false);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("plain sync write (no async downstream) never glitches the wrapper true", () -> {
			var a = signal(0);
			var pendingLog:Array<Bool> = [];
			root(_ -> {
				var m = memo(() -> isPending(() -> a()));
				renderEffect(() -> m(), v -> pendingLog.push(v));
			});
			flush();
			equals(pendingLog, [false]);
			a(1);
			flush();
			equals(pendingLog, [false]);
		});

		test("second write during an open flight keeps the wrapper true", () -> {
			var f = new Fetcher((v:Int) -> v * 2);
			var a = signal(0);
			var pendingLog:Array<Bool> = [];
			root(_ -> {
				var double = memo(() -> f.fetch(a()));
				renderEffect(() -> double(), _ -> {});
				var m = memo(() -> isPending(() -> a()));
				renderEffect(() -> m(), v -> pendingLog.push(v));
			});
			flush();
			f.resolveAll();
			flush();
			equals(pendingLog, [false]);
			a(1);
			flush();
			equals(pendingLog, [false, true]);
			a(2);
			flush();
			equals(pendingLog, [false, true]);
			f.resolveAll();
			flush();
			f.resolveAll();
			flush();
			equals(pendingLog, [false, true, false]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});

	// latest-beside-staged-read-4365.test.ts (#4365; F-1, F-6)
	describe("#4365: latest(a) beside b() on a batched write", () -> {
		for (reader in ["memo", "effect"])
			test('a throw from the pass does not stick ($reader)', () -> {
				var a = signal(1), b = signal(0);
				var passes:Array<String> = [];
				var out = "";
				var dispose = root(dispose -> {
					var f = () -> {
						var v = latest(() -> a()) + b() + 1;
						passes.push('${latest(() -> a())}+${b()}');
						if (v % 4 == 3) throw 'm:$v';
						v;
					};
					var view = errorBoundary(() -> untrack(() -> {
						if (reader == "effect") renderEffect(f, v -> out = 'title=$v') else {
							var m = memo(f);
							renderEffect(() -> m(), v -> out = 'title=$v');
						}
						"content";
					}), (e, _) -> '[E ${e()}]');
					renderEffect(() -> view(), v -> if (v != "content") out = v);
					dispose;
				});
				flush();
				equals(out, "title=2");
				passes.resize(0);
				b(3);
				a(2);
				flush();
				equals(passes, ["2+3"]);
				equals(out, "title=6");
				dispose();
			}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		for (order in ["[latest(s), s()]", "[s(), latest(s)]"])
			test('a memo of $order commits one whole frame on a plain write', () -> {
				var s = signal(1);
				var seen:Array<String> = [];
				var dispose = root(dispose -> {
					var m = memo(() -> order == "[latest(s), s()]" ? '${latest(() -> s())},${s()}' : '${s()},${latest(() -> s())}');
					renderEffect(() -> m(), v -> seen.push(v));
					dispose;
				});
				flush();
				s(2);
				flush();
				equals(seen, ["1,1", "2,2"]);
				dispose();
			});

		for (reader in ["memo", "effect"])
			for (latestFirst in [true, false])
				test('a pass in a flush that parks never shows b\'s staging beside its async ($reader ${latestFirst ? "[latest(a), b()]" : "[b(), latest(a)]"})', () -> {
					var a = signal(1), b = signal(1);
					var later:Null<Later<Int>> = null;
					var seen:Array<String> = [];
					var dispose = root(dispose -> {
						var slow = memo(Kit.either(() -> {
							var v = b();
							if (v > 1) {
								later = new Later<Int>();
								return (later : Dynamic);
							}
							(v : Dynamic);
						}));
						var f = () -> latestFirst ? [latest(() -> a()), b()] : [b(), latest(() -> a())];
						var m:Void->Array<Int> = if (reader == "memo") {
							var mm = memo(f);
							() -> mm();
						} else f;
						renderEffect(() -> m().concat([slow()]).join(","), v -> seen.push(v));
						dispose;
					});
					flush();
					a(2);
					b(2);
					flush();
					later.resolve(2);
					flush();
					for (frame in seen) {
						var p = frame.split(",");
						equals(latestFirst ? p[1] : p[0], p[2]);
					}
					equals(seen[seen.length - 1], "2,2,2");
					dispose();
				});

		for (reader in ["memo", "effect"]) {
			var entry = test('the pass re-derives ahead of a flush that parks, and at its landing ($reader)', () -> {
				var a = signal(1), b = signal(1), c = signal(1);
				var later:Null<Later<Int>> = null;
				var seen:Array<String> = [];
				var dispose = root(dispose -> {
					var slow = memo(Kit.either(() -> {
						var v = c();
						if (v > 1) {
							later = new Later<Int>();
							return (later : Dynamic);
						}
						(v : Dynamic);
					}));
					renderEffect(() -> slow(), _ -> {});
					var f = () -> '${latest(() -> a())},${b()}';
					if (reader == "memo") {
						var m = memo(f);
						renderEffect(() -> m(), v -> seen.push(v));
					} else
						renderEffect(f, v -> seen.push(v));
					dispose;
				});
				flush();
				a(2);
				b(2);
				c(2);
				flush();
				equals(seen, ["1,1", "2,1"]);
				later.resolve(2);
				flush();
				equals(seen, ["1,1", "2,1", "2,2"]);
				dispose();
			});
			// (known gap for the memo: Solid's rule not yet followed, DESIGN.md 2, Holds)
			if (reader == "memo") entry.skip();
		}
	});
}
