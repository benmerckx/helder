import helder.os.PointerType;
import helder.ui.gesture.Gesture;

// The shot: a press near the ball (near(x, y), in the <Scene> box's
// points) wins its pointer at once, before any slop, so <OrbitControls>'
// Scale on the same box loses it: a drag from the ball aims, a drag from
// anywhere else turns the camera, a second finger still pinches (the shot
// takes one pointer only). Began at the press, Changed as it moves (tx,
// ty: the pull from the ball, in points), Ended at the release (the shot),
// Cancelled when the pointer is.
class ShotGesture extends Gesture {
	// whether a press at x, y (box points) starts a shot
	public var near:(Float, Float) -> Bool = (_, _) -> false;
	// where it was pressed and where it is now (box points)
	public var startX(default, null) = 0.0;
	public var startY(default, null) = 0.0;

	public function new() {
		super();
	}

	// (one pointer: a finger, a pen or the mouse's left button)
	override function wants(type:PointerType, button:Int):Bool
		return enabled && pointers == 0 && (type != Mouse || button == 1);

	override function added() {
		if (active) return;
		var n = node;
		var lx = n == null ? fx : n.localX(fx, fy), ly = n == null ? fy : n.localY(fx, fy);
		if (!near(lx, ly)) {
			fail();
			return;
		}
		startX = lx;
		startY = ly;
		if (!accept()) {
			fail();
			return;
		}
		report(Began);
	}

	override function moved()
		if (active) report(Changed);

	override function lifted(cancelled:Bool)
		if (active) report(cancelled ? Cancelled : Ended);

	override function lost()
		if (active) report(Cancelled);
}
