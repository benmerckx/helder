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
	// a character typed (after KeyDown, one event per character: char)
	var Text;
	// the wheel or a trackpad scrolled (dx, dy)
	var Wheel;
	// the window's scale changed (Window.scale: another display's DPI);
	// a Resize follows if its size in pixels changed too
	var ScaleChange;
}

// One event, preallocated and refilled for each dispatch (App.run): copy
// what must outlive the callback.
class Event {
	public var kind:EventKind = None;
	public var window:Window;
	// KeyDown, KeyUp: the key (an X11 KeySym for now, also on macOS and
	// Windows: Latin-1 keys are their unshifted character code, Escape 0xFF1B)
	public var key = 0;
	// Text: the character, a Unicode code point (not a control character)
	public var char = 0;
	// the pointer (Mouse*, Wheel, from the top left) or the new size (Resize), in pixels
	public var x = 0;
	public var y = 0;
	// MouseDown, MouseUp: 1 left, 2 middle, 3 right
	public var button = 0;
	// Wheel: the distance in notches of a wheel (a trackpad's in fractions),
	// dy > 0 up (away from the user), dx > 0 right; as the system's
	// settings turn them (natural scrolling)
	public var dx = 0.0;
	public var dy = 0.0;

	public function new() {}
}
