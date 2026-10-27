import helder.os.Event;
import helder.os.TouchDrag;

// helder.os.TouchDrag, the touch gesture AndroidWindow and UIKitWindow share
// (`npm test -- touch`, run in CI's android and ios jobs; the simulator's own
// lane flings by SimTap): a tap, the slop, a drag's scrolls at where it
// started, its release, a fling's glide (as imports.mjs's: its speed, 5% less
// a frame, frame-rate independent), a finger that rested (no glide), a
// cancel, a new touch stopping a glide, a loop's wait while gliding.
class TouchDragTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TouchDragTest: FAIL: $what' + (detail == null ? "" : ' ($detail)'));
		}
	}

	static function near(a:Float, b:Float)
		return Math.abs(a - b) < 1e-6;

	// the glide's scrolls from now on, frame by frame (dt ms apart) until it stops
	static function glideAll(d:TouchDrag, from:Float, dt:Float):Array<Float> {
		var out = [], now = from;
		while (d.gliding && out.length < 10000) {
			if (d.glide(now)) out.push(d.dy);
			now += dt;
		}
		return out;
	}

	static function main() {
		var d = new TouchDrag(), e = new Event();
		// a tap: no scroll within the slop (8 points, 2 pixels a point), a click where it came down
		d.press(100, 200, 0, 2);
		check("within the slop: no scroll", !d.move(110, 205, 10) && !d.dragging);
		check("a tap", d.lift(20, false) == TouchDrag.TAP && !d.gliding);
		d.click(e, MouseDown);
		check("the tap where it came down", e.kind == MouseDown && e.x == 100 && e.y == 200 && e.button == 1);
		d.press(100, 200, 0, 2);
		check("a tap cancelled: nothing", d.lift(20, true) == TouchDrag.NONE);
		check("a lift without a press: nothing", d.lift(30, false) == TouchDrag.NONE);

		// a drag: past the slop, its scrolls by the finger's motion (the content follows), at where it started
		d.press(100, 200, 0, 2);
		check("past the slop: a scroll", d.move(100, 180, 16) && d.dragging);
		check("by the whole motion since the press", near(d.dx, 0) && near(d.dy, 20), '${d.dx},${d.dy}');
		check("more", d.move(100, 150, 32) && near(d.dy, 30));
		d.scroll(e, Mods.TOUCH);
		check("at where it started, Mods.TOUCH", e.kind == Scroll && e.x == 100 && e.y == 200 && e.mods == Mods.TOUCH && near(e.deltaY, 30));
		// (let go moving: the release, then the glide)
		check("let go: the drag's end", d.lift(40, false) == TouchDrag.END && !d.dragging && !d.down);
		d.scroll(e, 0);
		check("a scroll of nothing without Mods.TOUCH", e.kind == Scroll && e.mods == 0 && e.deltaX == 0 && e.deltaY == 0 && e.y == 200);
		check("gliding", d.gliding);
		// (its speed: 0.8 of the last move's and 0.2 of before, pixels a ms; 16 ms a frame, 5% less each)
		var v = 0.8 * (30 / 16) + 0.2 * (0.8 * (20 / 16));
		var steps = glideAll(d, 1000, TouchDrag.FRAME);
		check("the first frame's glide", steps.length > 10 && near(steps[0], v * 16 * 0.95), '${steps[0]} vs ${v * 16 * 0.95}');
		check("5% less a frame", near(steps[1], steps[0] * 0.95));
		var last = v * 16 * Math.pow(0.95, steps.length + 1);
		check("until under half a pixel a frame", last < 0.5 && steps[steps.length - 1] >= 0.5, '${steps.length} frames, the last ${steps[steps.length - 1]}, then $last');
		var total = 0.0;
		for (s in steps)
			total += s;
		// (at 30 frames a second: the same glide, two frames a scroll)
		d.press(100, 200, 0, 2);
		d.move(100, 180, 16);
		d.move(100, 150, 32);
		d.lift(40, false);
		var slow = glideAll(d, 5000, 2 * TouchDrag.FRAME), total2 = 0.0;
		for (s in slow)
			total2 += s;
		check("frame-rate independent", Math.abs(total - total2) < 1e-6 && slow.length <= steps.length / 2 + 2, '$total vs $total2, ${slow.length} scrolls');
		check("a glide's wait: a frame", near(d.wait(0.1), 0.1) && near(d.wait(-1), -1));
		d.press(100, 200, 0, 2);
		d.move(100, 150, 16);
		d.lift(20, false);
		check("while gliding, the loop waits a frame at most", near(d.wait(0.1), TouchDrag.FRAME / 1000) && near(d.wait(-1), TouchDrag.FRAME / 1000)
			&& near(d.wait(0.001), 0.001));
		// (a new touch stops it)
		d.press(50, 60, 100, 2);
		check("a new touch stops the glide", !d.gliding && !d.glide(200));
		// a finger that rested before it lifted: no glide; cancelled: none
		d.move(50, 20, 116);
		check("rested: the drag's end", d.lift(300, false) == TouchDrag.END && !d.gliding);
		d.press(50, 60, 400, 2);
		d.move(50, 20, 416);
		check("cancelled: its end, no glide", d.lift(420, true) == TouchDrag.END && !d.gliding);
		// a sideways fling glides sideways
		d.press(300, 300, 0, 1);
		d.move(260, 300, 10);
		d.move(200, 300, 20);
		d.lift(25, false);
		check("sideways", d.glide(0) && d.dx > 0 && d.dy == 0, '${d.dx},${d.dy}');
		Sys.println('TouchDragTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}
}
