package hxmc.ui.widgets;

// lucide's icons (ISC) by name: what the neutral element icon's name
// draws (<icon name="check"/>), each the markup inside an <svg> of 24 by
// 24, stroked (currentColor, 2 wide, round). ui's an Svg (svg), parsed once;
// a page's its inline <svg>'s content (hxmc.web.Neutral)
class Icons {
	// the <svg> an icon's markup goes in (a page's: NeutralMacro's element)
	public static inline var OPEN = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">';

	public static function markup(name:String):String
		return switch name {
			case "check": '<path d="M20 6 9 17l-5-5"/>';
			case "minus": '<path d="M5 12h14"/>';
			case "x": '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>';
			case "chevron-down": '<path d="m6 9 6 6 6-6"/>';
			case "chevron-right": '<path d="m9 18 6-6-6-6"/>';
			case "chevron-left": '<path d="m15 18-6-6 6-6"/>';
			case "search": '<path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/>';
			case "loader": '<path d="M21 12a9 9 0 1 1-6.219-8.56"/>';
			case "more": '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>';
			case "arrow-left": '<path d="m12 19-7-7 7-7"/><path d="M19 12H5"/>';
			case "arrow-right": '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>';
			case "circle": '<circle cx="12" cy="12" r="10"/>';
			case "panel-left": '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/>';
			case "folder": '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>';
			case _: throw 'hxmc.ui: no icon named "$name" (Icons)';
		}

	static var parsed:Null<Map<String, Svg>> = null;

	// an icon as ui draws it
	public static function svg(name:String):Svg {
		if (parsed == null) parsed = [];
		var s = parsed.get(name);
		if (s == null) parsed.set(name, s = Svg.parse(OPEN + markup(name) + "</svg>"));
		return s;
	}
}
