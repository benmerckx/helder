package helder.os;

import helder.os.Event;

// A finger's gesture on a touch screen, as the browser's (packages/os/
// imports.mjs), for the systems whose windows see the touches themselves
// (AndroidWindow, UIKitWindow): a tap clicks (MouseMove, MouseDown, MouseUp
// where it started, once it lifts); a drag (once the finger is SLOP points
// from where it started) scrolls what is under where it started: Scrolls at
// that point by the finger's motion (the content follows it), with
// Mods.TOUCH while it is down, ending with a Scroll of nothing without it;
// let go moving (its last move within 100 ms) it glides on, Scrolls without
// Mods.TOUCH at its speed slowing 5% a frame (60 a second), until under half
// a pixel a frame. A new touch stops a glide. Positions in pixels, times in
// milliseconds (the touches' own; the glide's a clock of its own: glide).
// Neither a drag nor a tap sends mouse events of its own.
class TouchDrag {
	// (lift's answers)
	public static inline var NONE = 0;
	public static inline var TAP = 1;
	public static inline var END = 2;
	// a drag starts this far from where the finger came down (points)
	public static inline var SLOP = 8.0;
	// a glide's frame (ms)
	public static inline var FRAME = 1000 / 60;

	// where the gesture started (its scrolls' and its tap's position)
	public var x(default, null) = 0.0;
	public var y(default, null) = 0.0;
	// the last scroll's (move's, glide's)
	public var dx(default, null) = 0.0;
	public var dy(default, null) = 0.0;
	public var down(default, null) = false;
	public var dragging(default, null) = false;
	public var gliding(get, never):Bool;

	// the finger's last position and time, its speed (pixels a ms, smoothed)
	var lx = 0.0;
	var ly = 0.0;
	var t = 0.0;
	var vx = 0.0;
	var vy = 0.0;
	var slop = SLOP;
	// the glide's speed (pixels a frame) and its last step's time (< 0: none yet)
	var gx = 0.0;
	var gy = 0.0;
	var gt = -1.0;

	public function new() {}

	inline function get_gliding():Bool
		return gx != 0 || gy != 0;

	// a finger down at x, y; scale: pixels per point (the slop's)
	public function press(x:Float, y:Float, time:Float, scale:Float) {
		stop();
		this.x = lx = x;
		this.y = ly = y;
		t = time;
		vx = vy = 0;
		slop = SLOP * scale;
		down = true;
		dragging = false;
	}

	// the finger moved: whether that scrolls (by dx, dy; Mods.TOUCH)
	public function move(x:Float, y:Float, time:Float):Bool {
		if (!down) return false;
		if (!dragging) {
			if (Math.sqrt((x - this.x) * (x - this.x) + (y - this.y) * (y - this.y)) <= slop) return false;
			dragging = true;
		}
		dx = lx - x;
		dy = ly - y;
		var dt = Math.max(1, time - t);
		vx = 0.8 * (dx / dt) + 0.2 * vx;
		vy = 0.8 * (dy / dt) + 0.2 * vy;
		lx = x;
		ly = y;
		t = time;
		return true;
	}

	// the finger lifted, or the system took it (cancelled): TAP (a click
	// where it started), END (the drag's end: a Scroll of nothing; a glide
	// follows when it was let go moving) or NONE
	public function lift(time:Float, cancelled:Bool):Int {
		if (!down) return NONE;
		down = false;
		if (!dragging) return cancelled ? NONE : TAP;
		dragging = false;
		dx = dy = 0;
		if (!cancelled && time - t <= 100) {
			gx = vx * 16;
			gy = vy * 16;
			gt = -1;
		}
		return END;
	}

	// the glide's scroll up to now (ms, any clock: its first step at once):
	// whether there is one (by dx, dy; no Mods.TOUCH)
	public function glide(now:Float):Bool {
		if (!gliding) return false;
		// (half a frame's slack: a loop the display paces steps once a frame)
		if (gt < 0) gt = now - 1.5 * FRAME;
		var sx = 0.0, sy = 0.0;
		while (now - gt >= FRAME) {
			gt += FRAME;
			gx *= 0.95;
			gy *= 0.95;
			if (Math.sqrt(gx * gx + gy * gy) < 0.5) {
				stop();
				break;
			}
			sx += gx;
			sy += gy;
		}
		if (sx == 0 && sy == 0) return false;
		dx = sx;
		dy = sy;
		return true;
	}

	public function stop() {
		gx = gy = 0;
		gt = -1;
	}

	// at most seconds, at most a glide's frame while it glides (a loop's wait)
	public function wait(seconds:Float):Float
		return gliding && (seconds < 0 || seconds > FRAME / 1000) ? FRAME / 1000 : seconds;

	// e as the gesture's Scroll (by dx, dy, at where it started; the window's to set)
	public function scroll(e:Event, mods:Int) {
		e.kind = Scroll;
		e.x = Std.int(x);
		e.y = Std.int(y);
		e.deltaX = dx;
		e.deltaY = dy;
		e.button = 0;
		e.mods = mods;
		e.text = "";
	}

	// e as a tap's MouseMove, MouseDown or MouseUp (button 1), where it started
	public function click(e:Event, kind:EventKind) {
		e.kind = kind;
		e.x = Std.int(x);
		e.y = Std.int(y);
		e.button = kind == MouseMove ? 0 : 1;
		e.mods = 0;
		e.text = "";
	}
}
