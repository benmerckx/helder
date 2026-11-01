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
	describe("App's back", () -> {
		test("onBack's answer: taken, not, none set", () -> {
			equals(App.back(), false);
			var asked = 0, take = true;
			App.onBack = () -> {
				asked++;
				take;
			};
			equals(App.back(), true);
			take = false;
			equals(App.back(), false);
			equals(asked, 2);
			App.onBack = null;
		});
		test("backDepth: never below 0, the history told when it starts and stops being deep", () -> {
			var told = [];
			App.backHistory = deep -> told.push(deep);
			App.backDepth = 1;
			App.backDepth = 2;
			App.backDepth = 1;
			App.backDepth = 0;
			App.backDepth = -1;
			equals(App.backDepth, 0);
			equals(told.join(","), "true,false");
			App.backHistory = null;
		});
	});
}
