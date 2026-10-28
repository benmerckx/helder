package helder.ui.gesture;

import helder.os.PointerType;

// A tap: one pointer pressed and released within the slop, nothing else
// having won it (a scroller's drag, a Pan). Its handler is told once,
// Ended, at the release (x, y: where; taps 1). Markup: onTap.
class Tap extends Gesture {
	override function wants(type:PointerType, button:Int):Bool
		return enabled && pointers == 0 && button == 1;

	override function moved()
		if (travel() > slop) fail();

	override function lifted(cancelled:Bool) {
		if (cancelled || pointers != 1 || !accept()) return;
		taps = 1;
		report(Ended);
	}
}
