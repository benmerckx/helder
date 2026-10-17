package hxmc.theme;

// shadcn/ui's look (MIT, https://ui.shadcn.com): its components' class
// lists, new-york-v4, and its neutral theme's tokens, light and dark
// (shadcn.json; its "shadcn" field names the commit they were copied
// from), as rules made at compile time. Installed as `ui.theme = Shadcn.sheet`.
class Shadcn {
	public static var sheet(get, null):hxmc.ui.StyleSheet;

	// (made when first read: its colours are parsed then)
	static function get_sheet():hxmc.ui.StyleSheet {
		if (sheet == null) sheet = Tw.sheet("shadcn.json");
		return sheet;
	}
}
