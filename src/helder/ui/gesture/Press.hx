package helder.ui.gesture;

import helder.os.PointerType;

// A press claimed at once inside a region: a pointer pressed where within
// says (node-local points) wins its arena at the press, before any slop, so
// the recognisers around it lose it (a Scale on the same node, a scroller's
// drag); one pressed elsewhere is left to them. One pointer: a finger, a pen
// or the mouse's button (button; 0: any), a second finger still the others'
// (a pinch). Began at the press (startX, startY), Changed as it moves (x, y;
// tx, ty from the press), Ended at the release, Cancelled when the pointer
// is. A game's shot from its ball, a handle on a canvas:
//
//   var shot = box.addGesture(new Press((x, y) -> nearBall(x, y)));
//   shot.onGesture = g -> if (g.state == Ended) fire(g.tx, g.ty);
class Press extends Gesture {
	// whether a press at x, y (its node's points) is claimed (all of the node: always)
	public var within:(x:Float, y:Float) -> Bool;
	// the mouse's button it takes (1 the left; 0 any)
	public var mouseButton = 1;
	// where it was pressed (its node's points)
	public var startX(default, null) = 0.0;
	public var startY(default, null) = 0.0;

	public function new(?within:(x:Float, y:Float) -> Bool) {
		super();
		this.within = within ?? (_, _) -> true;
	}

	override function wants(type:PointerType, button:Int):Bool
		return enabled && pointers == 0 && (type != Mouse || mouseButton == 0 || button == mouseButton);

	override function added() {
		if (active) return;
		var n = node;
		var lx = n == null ? fx : n.localX(fx, fy), ly = n == null ? fy : n.localY(fx, fy);
		if (!within(lx, ly) || !accept()) {
			fail();
			return;
		}
		startX = lx;
		startY = ly;
		report(Began);
	}

	override function moved()
		if (active) report(Changed);

	override function lifted(cancelled:Bool)
		if (active) report(cancelled ? Cancelled : Ended);

	override function lost()
		if (active) report(Cancelled);
}
