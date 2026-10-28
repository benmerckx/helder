package helder.os;

// A drag's glide, as a touch screen's: the drag's speed tracked from its
// moves (smoothed), and once let go moving (its last move within 100 ms) a
// glide at that speed, slowing 5% a frame (60 a second) until under half a
// unit a frame. The units are the caller's (TouchDrag's pixels, ui's
// TouchScroll's points); times in ms (any clock). It imports nothing (so
// that ui takes it without the windows: helder.os.Event's).
class Glide {
	// a glide's frame (ms)
	public static inline var FRAME = 1000 / 60;

	// the last step's scroll (step's)
	public var dx(default, null) = 0.0;
	public var dy(default, null) = 0.0;
	public var gliding(get, never):Bool;

	// the drag's speed (a ms, smoothed) and its last move's time
	var vx = 0.0;
	var vy = 0.0;
	var t = 0.0;
	// the glide's speed (a frame) and its last step's time (< 0: none yet)
	var gx = 0.0;
	var gy = 0.0;
	var gt = -1.0;

	public function new() {}

	inline function get_gliding():Bool
		return gx != 0 || gy != 0;

	// a drag starting at time (a glide stopped)
	public function start(time:Float) {
		stop();
		vx = vy = 0;
		t = time;
	}

	// the drag moved by dx, dy (the scroll's) at time
	public function move(dx:Float, dy:Float, time:Float) {
		var dt = Math.max(1, time - t);
		vx = 0.8 * (dx / dt) + 0.2 * vx;
		vy = 0.8 * (dy / dt) + 0.2 * vy;
		t = time;
	}

	// let go at time: whether it glides (its last move within 100 ms)
	public function release(time:Float):Bool {
		if (time - t > 100) return false;
		gx = vx * 16;
		gy = vy * 16;
		gt = -1;
		return gliding;
	}

	// the glide's scroll up to now (its first step at once): whether there
	// is one (by dx, dy)
	public function step(now:Float):Bool {
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
}
