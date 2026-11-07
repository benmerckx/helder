package helder.text;

// How helder.text's own engine draws glyphs: CoreGraphics' glyph pipeline
// (GlyphPipeline) with or without macOS's font smoothing.
//
// - On: what CoreText draws with font smoothing on (macOS's default):
//   outlines dilated by a radius set by the ink's luminance and the device
//   ppem before their coverage, darker and fuller than Off.
// - Off: what CoreText draws with smoothing off, what macOS browsers draw
//   for CSS's `-webkit-font-smoothing: antialiased`: the same pipeline
//   without the dilation.
//
// Both are arithmetic on outlines, the same pixels on every OS. Per app:
// Shaping.smoothing (HELDER_FONT_SMOOTHING=on|off; On by default
// everywhere, so goldens do not vary by OS); per window: a GlyphAtlas's
// (helder.ui's Renderer's, a <Surface>'s `fontSmoothing`). Each mode keeps
// its own atlas entries, so a switch back draws nothing again. After Rune's
// `FontSmoothing` (github.com/anomalyco/rune, MIT).
enum abstract FontSmoothing(Int) to Int {
	var On = 0;
	var Off = 1;

	// "on", "auto", "subpixel-antialiased" (as macOS's default): On;
	// "off", "antialiased", "none", "grayscale": Off; else null
	public static function parse(s:Null<String>):Null<FontSmoothing> {
		if (s == null) return null;
		return switch s.toLowerCase() {
			case "on" | "auto" | "smooth" | "subpixel-antialiased": On;
			case "off" | "antialiased" | "none" | "grayscale": Off;
			case _: null;
		}
	}

	public function toString():String
		return this == 0 ? "on" : "off";
}
