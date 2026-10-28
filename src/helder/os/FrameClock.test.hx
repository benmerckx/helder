package helder.os;

import helder.test.Test;

// FrameClock, the frame's time App.run keeps: a display's vsyncs at 60 and
// 120 Hz, a missed frame, a pause, a clock going back, the display's time
// in Timer.stamp's, nothing allocated a frame (natively and as wasm32-wasi).
// The vsyncs of a phone's display: CI's emulator and simulator jobs
// (tests/pack/Screen.hx).
function tests() {
	describe("FrameClock", () -> {
		test("the first frame's delta is a period; then the vsyncs' deltas", () -> {
			var c = new FrameClock();
			c.tick(10, true);
			equals([c.count, c.time, c.delta], [1.0, 10.0, FrameClock.PERIOD]);
			assert(c.vsync);
			c.tick(10 + 1 / 60, true);
			near(c.delta, 1 / 60, 1e-9);
			near(c.period, 1 / 60, 1e-9);
		});
		test("a 120 Hz display's period, learnt from its frames", () -> {
			var c = new FrameClock(), t = 5.0;
			for (_ in 0...60) {
				c.tick(t, true);
				t += 1 / 120;
			}
			near(c.period, 1 / 120, 1e-4);
			near(c.delta, 1 / 120, 1e-9);
		});
		test("a missed frame: its delta two periods, the period kept", () -> {
			var c = new FrameClock(), t = 0.0;
			for (_ in 0...30) {
				c.tick(t, true);
				t += 1 / 60;
			}
			t += 1 / 60;
			c.tick(t, true);
			near(c.delta, 2 / 60, 1e-9);
			near(c.period, 1 / 60, 1e-4);
		});
		test("after a pause the delta is a period, not the time away", () -> {
			var c = new FrameClock();
			c.tick(1, true);
			c.tick(1 + 1 / 60, true);
			c.pause();
			c.tick(31, true);
			near(c.delta, 1 / 60, 1e-9);
			equals(c.time, 31.0);
			c.tick(31 + 1 / 60, true);
			near(c.delta, 1 / 60, 1e-9);
		});
		test("a clock that goes back: no time passed", () -> {
			var c = new FrameClock();
			c.tick(2, false);
			c.tick(1.5, false);
			equals(c.delta, 0.0);
			assert(!c.vsync);
			near(c.period, FrameClock.PERIOD, 1e-9);
		});
		test("the display's time in Timer.stamp's", () -> {
			// (a vsync 4 ms ago in the display's clock, at 1000 s here)
			near(FrameClock.toStamp(99.996, 100, 1000), 999.996, 1e-9);
		});
		test("nothing allocated a frame", () -> {
			var c = new FrameClock(), t = 0.0;
			c.tick(t, true);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 0...5000) {
				t += k % 50 == 0 ? 2 / 60 : 1 / 60;
				c.tick(FrameClock.toStamp(t, t + 0.001, t + 7), true);
				if (k % 1000 == 999) c.pause();
			}
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			equals(c.count, 5001);
		});
	});
}

private function near(a:Float, b:Float, eps:Float)
	assert(Math.abs(a - b) <= eps, '$a is not $b (within $eps)');
