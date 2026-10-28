package helder.ui.gesture;

// A touch's drag scrolling what is under where it started (Ui's own, the
// last in the first finger's arena: the gestures of the nodes inside win
// first), as helder.os.TouchDrag did for the window: once past the slop it
// sends the drag's motion as Ui.wheel at where it started (the content
// follows the finger, a Wheel event first, the nearest scroller that can
// move that way), and the press is cancelled (PointerCancel: no click); let
// go moving (its last move within 100 ms) it glides on at its speed,
// slowing 5% a frame (60 a second), until under half a point a frame. A
// new touch stops a glide. Times in ms here (TouchDrag's).
@:allow(helder.ui.Ui)
class TouchScroll extends Gesture {
	static inline var FRAME = 1000 / 60;

	final ui:Ui;
	var startX = 0.0;
	var startY = 0.0;
	// (the scroll's speed, points a ms smoothed; the last move's time)
	var sx = 0.0;
	var sy = 0.0;
	var last = 0.0;
	// the glide's speed (points a frame) and its last step's time (< 0: none yet)
	var gx = 0.0;
	var gy = 0.0;
	var gt = -1.0;

	function new(ui:Ui) {
		super();
		this.ui = ui;
	}

	override function owner():Null<Ui>
		return ui;

	public var gliding(get, never):Bool;

	inline function get_gliding():Bool
		return gx != 0 || gy != 0;

	override function added() {
		stop();
		startX = fx;
		startY = fy;
		sx = sy = 0;
		last = time * 1000;
	}

	override function moved() {
		if (!active) {
			if (pointers > 1 || travel() <= slop || !accept()) return;
			state = Began;
		} else state = Changed;
		// (the content follows: the scroll the other way)
		var ddx = -pendX, ddy = -pendY, now = time * 1000, dt = Math.max(1, now - last);
		pendX = pendY = 0;
		sx = 0.8 * (ddx / dt) + 0.2 * sx;
		sy = 0.8 * (ddy / dt) + 0.2 * sy;
		last = now;
		ui.wheel(startX, startY, ddx, ddy);
	}

	override function lifted(cancelled:Bool) {
		if (!active) return;
		state = cancelled ? Cancelled : Ended;
		if (!cancelled && time * 1000 - last <= 100) {
			gx = sx * 16;
			gy = sy * 16;
			gt = -1;
			// (its frames: Ui.update steps it)
			ui.requestFrame();
		}
	}

	override function lost()
		if (active && pointers == 0) state = Cancelled;

	// the glide's scroll up to now (ms): whether it still glides
	function glide(now:Float):Bool {
		if (!gliding) return false;
		// (half a frame's slack: a loop the display paces steps once a frame)
		if (gt < 0) gt = now - 1.5 * FRAME;
		var ax = 0.0, ay = 0.0;
		while (now - gt >= FRAME) {
			gt += FRAME;
			gx *= 0.95;
			gy *= 0.95;
			if (Math.sqrt(gx * gx + gy * gy) < 0.5) {
				stop();
				break;
			}
			ax += gx;
			ay += gy;
		}
		if (ax != 0 || ay != 0) ui.wheel(startX, startY, ax, ay);
		return gliding;
	}

	function stop() {
		gx = gy = 0;
		gt = -1;
	}
}
