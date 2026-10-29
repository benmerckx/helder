package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

function tests() {
	test("writes wait for the flush", () -> {
		var count = signal(1);
		count(2);
		equals(count(), 1);
		flush();
		equals(count(), 2);
		count(c -> c + 1);
		count(c -> c + 1);
		flush();
		equals(count(), 4);
	});
	test("memo and effect", () -> {
		var count = signal(1);
		var double = memo(() -> count() * 2);
		var seen = [];
		root(_ -> effect(() -> double(), (v, p) -> seen.push('$v/$p')));
		equals(seen, []);
		flush();
		equals(seen, ["2/null"]);
		count(5);
		flush();
		equals(seen, ["2/null", "10/2"]);
	});
	test("derived signal", () -> {
		var x = signal(1);
		var y = signal(() -> x() + 1);
		equals(y(), 2);
		y(1);
		flush();
		equals(y(), 1);
		x(2);
		flush();
		equals(y(), 3);
	});
	test("a write in a root's body", () -> {
		var x = signal(1);
		throws(() -> root(_ -> x(2)));
	});
}
