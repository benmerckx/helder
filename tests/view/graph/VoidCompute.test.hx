package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

function tests() {
	test("a compute returning nothing", () -> {
		var x = signal(1), runs = 0;
		root(_ -> {
			effect(() -> {
				x();
				runs++;
			}, () -> {});
			effect(() -> onCleanup(() -> {}), () -> {});
		});
		flush();
		x(2);
		flush();
		equals(runs, 2);
	});
}
