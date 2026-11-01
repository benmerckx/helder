package helder.os;

import helder.test.Test;

// App's lifecycle (App.background, onBackground, onForeground): told once a
// change, whatever reports it (Android's activity paused and resumed, iOS's
// app in the background, the browser's tab hidden: those calls are their
// targets', a device's or a browser's)
function tests() {
	describe("App's lifecycle", () -> {
		test("out of sight and back, each told once", () -> {
			var away = 0, back = 0;
			App.onBackground = () -> away++;
			App.onForeground = () -> back++;
			App.lifecycle(true);
			App.lifecycle(true);
			assert(App.background);
			App.lifecycle(false);
			App.lifecycle(false);
			assert(!App.background);
			equals(away, 1);
			equals(back, 1);
			App.onBackground = null;
			App.onForeground = null;
		});
	});
}
