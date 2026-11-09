package studio;

import helder.ui.*;

// The studio's look, every value of it here (README.md's "Look"): near
// neutral darks, a hint of cool (the canvas darkest, the cards a step up,
// fields and hovers above), text in three greys, crisp at the top; one blue
// accent kept for few things (the selection, its handles, guides, focus,
// Play), the current page, layer and file a lighter fill; the sidebar, the inspector and the toolbar's fields as
// cards inset over the canvas, edged by faint hairlines; radii 6, 8 and
// 12; titles medium. Hanken Grotesk for the interface, Geist Mono for
// values. Dark first: the sheet's light colours are its dark ones until a
// light theme is made from the same tokens.
class Theme {
	// the fonts (apps/studio/fonts, added at start: Main.fonts)
	public static inline var UI = "Hanken Grotesk";
	public static inline var CODE = "Geist Mono";

	// type: sizes (points) and weights; a section's header in small capitals
	public static inline var BODY = 13;
	public static inline var SMALL = 11.5;
	public static inline var CAPS = 10.5;
	public static inline var MEDIUM = 500;

	// radii: controls (fields, buttons, rows), the canvas' frames and menus, cards
	public static inline var RADIUS = 6;
	public static inline var RADIUS_M = 8;
	public static inline var RADIUS_L = 12;
	// icons' size (Icons: Lucide's, 24 by 24, drawn at 16 or 14)
	public static inline var ICON = 16;
	public static inline var ICON_S = 14;

	// the layout: the cards' gap to the window and each other, the sidebar's
	// and the inspector's widths, the toolbar's height
	public static inline var GAP = 8;
	public static inline var SIDEBAR = 248;
	public static inline var HEADER = 44;
	public static inline var INSPECTOR = 264;
	// a row of the sidebar's tree and layers
	public static inline var ROW = 26;
	public static inline var LAYER = 24;
	public static inline var ASK = 520;
	// the canvas' room kept for the prompt bar (below), the frames' captions (above)
	public static inline var ASK_SPACE = 72;
	public static inline var TITLES = 30;

	// compact: a window narrower than this (a phone, a tablet upright) has
	// its panels as sheets over the canvas (Sheets): a sheet peeking this
	// tall (its handle and its first row), the bar switching them, the top
	// bar (where you are, undo, Play)
	public static inline var COMPACT = 900;
	public static inline var SHEET_PEEK = 84;
	public static inline var BAR = 60;
	public static inline var TOPBAR = 48;

	// the canvas: gaps between screens and flows, the zoom's spring
	public static inline var SCREEN_GAP = 40;
	public static inline var FLOW_GAP = 170;
	// (SwiftUI's duration and bounce: stiffness 210 and damping 29, as it was integrated)
	public static final ZOOM = helder.ui.motion.Curve.spring(0.43, 0);

	public static final colors:Map<String, Color> = withCode([
		// the darks, near neutral (a hint of cool): the canvas under everything, the cards, fields, hovers, what is pressed
		"canvas" => Color.parse("#0b0b0d"),
		"bg" => Color.parse("#141416"),
		"well" => Color.parse("#1c1c1f"),
		"hover" => Color.parse("#232326"),
		"active" => Color.parse("#2c2c30"),
		// what is current (a file, a layer, a sheet's tab): a lighter fill, not the accent
		"on" => Color.parse("rgba(255, 255, 255, 0.09)"),
		// hairlines: a card's edge, between sections; a frame's outline
		"line" => Color.parse("rgba(255, 255, 255, 0.07)"),
		"edge" => Color.parse("rgba(255, 255, 255, 0.14)"),
		// text: primary, secondary, quiet (greys, near white at the top)
		"fg" => Color.parse("#f0f0f2"),
		"fg2" => Color.parse("#a3a3aa"),
		"fg3" => Color.parse("#66666d"),
		// the accent, kept for few things: the selection, its handles, focus, Play; soft, its fill behind text; on it, white
		"accent" => Color.parse("#3b82f6"),
		"accent-hover" => Color.parse("#4b8ef7"),
		"accent-soft" => Color.parse("rgba(59, 130, 246, 0.16)"),
		"accent-fg" => Color.parse("#ffffff"),
		// the selection: the accent; a dark hairline outside it, for a node selected on a light screen
		"sel" => Color.parse("#3b82f6"),
		"sel-soft" => Color.parse("rgba(59, 130, 246, 0.28)"),
		"sel-halo" => Color.parse("rgba(0, 0, 0, 0.45)"),
		// under what covers the canvas; a card's shadow
		"scrim" => Color.parse("rgba(4, 4, 6, 0.6)"),
		"shade" => Color.parse("rgba(0, 0, 0, 0.4)"),
		// the code's hues, quieter: less saturated, tuned to the neutral darks
		"violet" => Color.parse("#b9aee0"),
		"blue" => Color.parse("#93b0dc"),
		"teal" => Color.parse("#8cc4c4"),
		"green" => Color.parse("#a8c9a0"),
		"orange" => Color.parse("#dfae8c"),
		"sand" => Color.parse("#dcc994"),
		"rose" => Color.parse("#dba7b6"),
		"red" => Color.parse("#ec8383"),
	]);

	// the code view's colours (helder.ui.code's CodeTheme tokens): its chrome the
	// studio's darks, its words in the code's hues, its selection and marks the accent's
	static function withCode(m:Map<String, Color>):Map<String, Color> {
		var by = [
			"background" => "bg", "gutter" => "bg", "panel" => "bg", "tooltip" => "well", "current-line" => "well", "panel-border" => "line",
			"indent-guide" => "line", "whitespace" => "fg3", "foreground" => "fg", "keyword" => "violet", "tag" => "blue", "type" => "sand", "function" => "teal",
			"string" => "green", "number" => "orange", "attribute" => "rose", "comment" => "fg3", "punctuation" => "fg2", "line-number" => "fg3",
			"line-number-active" => "fg2", "cursor" => "accent", "selection" => "sel-soft", "find-match" => "accent-soft", "find-current" => "sel",
			"error" => "red", "warning" => "sand", "info" => "fg3",
		];
		for (k => v in by) m.set("code-" + k, m.get(v));
		return m;
	}

	// a token's colour
	public static inline function c(name:String):Color
		return colors.get(name);

	static inline function t(name:String):Color
		return Color.parse('var(--$name)');

	// the studio's parts by slot (markup names a slot; the look is here)
	public static final sheet:StyleSheet = {
		rules: [
			// a card over the canvas: the sidebar, the inspector, the code
			{slot: "card", style: {background: t("bg"), radius: RADIUS_L, borderWidth: 1, borderColor: t("line"), overflow: Hidden}},
			// a section: its header (an icon, small capitals), its rows (a label left, a value right)
			{slot: "section", style: {padding: [10, 12, 8], rowGap: 2, borders: [1, 0, 0, 0], borderColor: t("line")}},
			{slot: "section-head", style: {direction: Row, alignItems: Center, columnGap: 7, padding: [2, 0, 6], color: t("fg3"), fontSize: CAPS,
				fontWeight: MEDIUM, letterSpacing: 0.7, textTransform: Uppercase, cursor: Default}},
			// a row of the sidebar (a file, a frame, a layer): data-on, the current one
			{slot: "nav-item", style: {direction: Row, alignItems: Center, columnGap: 7, height: ROW, padding: [0, 8], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "nav-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true"], style: {background: t("on"), color: t("fg")}},
			// buttons: an icon or a word, quiet until hovered
			{slot: "button", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 6, height: 28, minWidth: 28, padding: [0, 7], radius: RADIUS,
				color: t("fg2"), cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {color: t("fg"), background: t("hover")}},
			{slot: "button", when: ["data-on=true"], style: {color: t("fg"), background: t("active")}},
			{slot: "button", when: ["data-disabled=true"], style: {color: t("fg3"), background: Color.TRANSPARENT, cursor: Default}},
			// the accent's button (Play)
			{slot: "primary", style: {direction: Row, alignItems: Center, columnGap: 6, height: 28, padding: [0, 11, 0, 9], radius: RADIUS, background: t("accent"),
				color: t("accent-fg"), fontWeight: MEDIUM, cursor: Pointer}},
			{slot: "primary", when: ["hover"], style: {background: t("accent-hover")}},
			// the switch (Design, Code): a well, the current one raised
			{slot: "seg", style: {direction: Row, padding: 2, columnGap: 2, radius: RADIUS_M, background: t("well")}},
			{slot: "seg-item", style: {direction: Row, alignItems: Center, columnGap: 6, height: 24, padding: [0, 9], radius: RADIUS, color: t("fg3"), cursor: Pointer}},
			{slot: "seg-item", when: ["hover"], style: {color: t("fg2")}},
			{slot: "seg-item", when: ["data-on=true"], style: {background: t("active"), color: t("fg")}},
			// the toolbar's command field (secondary-K)
			{slot: "command", style: {direction: Row, alignItems: Center, columnGap: 8, height: 30, padding: [0, 10], radius: RADIUS_M, background: t("well"),
				borderWidth: 1, borderColor: t("line"), color: t("fg3"), cursor: Text}},
			{slot: "command", when: ["hover"], style: {borderColor: t("edge")}},
			{slot: "kbd", style: {padding: [1, 5], radius: 4, background: t("hover"), color: t("fg3"), fontSize: CAPS}},
			// the inspector's row: its label left, its value right (the code's font)
			{slot: "field", style: {direction: Row, alignItems: Center, columnGap: 8, height: 28, color: t("fg"), fontFamily: CODE, fontSize: SMALL}},
			{slot: "field-label", style: {width: 64, shrink: 0, color: t("fg2"), fontFamily: UI, fontSize: SMALL, cursor: ResizeEW}},
			{slot: "field-input", style: {grow: 1, minWidth: 0, height: 26, padding: [0, 8], radius: RADIUS, borderWidth: 1, borderColor: Color.TRANSPARENT,
				background: t("well"), color: t("fg"), fontFamily: CODE, fontSize: SMALL, textAlign: Right}},
			{slot: "field-input", when: ["hover"], style: {background: t("hover")}},
			{slot: "field-input", when: ["focus"], style: {background: t("well"), borderColor: t("accent")}},
			{slot: "field-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "field-input", when: ["selection"], style: {background: t("sel-soft")}},
			// the prompt bar's line
			{slot: "ask-input", style: {grow: 1, minWidth: 0, color: t("fg"), fontFamily: UI, fontSize: BODY}},
			{slot: "ask-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "ask-input", when: ["selection"], style: {background: t("sel-soft")}},
			// what floats over the canvas: the prompt bar, menus
			{slot: "floating", style: {background: t("bg"), radius: RADIUS_L, borderWidth: 1, borderColor: t("edge")}},
			{slot: "menu-item", style: {direction: Row, alignItems: Center, columnGap: 8, height: 30, padding: [0, 10], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "menu-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "menu-item", when: ["data-on=true"], style: {background: t("on"), color: t("fg")}},
			// compact: a sheet over the canvas, its handle
			{slot: "sheet", style: {background: t("bg"), borderColor: t("edge"), corners: [RADIUS_L, RADIUS_L, 0, 0]}},
			{slot: "sheet-handle", style: {width: 36, height: 4, radius: 2, background: t("edge")}},
			// a frame on the canvas: a faint outline; hovered, the accent's, faint; current, the accent's
			{slot: "screen", style: {radius: 2, background: t("bg"), borderWidth: 1, borderColor: t("line"), overflow: Hidden, cursor: Default}},
			{slot: "screen", when: ["hover"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("sel-soft")}},
			{slot: "screen", when: ["data-on=true"], style: {outlineWidth: 2, outlineOffset: 0, outlineColor: t("sel")}},
		],
		light: colors,
		dark: colors,
	};
}
