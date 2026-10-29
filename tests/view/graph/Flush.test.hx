package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// flush.test.ts
function tests() {
	afterEach(() -> flush());

	test("should batch updates", () -> {
		var x = signal(10);
		var effectSpy = new Spy();
		root(_ -> effect(() -> x(), (v, p) -> effectSpy.call(v, p)));
		flush();
		x(20);
		x(30);
		x(40);
		equals(effectSpy.calls, 1);
		flush();
		equals(effectSpy.calls, 2);
	});

	test("should wait for queue to flush", () -> {
		var x = signal(10);
		var effectSpy = new Spy();
		root(_ -> effect(() -> x(), (v, p) -> effectSpy.call(v, p)));
		flush();
		equals(effectSpy.calls, 1);
		x(20);
		flush();
		equals(effectSpy.calls, 2);
		x(30);
		flush();
		equals(effectSpy.calls, 3);
	});

	test("should not fail if called while flushing", () -> {
		var a = signal(10);
		var effectSpy = new Spy();
		root(_ -> effect(() -> a(), (v, p) -> {
			effectSpy.call(v, p);
			flush();
		}));
		flush();
		equals(effectSpy.calls, 1);
		a(20);
		flush();
		equals(effectSpy.calls, 2);
	});

	test("should run callback and flush before returning", () -> {
		var x = signal(10);
		var effectSpy = new Spy();
		root(_ -> effect(() -> x(), (v, p) -> effectSpy.call(v, p)));
		flush();
		var result = flush(() -> {
			x(20);
			equals(effectSpy.calls, 1);
			"done";
		});
		equals(result, "done");
		equals(effectSpy.calls, 2);
	});

	test("nested flush(fn) drains at each level", () -> {
		var x = signal(10);
		var y = signal(10);
		var effectSpy = new Spy();
		root(_ -> effect(() -> [x(), y()], (v, p) -> effectSpy.call(v, p)));
		flush();
		flush(() -> {
			x(20);
			equals(effectSpy.calls, 1);
			var inner = flush(() -> {
				y(30);
				equals(effectSpy.calls, 1);
				1;
			});
			equals(inner, 1);
			// the inner flush drained: the effect saw [20, 30]
			equals(effectSpy.calls, 2);
		});
		// the outer flush finds nothing pending
		equals(effectSpy.calls, 2);
	});
}
