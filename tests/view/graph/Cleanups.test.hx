package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// onCleanup.test.ts
function tests() {
	afterEach(() -> flush());

	test("should be invoked when computation is disposed", () -> {
		var disposeA = new Spy();
		var disposeB = new Spy();
		var disposeC = new Spy();
		var stopEffect = root(dispose -> {
			effect(() -> {
				onCleanup(disposeA.fn0());
				onCleanup(disposeB.fn0());
				onCleanup(disposeC.fn0());
			}, () -> {});
			dispose;
		});
		flush();
		stopEffect();
		equals(disposeA.calls, 1);
		equals(disposeB.calls, 1);
		equals(disposeC.calls, 1);
	});

	test("should not trigger wrong onCleanup", () -> {
		var disposeSpy = new Spy();
		root(_ -> {
			effect(() -> {
				onCleanup(disposeSpy.fn0());
			}, () -> {});
			var stopEffect = root(dispose -> {
				effect(() -> 0, () -> {});
				dispose;
			});
			stopEffect();
			flush();
			equals(disposeSpy.calls, 0);
		});
	});

	test("should clean up in reverse order", () -> {
		var disposeParent = new Spy();
		var disposeA = new Spy();
		var disposeB = new Spy();
		var calls = 0;
		var stopEffect = root(dispose -> {
			effect(() -> {
				onCleanup(() -> disposeParent.call(++calls));
				effect(() -> {
					onCleanup(() -> disposeA.call(++calls));
				}, () -> {});
				effect(() -> {
					onCleanup(() -> disposeB.call(++calls));
				}, () -> {});
			}, () -> {});
			dispose;
		});
		flush();
		stopEffect();
		assert(disposeB.calledWith(1));
		assert(disposeA.calledWith(2));
		assert(disposeParent.calledWith(3));
	});

	test("cleanup order is unwind: children before owner, later registrations before earlier", () -> {
		var order:Array<String> = [];
		var dispose = root(dispose -> {
			onCleanup(() -> order.push("A"));
			onCleanup(() -> order.push("B"));
			root(_ -> onCleanup(() -> order.push("C")));
			effect(() -> 0, (_, _) -> () -> order.push("D"));
			dispose;
		});
		flush();
		dispose();
		equals(order, ["D", "C", "B", "A"]);
	});

	test("should dispose all roots", () -> {
		var disposals:Array<String> = [];
		var dispose = root(dispose -> {
			root(_ -> {
				onCleanup(() -> disposals.push("SUBTREE 1"));
				effect(() -> {
					onCleanup(() -> disposals.push("+A1"));
				}, () -> {});
				effect(() -> {
					onCleanup(() -> disposals.push("+B1"));
				}, () -> {});
				effect(() -> {
					onCleanup(() -> disposals.push("+C1"));
				}, () -> {});
			});
			root(_ -> {
				onCleanup(() -> disposals.push("SUBTREE 2"));
				effect(() -> {
					onCleanup(() -> disposals.push("+A2"));
				}, () -> {});
				effect(() -> {
					onCleanup(() -> disposals.push("+B2"));
				}, () -> {});
				effect(() -> {
					onCleanup(() -> disposals.push("+C2"));
				}, () -> {});
			});
			onCleanup(() -> disposals.push("ROOT"));
			dispose;
		});
		flush();
		dispose();
		equals(disposals, ["+C2", "+B2", "+A2", "SUBTREE 2", "+C1", "+B1", "+A1", "SUBTREE 1", "ROOT"]);
	});
}
