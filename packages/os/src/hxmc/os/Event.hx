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
	// applied), one code point each; not with Control, Alt (Option) or the
	// Command key held, nor for the keys without a character
	var TextInput;
}

// Event.mods bits
class Mods {
	public static inline var SHIFT = 1;
	public static inline var CONTROL = 2;
	public static inline var ALT = 4;
	public static inline var META = 8;
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
	// MouseDown, MouseUp: 1 left, 2 middle, 3 right, 4 and 5 the wheel
	public var button = 0;
	// keys and mouse buttons: the modifiers held (Mods: Shift, Control, Alt, Meta: the Windows or Command key)
	public var mods = 0;
	// TextInput: the character
	public var text = "";

	public function new() {}
}
