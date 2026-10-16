package hxmc.ui;

// A TextEngine's laid-out text, which the same renderer's Canvas draws
interface Paragraph {
	// the widest line's width, the lines' heights
	var width(get, never):Float;
	var height(get, never):Float;
	var lineCount(get, never):Int;
	// the caret's position before character index i (UTF-16 units of the text): x, the line's top, its height
	function caret(i:Int):{x:Float, y:Float, height:Float};
	// the character index nearest to (x, y) in the paragraph
	function hit(x:Float, y:Float):Int;
}
