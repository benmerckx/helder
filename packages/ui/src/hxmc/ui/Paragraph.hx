package hxmc.ui;

// A TextEngine's laid-out text, which the same renderer's Canvas draws
interface Paragraph {
	// the widest line's width, the lines' heights
	var width(get, never):Float;
	var height(get, never):Float;
	var lineCount(get, never):Int;
	// the min-content width: the widest word (what a width of 0 lays out)
	var minWidth(get, never):Float;
	// the first line's baseline below the paragraph's top
	var baseline(get, never):Float;
	// the caret's position before character index i (UTF-16 units of the text): x, the line's top, its height
	function caret(i:Int):{x:Float, y:Float, height:Float};
	// the character index nearest to (x, y) in the paragraph
	function hit(x:Float, y:Float):Int;
	// what the characters start...end cover, line by line (top to bottom, left to right): a
	// rectangle for each visual run (several on a line of mixed directions), its line's top
	function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}>;
	// the width of the line at y (its top to its bottom; past the last: the last's), to align it
	function lineWidth(y:Float):Float;
	// the lines a text decoration of the characters start...end draws (an
	// underline, a line-through or an overline), snapped to the pixels of
	// scale (the window's per UI pixel), line by line: rectangles, each with
	// its line's width (the text drawn aligned in a box moves them as it
	// moves the line)
	function decoration(start:Int, end:Int, kind:TextDecoration, scale:Float):Array<{x:Float, y:Float, width:Float, height:Float, lineWidth:Float}>;
}
