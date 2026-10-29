package view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Memo;
import helder.view.graph.Node;
import helder.view.graph.Graph.*;
import view.graph.Kit;

private class MyError {
	public final message:String;

	public function new(message)
		this.message = message;
}

// createErrorBoundary.test.ts (F-12), error-is-an-answer.test.ts (D-41),
// effect-error-phases.test.ts (F-12's effect half). Halt mechanics
// (REACTIVITY_HALTED, resetErrorHalt, console logs) are Solid's: only an
// error surfacing from the flush is ported.
function tests() {
	afterEach(() -> try flush() catch (e:Dynamic) {});

	// (a boundary's value read to the end: a boundary made inside another's content is read too)
	function unwrap(v:Dynamic):Dynamic {
		while (Std.isOfType(v, Node))
			v = (v : Node<Dynamic>).read();
		return v;
	}

	describe("createErrorBoundary", () -> {
		test("should let errors bubble up when not handled", () -> {
			var error = new MyError("");
			var caught = throws(() -> {
				root(_ -> renderEffect(() -> throw error, _ -> {}));
				flush();
			});
			assert(caught == error);
		});

		test("should handle error", () -> {
			var b = root(_ -> errorBoundary(() -> throw new MyError(""), (_, _) -> "errored"));
			equals(b(), "errored");
		});

		test("should forward error to another handler", () -> {
			var error = new MyError("");
			var b = root(_ -> errorBoundary(() -> {
				var inner = errorBoundary(() -> throw error, (e, _) -> {
					assert(e() == error);
					throw e();
				});
				renderEffect(() -> inner(), _ -> {});
				(null : Dynamic);
			}, (_, _) -> "errored"));
			equals(b(), "errored");
		});

		test("should not duplicate error handler", () -> {
			var error = new MyError("");
			var handler = new Spy();
			var x = signal(0);
			var shouldThrow = false;
			root(_ -> {
				var b = errorBoundary(() -> {
					x();
					if (shouldThrow) throw error;
					(null : Dynamic);
				}, (e, _) -> handler.ret(e()));
				renderEffect(() -> b(), _ -> {});
			});
			x(1);
			flush();
			shouldThrow = true;
			x(2);
			flush();
			equals(handler.calls, 1);
		});

		test("should not trigger wrong handler", () -> {
			var error = new MyError("");
			var rootHandler = new Spy(), handler = new Spy();
			var x = signal(0);
			var shouldThrow = false;
			root(_ -> {
				var b = errorBoundary(() -> {
					renderEffect(() -> {
						x();
						if (shouldThrow) throw error;
					}, _ -> {});
					var b2 = errorBoundary(() -> (null : Dynamic), (e, _) -> handler.ret(e()));
					renderEffect(() -> b2(), _ -> {});
					(null : Dynamic);
				}, (e, _) -> rootHandler.ret(e()));
				renderEffect(() -> b(), _ -> {});
			});
			equals(rootHandler.calls, 0);
			shouldThrow = true;
			x(1);
			flush();
			equals(rootHandler.calls, 1);
			assert(!handler.calledWith(error));
		});

		test("should throw error if there are no handlers left", () -> {
			var error = new MyError("");
			var handler = new Spy();
			root(_ -> {
				var caught = throws(() -> {
					errorBoundary(() -> {
						errorBoundary(() -> throw error, (e, _) -> {
							handler.call(e());
							throw e();
						})();
					}, (e, _) -> {
						handler.call(e());
						throw e();
					})();
				});
				assert(caught == error);
			});
			equals(handler.calls, 2);
		});

		test("should handle errors when the effect is on the outside", () -> {
			var error = new MyError("");
			var rootHandler = new Spy();
			var x = signal(0);
			root(_ -> {
				var b = errorBoundary(() -> {
					if (x() > 0) throw error;
					errorBoundary(() -> throw error, (e, _) -> {
						assert(e() == error);
						null;
					});
					(null : Dynamic);
				}, (e, _) -> rootHandler.ret(e()));
				renderEffect(() -> b(), _ -> {});
			});
			equals(rootHandler.calls, 0);
			x(1);
			flush();
			assert(rootHandler.calledWith(error));
			equals(rootHandler.calls, 1);
		});

		test("should handle errors when the effect is on the outside and memo in the middle", () -> {
			var rootHandler = new Spy();
			root(_ -> {
				var b = errorBoundary(() -> (memo(() -> throw new MyError("")) : Dynamic), (e, _) -> rootHandler.ret(e()));
				renderEffect(() -> b(), _ -> {});
			});
			equals(rootHandler.calls, 1);
		});

		// (action → a write held by an async gate, Kit.hold: F-2, recovery is held like any content)
		test("should hold error boundary during transition when signal change clears error", () -> {
			var shouldError = signal(true);
			var result:Dynamic = null;
			root(_ -> {
				var b = errorBoundary(() -> {
					if (shouldError()) throw new MyError("test error");
					"content";
				}, (_, _) -> "error");
				renderEffect(() -> b(), v -> result = v);
			});
			flush();
			equals(result, "error");
			var release = Kit.hold(() -> shouldError(false), () -> shouldError());
			equals(result, "error");
			release();
			flush();
			equals(result, "content");
		});

		test("should catch errors thrown in render effect callbacks (back half)", () -> {
			var error = new MyError("effect callback error");
			var handler = new Spy();
			root(_ -> {
				var b = errorBoundary(() -> {
					renderEffect(() -> "value", _ -> throw error);
					"content";
				}, (e, _) -> {
					handler.call(e());
					"errored";
				});
				renderEffect(() -> b(), _ -> {});
			});
			flush();
			equals(handler.calls, 1);
			assert(handler.calledWith(error));
		});

		test("should catch errors thrown in user effect callbacks (back half)", () -> {
			var error = new MyError("user effect callback error");
			var handler = new Spy();
			var result:Dynamic = null;
			root(_ -> {
				var b = errorBoundary(() -> {
					effect(() -> "value", _ -> throw error);
					"content";
				}, (e, _) -> {
					handler.call(e());
					"errored";
				});
				renderEffect(() -> result = b(), _ -> {});
			});
			flush();
			equals(handler.calls, 1);
			assert(handler.calledWith(error));
			equals(result, "errored");
		});

		test("should catch errors thrown in effect cleanup functions (#2813)", () -> {
			var n = signal(0);
			var handler = new Spy();
			var result:Dynamic = null;
			root(_ -> {
				var b = errorBoundary(() -> {
					effect(() -> n(), v -> () -> if (v == 0) throw "cleanup boom");
					"content";
				}, (e, _) -> {
					handler.call(e());
					"errored";
				});
				renderEffect(() -> result = b(), _ -> {});
			});
			flush();
			n(1);
			flush();
			equals(handler.calls, 1);
			equals(handler.args[0][0], "cleanup boom");
			equals(result, "errored");
		});

		test("should catch errors thrown in user effect callbacks with error handler (back half)", () -> {
			var error = new MyError("user effect bundle error");
			var handler = new Spy(), errorHandler = new Spy();
			var result:Dynamic = null;
			root(_ -> {
				var b = errorBoundary(() -> {
					effect(() -> "value", _ -> throw error, errorHandler.fn1());
					"content";
				}, (e, _) -> {
					handler.call(e());
					"errored";
				});
				renderEffect(() -> result = b(), _ -> {});
			});
			flush();
			equals(handler.calls, 1);
			assert(handler.calledWith(error));
			equals(errorHandler.calls, 0);
			equals(result, "errored");
		});

		test("should recover from effect callback error after reset", () -> {
			var shouldThrow = true;
			var result:Dynamic = null;
			var resetFn:Null<Void->Void> = null;
			root(_ -> {
				var b = errorBoundary(() -> {
					renderEffect(() -> "value", _ -> if (shouldThrow) throw new MyError("effect callback error"));
					"content";
				}, (_, reset) -> {
					resetFn = reset;
					"errored";
				});
				renderEffect(() -> result = b(), _ -> {});
			});
			flush();
			equals(result, "errored");
			assert(resetFn != null);
			shouldThrow = false;
			resetFn();
			flush();
			equals(result, "content");
		});

		test("should throw effect callback errors when no boundary exists", () -> {
			var error = new MyError("uncaught effect error");
			var caught = throws(() -> {
				root(_ -> renderEffect(() -> "value", _ -> throw error));
				flush();
			});
			assert(caught == error);
		});

		test("should recover when async memo errors then dependency changes and boundary resets", () -> {
			var id = signal("bad");
			var result:Dynamic = null;
			var resetFn:Null<Void->Void> = null;
			root(_ -> {
				var data = memo(() -> {
					var i = id();
					i != "1" ? Kit.rejected('Item $i not found') : Kit.resolved({title: "Test Item"});
				});
				var boundary = errorBoundary(() -> loadingBoundary(() -> (data().title : Dynamic), () -> "loading")(), (e, reset) -> {
					resetFn = reset;
					"error: " + e();
				});
				renderEffect(() -> result = boundary(), _ -> {});
			});
			flush();
			flush();
			equals(result, "error: Item bad not found");
			id("1");
			resetFn();
			flush();
			flush();
			equals(result, "Test Item");
		});

		test("should recover when sync memo errors then dependency changes and boundary resets", () -> {
			var id = signal("bad");
			var result:Dynamic = null;
			var resetFn:Null<Void->Void> = null;
			root(_ -> {
				var data = memo(() -> {
					var i = id();
					if (i != "1") throw 'Item $i not found';
					"ok";
				});
				var boundary = errorBoundary(() -> data(), (_, reset) -> {
					resetFn = reset;
					"error";
				});
				renderEffect(() -> result = boundary(), _ -> {});
			});
			flush();
			equals(result, "error");
			id("1");
			resetFn();
			flush();
			equals(result, "ok");
		});

		test("does not loop when an async memo is read inside Loading > Errored (#2809)", () -> {
			function app(source:Later<{id:Int}>):Memo<Dynamic> {
				var posts = memo(() -> source);
				// (Solid's boundary flattens the accessor its content returns: read here)
				return loadingBoundary(() -> errorBoundary(() -> (posts().id : Dynamic), (e, _) -> "caught: " + e())(), () -> "loading");
			}
			var ok:Memo<Dynamic> = null, bad:Memo<Dynamic> = null;
			var resolved = new Later<{id:Int}>(), rejected = new Later<{id:Int}>();
			root(_ -> {
				ok = app(resolved);
				bad = app(rejected);
			});
			flush();
			equals(unwrap(ok), "loading");
			equals(unwrap(bad), "loading");
			resolved.resolve({id: 1});
			rejected.reject("posts failed");
			flush();
			equals(unwrap(ok), 1);
			equals(unwrap(bad), "caught: posts failed");
		});

		describe("Errored > Loading > Errored", () -> {
			function mountNested(content:Void->String) {
				var rendered:Dynamic = null;
				var dispose = root(dispose -> {
					var outer = errorBoundary(() -> loadingBoundary(() -> errorBoundary(content, (_, _) -> "inner caught")(), () -> "loading")(),
						(_, _) -> "outer caught");
					renderEffect(() -> rendered = outer(), _ -> {});
					dispose;
				});
				return {rendered: () -> rendered, dispose: dispose};
			}

			test("catches at the inner Errored when content throws in the mounting flush (Errored > Loading > Errored)", () -> {
				var m = mountNested(() -> throw "boom on mount");
				flush();
				equals(m.rendered(), "inner caught");
				m.dispose();
			});

			test("catches at the inner Errored when content throws reactively after a healthy commit (Errored > Loading > Errored)", () -> {
				var boom = signal(false);
				var m = mountNested(() -> {
					if (boom()) throw "boom";
					"ok";
				});
				flush();
				equals(m.rendered(), "ok");
				boom(true);
				flush();
				equals(m.rendered(), "inner caught");
				m.dispose();
			});

			test("catches an async rejection at the inner Errored (Errored > Loading > Errored)", () -> {
				var load = new Later<String>();
				var rendered:Dynamic = null;
				var dispose = root(dispose -> {
					var data = memo(() -> load);
					var outer = errorBoundary(() -> loadingBoundary(() -> errorBoundary(() -> 'value: ${data()}', (_, _) -> "inner caught")(),
						() -> "loading")(), (_, _) -> "outer caught");
					renderEffect(() -> rendered = outer(), _ -> {});
					dispose;
				});
				flush();
				equals(rendered, "loading");
				load.reject("boom async");
				flush();
				equals(rendered, "inner caught");
				dispose();
			});

			test("routes a sync mount error past a Loading to the outer Errored (Errored > Loading > content)", () -> {
				var rendered:Dynamic = null;
				var dispose = root(dispose -> {
					var outer = errorBoundary(() -> loadingBoundary(() -> (throw "boom on mount" : String), () -> "loading")(), (_, _) -> "outer caught");
					renderEffect(() -> rendered = outer(), _ -> {});
					dispose;
				});
				flush();
				equals(rendered, "outer caught");
				dispose();
			});

			test("routes a reactive sync error past a committed Loading to the outer Errored (Errored > Loading > content)", () -> {
				var boom = signal(false);
				var rendered:Dynamic = null;
				var dispose = root(dispose -> {
					var outer = errorBoundary(() -> loadingBoundary(() -> {
						if (boom()) throw "boom";
						"ok";
					}, () -> "loading")(), (_, _) -> "outer caught");
					renderEffect(() -> rendered = outer(), _ -> {});
					dispose;
				});
				flush();
				equals(rendered, "ok");
				boom(true);
				flush();
				equals(rendered, "outer caught");
				dispose();
			});
		});

		test("instantiates the fallback once per show: a second error reaches it through the `error` accessor, not a re-render", () -> {
			var a = signal(0), b = signal(0);
			var fallbackRuns = 0;
			var shown:Dynamic = null;
			root(_ -> {
				var boundary = errorBoundary(() -> {
					renderEffect(() -> if (a() > 0) throw 'a:${a()}', _ -> {});
					renderEffect(() -> if (b() > 0) throw 'b:${b()}', _ -> {});
					"content";
				}, (e, _) -> {
					fallbackRuns++;
					renderEffect(() -> e(), m -> shown = m);
					"fallback";
				});
				renderEffect(() -> boundary(), _ -> {});
			});
			flush();
			equals(fallbackRuns, 0);
			a(1);
			flush();
			equals(fallbackRuns, 1);
			equals(shown, "a:1");
			b(1);
			flush();
			equals(fallbackRuns, 1);
			equals(shown, "b:1");
		});

		test("holds user effects behind the error fallback until recovery", () -> {
			var log:Array<String> = [];
			var count = signal(0), bad = signal(false);
			var resetFn:Null<Void->Void> = null;
			var result:Dynamic = null;
			root(_ -> {
				var boundary = errorBoundary(() -> {
					effect(() -> count(), v -> log.push('user $v'));
					renderEffect(() -> if (bad()) throw "boom", _ -> {});
					"content";
				}, (_, reset) -> {
					resetFn = reset;
					"fallback";
				});
				renderEffect(() -> boundary(), v -> result = v);
			});
			flush();
			equals(result, "content");
			equals(log, ["user 0"]);
			bad(true);
			flush();
			equals(result, "fallback");
			count(1);
			flush();
			equals(log, ["user 0"]);
			bad(false);
			resetFn();
			flush();
			equals(result, "content");
			equals(log, ["user 0", "user 1"]);
		});
	});

	// error-is-an-answer.test.ts (D-41: an error ends the wait like a value, and shows when a value would)
	describe("an error is an answer", () -> {
		function scene(boundary:Bool) {
			var request = new Later<Int>(), sibling = new Later<Int>();
			var count = signal(1);
			var screen = {count: 0, data: (null : Dynamic), slow: 0};
			var log:Array<Dynamic> = [];
			var data:Memo<Int> = null;
			var dispose = root(d -> {
				data = memo(() -> {
					count();
					request;
				});
				var slow = memo(() -> {
					count();
					sibling;
				});
				renderEffect(() -> count(), v -> screen.count = v);
				if (boundary) {
					var errored = errorBoundary(() -> (data() : Dynamic), (e, _) -> 'Error ${e()}');
					renderEffect(() -> errored(), v -> screen.data = v);
				} else
					screen.data = "no boundary";
				renderEffect(() -> slow(), v -> screen.slow = v);
				effect(() -> data(), v -> log.push(v), e -> log.push(e));
				d;
			});
			return {
				screen: screen,
				log: log,
				data: data,
				ask: (n:Int) -> {
					request = new Later<Int>();
					sibling = new Later<Int>();
					count(n);
					flush();
				},
				untracked: () -> Kit.attempt(() -> data()),
				answer: (v:Int) -> request.resolve(v),
				fail: (e:Dynamic) -> request.reject(e),
				land: (v:Int) -> sibling.resolve(v),
				dispose: dispose
			};
		}

		for (boundary in [true, false]) {
			test('S-42: a held rejection reveals with its frame (boundary: $boundary)', () -> {
				var s = scene(boundary);
				var shown = boundary ? "Error 2" : "no boundary";
				flush();
				s.answer(1);
				s.land(1);
				flush();
				equals(s.screen, {count: 1, data: boundary ? (1 : Dynamic) : "no boundary", slow: 1});
				equals(s.log, ([1] : Array<Dynamic>));
				s.ask(2);
				equals(s.screen, {count: 1, data: boundary ? (1 : Dynamic) : "no boundary", slow: 1});
				equals(isPending(() -> s.data()), true);
				equals(latest(() -> s.data()), 1);
				s.fail("2");
				flush();
				equals(s.screen, {count: 1, data: boundary ? (1 : Dynamic) : "no boundary", slow: 1});
				equals(s.log, ([1] : Array<Dynamic>));
				equals((s.untracked() : Dynamic), 1);
				equals(isPending(() -> s.data()), true);
				equals(throws(() -> latest(() -> s.data())), "2");
				s.land(2);
				flush();
				equals(s.screen, {count: 2, data: (shown : Dynamic), slow: 2});
				equals(s.log, ([1, "2"] : Array<Dynamic>));
				equals((s.untracked() : Dynamic), "2");
				equals(isPending(() -> s.data()), false);
				s.dispose();
			});

			test('S-43: a held recovery keeps the shown error; the last good value is a new answer (boundary: $boundary)', () -> {
				var s = scene(boundary);
				var shown = boundary ? "Error 2" : "no boundary";
				var recovered:Dynamic = boundary ? (1 : Dynamic) : "no boundary";
				flush();
				s.answer(1);
				s.land(1);
				flush();
				s.ask(2);
				s.fail("2");
				s.land(2);
				flush();
				equals(s.screen, {count: 2, data: (shown : Dynamic), slow: 2});
				equals(s.log, ([1, "2"] : Array<Dynamic>));
				s.ask(3);
				equals(s.screen, {count: 2, data: (shown : Dynamic), slow: 2});
				equals((s.untracked() : Dynamic), "2");
				equals(isPending(() -> s.data()), true);
				s.answer(1);
				flush();
				equals(s.screen, {count: 2, data: (shown : Dynamic), slow: 2});
				equals((s.untracked() : Dynamic), "2");
				equals(s.log, ([1, "2"] : Array<Dynamic>));
				equals(isPending(() -> s.data()), true);
				equals(latest(() -> s.data()), 1);
				s.land(3);
				flush();
				equals(s.screen, {count: 3, data: recovered, slow: 3});
				equals((s.untracked() : Dynamic), 1);
				equals(s.log, ([1, "2", 1] : Array<Dynamic>));
				equals(isPending(() -> s.data()), false);
				s.dispose();
			});
		}

		test("recovering to the last good value after an async rejection reaches the effect", () -> {
			var count = signal(0);
			var log:Array<Dynamic> = [];
			var data:Memo<Int> = null;
			var dispose = root(d -> {
				data = memo(() -> count() == 1 ? Kit.rejected("failed") : Kit.resolved(1));
				effect(() -> data(), v -> log.push(v), e -> log.push(e));
				d;
			});
			flush();
			flush();
			count(1);
			flush();
			flush();
			equals(log, ([1, "failed"] : Array<Dynamic>));
			count(2);
			flush();
			flush();
			equals(data(), 1);
			equals(isPending(() -> data()), false);
			equals(log, ([1, "failed", 1] : Array<Dynamic>));
			dispose();
		});
	});

	// effect-error-phases.test.ts (#2839, #2840)
	describe("createEffect error phases", () -> {
		test("compute-phase throw with no handler: logged, run skipped, system alive", () -> {
			var log:Array<String> = [];
			var beat = signal(0), armed = signal(false);
			root(_ -> {
				renderEffect(() -> beat(), v -> log.push('beat=$v'));
				effect(() -> {
					if (armed()) throw "boom-compute";
					0;
				}, _ -> log.push("effect ran"));
			});
			flush();
			equals(log, ["beat=0", "effect ran"]);
			log.resize(0);
			armed(true);
			try flush() catch (e:Dynamic) fail('the flush threw $e');
			equals(log, []);
			beat(1);
			flush();
			equals(log, ["beat=1"]);
		});

		test("compute-phase throw with EffectBundle handler: handler receives it, no log", () -> {
			var log:Array<String> = [];
			var armed = signal(false);
			root(_ -> effect(() -> {
				if (armed()) throw "boom-compute";
				0;
			}, _ -> {}, e -> log.push('handler: $e')));
			flush();
			armed(true);
			flush();
			equals(log, ["handler: boom-compute"]);
		});

		test("handler receives the thrown error's identity, not the internal wrapper (#2840)", () -> {
			var boom = new MyError("boom-identity");
			var armed = signal(false);
			var received:Dynamic = null;
			root(_ -> effect(() -> {
				if (armed()) throw boom;
				0;
			}, _ -> {}, e -> received = e));
			flush();
			armed(true);
			flush();
			assert(received == boom);
			assert(Std.isOfType(received, MyError));
		});

		test("handler runs in a writable scope: signal writes are legal (#2840)", () -> {
			var armed = signal(false), errorMsg = signal("");
			var views:Array<String> = [];
			root(_ -> {
				effect(() -> {
					if (armed()) throw "boom-write";
					0;
				}, _ -> {}, e -> errorMsg((e : String)));
				renderEffect(() -> errorMsg(), v -> views.push(v));
			});
			flush();
			equals(views, [""]);
			armed(true);
			flush();
			equals(errorMsg(), "boom-write");
			equals(views, ["", "boom-write"]);
		});

		test("error that recovers before the effect phase never reaches the handler (#2840)", () -> {
			var source = signal(0);
			var handled:Array<String> = [], ran:Array<Int> = [];
			root(_ -> effect(() -> {
				var v = source();
				if (v == 1) throw "transient";
				v;
			}, v -> ran.push(v), e -> handled.push(e)));
			flush();
			equals(ran, [0]);
			source(1);
			source(2);
			flush();
			equals(handled, []);
			equals(ran, [0, 2]);
			source(1);
			flush();
			equals(handled, ["transient"]);
			equals(ran, [0, 2]);
		});

		// (action → a write held by an async gate, Kit.hold)
		test("a held transition defers the handler like it defers the effect arm (#2840)", () -> {
			var armed = signal(false);
			var handled:Array<String> = [];
			root(_ -> effect(() -> {
				if (armed()) throw "boom-held";
				0;
			}, _ -> {}, e -> handled.push(e)));
			flush();
			var release = Kit.hold(() -> armed(true), () -> armed());
			equals(handled, []);
			release();
			flush();
			equals(handled, ["boom-held"]);
		});

		test("async source rejection reaches the handler unwrapped (#2840)", () -> {
			var boom = new MyError("boom-async");
			var armed = signal(false);
			var received:Dynamic = null;
			var load = new Later<String>();
			root(_ -> {
				var data = memo(() -> armed() ? load : Kit.resolved("ok"));
				effect(() -> data(), _ -> {}, e -> received = e);
			});
			flush();
			flush();
			armed(true);
			flush();
			load.reject(boom);
			flush();
			assert(received == boom);
		});

		test("handler rethrow escalates to the nearest error boundary", () -> {
			var log:Array<String> = [];
			var armed = signal(false);
			root(_ -> {
				var boundary = errorBoundary(() -> {
					effect(() -> {
						if (armed()) throw "boom-compute";
						0;
					}, _ -> {}, e -> {
						log.push("handler saw it");
						throw e;
					});
					"content";
				}, (e, _) -> 'fallback:${e()}');
				renderEffect(() -> boundary(), v -> log.push(v));
			});
			flush();
			equals(log, ["content"]);
			log.resize(0);
			armed(true);
			flush();
			equals(log, ["handler saw it", "fallback:boom-compute"]);
		});

		test("effect-phase throw is NOT routed to the bundle handler; boundary catches it", () -> {
			var log:Array<String> = [];
			var armed = signal(false);
			root(_ -> {
				var boundary = errorBoundary(() -> {
					effect(() -> armed(), on -> if (on) throw "boom-effect", e -> log.push('handler: $e'));
					"content";
				}, (e, _) -> 'fallback:${e()}');
				renderEffect(() -> boundary(), v -> log.push(v));
			});
			flush();
			equals(log, ["content"]);
			log.resize(0);
			armed(true);
			flush();
			equals(log, ["fallback:boom-effect"]);
		});

		test("effect-phase throw with no boundary halts the system loudly", () -> {
			var log:Array<String> = [];
			var beat = signal(0), armed = signal(false);
			root(_ -> {
				renderEffect(() -> beat(), v -> log.push('beat=$v'));
				effect(() -> armed(), on -> if (on) throw "boom-effect", _ -> log.push("handler must not fire"));
			});
			flush();
			log.resize(0);
			equals(throws(() -> {
				armed(true);
				flush();
			}), "boom-effect");
			equals(log, []);
		});
	});
}
