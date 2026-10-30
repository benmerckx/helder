package helder.os;

import helder.test.Test;

// Haptics: tap and impact counted (here, natively and as wasm32-wasi
// without a vibrator, nothing felt and nothing failing), off when
// disabled; the browser's vibration and Android's feedback constants
// for each (iOS's generators and Android's JNI call are compiled for
// their targets, felt only on a device)
function tests() {
	describe("Haptics", () -> {
		test("tap and impact are asked for, quietly where nothing vibrates", () -> {
			var t = Haptics.taps, i = Haptics.impacts;
			Haptics.tap();
			Haptics.impact();
			Haptics.impact();
			equals(Haptics.taps, t + 1);
			equals(Haptics.impacts, i + 2);
		});
		test("disabled, nothing", () -> {
			var t = Haptics.taps;
			Haptics.enabled = false;
			Haptics.tap();
			Haptics.enabled = true;
			equals(Haptics.taps, t);
		});
		test("an impact is firmer than a tap", () -> {
			assert(Haptics.vibration(true) > Haptics.vibration(false));
			equals(Haptics.androidFeedback(false, 33), 4);
			equals(Haptics.androidFeedback(true, 33), 16);
			equals(Haptics.androidFeedback(true, 29), 1);
		});
	});
}
