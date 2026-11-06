package helder.os;

import helder.test.Test;

// Glide, a drag's glide (helder.ui's TouchScroll's, gltf-viewer's flick):
// the drag's speed from its moves, smoothed; let go moving a glide at that
// speed slowing 5% a frame until under half a unit a frame, the same
// whatever the frame rate; none once rested or cancelled, a new drag
// stopping it (natively and as wasm32-wasi).
function tests() {
	describe("Glide", () -> {
		// (the glide's steps from now on, dt ms apart until it stops)
		function all(g:Glide, from:Float, dt:Float):Array<Float> {
			var out = [], now = from;
			while (g.gliding && out.length < 10000) {
				if (g.step(now)) out.push(g.dy);
				now += dt;
			}
			return out;
		}
		test("let go moving: at the drag's speed, 5% less a frame, until under half a unit", () -> {
			var g = new Glide();
			g.start(0);
			g.move(0, 20, 16);
			g.move(0, 30, 32);
			assert(g.release(40) && g.gliding, "let go 8 ms after its last move: it glides");
			// (its speed: 0.8 of the last move's and 0.2 of before, units a ms; 16 ms a frame, 5% less each)
			var v = 0.8 * (30 / 16) + 0.2 * (0.8 * (20 / 16));
			var steps = all(g, 1000, Glide.FRAME);
			assert(steps.length > 10, '${steps.length} steps');
			approx(steps[0], v * 16 * 0.95, 1e-6, "the first frame's");
			approx(steps[1], steps[0] * 0.95, 1e-6, "5% less a frame");
			var after = v * 16 * Math.pow(0.95, steps.length + 1);
			assert(after < 0.5 && steps[steps.length - 1] >= 0.5, 'until under half a unit: ${steps.length} frames, the last ${steps[steps.length - 1]}, then $after');
		});
		test("frame-rate independent: at 30 frames a second, the same glide in half the steps", () -> {
			function glide(dt:Float):Array<Float> {
				var g = new Glide();
				g.start(0);
				g.move(0, 20, 16);
				g.move(0, 30, 32);
				g.release(40);
				return all(g, 5000, dt);
			}
			var fast = glide(Glide.FRAME), slow = glide(2 * Glide.FRAME);
			var a = 0.0, b = 0.0;
			for (s in fast)
				a += s;
			for (s in slow)
				b += s;
			approx(a, b, 1e-6);
			assert(slow.length <= fast.length / 2 + 2, '${slow.length} vs ${fast.length}');
		});
		test("rested before the lift, or stopped: no glide; a new drag stops one", () -> {
			var g = new Glide();
			g.start(0);
			g.move(0, 40, 16);
			assert(!g.release(300) && !g.gliding, "rested: no glide");
			g.start(400);
			g.move(0, 40, 416);
			assert(g.release(420) && g.gliding);
			g.start(500);
			assert(!g.gliding && !g.step(600), "a new drag stops it");
			g.move(0, 40, 516);
			g.release(520);
			g.stop();
			assert(!g.gliding && !g.step(700), "stopped");
		});
		test("sideways: a sideways glide", () -> {
			var g = new Glide();
			g.start(0);
			g.move(40, 0, 10);
			g.move(60, 0, 20);
			g.release(25);
			assert(g.step(0) && g.dx > 0 && g.dy == 0, '${g.dx},${g.dy}');
		});
	});
}
