package helder.ui;

// A component's part as either renderer has it (single-source components,
// @:neutral): what a neutral element's ref gets, a Node here, a
// page's element wrapped by its renderer (helder.web); the little a widget
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

	// a text field's selection, start to end (UTF-16 indices; equal: the
	// caret there); nothing on another part
	function select(start:Int, end:Int):Void;

	// the focusable parts inside it (not itself), the outermost, in order: a
	// tab stop (tabStop) one whether in the tab order or out of it
	function focusables():Array<Part>;

	// in the tab order (on) or out of it, still focused by a click or a
	// handler: a roving tab stop
	function tabStop(on:Bool):Void;

	// whether the focus is on it or inside it
	function holdsFocus():Bool;

	// whether it takes typed text (a text field: the arrows its caret's)
	function editable():Bool;
}
