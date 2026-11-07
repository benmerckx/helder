package helder.ui;

import helder.test.Test;

// ScreenContext: each screen's clock, timers, keymap, safe area and
// settings apart from the program's (main) and from each other's; run()
// makes one current and puts the last back, also when its function throws.
function tests() {
	describe("ScreenContext", () -> {
		test("the globals read the current screen's, the program's again after", () -> {
			var a = new ScreenContext("a"), b = new ScreenContext("b");
			var main = ScreenContext.main;
			equals(ScreenContext.current, main);
			a.run(() -> {
				equals(ScreenContext.current, a);
				assert(helder.ui.actions.Keymap.global == a.keymap);
				b.run(() -> equals(ScreenContext.current, b));
				equals(ScreenContext.current, a);
			});
			equals(ScreenContext.current, main);
			assert(helder.ui.actions.Keymap.global == main.keymap);
			assert(a.keymap != b.keymap);
		});
		test("a screen's animations and timers tick on its clock alone", () -> {
			var a = new ScreenContext("a"), b = new ScreenContext("b");
			var aSteps = 0, bSteps = 0, fired = [];
			a.run(() -> {
				Clock.add(t -> ++aSteps < 3);
				Clock.after(0.5, () -> fired.push("a"));
			});
			b.run(() -> Clock.add(t -> ++bSteps < 3));
			assert(a.animating && b.animating);
			equals(Clock.active, false);
			a.run(() -> {
				Clock.tick(a.now + 0.1);
				Clock.tick(a.now + 0.1);
			});
			equals(aSteps, 2);
			equals(bSteps, 0);
			equals(fired, []);
			a.run(() -> Clock.tick(a.now + 0.4));
			equals(fired, ["a"]);
			equals(a.animating, false);
			assert(b.animating);
			equals(a.nextTimer(), Math.POSITIVE_INFINITY);
		});
		test("a timer cancelled does not run", () -> {
			var a = new ScreenContext("a"), ran = false;
			var t = a.run(() -> Clock.after(0.1, () -> ran = true));
			t.cancel();
			a.run(() -> Clock.tick(a.now + 1));
			equals(ran, false);
		});
		test("settings and the safe area are each screen's", () -> {
			var a = new ScreenContext("a"), b = new ScreenContext("b");
			a.run(() -> helder.os.Store.open("prefs").set("theme", "dark"));
			equals(b.run(() -> helder.os.Store.open("prefs").get("theme")), null);
			equals(a.run(() -> helder.os.Store.open("prefs").get("theme")), "dark");
			equals(helder.os.Store.scope, null);
			a.run(() -> SafeArea.set(44, 0, 34, 0));
			helder.view.graph.Graph.flush();
			equals(a.safeArea.peek().top, 44);
			equals(b.safeArea.peek().top, 0);
			equals(SafeArea.insets.peek().top, ScreenContext.main.safeArea.peek().top);
		});
		test("run puts the last one back when its function throws", () -> {
			var a = new ScreenContext("a");
			var caught = try {
				a.run(function():Int throw "boom");
				false;
			} catch (_:Dynamic) true;
			assert(caught);
			equals(ScreenContext.current, ScreenContext.main);
		});
	});
}
