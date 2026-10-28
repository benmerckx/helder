package helder.ui.gesture;

// A drag: Began once its pointers' focus moved past the slop (along axis:
// a drag along the other one left to others, a scroller's), Changed as it
// moves (dx, dy; tx, ty since the press: its first call has the slop's
// travel too, as a scroller's drag starts), Ended when the last lifts (vx,
// vy: its speed then), Cancelled when it is taken. More fingers move the
// focus without a jump. Markup: onPan, pan-axis ("x", "y"), pan-min-pointers.
class Pan extends Gesture {
	public var axis:Axis = Both;
	// the pointers down before it may begin
	public var minPointers = 1;

	public function new(axis:Axis = Both) {
		super();
		this.axis = axis;
	}

	override function added()
		if (active) accept();

	override function moved() {
		if (axis == X) pendY = 0 else if (axis == Y) pendX = 0;
		if (active) {
			if (pendX != 0 || pendY != 0) report(Changed);
			return;
		}
		if (pointers < minPointers) return;
		var ax = Math.abs(travelX), ay = Math.abs(travelY);
		var past = switch axis {
			case X: ax > slop && ax > ay;
			case Y: ay > slop && ay > ax;
			case _: travel() > slop;
		}
		if (!past) return;
		if (!accept()) return;
		pendX = axis == Y ? 0 : travelX;
		pendY = axis == X ? 0 : travelY;
		report(Began);
	}

	override function lifted(cancelled:Bool)
		if (active && pointers <= minPointers) report(cancelled ? Cancelled : Ended);

	override function lost()
		if (active && pointers < minPointers) report(Cancelled);
}
