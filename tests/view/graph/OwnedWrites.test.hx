package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// owned-scope-write-guard.test.ts (the signal setter)
private function make():Void->Void {
	var s = signal(0);
	return () -> s(1);
}

function tests() {
	afterEach(() -> flush());

	describe("owned-scope write guard: signal", () -> {
		test("allows a write with no owner", () -> {
			var write = make();
			write();
		});

		test("throws in a createRoot body", () -> {
			var write = make();
			throws(() -> root(_ -> write()));
		});

		test("throws under a root re-entered with runWithOwner", () -> {
			var write = make();
			var owner = root(_ -> getOwner());
			throws(() -> runWithOwner(owner, write));
		});

		test("throws in a root created inside a memo body", () -> {
			var write = make();
			var m = memo(() -> {
				root(_ -> write());
				1;
			});
			throws(() -> m());
		});

		test("throws in a memo body", () -> {
			var write = make();
			var m = memo(() -> {
				write();
				1;
			});
			throws(() -> m());
		});

		test("allows a write from an effect's effect phase", () -> {
			var write = make();
			var tick = signal(0);
			root(_ -> {
				effect(() -> tick(), () -> write());
			});
			flush();
			tick(1);
			flush();
		});
	});
}
