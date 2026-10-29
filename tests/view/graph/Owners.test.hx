package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// getOwner.test.ts
function tests() {
	afterEach(() -> flush());

	test("should return current owner", () -> {
		root(_ -> {
			var owner = getOwner();
			assert(owner != null);
			effect(() -> {
				assert(getOwner() != null);
				assert(getOwner() != owner);
			}, () -> {});
		});
	});

	test("should return parent scope from inside untrack", () -> {
		root(_ -> {
			untrack(() -> assert(getOwner() != null));
		});
	});
}
