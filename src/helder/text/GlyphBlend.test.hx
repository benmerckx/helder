package helder.text;

import helder.test.Test;
import helder.text.Shaping.GlyphBlend;

// Windows' grayscale text blend (GlyphBlend, UiShader's the same): plain
// coverage at gamma 1 without contrast, the ends kept, light text on dark
// given more ink than its coverage and dark on light less, the gamma's
// ratios Direct2D's table's (Windows Terminal's scaling)
@:test.interp
function tests() {
	describe("GlyphBlend", () -> {
		test("gamma 1, no contrast: the coverage as it is", () -> {
			var b = new GlyphBlend(1.0, 0);
			equals([for (a in [0.0, 0.25, 0.5, 1.0]) b.apply(a, 1, 1, 1)], [0.0, 0.25, 0.5, 1.0]);
		});
		test("Windows' defaults (1.8, 1): the ends kept, light text bolder, dark text's contrast", () -> {
			var b = new GlyphBlend(1.8, 1);
			equals([b.apply(0, 1, 1, 1), b.apply(1, 1, 1, 1), b.apply(0, 0, 0, 0), b.apply(1, 0, 0, 0)], [0.0, 1.0, 0.0, 1.0]);
			assert(b.apply(0.5, 0.9, 0.9, 0.9) > 0.6, "light on dark: more ink");
			assert(b.apply(0.5, 0, 0, 0) < 0.5, "dark on light: less");
			var r = GlyphBlend.ratiosOf(1.8);
			equals([for (v in r) Math.round(v * 10000)], [1481, -8946, 14759, -3247]);
		});
	});
}
