package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// createRoot.test.ts
function tests() {
	afterEach(() -> flush());

	test("should dispose of inner computations", () -> {
		var x = signal(10);
		var memoSpy = new Spy();
		root(dispose -> {
			memo(() -> {
				memoSpy.call();
				x() + 10;
			});
			dispose();
		});
		equals(memoSpy.calls, 1);
		flush();
		x(50);
		flush();
		equals(memoSpy.calls, 1);
	});

	test("should return result", () -> {
		var result = root(dispose -> {
			dispose();
			10;
		});
		equals(result, 10);
	});

	test("should create new tracking scope", () -> {
		var x = signal(0);
		var effectSpy = new Spy();
		var stopEffect = root(dispose -> {
			effect(() -> {
				x();
				root(_ -> effect(() -> x(), (v, p) -> effectSpy.call(v, p)));
			}, () -> {});
			dispose;
		});
		flush();
		assert(effectSpy.calledWith(0, null));
		equals(effectSpy.calls, 1);
		stopEffect();
		x(10);
		flush();
		assert(!effectSpy.calledWith(10, 0));
		equals(effectSpy.calls, 1);
	});

	test("should not be reactive", () -> {
		var x = signal(0);
		var rootSpy = new Spy();
		root(_ -> {
			x();
			rootSpy.call();
		});
		equals(rootSpy.calls, 1);
		x(1);
		flush();
		equals(rootSpy.calls, 1);
	});

	test("should hold parent tracking", () -> {
		root(_ -> {
			var parent = getOwner();
			root(_ -> {
				assert(require(getOwner()).parent == parent);
			});
		});
	});

	test("should not throw if dispose called during active disposal process", () -> {
		root(dispose -> {
			onCleanup(() -> dispose());
			dispose();
		});
	});
}
