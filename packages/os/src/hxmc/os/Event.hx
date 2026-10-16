package hxmc.os;

enum abstract EventKind(Int) {
	var None;
	// the window's close button: the window stays open until close()
	var Close;
	var Resize;
	var KeyDown;
	var KeyUp;
	var MouseMove;
	var MouseDown;
	var MouseUp;
}

// One event, preallocated and refilled for each dispatch (App.run): copy
// what must outlive the callback.
class Event {
	public var kind:EventKind = None;
	public var window:Window;
	// KeyDown, KeyUp: the key (an X11 KeySym for now, also on macOS: Latin-1
	// keys are their unshifted character code, Escape 0xFF1B)
	public var key = 0;
	// the pointer (Mouse*, from the top left) or the new size (Resize), in pixels
	public var x = 0;
	public var y = 0;
	// MouseDown, MouseUp: 1 left, 2 middle, 3 right, 4 and 5 the wheel
	public var button = 0;

	public function new() {}
}
