package hxmc.ui.native;

// What a test does to a backend's widgets through the platform's own calls
// (NativeTest): a click, text set as typed, a toggle, a slider moved, each
// reported back as the user's would be; what the widgets hold and where the
// platform put them (x, y, width, height in the window's client area).
interface NativeDriver {
	function click(handle:Int):Void;
	function type(handle:Int, text:String):Void;
	function toggle(handle:Int, on:Bool):Void;
	function slide(handle:Int, value:Float):Void;
	function fieldText(handle:Int):String;
	function sliderValue(handle:Int):Float;
	function allocation(handle:Int):Array<Int>;
	// the window's pixels as a PNG file: false when the platform cannot
	function screenshot(path:String):Bool;
}
