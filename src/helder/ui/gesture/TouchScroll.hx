package helder.ui.gesture;

// A touch's drag scrolling what is under where it started (Ui's own, the
// last in the first finger's arena: the gestures of the nodes inside win
// first), as helder.os.TouchDrag did for the window: once past the slop it
// sends the drag's motion as Ui.wheel at where it started (the content
// follows the finger, a Wheel event first, the nearest scroller that can
// move that way), and the press is cancelled (PointerCancel: no click); let
// go moving (its last move within 100 ms) it glides on at its speed,
// slowing 5% a frame (60 a second), until under half a point a frame. A
// new touch stops a glide. Times in ms here (TouchDrag's); the glide's
// physics TouchDrag's own (helder.os.Glide).
@:allow(helder.ui.Ui)
class TouchScroll extends Gesture {
	final ui:Ui;
	var startX = 0.0;
	var startY = 0.0;
	// (the scroll's speed and its glide, points)
	final g = new helder.os.Glide();

	function new(ui:Ui) {
		super();
		this.ui = ui;
	}

	override function owner():Null<Ui>
		return ui;

	public var gliding(get, never):Bool;

	inline function get_gliding():Bool
		return g.gliding;

	override function added() {
		g.start(time * 1000);
		startX = fx;
		startY = fy;
	}

	override function moved() {
		if (!active) {
			if (pointers > 1 || travel() <= slop || !accept()) return;
			state = Began;
		} else state = Changed;
		// (the content follows: the scroll the other way)
		var ddx = -pendX, ddy = -pendY;
		pendX = pendY = 0;
		g.move(ddx, ddy, time * 1000);
		ui.wheel(startX, startY, ddx, ddy);
	}

	override function lifted(cancelled:Bool) {
		if (!active) return;
		state = cancelled ? Cancelled : Ended;
		// (its frames: Ui.update steps it)
		if (!cancelled && g.release(time * 1000)) ui.requestFrame();
	}

	override function lost()
		if (active && pointers == 0) state = Cancelled;

	// the glide's scroll up to now (ms): whether it still glides
	function glide(now:Float):Bool {
		if (g.step(now)) ui.wheel(startX, startY, g.dx, g.dy);
		return gliding;
	}

	function stop()
		g.stop();
}
