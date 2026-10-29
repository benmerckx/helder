package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// untrack.test.ts
function tests() {
	afterEach(() -> flush());

	test("should not create dependency", () -> {
		var effectSpy = new Spy();
		var memoSpy = new Spy();
		var x = signal(10);
		var a = memo(() -> x() + 10);
		var b = memo(() -> {
			memoSpy.call();
			untrack(() -> a()) + 10;
		});
		root(_ -> effect(() -> {
			effectSpy.call();
			equals(untrack(() -> x()), 10);
			equals(untrack(() -> a()), 20);
			equals(untrack(() -> b()), 30);
		}, () -> {}));
		flush();
		equals(effectSpy.calls, 1);
		equals(memoSpy.calls, 1);
		x(20);
		flush();
		equals(effectSpy.calls, 1);
		equals(memoSpy.calls, 1);
	});

	test("should not affect deep dependency being created", () -> {
		var effectSpy = new Spy();
		var memoSpy = new Spy();
		var x = signal(10);
		var y = signal(10);
		var z = signal(10);
		var a = memo(() -> {
			memoSpy.call();
			x() + untrack(() -> y()) + untrack(() -> z()) + 10;
		});
		root(_ -> effect(() -> {
			effectSpy.call();
			equals(untrack(() -> x()), 10);
			equals(untrack(() -> a()), 40);
		}, () -> {}));
		flush();
		equals(effectSpy.calls, 1);
		equals(a(), 40);
		equals(memoSpy.calls, 1);
		x(20);
		flush();
		equals(effectSpy.calls, 1);
		equals(a(), 50);
		equals(memoSpy.calls, 2);
		y(20);
		flush();
		equals(effectSpy.calls, 1);
		equals(a(), 60);
		equals(memoSpy.calls, 3);
		z(20);
		flush();
		equals(effectSpy.calls, 1);
		equals(a(), 70);
		equals(memoSpy.calls, 4);
	});

	test("should track owner across peeks", () -> {
		var x = signal(0);
		var childCompute = new Spy();
		var childDispose = new Spy();
		function createChild() {
			var a = memo(() -> x() * 2);
			root(_ -> effect(() -> {
				childCompute.call(a());
				onCleanup(childDispose.fn0());
			}, () -> {}));
		}
		var dispose = root(dispose -> {
			untrack(() -> createChild());
			dispose;
		});
		flush();
		x(1);
		flush();
		assert(childCompute.calledWith(2));
		equals(childDispose.calls, 1);
		dispose();
		equals(childDispose.calls, 2);
		x(2);
		flush();
		assert(!childCompute.calledWith(4));
		equals(childDispose.calls, 2);
	});
}
