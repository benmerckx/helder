package hxmc.ui;

// What draws a UI tree: the GPU renderer (hxmc.ui.draw.Renderer) or a test's.
// Coordinates are window pixels moved by the current translation (translate
// adds to it: a scrolled node's children); clips nest (each intersects the
// current one) and are restored with the translation they were pushed at.
interface Canvas {
	function translate(dx:Float, dy:Float):Void;
	function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float):Void;
	function popClip():Void;
	function pushOpacity(alpha:Float):Void;
	function popOpacity():Void;
	// a rectangle with rounded corners, filled, with a border inside it
	function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color):Void;
	// a rounded rectangle faded over blur pixels on each side of its edge
	function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float):Void;
	// a TextEngine's paragraph with its first line's top left at (x, y), aligned in width
	function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color):Void;
}
