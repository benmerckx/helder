package view.graph;

import helder.test.Test;
import helder.view.graph.Awaitable;
import helder.view.graph.Graph.*;

// Solid 2's async fundamentals (DESIGN.md 2, Holds), each test the F-rule it states.
function tests() {
	describe("first load", () -> {
		test("a render effect waits for it; untracked, it is not ready (F-2, F-9)", () -> {
			var load = new Later<String>();
			var user = memo(() -> load);
			var shown = [];
			root(_ -> renderEffect(() -> user(), v -> shown.push(v)));
			flush();
			equals(shown, []);
			throws(() -> user());
			equals(isPending(() -> user()), false);
			load.resolve("ada");
			flush();
			equals(shown, ["ada"]);
			equals(user(), "ada");
		});

		test("an armed boundary shows its fallback, then the content (F-4)", () -> {
			var load = new Later<String>();
			var user = memo(() -> load);
			var shown = [];
			root(_ -> {
				var b = loadingBoundary(() -> user(), () -> "loading");
				renderEffect(() -> b(), v -> shown.push(v));
			});
			flush();
			equals(shown, ["loading"]);
			load.resolve("ada");
			flush();
			equals(shown, ["loading", "ada"]);
		});

		test("a boundary catches a render effect of its content", () -> {
			var load = new Later<String>();
			var user = memo(() -> load);
			var shown = [], inner = [];
			root(_ -> {
				var b = loadingBoundary(() -> {
					renderEffect(() -> user(), v -> inner.push(v));
					"content";
				}, () -> "loading");
				renderEffect(() -> b(), v -> shown.push(v));
			});
			flush();
			equals(shown, ["loading"]);
			equals(inner, []);
			load.resolve("ada");
			flush();
			equals(inner, ["ada"]);
			equals(shown, ["loading", "content"]);
		});
	});

	describe("a change that needs async", () -> {
		function setup() {
			var loads = new Map<Int, Later<String>>();
			var id = signal(1);
			var user = memo(() -> {
				var l = new Later<String>();
				loads.set(id(), l);
				l;
			});
			var shown = [];
			root(_ -> renderEffect(() -> '${id()}:${user()}', v -> shown.push(v)));
			loads.get(1).resolve("ada");
			flush();
			return {loads: loads, id: id, user: user, shown: shown};
		}

		test("is held: the screen keeps what it showed, then reveals as one frame (F-1, F-2)", () -> {
			var s = setup();
			equals(s.shown, ["1:ada"]);
			s.id(2);
			flush();
			equals(s.shown, ["1:ada"]);
			equals(s.id(), 1);
			equals(s.user(), "ada");
			s.loads.get(2).resolve("bob");
			flush();
			equals(s.shown, ["1:ada", "2:bob"]);
			equals(s.id(), 2);
		});

		test("isPending and latest look ahead of the hold (F-6, F-9)", () -> {
			var s = setup();
			var pending = [], latestId = [];
			root(_ -> {
				renderEffect(() -> isPending(() -> s.user()), v -> pending.push(v));
				renderEffect(() -> latest(() -> s.id()), v -> latestId.push(v));
			});
			s.id(2);
			flush();
			equals(pending, [false, true]);
			equals(latestId, [1, 2]);
			s.loads.get(2).resolve("bob");
			flush();
			equals(pending, [false, true, false]);
			equals(s.shown, ["1:ada", "2:bob"]);
		});

		test("an unrelated write commits beside it (F-2)", () -> {
			var s = setup();
			var x = signal(0), seen = [];
			root(_ -> renderEffect(() -> x(), v -> seen.push(v)));
			s.id(2);
			flush();
			x(1);
			flush();
			equals(seen, [0, 1]);
			equals(s.shown, ["1:ada"]);
		});

		test("a render effect reading a held value is served the committed one, the truth at the commit (F-3)", () -> {
			var s = setup();
			var x = signal(0), seen = [];
			root(_ -> renderEffect(() -> '${x()}/${s.user()}', v -> seen.push(v)));
			s.id(2);
			flush();
			x(1);
			flush();
			equals(seen, ["0/ada", "1/ada"]);
			s.loads.get(2).resolve("bob");
			flush();
			equals(seen, ["0/ada", "1/ada", "1/bob"]);
		});

		test("a superseded run is cancelled, its answer dropped", () -> {
			var s = setup();
			s.id(2);
			flush();
			s.id(3);
			flush();
			assert(s.loads.get(2).cancelled);
			s.loads.get(2).resolve("bob");
			flush();
			equals(s.shown, ["1:ada"]);
			s.loads.get(3).resolve("cy");
			flush();
			equals(s.shown, ["1:ada", "3:cy"]);
		});

		test("a disarmed boundary keeps its content and holds (F-5)", () -> {
			var loads = new Map<Int, Later<String>>();
			var id = signal(1);
			var user = memo(() -> {
				var l = new Later<String>();
				loads.set(id(), l);
				l;
			});
			var shown = [];
			root(_ -> {
				var b = loadingBoundary(() -> user(), () -> "loading");
				renderEffect(() -> b(), v -> shown.push(v));
			});
			flush();
			loads.get(1).resolve("ada");
			flush();
			equals(shown, ["loading", "ada"]);
			id(2);
			flush();
			equals(shown, ["loading", "ada"]);
			loads.get(2).resolve("bob");
			flush();
			equals(shown, ["loading", "ada", "bob"]);
		});

		test("a user effect holds nothing: it runs when the value lands", () -> {
			var s = setup();
			var x = signal(0), seen = [];
			root(_ -> effect(() -> s.user(), v -> seen.push(v)));
			flush();
			equals(seen, ["ada"]);
			s.id(2);
			flush();
			s.loads.get(2).resolve("bob");
			flush();
			equals(seen, ["ada", "bob"]);
		});
	});

	describe("errors", () -> {
		test("an async error sends the boundary to its fallback; pending is not an error (F-12)", () -> {
			var load = new Later<String>();
			var user = memo(() -> load);
			var shown = [];
			root(_ -> {
				var b = errorBoundary(() -> loadingBoundary(() -> user(), () -> "loading")(), (e, reset) -> 'failed: ${e()}');
				renderEffect(() -> b(), v -> shown.push(v));
			});
			flush();
			equals(shown, ["loading"]);
			load.reject("offline");
			flush();
			equals(shown, ["loading", "failed: offline"]);
		});
	});
}
