package hxmc.ui;

// A part of a paragraph in another font (TextEngine.layout): the UTF-16
// units start (inclusive) to end of its text.
class TextSpan {
	public final start:Int;
	public final end:Int;
	public final font:Font;

	public function new(start:Int, end:Int, font:Font) {
		this.start = start;
		this.end = end;
		this.font = font;
	}
}
