package helder.os;

import helder.os.android.Haptic;
import helder.os.uikit.UIKitWindow;
import helder.os.web.Dom;
import hxmc.unsafe.*;

// A touch felt: tap, a light tick (something picked: a tab, a tile, a
// selection), impact, a firmer pulse (something done: a purchase
// confirmed, an order given). iOS: UISelectionFeedbackGenerator and
// UIImpactFeedbackGenerator (medium); Android: the activity's view's
// performHapticFeedback (CLOCK_TICK; CONFIRM from API 30, else
// VIRTUAL_KEY), as the system's haptic settings allow, no permission
// needed; the browser: navigator.vibrate (10 ms, 25 ms), nothing where
// the browser has none (iOS Safari, desktops); elsewhere nothing.
// enabled false turns them off (an app's setting).
class Haptics {
	public static var enabled = true;
	// how many were asked for (each kind), enabled or not on this target: for tests
	public static var taps(default, null) = 0;
	public static var impacts(default, null) = 0;

	public static function tap()
		play(false);

	public static function impact()
		play(true);

	// the browser's vibration (ms) for each
	public static inline function vibration(strong:Bool):Int
		return strong ? 25 : 10;

	// Android's HapticFeedbackConstants for each at an API level: CLOCK_TICK
	// (4); CONFIRM (16, API 30), else VIRTUAL_KEY (1)
	public static function androidFeedback(strong:Bool, sdk:Int):Int
		return strong ? (sdk >= 30 ? 16 : 1) : 4;

	static function play(strong:Bool) {
		if (!enabled) return;
		if (strong) impacts++ else taps++;
		if (Mem.platform() >= 1) UIKitWindow.haptic(strong) else if (Mem.os() == 3) Dom.vibrate(vibration(strong)) else if (Mem.target() >= 9)
			Haptic.perform(strong);
	}
}
