package view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Memo;
import helder.view.graph.Graph.*;
import view.graph.Kit;

// Holds and transactions (F-1, F-2, F-3, F-7): spec-async-semantics A15 and
// the A29 reader cases, tick-scoped-pass-transaction.test.ts,
// direction-rule-probe.test.ts, born-held.test.ts. Solid's `action` holding
// a write is Kit.hold: the write held by an async gate a render effect reads.
function tests() {
	afterEach(() -> flush());

	describe("A15: overlapping transitions settle as one unit", () -> {
		for (child in [false, true])
			for (boundary in [false, true])
				test('holds a reveal of an existing async flight (child=$child, boundary=$boundary)', () -> {
					var value = signal(0), show = signal(false);
					var f = new Fetcher((v:Int) -> v);
					var valueLine = "", showLine = "";
					var slot:Dynamic = null;
					var childLog:Array<Int> = [];
					var dispose = root(d -> {
						var details = memo(() -> f.fetch(value()));
						renderEffect(() -> '${value()} ${isPending(() -> value())}', v -> valueLine = v);
						renderEffect(() -> '${show()} ${isPending(() -> show())}', v -> showLine = v);
						function content():Dynamic {
							if (!show()) return "hidden";
							if (!child) return details();
							renderEffect(() -> details(), v -> childLog.push(v));
							return "shown";
						}
						var b = boundary ? loadingBoundary(content, () -> "loading") : null;
						renderEffect(() -> b != null ? b() : content(), v -> slot = v);
						d;
					});
					flush();
					equals(([valueLine, showLine, slot] : Array<Dynamic>), (["0 false", "false false", "hidden"] : Array<Dynamic>));
					for (next in [1, 2]) {
						show(false);
						flush();
						value(next);
						flush();
						equals(([valueLine, showLine, slot] : Array<Dynamic>), (['$next false', "false false", "hidden"] : Array<Dynamic>));
						var previousChildCount = childLog.length;
						show(true);
						flush();
						equals(([valueLine, showLine, slot] : Array<Dynamic>), (['$next false', "false true", "hidden"] : Array<Dynamic>));
						equals(show(), false);
						equals(isPending(() -> value()), false);
						equals(isPending(() -> show()), true);
						equals(childLog.length, previousChildCount);
						f.resolveAll();
						flush();
						equals(([valueLine, showLine, slot] : Array<Dynamic>), (['$next false', "true false", child ? ("shown" : Dynamic) : next] : Array<Dynamic>));
						equals(show(), true);
						equals(isPending(() -> show()), false);
						if (child) equals(childLog[childLog.length - 1], next);
					}
					dispose();
				});

		test("holds every reveal that discovers the same flight; all complete at the landing (signal)", () -> {
			var show1 = signal(false), show2 = signal(false);
			var f = new Fetcher((v:Int) -> v);
			var get = signal(0);
			var frames:Array<Array<Dynamic>> = [];
			var dispose = root(d -> {
				var details = memo(() -> f.fetch(get()));
				renderEffect(() -> show1() ? (details() : Dynamic) : "h1", v -> frames.push(["1", v, isPending(() -> show1())]));
				renderEffect(() -> show2() ? (details() : Dynamic) : "h2", v -> frames.push(["2", v, isPending(() -> show2())]));
				renderEffect(() -> get(), v -> frames.push(["value", v]));
				d;
			});
			flush();
			f.resolveAll();
			flush();
			frames.resize(0);
			get(1);
			flush();
			equals(frames, [(["value", 1] : Array<Dynamic>)]);
			frames.resize(0);
			show1(true);
			flush();
			show2(true);
			flush();
			equals(frames, []);
			equals([show1(), show2()], [false, false]);
			f.resolveAll();
			flush();
			equals([show1(), show2()], [true, true]);
			equals([for (fr in frames) if (Std.isOfType(fr[1], Int)) fr], [(["1", 1, false] : Array<Dynamic>), (["2", 1, false] : Array<Dynamic>)]);
			equals([for (fr in frames) if (fr[1] == 0) fr], []);
			dispose();
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("a shared reader forces one settle point: nothing commits until both asyncs resolve", () -> {
			var a = signal(1), b = signal(1);
			var fa = new Fetcher((t:Int) -> t * 10), fb = new Fetcher((t:Int) -> t * 100);
			var log:Array<String> = [];
			root(_ -> {
				var ma = memo(() -> fa.fetch(a()));
				var mb = memo(() -> fb.fetch(b()));
				var joined = memo(() -> '${ma()}|${mb()}');
				renderEffect(() -> joined(), v -> log.push(v));
			});
			flush();
			fa.resolveAll();
			fb.resolveAll();
			flush();
			equals(log, ["10|100"]);
			log.resize(0);
			a(2);
			flush();
			b(2);
			flush();
			fa.resolveAll();
			flush();
			equals(log, []);
			fb.resolveAll();
			flush();
			equals(log, ["20|200"]);
		});

		test("disjoint graphs keep independent transitions: each settles on its own", () -> {
			var a = signal(1), b = signal(1);
			var fa = new Fetcher((t:Int) -> t * 10), fb = new Fetcher((t:Int) -> t * 100);
			var log:Array<String> = [];
			root(_ -> {
				var ma = memo(() -> fa.fetch(a()));
				var mb = memo(() -> fb.fetch(b()));
				renderEffect(() -> ma(), v -> log.push('a=$v'));
				renderEffect(() -> mb(), v -> log.push('b=$v'));
			});
			flush();
			fa.resolveAll();
			fb.resolveAll();
			flush();
			log.sort(Reflect.compare);
			equals(log, ["a=10", "b=100"]);
			log.resize(0);
			a(2);
			flush();
			b(2);
			flush();
			fa.resolveAll();
			flush();
			equals(log, ["a=20"]);
			fb.resolveAll();
			flush();
			equals(log, ["a=20", "b=200"]);
		});
	});

	// spec-async-semantics.test.ts (A29 reader cases; F-3: a reader holding nothing shows the committed value)
	describe("a reader that links to a held node during the hold re-derives at the commit", () -> {
		test("a render effect created while an action holds a signal write: committed now, the truth at the commit", () -> {
			var s = signal(0);
			var early:Array<Int> = [];
			root(_ -> renderEffect(() -> s(), v -> early.push(v)));
			flush();
			var release = Kit.hold(() -> s(1), () -> s());
			var late:Array<Int> = [];
			root(_ -> renderEffect(() -> s(), v -> late.push(v)));
			flush();
			equals(early, [0]);
			equals(late, [0]);
			release();
			flush();
			equals(early, [0, 1]);
			equals(late, [0, 1]);
			equals(s(), 1);
		});

		test("the transaction's own effect is not replayed: one frame per reveal", () -> {
			var a = signal(0), b = signal(0);
			var log:Array<String> = [];
			root(_ -> renderEffect(() -> '${a()}:${b()}', v -> log.push(v)));
			flush();
			var release = Kit.hold(() -> a(1), () -> a());
			b(1);
			flush();
			equals(log, ["0:0", "0:1"]);
			release();
			flush();
			equals(log, ["0:0", "0:1", "1:1"]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});

	// tick-scoped-pass-transaction.test.ts: membership in a hold is the tick's (ruling 1; F-2)
	describe("membership in a hold is the tick's — the work one flush settles", () -> {
		function twoHolds() {
			var a = signal(0), b = signal(0);
			var releaseA = Kit.hold(() -> a(1), () -> a());
			var releaseB = Kit.hold(() -> b(2), () -> b());
			var shownA:Array<Int> = [], shownB:Array<Int> = [];
			return {
				a: a,
				b: b,
				releaseA: releaseA,
				releaseB: releaseB,
				shownA: shownA,
				shownB: shownB,
				mountA: () -> root(_ -> {
					var m = memo(() -> a());
					renderEffect(() -> m(), v -> shownA.push(v));
				}),
				mountB: () -> root(_ -> {
					var m = memo(() -> b());
					renderEffect(() -> m(), v -> shownB.push(v));
				})
			};
		}

		test("mountA(); mountB(); flush() — one frame over two foreign holds: the holds merge, both reveal at the second release", () -> {
			var h = twoHolds();
			h.mountA();
			h.mountB();
			flush();
			equals(h.shownA, []);
			equals(h.shownB, []);
			equals([isPending(() -> h.a()), isPending(() -> h.b())], [true, true]);
			h.releaseA();
			flush();
			equals(h.a(), 0);
			equals(h.b(), 0);
			equals(h.shownA, []);
			equals(h.shownB, []);
			equals([isPending(() -> h.a()), isPending(() -> h.b())], [true, true]);
			h.releaseB();
			flush();
			equals([h.a(), h.b()], [1, 2]);
			equals(h.shownA, [1]);
			equals(h.shownB, [2]);
			equals([isPending(() -> h.a()), isPending(() -> h.b())], [false, false]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("mountA(); flush(); mountB(); flush() — the manual flush ends the frame: independent, A reveals at its own release while B stays held", () -> {
			var h = twoHolds();
			h.mountA();
			flush();
			h.mountB();
			flush();
			equals(h.shownA, []);
			equals(h.shownB, []);
			equals([isPending(() -> h.a()), isPending(() -> h.b())], [true, true]);
			h.releaseA();
			flush();
			equals(h.a(), 1);
			equals(h.b(), 0);
			equals(h.shownA, [1]);
			equals(h.shownB, []);
			equals([isPending(() -> h.a()), isPending(() -> h.b())], [false, true]);
			h.releaseB();
			flush();
			equals(h.b(), 2);
			equals(h.shownB, [2]);
			equals(isPending(() -> h.b()), false);
		});
	});

	// direction-rule-probe.test.ts: the hold waits for a first load a render
	// effect consumes outside a boundary (F-2, D-6); under a fresh Loading the
	// boundary catches it (F-4)
	describe("the hold waits for a first load it mounts", () -> {
		function run(shape:String) {
			var user = signal("ann"), open = signal(false);
			var log:Array<String> = [];
			var gates:Array<Void->Void> = [];
			function page():Memo<String> {
				return memo(() -> {
					var u = user();
					var l = new Later<String>();
					gates.push(() -> l.resolve('page-$u'));
					l;
				});
			}
			root(_ -> {
				renderEffect(() -> user(), u -> log.push('header $u'));
				if (shape == "in-flush" || shape == "in-flush-boundary")
					renderEffect(() -> {
						if (!open()) return;
						if (shape == "in-flush-boundary") {
							var view = untrack(() -> loadingBoundary(() -> page()(), () -> "fallback"));
							renderEffect(() -> view(), x -> log.push('view $x'));
						} else {
							var p = page();
							renderEffect(() -> p(), x -> log.push('page $x'));
						}
					}, _ -> {});
			});
			flush();
			var release = Kit.hold(() -> user("bob"), () -> user());
			if (shape == "two-mounts-outside")
				for (n in [1, 2])
					root(_ -> {
						var p = page();
						renderEffect(() -> p(), x -> log.push('page$n $x'));
					});
			else if (shape == "one-mount-then-sync-reader") {
				root(_ -> {
					var p = page();
					renderEffect(() -> p(), x -> log.push('page $x'));
				});
				root(_ -> {
					var m = memo(() -> user().toUpperCase());
					renderEffect(() -> m(), x -> log.push('sync $x'));
				});
			} else
				open(true);
			flush();
			var beforeRelease = log.length;
			release();
			flush();
			var atRelease = log.slice(beforeRelease);
			for (g in gates.splice(0, gates.length))
				g();
			flush();
			return {log: log, atRelease: atRelease};
		}

		function containsAll(log:Array<String>, items:Array<String>)
			for (i in items)
				assert(log.contains(i), '$i in $log');

		test("same tick, two mounts outside a flush: the hold waits for both pages", () -> {
			var r = run("two-mounts-outside");
			equals(r.atRelease, []);
			containsAll(r.log, ["header bob", "page1 page-bob", "page2 page-bob"]);
		});

		test("same tick, a mount then a sync reader: the hold waits for the page", () -> {
			var r = run("one-mount-then-sync-reader");
			equals(r.atRelease, []);
			containsAll(r.log, ["header bob", "page page-bob", "sync BOB"]);
		});

		test("in a flush that joined the hold: the hold waits for the mount's first load", () -> {
			var r = run("in-flush");
			equals(r.atRelease, []);
			containsAll(r.log, ["header bob", "page page-bob"]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)

		test("in a flush, under a Loading that has not shown content: the hold lands at its release; the boundary shows its fallback meanwhile", () -> {
			var r = run("in-flush-boundary");
			equals(r.log.slice(0, 2), ["header ann", "view fallback"]);
			equals(r.atRelease, ["header bob"]);
		});
	});

	// born-held.test.ts (A29, creation-time form; F-2, F-7)
	describe("A29 born held: nodes created mainline during a hold", () -> {
		function heldSignal() {
			var x = signal(0);
			var pre:Array<Int> = [];
			root(_ -> renderEffect(() -> x(), v -> pre.push(v)));
			flush();
			var release = Kit.hold(() -> x(1), () -> x());
			return {x: x, pre: pre, release: release};
		}

		test("a fresh memo + render effect derive from the held world and are held with it; a fresh direct effect shows the committed frame", () -> {
			var h = heldSignal();
			equals(h.pre, [0]);
			var viaMemo:Array<Int> = [], direct:Array<Int> = [], derived:Array<Int> = [];
			root(_ -> {
				var m = memo(() -> {
					var v = h.x();
					derived.push(v);
					v;
				});
				renderEffect(() -> m(), v -> viaMemo.push(v));
				renderEffect(() -> h.x(), v -> direct.push(v));
			});
			flush();
			equals(derived, [1]);
			equals(viaMemo, []);
			equals(direct, [0]);
			equals(h.pre, [0]);
			h.release();
			flush();
			equals(viaMemo, [1]);
			equals(direct, [0, 1]);
			equals(h.pre, [0, 1]);
		});

		test("an unrelated mainline write after the mount is not swallowed into the action", () -> {
			var h = heldSignal();
			var y = signal(0);
			var yLog:Array<Int> = [];
			root(_ -> renderEffect(() -> y(), v -> yLog.push(v)));
			flush();
			yLog.resize(0);
			root(_ -> memo(() -> h.x()));
			y(1);
			flush();
			equals(yLog, [1]);
			equals(y(), 1);
			h.release();
			flush();
		});

		test("an untracked read of a born-held memo has no committed value to serve and throws NotReady until the commit", () -> {
			var h = heldSignal();
			var m = root(_ -> memo(() -> h.x()));
			assert(Std.isOfType(throws(() -> m()), NotReady));
			h.release();
			flush();
			equals(m(), 1);
		});

		test("inside a flush nothing changes: a memo whose branch flips mainline still enters (#3408)", () -> {
			var h = heldSignal();
			var fixed = signal(true);
			var log:Array<String> = [];
			root(_ -> {
				var sel = memo(() -> fixed() ? -1 : h.x());
				renderEffect(() -> sel(), v -> log.push('sel:$v'));
			});
			flush();
			equals(log, ["sel:-1"]);
			fixed(false);
			flush();
			equals(log, ["sel:-1"]);
			h.release();
			flush();
			equals(log, ["sel:-1", "sel:1"]);
		}).skip(); // (known gap: Solid's rule not yet followed, DESIGN.md 2, Holds)
	});
}
