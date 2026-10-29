package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// createMemo.test.ts (sync)
function tests() {
	afterEach(() -> flush());

	test("should store and return value on read", () -> {
		var x = signal(1);
		var y = signal(1);
		var a = memo(() -> x() + y());
		equals(a(), 2);
		flush();
		equals(a(), 2);
	});

	test("should update when dependency is updated", () -> {
		var x = signal(1);
		var y = signal(1);
		var a = memo(() -> x() + y());
		x(2);
		flush();
		equals(a(), 3);
		y(2);
		flush();
		equals(a(), 4);
	});

	test("should update when deep dependency is updated", () -> {
		var x = signal(1);
		var y = signal(1);
		var a = memo(() -> x() + y());
		var b = memo(() -> a());
		x(2);
		flush();
		equals(b(), 3);
	});

	test("should update when deep computed dependency is updated", () -> {
		var x = signal(10);
		var y = signal(10);
		var a = memo(() -> x() + y());
		var b = memo(() -> a());
		var c = memo(() -> b());
		x(20);
		flush();
		equals(c(), 30);
	});

	test("should only re-compute when needed", () -> {
		var computed = new Spy();
		var x = signal(10);
		var y = signal(10);
		var a = memo(() -> computed.ret(x() + y()));
		equals(computed.calls, 1);
		assert(computed.calledWith(20));
		a();
		equals(computed.calls, 1);
		x(20);
		equals(computed.calls, 1);
		flush();
		equals(computed.calls, 1);
		a();
		equals(computed.calls, 2);
		y(20);
		flush();
		equals(computed.calls, 2);
		a();
		equals(computed.calls, 3);
	});

	test("should keep observed ownerless memos subscribed", () -> {
		var memoA = new Spy();
		var memoB = new Spy();
		var x = signal(10);
		var y = signal(10);
		var value:Null<Int> = null;
		root(_ -> {
			var a = memo(() -> memoA.ret(x()));
			var b = memo(() -> memoB.ret(y()));
			var c = memo(() -> a() + b());
			renderEffect(() -> value = c(), () -> {});
		});
		flush();
		equals(value, 20);
		equals(memoA.calls, 1);
		equals(memoB.calls, 1);
		x(20);
		flush();
		equals(value, 30);
		equals(memoA.calls, 2);
		equals(memoB.calls, 1);
		y(20);
		flush();
		equals(value, 40);
		equals(memoA.calls, 2);
		equals(memoB.calls, 2);
	});

	test("should discover new dependencies", () -> {
		var x = signal(1);
		var y = signal(0);
		var c = memo(() -> x() != 0 ? x() : y());
		equals(c(), 1);
		x(0);
		flush();
		equals(c(), 0);
		y(10);
		flush();
		equals(c(), 10);
	});

	test("should accept equals option", () -> {
		var x = signal(0);
		// skip even numbers
		var a = memo(() -> x(), {equals: (prev, next) -> prev + 1 == next});
		var effectA = new Spy();
		root(_ -> effect(() -> a(), (v, p) -> effectA.call(v, p)));
		flush();
		equals(a(), 0);
		equals(effectA.calls, 1);
		x(2);
		flush();
		equals(a(), 2);
		equals(effectA.calls, 2);
		// no change
		x(3);
		flush();
		equals(a(), 2);
		equals(effectA.calls, 2);
	});

	test("should ignore equals before memo initialization", () -> {
		var x = signal(1);
		var a = memo(() -> x(), {equals: (_, _) -> true});
		equals(a(), 1);
	});

	// (adapted: no error boundary; the memo's error is thrown where it is read)
	test("should route init errors through the boundary without a memo fallback", () -> {
		root(_ -> {
			var a = memo(() -> {
				if (true) throw "init";
				"";
			});
			throws(() -> a());
		});
	});

	// writable derived signals: the sync tests of describe("async compute")
	describe("writable derived", () -> {
		test("a source change in the write's flush re-runs the memo; a prev-ignoring memo discards the write", () -> {
			var r = root(_ -> {
				var o = signal(0);
				var d = signal(() -> o());
				{original: o, derived: d};
			});
			equals(r.derived(), 0);
			r.original(1);
			r.derived(2);
			flush();
			equals(r.original(), 1);
			equals(r.derived(), 1);
			r.original(3);
			flush();
			equals(r.derived(), 3);
		});

		test("a source change through an intermediate memo re-runs the written memo in the same flush", () -> {
			var observed:Null<Int> = null;
			var r = root(_ -> {
				var a = signal(0);
				var b = memo(() -> a() * 10);
				var c = signal(() -> b());
				renderEffect(() -> c(), v -> observed = v);
				{a: a, c: c};
			});
			flush();
			equals(observed, 0);
			r.a(1);
			r.c(99);
			flush();
			equals(observed, 10);
			r.c(99);
			flush();
			equals(observed, 99);
			r.a(2);
			flush();
			equals(observed, 20);
		});

		test("write then source change in one flush: the memo re-runs with the write as prev", () -> {
			var prevs:Array<Null<Int>> = [];
			var r = root(_ -> {
				var original = signal(0);
				var d = signal((prev:Null<Int>) -> {
					prevs.push(prev);
					original();
				});
				{original: original, derived: d};
			});
			equals(r.derived(), 0);
			r.derived(2);
			r.original(1);
			flush();
			equals(r.derived(), 1);
			equals(prevs[prevs.length - 1], 2);
		});

		test("latest manual write wins on a memo within a tick", () -> {
			var r = root(_ -> {
				var original = signal(0);
				var d = signal(() -> original());
				{original: original, derived: d};
			});
			r.derived(2);
			r.derived(3);
			flush();
			equals(r.derived(), 3);
		});

		test("derived signal resumes tracking after repeated same manual writes", () -> {
			var observed:Null<Int> = null;
			var r = root(_ -> {
				var original = signal(0);
				var derived = signal(() -> original());
				renderEffect(() -> derived(), v -> observed = v);
				{original: original, derived: derived};
			});
			flush();
			equals(observed, 0);
			r.derived(42);
			flush();
			equals(observed, 42);
			r.derived(42);
			flush();
			equals(observed, 42);
			r.original(1);
			flush();
			equals(observed, 1);
		});

		test("a same-value manual write does not hold against a same-flush source change", () -> {
			var r = root(_ -> {
				var original = signal(0);
				var d = signal(() -> original());
				{original: original, derived: d};
			});
			r.original(1);
			r.derived(0);
			flush();
			equals(r.derived(), 1);
		});

		test("subscribers see the re-derived value when upstream changed in the write's flush", () -> {
			var observed:Null<Int> = null;
			var r = root(_ -> {
				var original = signal(0);
				var derived = signal(() -> original());
				renderEffect(() -> derived(), v -> observed = v);
				{original: original, derived: derived};
			});
			flush();
			equals(observed, 0);
			r.original(1);
			r.derived(2);
			flush();
			equals(observed, 1);
			r.derived(2);
			flush();
			equals(observed, 2);
		});
	});
}
