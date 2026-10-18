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
	// a character typed (after KeyDown: with Shift, the layout and dead keys
	// applied), one code point each (an input method's commit: at once); not
	// with Control, Alt (Option) or the Command key held, nor for the keys
	// without a character
	var TextInput;
	// the system lost the window's pixels (X11's Expose, Win32's WM_PAINT):
	// draw a frame again, even with nothing changed
	var Redraw;
	// an input method's composition (the text not committed yet, shown where
	// it is typed): text, the caret in it (x, UTF-16); empty: it ended
	// (committed: TextInput follows; or cancelled). In the browser and on
	// macOS, while Window.startTextInput is on
	var TextEditing;
	// the wheel or a trackpad: deltaX, deltaY in pixels (as a browser's wheel
	// event: positive scrolls toward the right and the bottom), at the
	// pointer (x, y); a wheel's notch is 40 pixels, a trackpad's motion
	// exact
	var Scroll;
	// the window's scale changed (Window.scale: another display's DPI);
	// a Resize follows if its size in pixels changed too
	var ScaleChange;
	// Android: the system took the window (the app went to the background):
	// its Surface is lost (Surface.lost) and nothing is drawn until Resume;
	// iOS: the app went to the background (the Surface stays), no frames
	var Suspend;
	// Android: a new window for the Surface (Surface.reattach), drawn to
	// again; iOS: back in the foreground
	var Resume;
}

// Event.mods bits
class Mods {
	public static inline var SHIFT = 1;
	public static inline var CONTROL = 2;
	public static inline var ALT = 4;
	public static inline var META = 8;
	// Scroll, in the browser: a touch drag's, the finger on the canvas (the
	// drag ends with a Scroll of nothing without it, then its glide's)
	public static inline var TOUCH = 16;
}

// One event, preallocated and refilled for each dispatch (App.run): copy
// what must outlive the callback.
class Event {
	public var kind:EventKind = None;
	public var window:Window;
	// KeyDown, KeyUp: the key (an X11 KeySym for now, also on macOS and
	// Windows: Latin-1 keys are their unshifted character code, Escape 0xFF1B)
	public var key = 0;
	// the pointer (Mouse*, from the top left) or the new size (Resize), in pixels
	public var x = 0;
	public var y = 0;
	// MouseDown, MouseUp: 1 left, 2 middle, 3 right
	public var button = 0;
	// Scroll: pixels toward the right and the bottom
	public var deltaX = 0.0;
	public var deltaY = 0.0;
	// keys, mouse buttons and scrolls: the modifiers held (Mods: Shift, Control, Alt, Meta: the Windows or Command key)
	public var mods = 0;
	// TextInput: the characters; TextEditing: the composition
	public var text = "";

	public function new() {}
}
