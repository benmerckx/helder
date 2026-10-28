package helder.scene.input;

import helder.os.Pointer;

// An on-screen control a finger drives (Unity's on-screen controls, as
// virtual devices: gameplay reads the actions bound to it as it reads a
// gamepad's): it takes a finger whose press began in its zone, nobody's
// yet (not the ui's: helder.os's Pointer.owner, marked Control then), and
// keeps it until it lifts or is cancelled, wherever it goes; a finger
// sliding over another control from elsewhere does not press it. Actions'
// step feeds it (helder.os.Pointers, read once a step): VirtualStick,
// VirtualButton, and the zones of Touch and TouchDelta bindings.
class TouchControl {
	public final zone:Zone;
	// the slot of the finger it holds (-1: none)
	public var pointer(default, null) = -1;
	// called when it changes (a press, a release, the stick moved: a ui
	// drawing it asks for a frame)
	public var changed:Null<Void->Void> = null;

	function new(zone:Zone) {
		this.zone = zone;
	}

	// (whether it takes the press of p, at its start: one finger at a time)
	function wants(p:Pointer, width:Float, height:Float, scale:Float):Bool
		return pointer < 0 && zone.contains(p.startX, p.startY, width, height, scale);

	// (its finger: taken, moved (down still), lifted or cancelled)
	function take(p:Pointer, width:Float, height:Float, scale:Float) {
		pointer = p.id;
	}

	function follow(p:Pointer, scale:Float) {}

	function lift(p:Pointer, cancelled:Bool) {
		if (pointer == p.id) pointer = -1;
	}

	inline function tell()
		if (changed != null) changed();
}
