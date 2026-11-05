package helder.os;

// The pointer's shape over a window (Window.cursor): the system's own on
// each platform (X11's cursor font, Win32's IDC_ ones, NSCursor, CSS's names).
// helder.ui's nodes take it too (Style.cursor, ui's Cursor), with Auto.
enum abstract Cursor(Int) to Int {
	// (a node's: its parent's; a window shows Default for it)
	var Auto = -1;
	var Default = 0;
	// a link or a button: a hand
	var Pointer = 1;
	// text: an I-beam
	var Text = 2;
	var Crosshair = 3;
	var Move = 4;
	var NotAllowed = 5;
	// resizing left and right, up and down
	@:css("ew-resize") var ResizeEW = 6;
	@:css("ns-resize") var ResizeNS = 7;
	// something that can be dragged, and being dragged: an open and a closed hand
	var Grab = 8;
	var Grabbing = 9;
}
