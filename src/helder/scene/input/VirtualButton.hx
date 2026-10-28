package helder.scene.input;

import helder.os.Pointer;

// An on-screen button (Unity's OnScreenButton): a finger pressed in its
// zone holds it down; it slides off (past the zone, a slop of points
// around it) and the button lets go (a drag off cancels: it is not pressed
// again until the next press), as it does at the finger's release or
// cancel. press() and release() drive it from elsewhere (a ui button's
// onPointerDown). Bound as Button(button); a press and its release within
// one step still count.
class VirtualButton extends TouchControl {
	// down now
	public var down(default, null) = false;
	// its presses and releases so far (Actions read them once a step)
	public var presses(default, null) = 0;
	public var releases(default, null) = 0;
	// how far outside its zone a finger may slide (points)
	public var slop = 16.0;

	// (the window's size and scale at the press: the zone's, as the finger slides)
	var width = 1.0;
	var height = 1.0;
	var scale = 1.0;

	public function new(o:{zone:Zone, ?slop:Float}) {
		super(o.zone);
		if (o.slop != null) slop = o.slop;
	}

	public function press() {
		if (down) return;
		down = true;
		presses++;
		tell();
	}

	public function release() {
		if (!down) return;
		down = false;
		releases++;
		tell();
	}

	override function take(p:Pointer, width:Float, height:Float, scale:Float) {
		super.take(p, width, height, scale);
		this.width = width;
		this.height = height;
		this.scale = scale;
		press();
	}

	override function follow(p:Pointer, scale:Float) {
		if (!down || pointer != p.id) return;
		// (outside the zone and its slop: off)
		var s = slop * scale;
		var inside = zone.radius >= 0 ? {
			var dx = p.x - zone.x0 * width, dy = p.y - zone.y0 * height, r = zone.radius * scale + s;
			dx * dx + dy * dy <= r * r;
		} : p.x >= zone.x0 * width - s && p.x <= zone.x1 * width + s && p.y >= zone.y0 * height - s && p.y <= zone.y1 * height + s;
		if (!inside) release();
	}

	override function lift(p:Pointer, cancelled:Bool) {
		if (pointer != p.id) return;
		super.lift(p, cancelled);
		release();
	}
}
