package hxmc.text;

// A part of a TextLayout's text in other fonts: the UTF-16 units start
// (inclusive) to end, its FontSet and line height (a multiple of its size).
class TextRun {
	public final start:Int;
	public final end:Int;
	public final fonts:FontSet;
	public final lineHeight:Float;

	public function new(start:Int, end:Int, fonts:FontSet, lineHeight:Float) {
		this.start = start;
		this.end = end;
		this.fonts = fonts;
		this.lineHeight = lineHeight;
	}
}
