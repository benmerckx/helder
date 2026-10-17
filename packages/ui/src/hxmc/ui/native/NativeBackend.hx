package hxmc.ui.native;

import hxmc.ui.*;

// A platform's controls for NativeHost: one window with a container where
// widgets are placed absolutely, widgets made, updated from their Control
// (or a TextNode: a label of its text, font and colour), measured, placed
// and destroyed; the platform's events pumped. Handles are the backend's
// (non-zero); its events go to the host's callbacks.
interface NativeBackend {
	function openWindow(title:String, width:Int, height:Int, host:NativeHost):Void;
	function closeWindow():Void;
	// the container's size in pixels
	function windowWidth():Int;
	function windowHeight():Int;
	// a widget for a control (kind and properties) or a TextNode's label
	function create(n:Node):Int;
	// its properties from the node (text, state, value, font, colour)
	function update(handle:Int, n:Node):Void;
	function place(handle:Int, x:Float, y:Float, width:Float, height:Float):Void;
	function destroy(handle:Int):Void;
	// a control's natural size, or its height for a width (NaN: none)
	function measure(c:Control, width:Float):Size;
	// text as the platform lays it out: its size within maxWidth (NaN: one line per paragraph)
	function measureText(text:String, font:Font, maxWidth:Float):Size;
	// handles the platform's events (waiting for one when block): false once the window is closed
	function pump(block:Bool):Bool;
}
