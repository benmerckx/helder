package hxmc.os;

// The pointer's shape over a window (Window.cursor): the system's own on
// each platform (X11's cursor font, Win32's IDC_ ones, NSCursor, CSS's names).
enum abstract Cursor(Int) to Int {
	var Default;
	// a link or a button: a hand
	var Pointer;
	// text: an I-beam
	var Text;
	var Crosshair;
	var Move;
	var NotAllowed;
	// resizing left and right, up and down
	var ResizeEW;
	var ResizeNS;
	// something that can be dragged, and being dragged: an open and a closed hand
	var Grab;
	var Grabbing;
}
