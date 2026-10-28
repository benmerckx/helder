package helder.ui.gesture;

// Pan, pinch and rotate at once (Flutter's scale, what a camera wants):
// Began once its pointers' focus moved past the slop, or two pointers
// down moved at all; then Changed with the focus's motion (dx, dy, tx,
// ty), the spread's ratio (dscale; scale since it began: a pinch) and the
// turn of its first two pointers (dangle, angle); Ended when the pointers
// down fall under minPointers (or the last lifts), Cancelled when taken.
// A finger put down or lifted makes no jump. Markup: onScale (from one
// pointer), onPinch (from two).
class Scale extends Gesture {
	// the pointers down before it may begin (1: a drag; 2: a pinch)
	public var minPointers = 1;

	public function new(minPointers = 1) {
		super();
		this.minPointers = minPointers;
	}

	override function added()
		if (active) accept();

	override function moved() {
		if (active) {
			report(Changed);
			return;
		}
		if (pointers < minPointers) return;
		if (pointers < 2 && travel() > slop || pointers >= 2) {
			if (!accept()) return;
			report(Began);
		}
	}

	override function lifted(cancelled:Bool)
		if (active && (pointers <= minPointers || pointers == 1)) report(cancelled ? Cancelled : Ended);

	override function lost()
		if (active && (pointers < minPointers || pointers == 0)) report(Cancelled);
}
