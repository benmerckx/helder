package helder.ui.widgets;

// A data grid's colours, by theme token: a StyleSheet's light and dark
// colours named "grid-" and one of NAMES win, else the neutral defaults
// here. Resolved once per sheet and appearance.
class GridTheme {
	public static final NAMES = [
		"background", "foreground", "muted", "line", "header", "header-foreground", "gutter", "hover", "selection", "cursor", "edited", "added",
		"deleted", "skeleton", "scrollbar", "resize"
	];
	public static inline var BACKGROUND = 0;
	public static inline var FOREGROUND = 1;
	public static inline var MUTED = 2;
	public static inline var LINE = 3;
	public static inline var HEADER = 4;
	public static inline var HEADER_FOREGROUND = 5;
	public static inline var GUTTER = 6;
	public static inline var HOVER = 7;
	public static inline var SELECTION = 8;
	public static inline var CURSOR = 9;
	public static inline var EDITED = 10;
	public static inline var ADDED = 11;
	public static inline var DELETED = 12;
	public static inline var SKELETON = 13;
	public static inline var SCROLLBAR = 14;
	public static inline var RESIZE = 15;

	static final LIGHT:Array<Color> = [
		Color.rgb(0xFFFFFF), Color.rgb(0x1C1C1E), Color.rgb(0x8A8A8E), Color.rgb(0xE8E8EA), Color.rgb(0xFAFAFA), Color.rgb(0x5C5C60),
		Color.rgb(0xFAFAFA), Color.rgba(0x000000, 0.03), Color.rgba(0x2563EB, 0.10), Color.rgb(0x2563EB), Color.rgba(0xD97706, 0.14),
		Color.rgba(0x16A34A, 0.10), Color.rgba(0xDC2626, 0.08), Color.rgba(0x000000, 0.06), Color.rgba(0x000000, 0.28), Color.rgb(0x2563EB)
	];
	static final DARK:Array<Color> = [
		Color.rgb(0x1E1E20), Color.rgb(0xECECEE), Color.rgb(0x8E8E93), Color.rgb(0x2E2E31), Color.rgb(0x232326), Color.rgb(0xA5A5AA),
		Color.rgb(0x232326), Color.rgba(0xFFFFFF, 0.03), Color.rgba(0x60A5FA, 0.16), Color.rgb(0x60A5FA), Color.rgba(0xF59E0B, 0.18),
		Color.rgba(0x22C55E, 0.14), Color.rgba(0xEF4444, 0.14), Color.rgba(0xFFFFFF, 0.07), Color.rgba(0xFFFFFF, 0.28), Color.rgb(0x60A5FA)
	];

	// the colours now, by the indices above
	public final colors:Array<Color> = [for (c in LIGHT) c];

	var sheet:Null<StyleSheet> = null;
	var dark = false;
	var resolved = false;

	public function new() {}

	// the colours for a sheet and an appearance; whether they changed
	public function resolve(sheet:Null<StyleSheet>, dark:Bool):Bool {
		if (resolved && sheet == this.sheet && dark == this.dark) return false;
		resolved = true;
		this.sheet = sheet;
		this.dark = dark;
		var base = dark ? DARK : LIGHT;
		var tokens = sheet == null ? null : dark && sheet.dark != null ? sheet.dark : sheet.light;
		for (k in 0...NAMES.length) {
			var c = tokens == null ? null : tokens.get("grid-" + NAMES[k]);
			colors[k] = c != null ? c : base[k];
		}
		return true;
	}
}
