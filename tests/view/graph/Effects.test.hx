package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// createEffect.test.ts (sync)
function tests() {
	afterEach(() -> flush());

	test("should run effect", () -> {
		var x = signal(0);
		var compute = new Spy();
		var effectSpy = new Spy();
		root(_ -> effect(() -> {
			compute.call();
			x();
		}, (v, p) -> effectSpy.call(v, p)));
		equals(compute.calls, 1);
		equals(effectSpy.calls, 0);
		flush();
		equals(compute.calls, 1);
		equals(effectSpy.calls, 1);
		assert(effectSpy.calledWith(0, null));
		x(1);
		flush();
		equals(compute.calls, 2);
		equals(effectSpy.calls, 2);
		assert(effectSpy.calledWith(1, 0));
	});

	test("should run effect on change", () -> {
		var effectSpy = new Spy();
		var x = signal(10);
		var y = signal(10);
		var a = memo(() -> x() + y());
		var b = memo(() -> a());
		root(_ -> effect(() -> b(), (v, p) -> effectSpy.call(v, p)));
		equals(effectSpy.calls, 0);
		x(20);
		flush();
		equals(effectSpy.calls, 1);
		y(20);
		flush();
		equals(effectSpy.calls, 2);
		x(20);
		y(20);
		flush();
		equals(effectSpy.calls, 2);
	});

	test("should handle nested effect", () -> {
		var x = signal(0);
		var y = signal(0);
		var outerEffect = new Spy();
		var innerEffect = new Spy();
		var innerPureDispose = new Spy();
		var innerEffectDispose = new Spy();
		var stopEffect = root(dispose -> {
			effect(() -> {
				x();
				effect(() -> {
					y();
					onCleanup(innerPureDispose.fn0());
				}, (_, _) -> {
					innerEffect.call();
					() -> innerEffectDispose.call();
				});
			}, () -> outerEffect.call());
			dispose;
		});
		flush();
		equals(outerEffect.calls, 1);
		equals(innerEffect.calls, 1);
		equals(innerPureDispose.calls, 0);
		equals(innerEffectDispose.calls, 0);

		y(1);
		flush();
		equals(outerEffect.calls, 1);
		equals(innerEffect.calls, 2);
		equals(innerPureDispose.calls, 1);
		equals(innerEffectDispose.calls, 1);

		y(2);
		flush();
		equals(outerEffect.calls, 1);
		equals(innerEffect.calls, 3);
		equals(innerPureDispose.calls, 2);
		equals(innerEffectDispose.calls, 2);

		innerEffect.reset();
		innerPureDispose.reset();
		innerEffectDispose.reset();

		x(1);
		flush();
		equals(outerEffect.calls, 2);
		equals(innerEffect.calls, 1); // a new one
		equals(innerPureDispose.calls, 1);
		equals(innerEffectDispose.calls, 1);

		y(3);
		flush();
		equals(outerEffect.calls, 2);
		equals(innerEffect.calls, 2);
		equals(innerPureDispose.calls, 2);
		equals(innerEffectDispose.calls, 2);

		stopEffect();
		x(10);
		y(10);
		equals(outerEffect.calls, 2);
		equals(innerEffect.calls, 2);
		equals(innerPureDispose.calls, 3);
		equals(innerEffectDispose.calls, 3);
	});

	test("should stop effect", () -> {
		var effectSpy = new Spy();
		var x = signal(10);
		var stopEffect = root(dispose -> {
			effect(() -> x(), (v, p) -> effectSpy.call(v, p));
			dispose;
		});
		stopEffect();
		x(20);
		flush();
		equals(effectSpy.calls, 0);
	});

	test("should run all disposals before each new run", () -> {
		var effectSpy = new Spy();
		var disposeA = new Spy();
		var disposeB = new Spy();
		var disposeC = new Spy();
		function fnA()
			onCleanup(disposeA.fn0());
		function fnB()
			onCleanup(disposeB.fn0());
		var x = signal(0);
		root(_ -> effect(() -> {
			fnA();
			fnB();
			x();
		}, (_, _) -> {
			effectSpy.call();
			disposeC.fn0();
		}));
		flush();
		equals(effectSpy.calls, 1);
		equals(disposeA.calls, 0);
		equals(disposeB.calls, 0);
		equals(disposeC.calls, 0);
		for (i in 1...4) {
			x(i);
			flush();
			equals(effectSpy.calls, i + 1);
			equals(disposeA.calls, i);
			equals(disposeB.calls, i);
			equals(disposeC.calls, i);
		}
	});

	test("should dispose of nested effect", () -> {
		var x = signal(0);
		var innerEffect = new Spy();
		var stopEffect = root(dispose -> {
			effect(() -> {
				effect(() -> x(), (v, p) -> innerEffect.call(v, p));
			}, () -> {});
			dispose;
		});
		stopEffect();
		x(10);
		flush();
		equals(innerEffect.calls, 0);
	});

	test("should conditionally observe", () -> {
		var x = signal(0);
		var y = signal(0);
		var condition = signal(true);
		var a = memo(() -> condition() ? x() : y());
		var effectSpy = new Spy();
		root(_ -> effect(() -> a(), (v, p) -> effectSpy.call(v, p)));
		flush();
		equals(effectSpy.calls, 1);
		y(1);
		flush();
		equals(effectSpy.calls, 1);
		x(1);
		flush();
		equals(effectSpy.calls, 2);
		condition(false);
		flush();
		equals(effectSpy.calls, 2);
		y(2);
		flush();
		equals(effectSpy.calls, 3);
		x(3);
		flush();
		equals(effectSpy.calls, 3);
	});

	test("should dispose of nested conditional effect", () -> {
		var condition = signal(true);
		var disposeA = new Spy();
		var disposeB = new Spy();
		function fnA()
			effect(() -> onCleanup(disposeA.fn0()), () -> {});
		function fnB()
			effect(() -> onCleanup(disposeB.fn0()), () -> {});
		root(_ -> effect(() -> condition() ? fnA() : fnB(), () -> {}));
		flush();
		condition(false);
		flush();
		equals(disposeA.calls, 1);
	});

	test("should handle looped effects", () -> {
		var values:Array<Int> = [];
		var loop = 2;
		var value = signal(0);
		root(_ -> effect(() -> {
			values.push(value());
			for (i in 0...loop)
				effect(() -> {
					values.push(value() + i);
				}, () -> {});
		}, () -> {}));
		flush();
		equals(values, [0, 0, 1]);
		loop = 1;
		values = [];
		value(1);
		flush();
		equals(values, [1, 1]);
		values = [];
		value(2);
		flush();
		equals(values, [2, 2]);
	});

	test("should apply changes in effect in same flush", () -> {
		var x = signal(0);
		var y = signal(0);
		var a = memo(() -> x() + 1);
		var b = memo(() -> a() + 2);
		root(_ -> effect(() -> y(), () -> x(n -> n + 1)));
		flush();
		equals(x(), 1);
		equals(b(), 4);
		equals(a(), 2);
		y(1);
		flush();
		equals(x(), 2);
		equals(b(), 5);
		equals(a(), 3);
		y(2);
		flush();
		equals(x(), 3);
		equals(b(), 6);
		equals(a(), 4);
	});

	test("should run parent effect before child effect", () -> {
		var x = signal(0);
		var condition = memo(() -> x());
		var calls = 0;
		root(_ -> effect(() -> {
			effect(() -> {
				x();
				calls++;
			}, () -> {});
			condition();
		}, () -> {}));
		x(1);
		flush();
		equals(calls, 2);
	});

	test("should run render effect before user effects", () -> {
		var x = signal(0);
		var mark = "";
		root(_ -> {
			effect(() -> x(), () -> mark += "b");
			renderEffect(() -> x(), () -> mark += "a");
		});
		flush();
		equals(mark, "ab");
		x(1);
		flush();
		equals(mark, "abab");
	});

	describe("schedule option", () -> {
		test("runs initial render-effect callback synchronously without schedule (default)", () -> {
			var calls = 0;
			root(_ -> {
				renderEffect(() -> 1, () -> calls++);
				equals(calls, 1);
			});
			flush();
			equals(calls, 1);
		});
	});

	describe("final returned cleanup runs at the effect's own disposal", () -> {
		test("runs once at disposal, after per-rerun cleanups", () -> {
			var x = signal(0);
			var cleanup = new Spy();
			var dispose = root(dispose -> {
				effect(() -> x(), (_, _) -> cleanup.fn0());
				dispose;
			});
			flush();
			equals(cleanup.calls, 0);
			x(1);
			flush();
			equals(cleanup.calls, 1);
			dispose();
			equals(cleanup.calls, 2);
			x(2);
			flush();
			equals(cleanup.calls, 2);
		});

		test("fires in unwind order at the effect's structural position", () -> {
			var order:Array<String> = [];
			var x = signal(0);
			var dispose = root(dispose -> {
				onCleanup(() -> order.push("onCleanup:before"));
				effect(() -> x(), (_, _) -> () -> order.push("effect:A"));
				effect(() -> x(), (_, _) -> () -> order.push("effect:B"));
				onCleanup(() -> order.push("onCleanup:after"));
				dispose;
			});
			flush();
			dispose();
			equals(order, ["effect:B", "effect:A", "onCleanup:after", "onCleanup:before"]);
		});

		test("early individual disposal fires the cleanup once; outer disposal does not re-run it", () -> {
			var x = signal(0);
			var cleanup = new Spy();
			var disposeInner:Null<Void->Void> = null;
			var disposeOuter = root(dispose -> {
				root(d -> {
					disposeInner = d;
					effect(() -> x(), (_, _) -> cleanup.fn0());
				});
				dispose;
			});
			flush();
			disposeInner();
			equals(cleanup.calls, 1);
			disposeOuter();
			equals(cleanup.calls, 1);
		});

		test("render effect final cleanup follows the same rule", () -> {
			var x = signal(0);
			var cleanup = new Spy();
			var dispose = root(dispose -> {
				renderEffect(() -> x(), (_, _) -> cleanup.fn0());
				dispose;
			});
			flush();
			x(1);
			flush();
			equals(cleanup.calls, 1);
			dispose();
			equals(cleanup.calls, 2);
		});
	});
}
