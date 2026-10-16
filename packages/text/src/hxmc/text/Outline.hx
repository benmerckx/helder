package hxmc.text;

// A path being built: moveTo, lineTo, quadTo, close. The rasterizer is one
// (it draws as it goes); Path records the segments.
interface Outline {
	function moveTo(x:Float, y:Float):Void;
	function lineTo(x:Float, y:Float):Void;
	function quadTo(cx:Float, cy:Float, x:Float, y:Float):Void;
	function close():Void;
}
