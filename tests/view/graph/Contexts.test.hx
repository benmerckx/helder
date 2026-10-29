package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// context.test.ts
function tests() {
	afterEach(() -> flush());

	// (adapted: helder's setContext takes the value; Solid's defaults to the context's default)
	test("should create context", () -> {
		var c = context(1);
		equals(c.defaultValue, 1);
		root(_ -> {
			setContext(c, c.defaultValue);
			equals(use(c), 1);
		});
	});

	test("should forward context across roots", () -> {
		var c = context(1);
		root(_ -> {
			setContext(c, 2);
			root(_ -> {
				equals(use(c), 2);
				root(_ -> {
					equals(use(c), 2);
				});
			});
		});
	});

	test("should not expose context on parent when set in child", () -> {
		var c = context(1);
		root(_ -> {
			root(_ -> {
				setContext(c, 4);
			});
			equals(use(c), 1);
		});
	});

	test("should throw error when trying to get context outside owner", () -> {
		var c:helder.view.graph.Context<Int> = context();
		throws(() -> use(c));
	});

	test("should throw error when trying to set context outside owner", () -> {
		var c:helder.view.graph.Context<Int> = context();
		throws(() -> setContext(c, 1));
	});

	test("should throw error when trying to get context without setting it first", () -> {
		var c:helder.view.graph.Context<Int> = context();
		throws(() -> root(_ -> use(c)));
	});

	describe("ContextNotFoundError dev messages", () -> {
		test("null is a value: a null default and a provided null both read back", () -> {
			var optNull:helder.view.graph.Context<Null<String>> = context(null);
			root(_ -> equals(use(optNull), null));
			var noDefault:helder.view.graph.Context<Null<String>> = context();
			root(_ -> {
				setContext(noDefault, null);
				equals(use(noDefault), null);
			});
		});
	});
}
