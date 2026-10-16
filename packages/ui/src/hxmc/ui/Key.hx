package hxmc.ui;

// Key codes: X11 KeySyms, as hxmc.os.Event.key gives them on every
// platform (Latin-1 keys are their unshifted character code: 'a' is 0x61)
class Key {
	public static inline var BACKSPACE = 0xFF08;
	public static inline var TAB = 0xFF09;
	public static inline var ENTER = 0xFF0D;
	public static inline var ESCAPE = 0xFF1B;
	public static inline var HOME = 0xFF50;
	public static inline var LEFT = 0xFF51;
	public static inline var UP = 0xFF52;
	public static inline var RIGHT = 0xFF53;
	public static inline var DOWN = 0xFF54;
	public static inline var PAGE_UP = 0xFF55;
	public static inline var PAGE_DOWN = 0xFF56;
	public static inline var END = 0xFF57;
	public static inline var DELETE = 0xFFFF;
	public static inline var SHIFT = 0xFFE1;
	public static inline var CONTROL = 0xFFE3;
	public static inline var ALT = 0xFFE9;
	public static inline var META = 0xFFE7;
	public static inline var SPACE = 0x20;

	// Event.mods bits
	public static inline var MOD_SHIFT = 1;
	public static inline var MOD_CONTROL = 2;
	public static inline var MOD_ALT = 4;
	public static inline var MOD_META = 8;
}
