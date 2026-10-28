package helder.ui;

import helder.test.Test;
import helder.view.Render;

// The safe area in ui (SafeArea, Ui.safeArea): env(safe-area-inset-*)
// resolved, with calc(), max() and min() folded; markup's literal
// attributes naming it bound, laid out again when the insets change (a
// rotation); a box's padding from it inset from a phone's bars
// (natively and as wasm32-wasi). The insets themselves, a phone's: CI's
// emulator and simulator jobs (tests/pack/Screen.hx).
function tests() {
	describe("SafeArea", () -> {
		final e = new Edges(47, 0, 34, 12);
		afterEach(() -> SafeArea.set(0, 0, 0, 0));
		test("env() replaced by the insets' pixels", () -> {
			equals(SafeArea.resolve("env(safe-area-inset-top)", e), "47px");
			equals(SafeArea.resolve("env(safe-area-inset-top) 16px env(safe-area-inset-bottom) env(safe-area-inset-left)", e), "47px 16px 34px 12px");
			equals(SafeArea.resolve("env( safe-area-inset-right )", e), "0px");
			// (a name it does not know: the fallback, else 0)
			equals(SafeArea.resolve("env(titlebar-area-x, 8px)", e), "8px");
			equals(SafeArea.resolve("env(titlebar-area-x)", e), "0px");
		});
		test("calc(), max() and min() of pixels folded", () -> {
			equals(SafeArea.resolve("calc(env(safe-area-inset-top) + 8px)", e), "55px");
			equals(SafeArea.resolve("calc(env(safe-area-inset-bottom) - 4px) 16px", e), "30px 16px");
			equals(SafeArea.resolve("max(12px, env(safe-area-inset-bottom))", e), "34px");
			equals(SafeArea.resolve("min(12px, env(safe-area-inset-bottom))", e), "12px");
			equals(SafeArea.resolve("max(calc(env(safe-area-inset-left) + 1px), 4px)", e), "13px");
			// (a percentage: Dim's calc, the pixels added up)
			equals(SafeArea.resolve("calc(100% - env(safe-area-inset-bottom))", e), "calc(100% - 34px)");
			// (the name's end: not another function's)
			equals(SafeArea.resolve("xmax(1px, 2px)", e), "xmax(1px, 2px)");
		});
		test("markup's literal env() attributes follow the insets", () -> {
			var ui = new Ui(null, 390, 844);
			var dispose = Render.render(Fixture.view(), ui.root);
			ui.update();
			var bar = ui.root.find("bar"), page = ui.root.find("page");
			equals([bar.style.paddingTop, bar.style.paddingBottom, page.style.paddingLeft], [0.0, 12.0, 16.0]);
			// (a phone's: the notch, the home indicator)
			SafeArea.set(47, 0, 34, 0);
			ui.update();
			equals([bar.style.paddingTop, bar.style.paddingBottom, page.style.paddingLeft], [47.0, 34.0, 16.0]);
			equals(bar.rect().height, 47.0 + 20 + 34);
			// (turned: the notch at the left)
			SafeArea.set(0, 47, 21, 47);
			ui.update();
			equals([bar.style.paddingTop, bar.style.paddingBottom, page.style.paddingLeft], [0.0, 21.0, 63.0]);
			dispose();
		});
		test("set: the signal only when they changed", () -> {
			var seen = 0;
			var stop = helder.view.Reactive.root(d -> {
				helder.view.Reactive.effect(() -> {
					SafeArea.insets.value;
					seen++;
				});
				d;
			});
			SafeArea.set(1, 2, 3, 4);
			SafeArea.set(1, 2, 3, 4);
			equals(seen, 2);
			stop();
		});
	});
}

private class Fixture implements helder.view.Markup {
	public static function view()
		return <view tag="page" padding-left="calc(env(safe-area-inset-left) + 16px)">
			<view tag="bar" padding-top="env(safe-area-inset-top)" padding-bottom="max(12px, env(safe-area-inset-bottom))">
				<view height={20}/>
			</view>
		</view>;
}
