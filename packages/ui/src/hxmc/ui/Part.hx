package hxmc.ui;

// A widget's part as either renderer has it (docs/plans/native-or-drawn.md:
// single-source widgets): what a neutral element's ref gets, a Node here, a
// page's element wrapped by its renderer (hxmc.web); the little a widget
// does to its parts beyond their attributes
interface Part {
	// takes the focus (visible: its ring shown, as after a key)
	function focus(visible:Bool = true):Void;

	// its box in the window's (the page's) coordinates, after layout
	function rect():{x:Float, y:Float, width:Float, height:Float};

	// scrolled into view in the scrollers around it
	function scrollIntoView():Void;

	// whether p is it or inside it
	function contains(p:Part):Bool;

	// an attribute (data-*, aria-*), null where it has none
	function attr(name:String):Null<String>;

	// whether it is laid out right to left (dir, its own or inherited)
	function rtl():Bool;

	// takes the pointer pressed on it or inside it: its moves and its release
	// come to it wherever the pointer goes, until it is released
	function capture():Void;
}
