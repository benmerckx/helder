package helder.ui.code;

import helder.syntax.Lexer.TokenClass;

// A code editor's colours, by theme token: a StyleSheet's light and dark
// colours of these names (without the dashes) win, else the defaults here
// (GitHub's light and dark): "code-background", "code-foreground", the
// token classes' ("code-keyword", "code-string", "code-number",
// "code-comment", "code-type", "code-function", "code-tag",
// "code-attribute", "code-punctuation"), the gutter's ("code-gutter",
// "code-line-number", "code-line-number-active"), "code-current-line",
// "code-selection", "code-cursor", "code-indent-guide", "code-whitespace",
// the diagnostics' ("code-error", "code-warning", "code-info"), find's
// ("code-find-match", "code-find-current") and "code-panel" (find's and go
// to line's panel). Resolved once per sheet and appearance.
class CodeTheme {
	public static final NAMES = [
		"background", "foreground", "keyword", "string", "number", "comment", "type", "function", "tag", "attribute", "punctuation", "gutter", "line-number",
		"line-number-active", "current-line", "selection", "cursor", "indent-guide", "whitespace", "error", "warning", "info", "find-match", "find-current",
		"panel", "panel-border", "tooltip"
	];
	public static inline var BACKGROUND = 0;
	public static inline var FOREGROUND = 1;
	// (the token classes' colours: TokenClass + 1, Plain the foreground)
	public static inline var GUTTER = 11;
	public static inline var LINE_NUMBER = 12;
	public static inline var LINE_NUMBER_ACTIVE = 13;
	public static inline var CURRENT_LINE = 14;
	public static inline var SELECTION = 15;
	public static inline var CURSOR = 16;
	public static inline var INDENT_GUIDE = 17;
	public static inline var WHITESPACE = 18;
	public static inline var ERROR = 19;
	public static inline var WARNING = 20;
	public static inline var INFO = 21;
	public static inline var FIND_MATCH = 22;
	public static inline var FIND_CURRENT = 23;
	public static inline var PANEL = 24;
	public static inline var PANEL_BORDER = 25;
	public static inline var TOOLTIP = 26;

	static final LIGHT:Array<Color> = [
		Color.rgb(0xFFFFFF), Color.rgb(0x1F2328), Color.rgb(0xCF222E), Color.rgb(0x0A3069), Color.rgb(0x0550AE), Color.rgb(0x6E7781), Color.rgb(0x953800),
		Color.rgb(0x8250DF), Color.rgb(0x116329), Color.rgb(0x0550AE), Color.rgb(0x57606A), Color.rgb(0xFFFFFF), Color.rgb(0x8C959F), Color.rgb(0x1F2328),
		Color.rgb(0xF6F8FA), Color.rgba(0x0969DA, 0.22), Color.rgb(0x0969DA), Color.rgb(0xD8DEE4), Color.rgba(0x8C959F, 0.8), Color.rgb(0xCF222E),
		Color.rgb(0x9A6700), Color.rgb(0x0969DA), Color.rgba(0xD4A72C, 0.35), Color.rgba(0xD4A72C, 0.7), Color.rgb(0xF6F8FA), Color.rgb(0xD0D7DE),
		Color.rgb(0xFFFFFF)
	];
	static final DARK:Array<Color> = [
		Color.rgb(0x0D1117), Color.rgb(0xE6EDF3), Color.rgb(0xFF7B72), Color.rgb(0xA5D6FF), Color.rgb(0x79C0FF), Color.rgb(0x8B949E), Color.rgb(0xFFA657),
		Color.rgb(0xD2A8FF), Color.rgb(0x7EE787), Color.rgb(0x79C0FF), Color.rgb(0x8B949E), Color.rgb(0x0D1117), Color.rgb(0x6E7681), Color.rgb(0xE6EDF3),
		Color.rgb(0x161B22), Color.rgba(0x388BFD, 0.3), Color.rgb(0x58A6FF), Color.rgb(0x21262D), Color.rgba(0x6E7681, 0.8), Color.rgb(0xF85149),
		Color.rgb(0xD29922), Color.rgb(0x58A6FF), Color.rgba(0xBB8009, 0.35), Color.rgba(0xBB8009, 0.75), Color.rgb(0x161B22), Color.rgb(0x30363D),
		Color.rgb(0x161B22)
	];

	// the colours now, by the indices above
	public final colors:Array<Color> = [for (c in LIGHT) c];

	// (what they were resolved from)
	var sheet:Null<StyleSheet> = null;
	var dark = false;
	var resolved = false;

	public function new() {}

	// the colours for a sheet and an appearance (again only when either changed)
	public function resolve(sheet:Null<StyleSheet>, dark:Bool) {
		if (resolved && sheet == this.sheet && dark == this.dark) return;
		resolved = true;
		this.sheet = sheet;
		this.dark = dark;
		var base = dark ? DARK : LIGHT;
		var tokens = sheet == null ? null : dark && sheet.dark != null ? sheet.dark : sheet.light;
		for (k in 0...NAMES.length) {
			var c = tokens == null ? null : tokens.get("code-" + NAMES[k]);
			colors[k] = c != null ? c : base[k];
		}
	}

	// a token class's colour
	public inline function token(cls:Int):Color
		return colors[cls == (TokenClass.Plain : Int) ? FOREGROUND : cls + 1];
}
