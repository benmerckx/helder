package view.graph;

import helder.test.Test;
import helder.view.graph.Graph.*;

// DESIGN.md 2, Allocation: a steady write and its flush, through a memo to
// a render effect and an effect, allocate nothing (hxmc.GcStats, this
// thread's). The values are objects made beforehand: a type parameter's
// Int or Float is boxed where it is stored (hxmc's generics), 16 bytes a
// value, which is the value's, not the graph's.
function tests() {
	afterEach(() -> flush());

	final cells = [for (k in 0...8) new Cell(k)];

	test("a write, a flush, a memo, a render effect and an effect: nothing allocated", () -> {
		var at = signal(cells[0]);
		var next = memo(() -> cells[(at().k + 1) % cells.length]);
		var shown:Null<Cell> = null, applied = 0;
		var dispose = root(d -> {
			renderEffect(() -> next(), v -> shown = v);
			effect(() -> at() == next() ? null : at(), v -> applied++);
			d;
		});
		flush();
		// (warm: the queues grown to their size)
		for (k in 1...10) {
			at(cells[k % cells.length]);
			flush();
		}
		var before = hxmc.GcStats.threadBytesAllocated();
		for (k in 10...2010) {
			at(cells[k % cells.length]);
			flush();
		}
		equals(hxmc.GcStats.threadBytesAllocated() - before, 0.0);
		equals(shown, cells[2010 % cells.length]);
		equals(applied, 2010);
		dispose();
	});

	test("an update, and a flush with nothing to do: nothing allocated", () -> {
		var at = signal(cells[0]);
		var shown:Null<Cell> = null;
		var dispose = root(d -> {
			renderEffect(() -> at(), v -> shown = v);
			d;
		});
		flush();
		function step(c:Cell)
			return cells[(c.k + 1) % cells.length];
		for (k in 0...10) {
			at(step);
			flush();
		}
		var before = hxmc.GcStats.threadBytesAllocated();
		for (k in 0...2000) {
			at(step);
			flush();
			flush();
		}
		equals(hxmc.GcStats.threadBytesAllocated() - before, 0.0);
		equals(shown, cells[2010 % cells.length]);
		dispose();
	});
}

private class Cell {
	public final k:Int;

	public function new(k)
		this.k = k;
}
