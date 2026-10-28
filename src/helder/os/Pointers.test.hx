package helder.os;

import helder.os.Event;
import helder.test.Test;

// helder.os.Pointers without a window: the mouse's slot from its events,
// touches' slots (dense, reused, in down order), a frame's motion and
// presses, samples, cancels, and nothing allocated (`bun run helder test
// src/helder/os`, natively and as wasm32-wasi).
// The back ends' own: the touch-web lane (Chromium's touches and pens).
function tests() {
	describe("Pointers", () -> {
		beforeEach(() -> Pointers.reset());
		test("the mouse is slot 0, after its own events", () -> {
			var seen:Array<String> = [];
			var relay = Pointers.relay(e -> seen.push(e.kind == PointerDown ? 'pd ${e.pointer.id} ${e.pointer.buttons}' : e.kind == PointerMove ? 'pm ${e.x},${e.y}' : e.kind == PointerUp ? "pu" : e.kind == MouseDown ? "md" : e.kind == MouseUp ? "mu" : e.kind == MouseMove ? "mm" : "?"));
			var e = mouseEvent(MouseMove, 0, 10, 20);
			relay(e);
			relay(mouseEvent(MouseDown, 1, 10, 20));
			relay(mouseEvent(MouseDown, 3, 12, 20));
			relay(mouseEvent(MouseUp, 1, 12, 20));
			relay(mouseEvent(MouseUp, 3, 12, 20));
			equals(seen, ["mm", "pm 10,20", "md", "pd 0 1", "md", "pm 12,20", "mu", "pm 12,20", "mu", "pu"]);
			var m = Pointers.get(0);
			assert(m.type == Mouse && !m.down && m.phase == Up && m.press == 1);
			// (a tap's compatibility events are not the mouse's)
			seen.resize(0);
			var tap = mouseEvent(MouseDown, 1, 5, 5);
			tap.mods = Mods.TOUCH;
			relay(tap);
			equals(seen, ["md"]);
		});
		test("touches: dense slots in down order, the first primary", () -> {
			var a = Pointers.press(null, 101, Touch, 10, 10, 1, 0), b = Pointers.press(null, 7, Touch, 50, 60, 0.5, 1);
			equals([a.id, b.id, Pointers.count], [1, 2, 2]);
			assert(a.primary && !b.primary && b.pressure == 0.5 && b.startX == 50);
			assert(Pointers.find(7, Touch) == b && Pointers.find(7, Pen) == null);
			var first = a.press;
			Pointers.lift(a, false, 2);
			equals([Pointers.count, Pointers.at(0).id], [1, 2]);
			// (the slot given to the next one, its press counted anew)
			var c = Pointers.press(null, 9, Pen, 0, 0, 1, 3);
			equals([c.id, Pointers.at(1).id], [1, 1]);
			assert(c == a && c.press > first && c.type == Pen && c.owner == None);
		});
		test("a frame: motion added up, presses and releases until the next step", () -> {
			var p = Pointers.press(null, 1, Touch, 0, 0, 1, 0);
			@:privateAccess p.moveTo(3, 4, 1, 1);
			@:privateAccess p.moveTo(5, 9, 1, 2);
			equals([p.dx, p.dy], [5.0, 9.0]);
			assert(Pointers.justDown(p) && !Pointers.justUp(p));
			Pointers.lift(p, false, 3);
			assert(Pointers.justDown(p) && Pointers.justUp(p) && !p.down, "a press and its release within a frame");
			Pointers.step();
			equals([p.dx, p.dy], [0.0, 0.0]);
			assert(!Pointers.justDown(p) && !Pointers.justUp(p));
		});
		test("a cancel ends the press, not tapping", () -> {
			var p = Pointers.press(null, 1, Touch, 0, 0, 1, 0);
			var seen = [];
			Pointers.cancelAll(null, new Event(), e -> seen.push(e.kind == PointerCancel && e.pointer == p));
			equals(seen, [true]);
			assert(Pointers.cancelled(p) && !p.down && Pointers.count == 0);
		});
		test("samples: the batch before an event, the latest SAMPLES", () -> {
			var p = Pointers.press(null, 1, Touch, 0, 0, 1, 0);
			equals(p.samples, 1);
			for (i in 0...10)
				@:privateAccess p.sample(i, i * 2, i);
			@:privateAccess p.moveTo(100, 200, 1, 11);
			equals(p.samples, Pointer.SAMPLES);
			equals([p.sampleX(0), p.sampleX(Pointer.SAMPLES - 1), p.sampleY(Pointer.SAMPLES - 1)], [3.0, 100.0, 200.0]);
			@:privateAccess p.moveTo(101, 200, 1, 12);
			equals([p.samples, Std.int(p.sampleX(0))], [1, 101]);
		});
		test("every slot taken: the next touch ignored", () -> {
			for (i in 1...Pointers.MAX)
				assert(Pointers.press(null, i, Touch, 0, 0, 1, 0) != null);
			assert(Pointers.press(null, 99, Touch, 0, 0, 1, 0) == null);
			equals(Pointers.count, Pointers.MAX - 1);
		});
		test("nothing allocated: presses, moves, events, frames", () -> {
			var e = new Event(), mouse = mouseEvent(MouseMove, 0, 1, 1), n = 0;
			var relay = Pointers.relay(_ -> n++);
			function round(k:Int) {
				var p = Pointers.press(null, k, Touch, 0, 0, 1, k);
				@:privateAccess p.sample(1, 1, k);
				@:privateAccess p.moveTo(2, 3, 1, k);
				Pointers.fill(e, PointerMove, p);
				mouse.x = k & 255;
				relay(mouse);
				Pointers.lift(p, k & 1 == 0, k);
				Pointers.step();
			}
			round(0);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 1...2000)
				round(k);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			assert(n > 2000);
		});
	});
}

private function mouseEvent(kind:EventKind, button:Int, x:Int, y:Int):Event {
	var e = new Event();
	e.kind = kind;
	e.button = button;
	e.x = x;
	e.y = y;
	return e;
}
