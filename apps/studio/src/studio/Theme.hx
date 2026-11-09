package studio;

import helder.ui.*;

// The studio's look, every value of it here, so the design is refined in
// one place. For now a wireframe: one neutral grey ramp, no hues, text in
// three greys, hairlines only between regions, no gradients or shadows,
// what is selected or focused outlined in near-white. Hanken Grotesk for
// the interface, Geist Mono for values; one body size, one small size,
// regular and medium. One dark look for now: the sheet's light colours are
// its dark ones.
class Theme {
	// the fonts (apps/studio/fonts, added at start: Main.fonts)
	public static inline var UI = "Hanken Grotesk";
	public static inline var CODE = "Geist Mono";

	// type: sizes (points) and weights
	public static inline var BODY = 13;
	public static inline var SMALL = 11.5;
	public static inline var MEDIUM = 500;

	// the one radius (fields, buttons, the screens' corners)
	public static inline var RADIUS = 3;

	// the layout's sizes
	public static inline var SIDEBAR = 220;
	public static inline var HEADER = 44;
	public static inline var INSPECTOR = 240;
	// the layers' panel (a design's frame zoomed into), a row of it
	public static inline var LAYERS = 200;
	public static inline var LAYER = 22;
	public static inline var ASK = 520;
	// the canvas' room kept for the prompt bar (below), the flows' titles and captions (above)
	public static inline var ASK_SPACE = 72;
	public static inline var TITLES = 50;

	// compact: a window narrower than this (a phone, a tablet upright) has
	// the screens' list as a drawer and the inspector as a bottom sheet,
	// SHEET tall open, SHEET_PEEK closed (its handle and the selection's name)
	public static inline var COMPACT = 900;
	public static inline var SHEET = 300;
	public static inline var SHEET_PEEK = 52;
	public static inline var DRAWER = 260;

	// the canvas: gaps between screens and flows, the zoom's spring
	public static inline var SCREEN_GAP = 40;
	public static inline var FLOW_GAP = 170;
	// (SwiftUI's duration and bounce: stiffness 210 and damping 29, as it was integrated)
	public static final ZOOM = helder.ui.motion.Curve.spring(0.43, 0);

	public static final colors:Map<String, Color> = withCode([
		// greys:the chrome (sidebar, header, panels), the canvas under the screens, fields, hover
		"bg" => Color.parse("#141414"),
		"canvas" => Color.parse("#0e0e0e"),
		"well" => Color.parse("#1c1c1c"),
		"hover" => Color.parse("#222222"),
		// hairlines: between regions; a screen's outline
		"line" => Color.parse("rgba(255, 255, 255, 0.08)"),
		"edge" => Color.parse("rgba(255, 255, 255, 0.16)"),
		// text: primary, secondary, quiet
		"fg" => Color.parse("#e6e6e6"),
		"fg2" => Color.parse("#9a9a9a"),
		"fg3" => Color.parse("#636363"),
		// selection, focus: near-white; a dark hairline outside it, for a node selected on a light screen
		"sel" => Color.parse("rgba(255, 255, 255, 0.72)"),
		"sel-soft" => Color.parse("rgba(255, 255, 255, 0.10)"),
		"sel-halo" => Color.parse("rgba(0, 0, 0, 0.55)"),
		// under a drawer over the canvas
		"scrim" => Color.parse("rgba(0, 0, 0, 0.5)"),
	]);

	// the code view's colours (helder.ui.code's CodeTheme tokens) from the same greys: its
	// words in the three text greys, its selection and marks the selection's, no hues
	static function withCode(m:Map<String, Color>):Map<String, Color> {
		var by = [
			"background" => "bg", "gutter" => "bg", "panel" => "bg", "tooltip" => "well", "current-line" => "well", "panel-border" => "line",
			"indent-guide" => "line", "whitespace" => "fg3", "foreground" => "fg", "keyword" => "fg", "tag" => "fg", "type" => "fg", "function" => "fg",
			"string" => "fg2", "number" => "fg2", "attribute" => "fg2", "comment" => "fg3", "punctuation" => "fg3", "line-number" => "fg3",
			"line-number-active" => "fg2", "cursor" => "fg", "selection" => "sel-soft", "find-match" => "sel-soft", "find-current" => "edge",
			"error" => "fg", "warning" => "fg2", "info" => "fg3",
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
			// a sidebar's item: a screen, a view; data-on: the current one
			{slot: "nav-item", style: {direction: Row, alignItems: Center, padding: [5, 8], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "nav-item", when: ["hover"], style: {color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true"], style: {background: t("well"), color: t("fg")}},
			// buttons: quiet, their icon or text alone
			{slot: "button", style: {direction: Row, alignItems: Center, padding: [5, 7], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {color: t("fg"), background: t("hover")}},
			{slot: "button", when: ["data-disabled=true"], style: {color: t("fg3"), background: Color.TRANSPARENT, cursor: Default}},
			// the switch (Design, Code): text, the current one in the primary grey
			{slot: "seg", style: {direction: Row, columnGap: 2}},
			{slot: "seg-item", style: {padding: [3, 8], radius: RADIUS, color: t("fg3"), cursor: Pointer}},
			{slot: "seg-item", when: ["hover"], style: {color: t("fg2")}},
			{slot: "seg-item", when: ["data-on=true"], style: {background: t("well"), color: t("fg")}},
			// the inspector's row: its label, its value in the code's font
			{slot: "field", style: {direction: Row, alignItems: Center, columnGap: 8, padding: [4, 0], color: t("fg"), fontFamily: CODE, fontSize: SMALL}},
			{slot: "field-label", style: {width: 56, shrink: 0, color: t("fg3"), fontFamily: UI, fontSize: SMALL, cursor: ResizeEW}},
			{slot: "field-input", style: {grow: 1, minWidth: 0, padding: [3, 6], radius: RADIUS, borderWidth: 1, borderColor: Color.TRANSPARENT, color: t("fg"),
				fontFamily: CODE, fontSize: SMALL}},
			{slot: "field-input", when: ["hover"], style: {background: t("well")}},
			{slot: "field-input", when: ["focus"], style: {background: t("well"), borderWidth: 1, borderColor: t("sel")}},
			{slot: "field-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "field-input", when: ["selection"], style: {background: t("sel-soft")}},
			// the prompt bar's line
			{slot: "ask-input", style: {grow: 1, minWidth: 0, color: t("fg"), fontFamily: UI, fontSize: BODY}},
			{slot: "ask-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "ask-input", when: ["selection"], style: {background: t("sel-soft")}},
			// what floats over the canvas: the inspector, the prompt bar
			{slot: "floating", style: {background: t("bg"), borderWidth: 1, borderColor: t("line")}},
			// compact: the inspector's bottom sheet (a hairline above it), its handle; the screens' drawer
			{slot: "sheet", style: {background: t("bg"), borderColor: t("line")}},
			{slot: "sheet-handle", style: {width: 36, height: 4, radius: 2, background: t("edge")}},
			{slot: "drawer", style: {background: t("bg"), borderColor: t("line")}},
			// a screen on the canvas: a thin outline; hovered and current ringed a little outside it (its program's own edge may be light)
			{slot: "screen", style: {radius: RADIUS, background: t("bg"), borderWidth: 1, borderColor: t("edge"), overflow: Hidden, cursor: Pointer}},
			{slot: "screen", when: ["hover"], style: {outlineWidth: 1, outlineOffset: 4, outlineColor: t("edge")}},
			{slot: "screen", when: ["data-on=true"], style: {outlineWidth: 1, outlineOffset: 4, outlineColor: t("sel"), cursor: Crosshair}},
		],
		light: colors,
		dark: colors,
	};
}
