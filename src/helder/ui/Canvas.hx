package helder.ui;

import helder.image.Image;

// What draws a UI tree: the GPU renderer (helder.ui.draw.Renderer) or a test's.
// Coordinates are window pixels moved by the current translation (translate
// adds to it: a scrolled node's children) and through the transforms pushed
// (each applied to what is drawn after it, inside the ones pushed before);
// clips nest (each intersects the current one) and are restored with the
// translation they were pushed at.
interface Canvas {
	function translate(dx:Float, dy:Float):Void;
	// corners (given): each corner's radius, over radius (top left, top right, bottom right, bottom left)
	function pushClip(x:Float, y:Float, w:Float, h:Float, radius:Float, ?corners:Corners):Void;
	function popClip():Void;
	function pushOpacity(alpha:Float):Void;
	function popOpacity():Void;
	// an affine transform, in the current coordinates: x' = a x + c y + e, y' = b x + d y + f
	function pushTransform(a:Float, b:Float, c:Float, d:Float, e:Float, f:Float):Void;
	function popTransform():Void;
	// a rectangle with rounded corners, filled, with a border inside it;
	// sides (given): each side's width, over borderWidth
	function rect(x:Float, y:Float, w:Float, h:Float, radius:Float, fill:Color, borderWidth:Float, border:Color, ?corners:Corners, ?sides:Edges):Void;
	// a rounded rectangle blurred (CSS's blur: a Gaussian whose standard
	// deviation is half of it); offset (given): x, y and spread from the box
	// that casts it, which it is not drawn under (CSS's outer box shadow)
	function shadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, ?corners:Corners, ?offset:Array<Float>):Void;
	// an inset shadow inside a padding box (its corners): the box darkened
	// from outside a rectangle moved by dx, dy and shrunk by spread, blurred
	function insetShadow(x:Float, y:Float, w:Float, h:Float, radius:Float, color:Color, blur:Float, dx:Float, dy:Float, spread:Float,
		?corners:Corners):Void;
	// a vector path (in the current coordinates) filled (null: not) and
	// stroked (null: not), each with a colour or a gradient over its bounds
	function path(p:Path, fill:Null<Paint>, ?stroke:Stroke):Void;
	// the part u0, v0, u1, v1 (0...1) of an image stretched over a rectangle
	// with rounded corners
	function image(img:Image, x:Float, y:Float, w:Float, h:Float, u0:Float, v0:Float, u1:Float, v1:Float, radius:Float, ?corners:Corners):Void;
	// a TextEngine's paragraph with its first line's top left at (x, y), aligned in width;
	// colors: its spans' (in the order of the spans it was laid out with), else color
	function text(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, ?colors:Array<Color>):Void;
	// the same paragraph's shadow (Style.textShadow): its glyphs in one
	// colour (or its spans'), blurred as CSS blurs a text shadow
	function textShadow(p:Paragraph, x:Float, y:Float, width:Float, align:TextAlign, color:Color, blur:Float, ?colors:Array<Color>):Void;
}
