package studio;

import helder.ui.*;

// The studio's look, every value of it here (README.md's "Look"): near
// neutral darks, a hint of cool (the canvas darkest, the panels a step up,
// fields and hovers above), text in three greys, crisp at the top; one blue
// accent for what is current or acts (the selection, its handles, guides,
// focus, Play, the switch's side; the current page, layer, file and tab a
// tint of it, their icons in it); files' icons a quiet hue by kind. The
// panels flush with the window, a hairline between them and the canvas;
// dense: 12-point type, 24-point rows, fields with their label inside;
// hierarchy by weight and grey, not boxes; radii 4 and 6; no shadow but a
// popover's. State changes at once: motion only where something moves
// (the camera, a phone's sheet, Play opening). Hanken Grotesk for the
// interface, Geist Mono for values. Dark first: the sheet's light colours
// are its dark ones until a light theme is made from the same tokens.
class Theme {
	// the fonts (apps/studio/fonts, added at start: Main.fonts)
	public static inline var UI = "Hanken Grotesk";
	public static inline var CODE = "Geist Mono";

	// type: sizes (points) and weights; the phone bar's labels and shortcuts the smallest
	public static inline var BODY = 12;
	public static inline var SMALL = 11;
	public static inline var CAPS = 10;
	public static inline var MEDIUM = 500;
	// the code view's size and line
	public static inline var CODE_SIZE = 12;
	public static inline var CODE_LINE = 18;

	// radii: controls (fields, buttons, rows), what floats (the command
	// field, menus, the prompt bar), a phone's sheet
	public static inline var RADIUS = 4;
	public static inline var RADIUS_M = 6;
	public static inline var RADIUS_L = 10;
	// icons' size (Icons: Lucide's, 24 by 24, drawn at 16, 14 or 12)
	public static inline var ICON = 16;
	public static inline var ICON_S = 14;
	public static inline var ICON_XS = 12;

	// the layout: the panels' widths, the toolbar's height (the sidebar's
	// top row the same: one hairline across), a panel's inset
	public static inline var SIDEBAR = 240;
	public static inline var HEADER = 40;
	public static inline var INSPECTOR = 256;
	public static inline var PAD = 12;
	// a row of the sidebar's tree and layers, an inspector's field, a button
	public static inline var ROW = 24;
	public static inline var LAYER = 22;
	public static inline var FIELD = 24;
	public static inline var BUTTON = 26;
	// on a phone (narrower than helder.ui's md): rows and fields a finger's
	public static inline var TOUCH_ROW = 32;
	public static inline var TOUCH_FIELD = 30;
	public static inline var ASK = 520;
	// the canvas' room kept for the prompt bar (below), the frames' captions (above)
	public static inline var ASK_SPACE = 64;
	public static inline var TITLES = 30;

	// compact: a window narrower than this (a phone, a tablet upright) has
	// its panels as sheets over the canvas (Sheets): a sheet peeking this
	// tall (its handle and its first row), the bar switching them, the top
	// bar (where you are, undo, Play)
	public static inline var COMPACT = 900;
	public static inline var SHEET_PEEK = 84;
	public static inline var BAR = 56;
	public static inline var TOPBAR = 44;

	// the canvas: gaps between screens and flows; the zoom's spring, short
	// (the camera's travel the one motion followed on the desktop)
	public static inline var SCREEN_GAP = 40;
	public static inline var FLOW_GAP = 170;
	public static final ZOOM = helder.ui.motion.Curve.spring(0.3, 0);
	// the selection's handles (white squares edged in the accent)
	public static inline var HANDLE = 7;
	// the one shadow: what pops over (a menu, the command list, a phone's sheet)
	public static inline var POPOVER = "0 12 32 rgba(0,0,0,0.45)";
	public static inline var SHEET_SHADOW = "0 -8 24 rgba(0,0,0,0.35)";

	public static final colors:Map<String, Color> = withKinds(withCode([
		// the darks, near neutral (a hint of cool): the canvas under everything, the cards, fields, hovers, what is pressed
		"canvas" => Color.parse("#0b0b0d"),
		"bg" => Color.parse("#141416"),
		"well" => Color.parse("#1c1c1f"),
		"hover" => Color.parse("#232326"),
		"active" => Color.parse("#2c2c30"),
		// what is current (a file, a layer, a sheet's tab, the switch's side): a tint of the accent
		"on" => Color.parse("rgba(59, 130, 246, 0.16)"),
		"on-hover" => Color.parse("rgba(59, 130, 246, 0.22)"),
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
		// the accent as ink on the darks (a current icon, the switch's word): lighter, to read at 14 points
		"accent-ink" => Color.parse("#7eaaf8"),
		// focus: a ring in the accent
		"focus" => Color.parse("rgba(59, 130, 246, 0.7)"),
		// the selection: the accent; a dark hairline outside it, for a node selected on a light screen
		"sel" => Color.parse("#3b82f6"),
		"sel-soft" => Color.parse("rgba(59, 130, 246, 0.28)"),
		"sel-halo" => Color.parse("rgba(0, 0, 0, 0.45)"),
		// the code's hues, quieter: less saturated, tuned to the neutral darks
		"violet" => Color.parse("#b9aee0"),
		"blue" => Color.parse("#93b0dc"),
		"teal" => Color.parse("#8cc4c4"),
		"green" => Color.parse("#a8c9a0"),
		"orange" => Color.parse("#dfae8c"),
		"sand" => Color.parse("#dcc994"),
		"rose" => Color.parse("#dba7b6"),
		"red" => Color.parse("#ec8383"),
	]));

	// files' icons by kind (FileView.hue): the code's hues, a design's violet,
	// a story's orange, code blue, an image green; folders and the rest grey
	static function withKinds(m:Map<String, Color>):Map<String, Color> {
		var by = [
			"dir" => "fg3", "design" => "violet", "story" => "orange", "code" => "blue", "image" => "green", "font" => "rose", "model" => "teal",
			"audio" => "sand", "other" => "fg3",
		];
		for (k => v in by) m.set("kind-" + k, m.get(v));
		return m;
	}

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
			// a panel flush with the window: the sidebar, the inspector, the code, the toolbar (its edge: a hairline toward the canvas)
			{slot: "panel", style: {background: t("bg"), borderColor: t("line"), overflow: Hidden}},
			// a section: its header (a word, medium), its rows; a hairline above it
			{slot: "section", style: {padding: [8, PAD, PAD], rowGap: 6, borders: [1, 0, 0, 0], borderColor: t("line")}},
			{slot: "section-head", style: {direction: Row, alignItems: Center, columnGap: 6, height: ROW, color: t("fg"), fontWeight: MEDIUM, cursor: Default}},
			// a row of the sidebar (a file, a frame, a layer): data-on, the current one
			{slot: "nav-item", style: {direction: Row, alignItems: Center, columnGap: 6, height: ROW, padding: [0, 8], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "nav-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true"], style: {background: t("on"), color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true", "hover"], style: {background: t("on-hover")}},
			{slot: "nav-item", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: -1, outlineColor: t("focus")}},
			// buttons: an icon or a word, quiet until hovered
			{slot: "button", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 4, height: BUTTON, minWidth: BUTTON, padding: [0, 5],
				radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {color: t("fg"), background: t("hover")}},
			{slot: "button", when: ["data-on=true"], style: {color: t("accent-ink"), background: t("on")}},
			{slot: "button", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("focus")}},
			{slot: "button", when: ["data-disabled=true"], style: {color: t("fg3"), background: Color.TRANSPARENT, cursor: Default}},
			// the accent's button (Play)
			{slot: "primary", style: {direction: Row, alignItems: Center, columnGap: 5, height: BUTTON, padding: [0, 10, 0, 8], radius: RADIUS, background: t("accent"),
				color: t("accent-fg"), fontWeight: MEDIUM, cursor: Pointer}},
			{slot: "primary", when: ["hover"], style: {background: t("accent-hover")}},
			{slot: "primary", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 1, outlineColor: t("focus")}},
			// a segmented control (Design and Code; a story's choices): a well, the current side the accent's tint
			{slot: "seg", style: {direction: Row, padding: 2, columnGap: 2, radius: RADIUS_M, background: t("well")}},
			{slot: "seg-item", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 5, height: FIELD - 2, padding: [0, 8], radius: RADIUS,
				color: t("fg3"), cursor: Pointer}},
			{slot: "seg-item", when: ["hover"], style: {color: t("fg2")}},
			{slot: "seg-item", when: ["data-on=true"], style: {background: t("on"), color: t("accent-ink")}},
			{slot: "seg-item", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("focus")}},
			// the toolbar's command field (secondary-K)
			{slot: "command", style: {direction: Row, alignItems: Center, columnGap: 6, height: BUTTON, padding: [0, 8], radius: RADIUS_M, background: t("well"),
				color: t("fg3"), cursor: Text}},
			{slot: "command", when: ["hover"], style: {background: t("hover")}},
			{slot: "command", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("focus")}},
			{slot: "kbd", style: {color: t("fg3"), fontSize: SMALL}},
			// the inspector's field: its label inside, quiet, left (a number's scrubs it), its value after it (the code's font)
			{slot: "field", style: {direction: Row, alignItems: Center, columnGap: 6, grow: 1, basis: 0, minWidth: 0, height: FIELD, padding: [0, 0, 0, 8], radius: RADIUS,
				background: t("well"), borderWidth: 1, borderColor: Color.TRANSPARENT}},
			{slot: "field", when: ["hover"], style: {background: t("hover")}},
			{slot: "field", when: ["has:focus"], style: {background: t("well"), borderColor: t("accent")}},
			{slot: "field-label", style: {shrink: 0, color: t("fg3"), fontFamily: UI, fontSize: SMALL, cursor: ResizeEW}},
			{slot: "field-input", style: {grow: 1, minWidth: 0, height: FIELD - 2, padding: [0, 8, 0, 0], color: t("fg"), fontFamily: CODE, fontSize: SMALL,
				outlineStyle: None}},
			{slot: "field-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "field-input", when: ["selection"], style: {background: t("sel-soft")}},
			// a row of fields (the inspector's grid: two to a row, or one)
			{slot: "fields", style: {direction: Row, columnGap: 6}},
			// a colour's swatch, inside its field
			{slot: "swatch", style: {width: 12, height: 12, radius: 2, shrink: 0, borderWidth: 1, borderColor: t("edge")}},
			// the prompt bar's line
			{slot: "ask-input", style: {grow: 1, minWidth: 0, color: t("fg"), fontFamily: UI, fontSize: BODY, outlineStyle: None}},
			{slot: "ask-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "ask-input", when: ["selection"], style: {background: t("sel-soft")}},
			// what floats over the canvas: the prompt bar, menus
			{slot: "floating", style: {background: t("bg"), radius: RADIUS_M, borderWidth: 1, borderColor: t("edge")}},
			{slot: "menu-item", style: {direction: Row, alignItems: Center, columnGap: 8, height: ROW + 2, padding: [0, 8], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "menu-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "menu-item", when: ["data-on=true"], style: {background: t("on"), color: t("fg")}},
			{slot: "menu-item", when: ["data-on=true", "hover"], style: {background: t("on-hover")}},
			// a layer's row, a little tighter than the tree's
			{slot: "nav-item", when: ["data-layer=true"], style: {height: LAYER}},
			// on a phone: rows and fields a finger's
			{slot: "nav-item", when: ["not:md"], style: {height: TOUCH_ROW}},
			{slot: "menu-item", when: ["not:md"], style: {height: TOUCH_ROW}},
			{slot: "field", when: ["not:md"], style: {height: TOUCH_FIELD}},
			{slot: "field-input", when: ["not:md"], style: {height: TOUCH_FIELD - 2}},
			{slot: "seg-item", when: ["not:md"], style: {height: TOUCH_FIELD - 2}},
			// compact: a sheet over the canvas, its handle
			{slot: "sheet", style: {background: t("bg"), borderColor: t("edge"), corners: [RADIUS_L, RADIUS_L, 0, 0]}},
			{slot: "sheet-handle", style: {width: 36, height: 4, radius: 2, background: t("edge")}},
			// a frame on the canvas: a faint outline; hovered, the accent's, faint; current, the accent's
			{slot: "screen", style: {radius: 0, background: t("bg"), borderWidth: 1, borderColor: t("line"), overflow: Hidden, cursor: Default}},
			{slot: "screen", when: ["hover"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("sel-soft")}},
			{slot: "screen", when: ["data-on=true"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("sel")}},
		],
		light: colors,
		dark: colors,
	};
}
