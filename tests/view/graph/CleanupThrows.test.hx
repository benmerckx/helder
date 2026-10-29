package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;
import helder.view.graph.Owner;

// cleanup-throw-continues.test.ts
private function boom(message = "boom"):Void
	throw message;

function tests() {
	afterEach(() -> flush());

	describe("root dispose", () -> {
		test("runs every cleanup in the tree and rethrows the first error after", () -> {
			var log:Array<String> = [];
			var inner:Null<Owner> = null;
			var sibling:Null<Owner> = null;
			var dispose = root(dispose -> {
				onCleanup(() -> log.push("root"));
				root(_ -> {
					inner = getOwner();
					onCleanup(() -> log.push("inner first"));
					renderEffect(() -> 1, (_, _) -> () -> log.push("effect cleanup"));
					onCleanup(() -> boom("first error"));
					onCleanup(() -> log.push("inner last"));
				});
				root(_ -> {
					sibling = getOwner();
					onCleanup(() -> boom("second error"));
					onCleanup(() -> log.push("sibling"));
				});
				dispose;
			});
			flush();
			// children go newest first: the sibling's error is the first thrown
			equals(throws(dispose), "second error");
			equals(log, ["sibling", "effect cleanup", "inner last", "inner first", "root"]);
			assert(require(inner).isDisposed);
			assert(require(sibling).isDisposed);
		});

		test("rethrows once: a later teardown does not see the error again", () -> {
			var first = root(dispose -> {
				onCleanup(() -> boom());
				dispose;
			});
			var second = root(dispose -> {
				onCleanup(() -> {});
				dispose;
			});
			equals(throws(first), "boom");
			second();
			flush();
		});

		test("a throwing effect cleanup does not stop the owner's own cleanups", () -> {
			var log:Array<String> = [];
			var dispose = root(dispose -> {
				onCleanup(() -> log.push("owner"));
				effect(() -> 1, (_, _) -> () -> boom());
				dispose;
			});
			flush();
			equals(throws(dispose), "boom");
			equals(log, ["owner"]);
		});
	});

	describe("inside a flush", () -> {
		test("a branch switch runs every cleanup of the old frame, commits, then the flush throws", () -> {
			var log:Array<String> = [];
			var seen:Array<String> = [];
			var show = signal(true);
			var dispose = root(dispose -> {
				var view = memo(() -> {
					if (!show()) "off" else {
						onCleanup(() -> log.push("first"));
						renderEffect(() -> 1, (_, _) -> () -> log.push("effect cleanup"));
						onCleanup(() -> boom());
						"on";
					}
				});
				renderEffect(() -> view(), v -> seen.push(v));
				dispose;
			});
			flush();
			show(false);
			equals(throws(() -> flush()), "boom");
			equals(log, ["effect cleanup", "first"]);
			// the flush completed before rethrowing: the new branch is on screen
			equals(seen, ["on", "off"]);
			// no latch, nothing left half-applied
			flush();
			show(true);
			flush();
			equals(seen, ["on", "off", "on"]);
			equals(throws(dispose), "boom");
			equals(log, ["effect cleanup", "first", "effect cleanup", "first"]);
		});

		test("a root disposed by an effect: the effect continues, the flush rethrows at its end", () -> {
			var log:Array<String> = [];
			var go = signal(false);
			var disposeOther = root(dispose -> {
				onCleanup(() -> log.push("other first"));
				onCleanup(() -> boom());
				dispose;
			});
			var dispose = root(dispose -> {
				effect(() -> go(), v -> {
					if (!v) return;
					disposeOther();
					log.push("after dispose");
				});
				dispose;
			});
			flush();
			go(true);
			equals(throws(() -> flush()), "boom");
			equals(log, ["other first", "after dispose"]);
			dispose();
		});
	});

	describe("unobserved hooks", () -> {
		// (adapted: Solid's source is a lazy memo; helder's memos have no lazy option)
		test("a throwing hook does not stop the teardown around it", () -> {
			var log:Array<String> = [];
			var source:Null<helder.view.graph.Memo<Int>> = null;
			var disposeSource = root(dispose -> {
				source = memo(() -> 1, {
					unobserved: () -> {
						log.push("hook");
						boom("hook");
					}
				});
				dispose;
			});
			var dispose = root(dispose -> {
				var s = require(source);
				renderEffect(() -> s(), () -> {});
				onCleanup(() -> log.push("root"));
				dispose;
			});
			flush();
			equals(throws(dispose), "hook");
			equals(log, ["hook", "root"]);
			disposeSource();
		});
	});
}
