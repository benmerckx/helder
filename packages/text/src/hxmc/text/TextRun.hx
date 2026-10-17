package hxmc.text;

// A part of a TextLayout's text in other fonts: the UTF-16 units start
// (inclusive) to end, its FontSet and line height (a multiple of its size),
// the space added after each character and to each space (pixels).
class TextRun {
	public final start:Int;
	public final end:Int;
	public final fonts:FontSet;
	public final lineHeight:Float;
	public final letterSpacing:Float;
	public final wordSpacing:Float;

	public function new(start:Int, end:Int, fonts:FontSet, lineHeight:Float, letterSpacing = 0.0, wordSpacing = 0.0) {
		this.start = start;
		this.end = end;
		this.fonts = fonts;
		this.lineHeight = lineHeight;
		this.letterSpacing = letterSpacing;
		this.wordSpacing = wordSpacing;
	}
}
