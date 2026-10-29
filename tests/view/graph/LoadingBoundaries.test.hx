package view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Memo;
import helder.view.graph.Signal;
import helder.view.graph.Graph.*;
import view.graph.Kit;

// createLoadingBoundary.test.ts (F-4, F-5, F-12), and spec-async-semantics
// A15 and A19's boundary cases. Solid's projections are async memos here.
function tests() {
	afterEach(() -> flush());

	describe("createLoadingBoundary", () -> {
		// (adapted: an async memo for the projection)
		test("nested boundaries - inner catches async", () -> {
			var load = new Later<Int>();
			var outerResult:Dynamic = null, innerResult:Dynamic = null;
			root(_ -> {
				var value = memo(() -> load);
				var outer = loadingBoundary(() -> {
					var inner = loadingBoundary(() -> (value() : Dynamic), () -> "inner-loading");
					renderEffect(() -> innerResult = inner(), _ -> {});
					("outer-content" : Dynamic);
				}, () -> "outer-loading");
				renderEffect(() -> outerResult = outer(), _ -> {});
			});
			flush();
			equals(innerResult, "inner-loading");
			equals(outerResult, "outer-content");
			load.resolve(1);
			flush();
			equals(innerResult, 1);
			equals(outerResult, "outer-content");
		});

		function rejectionScene(nested:Bool) {
			var count = signal(0);
			var current = new Later<Int>();
			var first:Dynamic = null, second:Dynamic = null;
			root(_ -> {
				var source = memo(() -> {
					count();
					current;
				});
				var branch1 = loadingBoundary(() -> errorBoundary(() -> nested ? loadingBoundary(() -> ('S: ${source()}' : Dynamic),
					() -> null)() : ('S: ${source()}' : Dynamic), (_, _) -> "error1")(), () -> null);
				var branch2 = errorBoundary(() -> loadingBoundary(() -> ('S: ${source()}' : Dynamic), () -> null)(), (_, _) -> "error2");
				renderEffect(() -> first = branch1(), _ -> {});
				renderEffect(() -> second = branch2(), _ -> {});
			});
			flush();
			return {
				count: count,
				current: () -> current,
				next: () -> current = new Later<Int>(),
				shown: () -> [first, second]
			};
		}

		for (nested in [false, true])
			test(nested ? "nested Loading does not suppress eventual error fallback" : "surfaces async rejection consistently for Loading/Errored orderings",
				() -> {
					var s = rejectionScene(nested);
					equals(s.shown(), [null, null]);
					s.current().reject(100);
					flush();
					equals(s.shown(), ["error1", "error2"]);
					s.next();
					s.count(1);
					flush();
					equals(s.shown(), ["error1", "error2"]);
					s.current().reject(100);
					flush();
					equals(s.shown(), ["error1", "error2"]);
				});

		test("clears held errors after a refresh resolves successfully", () -> {
			var s = rejectionScene(false);
			s.current().reject(100);
			flush();
			equals(s.shown(), ["error1", "error2"]);
			s.next();
			s.count(1);
			flush();
			equals(s.shown(), ["error1", "error2"]);
			s.current().resolve(10);
			flush();
			equals(s.shown(), ["S: 10", "S: 10"]);
		});

		// (adapted: an async memo for the projection)
		test("side effect only runs when no longer pending", () -> {
			var load = new Later<Int>();
			var runs = 0;
			var result:Dynamic = null;
			root(_ -> {
				var value = memo(() -> load);
				var boundary = loadingBoundary(() -> (value() : Dynamic), () -> "loading");
				renderEffect(() -> result = boundary(), _ -> runs++);
			});
			flush();
			equals(result, "loading");
			equals(runs, 1);
			load.resolve(1);
			flush();
			equals(result, 1);
			equals(runs, 2);
		});

		// (adapted: an async memo for the projection)
		test("handles rapid signal changes while pending", () -> {
			var f = new Fetcher((v:Int) -> v * 2);
			var x = signal(1);
			var result:Dynamic = null;
			root(_ -> {
				var value = memo(() -> f.fetch(x()));
				var boundary = loadingBoundary(() -> (value() : Dynamic), () -> "loading");
				renderEffect(() -> result = boundary(), _ -> {});
			});
			flush();
			equals(result, "loading");
			x(2);
			flush();
			equals(result, "loading");
			f.resolveAll();
			flush();
			equals(result, 4);
		});

		test("does not throw dev error when pending async value is read inside a tracking scope", () -> {
			var load = new Later<String>();
			var result:Dynamic = null;
			root(_ -> {
				var data = memo(() -> load);
				flush();
				untrack(() -> {
					var boundary = loadingBoundary(() -> (data() : Dynamic), () -> "loading");
					renderEffect(() -> result = boundary(), _ -> {});
				});
			});
			flush();
			equals(result, "loading");
			load.resolve("Hello world!");
			flush();
			equals(result, "Hello world!");
		});

		describe("async memo resolves to same value as initial (solidjs#2604)", () -> {
			for (v in [100, 101])
				test(v == 100 ? "same value resolves through boundary" : "different value resolves through boundary", () -> {
					var load = new Later<Int>();
					var result:Dynamic = null;
					root(_ -> {
						var data = memo(() -> load);
						var boundary = loadingBoundary(() -> (data() : Dynamic), () -> "loading");
						renderEffect(() -> result = boundary(), _ -> {});
					});
					flush();
					equals(result, "loading");
					load.resolve(v);
					flush();
					equals(result, v);
				});

			test("does not re-run compute when resolving same value", () -> {
				var load = new Later<Int>();
				var callCount = 0;
				var result:Dynamic = null;
				root(_ -> {
					var data = memo(() -> {
						callCount++;
						load;
					});
					var boundary = loadingBoundary(() -> (data() : Dynamic), () -> "loading");
					renderEffect(() -> result = boundary(), _ -> {});
				});
				flush();
				equals(callCount, 1);
				equals(result, "loading");
				load.resolve(100);
				flush();
				equals(result, 100);
				equals(callCount, 1);
			});
		});

		// (mountLike: a memo making the boundary, a render effect reading what it made)
		describe("fresh boundary around updating async source", () -> {
			function keyed(page:Signal<String>, content:String->Dynamic) {
				var result:Dynamic = null;
				root(_ -> {
					var shown = memo(() -> {
						var p = page();
						loadingBoundary(() -> content(p), () -> "loading");
					});
					renderEffect(() -> result = shown()(), _ -> {});
				});
				return () -> result;
			}

			function pageSource(page:Signal<String>) {
				var current = new Later<String>();
				var source = root(_ -> memo(() -> {
					var p = page();
					var l = current;
					// (await current.promise; return `value-${page}`)
					var r = new Later<String>();
					l.onAnswer(_ -> r.resolve('value-$p'), e -> r.reject(e));
					r;
				}));
				return {source: source, resolve: () -> current.resolve(""), renew: () -> current = new Later<String>()};
			}

			test("shows fallback when a keyed subtree directly inserts an external pending async source", () -> {
				var page = signal("a");
				var s = pageSource(page);
				var result = keyed(page, p -> 'Page $p: ${s.source()}');
				flush();
				equals(result(), "loading");
				s.resolve();
				flush();
				equals(result(), "Page a: value-a");
				s.renew();
				page("b");
				flush();
				equals(result(), "loading");
				s.resolve();
				flush();
				equals(result(), "Page b: value-b");
			});

			test("settled normal and latest reads converge for async sibling memos", () -> {
				var c = new Clock();
				var og = signal(553);
				var result:Dynamic = null;
				var direct:Memo<Int> = null;
				var boundary:Memo<Dynamic> = null;
				root(_ -> {
					var derived1 = memo(() -> c.delay(1000, og() + 1));
					var derived2 = memo(() -> c.delay(1000, derived1() + 1));
					direct = derived2;
					// (the two sync memos as the content's two reads)
					boundary = loadingBoundary(() -> ('a. ${derived2()} b. ${latest(() -> derived2())}' : Dynamic), () -> "Loading...");
					renderEffect(() -> result = boundary(), _ -> {});
				});
				flush();
				equals(result, "Loading...");
				c.advanceTo(1000);
				equals(result, "Loading...");
				c.advanceTo(2000);
				equals(direct(), 555);
				equals(latest(() -> direct()), 555);
				equals(boundary(), "a. 555 b. 555");
				equals(result, "a. 555 b. 555");
				og(v -> v + 1);
				flush();
				equals(result, "a. 555 b. 555");
				c.advanceTo(3000);
				equals(result, "a. 555 b. 555");
				c.advanceTo(4000);
				equals(result, "a. 556 b. 556");
			});

			test("shows inline pending when a keyed subtree revalidates an external async source with isPending", () -> {
				var page = signal("a");
				var s = pageSource(page);
				var result = keyed(page, p -> 'Page $p: ${isPending(() -> s.source()) ? "pending" : s.source()}');
				flush();
				equals(result(), "loading");
				s.resolve();
				flush();
				equals(result(), "Page a: value-a");
				s.renew();
				page("b");
				flush();
				equals(result(), "Page b: pending");
				s.resolve();
				flush();
				equals(result(), "Page b: value-b");
			});

			test("shows inline pending when a keyed subtree only reads isPending for an updating async source", () -> {
				var page = signal("a");
				var s = pageSource(page);
				var result = keyed(page, p -> 'Page $p: ${isPending(() -> s.source()) ? "pending" : "ready"}');
				flush();
				equals(result(), "loading");
				s.resolve();
				flush();
				equals(result(), "Page a: ready");
				s.renew();
				page("b");
				flush();
				equals(result(), "Page b: pending");
				s.resolve();
				flush();
				equals(result(), "Page b: ready");
			});

			test("shows fallback when a keyed subtree mounts a nested insert over an external pending async source", () -> {
				var page = signal("a");
				var s = pageSource(page);
				var result = keyed(page, p -> {
					// (the boundary's body runs once per mount here: no `started` flag needed)
					renderEffect(() -> s.source(), _ -> {});
					'Page $p: <span />';
				});
				flush();
				equals(result(), "loading");
				s.resolve();
				flush();
				equals(result(), "Page a: <span />");
				s.renew();
				page("b");
				flush();
				equals(result(), "loading");
				s.resolve();
				flush();
				equals(result(), "Page b: <span />");
			});

			for (nestedInsert in [false, true])
				test(nestedInsert ? "shows fallback for nested insert when each keyed branch reads its own external async source" : "shows fallback when each keyed branch reads its own external async source",
					() -> {
						var page = signal("a");
						var loadA = new Later<String>(), loadB = new Later<String>();
						var sourceA = root(_ -> memo(() -> loadA)), sourceB = root(_ -> memo(() -> loadB));
						var result = keyed(page, p -> {
							var source = p == "a" ? sourceA : sourceB;
							if (nestedInsert) {
								renderEffect(() -> source(), _ -> {});
								return 'Page $p: <span />';
							}
							'Page $p: ${source()}';
						});
						flush();
						equals(result(), "loading");
						loadA.resolve("value-a");
						flush();
						equals(result(), nestedInsert ? "Page a: <span />" : "Page a: value-a");
						page("b");
						flush();
						equals(result(), "loading");
						loadB.resolve("value-b");
						flush();
						equals(result(), nestedInsert ? "Page b: <span />" : "Page b: value-b");
					});
		});

		test("stops loading when a pending child is disposed before its promise settles", () -> {
			var result:Dynamic = null;
			var showAsync = signal(true);
			var load = new Later<String>();
			function child() {
				var data = memo(() -> load);
				return () -> data();
			}
			root(_ -> {
				var boundary = loadingBoundary(() -> (showAsync() ? child()() : "sync" : Dynamic), () -> "loading");
				renderEffect(() -> result = boundary(), _ -> {});
			});
			flush();
			equals(result, "loading");
			load.resolve("async");
			showAsync(false);
			flush();
			equals(result, "sync");
		});

		test("instantiates the fallback once per show: a second reader going pending does not rebuild it", () -> {
			var fallbackRuns = 0;
			var result:Dynamic = null;
			var loadA = new Later<String>(), loadB = new Later<String>();
			var showB = signal(false);
			root(_ -> {
				var dataA = memo(() -> loadA);
				var dataB = memo(() -> loadB);
				var boundary = loadingBoundary(() -> {
					var cells = {a: "", b: ""};
					renderEffect(() -> dataA(), v -> cells.a = v);
					renderEffect(() -> showB() ? dataB() : "-", v -> cells.b = v);
					(cells : Dynamic);
				}, () -> {
					fallbackRuns++;
					"loading";
				});
				renderEffect(() -> boundary(), v -> result = v);
			});
			flush();
			equals(result, "loading");
			equals(fallbackRuns, 1);
			showB(true);
			flush();
			equals(fallbackRuns, 1);
			loadA.resolve("A");
			flush();
			equals(result, "loading");
			equals(fallbackRuns, 1);
			loadB.resolve("B");
			flush();
			equals(result, {a: "A", b: "B"});
			equals(fallbackRuns, 1);
		});

		test("holds every queued run behind the fallback until the reveal; the synchronous first render goes through", () -> {
			var log:Array<String> = [];
			var count = signal(0);
			var load = new Later<String>();
			var result:Dynamic = null;
			root(_ -> {
				var data = memo(() -> load);
				var boundary = loadingBoundary(() -> {
					var cell = {data: ""};
					renderEffect(() -> data(), v -> cell.data = v);
					renderEffect(() -> count(), v -> log.push('render $v'));
					effect(() -> count(), v -> log.push('user $v'));
					(cell : Dynamic);
				}, () -> "loading");
				renderEffect(() -> boundary(), v -> result = v);
			});
			flush();
			equals(result, "loading");
			equals(log, ["render 0"]);
			count(1);
			flush();
			equals(log, ["render 0"]);
			load.resolve("ready");
			flush();
			equals(result, {data: "ready"});
			equals(log, ["render 0", "render 1", "user 1"]);
			count(2);
			flush();
			equals(log, ["render 0", "render 1", "user 1", "render 2", "user 2"]);
		});
	});

	// spec-async-semantics.test.ts
	describe("A15: a loading boundary catches an existing flight", () -> {
		test("lets a new loading boundary catch an existing flight without holding the reveal", () -> {
			var f = new Fetcher((v:Int) -> v);
			var value = signal(0), show = signal(false);
			var showLine = "", slot:Dynamic = null;
			root(_ -> {
				var details = memo(() -> f.fetch(value()));
				renderEffect(() -> '${show()} ${isPending(() -> show())}', v -> showLine = v);
				renderEffect(() -> show() ? loadingBoundary(() -> (details() : Dynamic), () -> "loading")() : "hidden", v -> slot = v);
			});
			flush();
			equals(([showLine, slot] : Array<Dynamic>), (["false false", "hidden"] : Array<Dynamic>));
			value(1);
			flush();
			equals(value(), 1);
			show(true);
			flush();
			equals(([showLine, slot] : Array<Dynamic>), (["true false", "loading"] : Array<Dynamic>));
			equals(show(), true);
			equals(isPending(() -> show()), false);
			f.resolveAll();
			flush();
			equals(([showLine, slot] : Array<Dynamic>), (["true false", 1] : Array<Dynamic>));
		});
	});

	describe("A19: boundaries and verdicts", () -> {
		test("initialized refetch under a nested loading boundary: content holds, verdicts stay pending until resolution", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var tick = signal(1);
			var rendered:Dynamic = null;
			var data = root(_ -> {
				var data = memo(() -> f.fetch(tick()));
				var boundary = loadingBoundary(() -> 'v:${data()}', () -> "loading");
				renderEffect(() -> rendered = boundary(), _ -> {});
				data;
			});
			flush();
			f.resolveAll();
			flush();
			equals(rendered, "v:10");
			tick(2);
			flush();
			equals(rendered, "v:10");
			equals(isPending(() -> tick()), true);
			equals(isPending(() -> data()), true);
			f.resolveAll();
			flush();
			equals(rendered, "v:20");
			equals(isPending(() -> tick()), false);
			equals(isPending(() -> data()), false);
		});

		// (F-4: a mount into a boundary that has shown content holds the change, F-2)
		test("nav revealing an uninitialized async: trigger pending until the new view can show, data is loading (not pending)", () -> {
			var f = new Fetcher((v:Int) -> v * 10);
			var location = signal(1);
			var rendered:Dynamic = null;
			root(_ -> {
				var page2Data = memo(() -> f.fetch(location()));
				var boundary = loadingBoundary(() -> location() == 2 ? 'page2:${page2Data()}' : "page1", () -> "fallback");
				renderEffect(() -> rendered = boundary(), _ -> {});
			});
			flush();
			equals(rendered, "page1");
			location(2);
			flush();
			equals(rendered, "page1");
			equals(location(), 1);
			equals(isPending(() -> location()), true);
			f.resolveAll();
			flush();
			equals(rendered, "page2:20");
			equals(location(), 2);
			equals(isPending(() -> location()), false);
		});
	});
}
