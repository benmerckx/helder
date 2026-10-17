package hxmc.theme;

import hxmc.ui.Color;
import hxmc.ui.StyleSheet;

// shadcn/ui's look (MIT, https://ui.shadcn.com): its components' class
// lists, new-york-v4, and its neutral theme's tokens, light and dark
// (shadcn.json; its "shadcn" field names the commit they were copied
// from), as rules made at compile time. Installed as `ui.theme = Shadcn.sheet`.
class Shadcn {
	public static var sheet(get, null):StyleSheet;

	// (made when first read: its colours are parsed then)
	static function get_sheet():StyleSheet {
		if (sheet == null) sheet = Tw.sheet("shadcn.json");
		return sheet;
	}

	// the sheet with tokens of one's own (names without the dashes:
	// "primary", "ring"; CSS colours: "oklch(0.6 0.2 260)", "#2563eb"), the
	// others shadcn's: a new sheet sharing its rules, so that switching
	// between it and others re-resolves their colours
	public static function withTokens(?light:Map<String, String>, ?dark:Map<String, String>):StyleSheet {
		function merged(base:Map<String, Color>, own:Null<Map<String, String>>):Map<String, Color> {
			var m = base.copy();
			if (own != null) for (k => v in own)
				m[k] = Color.parse(v);
			return m;
		}
		var s = sheet;
		return {rules: s.rules, light: merged(s.light, light), dark: merged(s.dark, dark), lengths: s.lengths};
	}
}
