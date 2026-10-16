package hxmc.ui;

// Lays out text for TextNode: the renderer's (hxmc.ui.draw.DrawText, on
// hxmc.text) or a test's. A Paragraph is the engine's own object; the
// Canvas of the same renderer draws it.
interface TextEngine {
	// the text in lines no wider than maxWidth (NaN: one line per hard break)
	function layout(text:String, font:Font, maxWidth:Float):Paragraph;
}
