package helder.ui;

// Lays out text for TextNode: the renderer's (helder.ui.draw.DrawText, on
// helder.text) or a test's. A Paragraph is the engine's own object; the
// Canvas of the same renderer draws it.
interface TextEngine {
	// the text in lines no wider than maxWidth (NaN: one line per hard break);
	// spans: parts of it in other fonts (in order, not overlapping); maxLines:
	// at most so many (0: any), the last ending in an ellipsis when cut
	// (justify: the lines justified to maxWidth, as TextAlign.Justify); base:
	// the direction its paragraphs are in (0 left to right, 1 right to left,
	// from Style.dir; -1: each from its first strong character); cut: lines
	// wider than it ending in an ellipsis within it (TextOverflow.Ellipsis;
	// -1: none)
	function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0, justify:Bool = false, base:Int = -1, cut:Float = -1):Paragraph;
}
