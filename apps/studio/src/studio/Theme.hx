package studio;

import helder.ui.*;

// The studio's look, every value of it here (the "Prism" direction, made
// minimal; not signed off, so one place to change): a near-black frame,
// the canvas flush against the sidebar at a hairline, radii of 4 and 6
// points, Hanken Grotesk for the interface and Geist Mono for values, five
// kinds' hues used only as dots and badges, cyan for what is selected.
// One dark look for now: the sheet's light colours are its dark ones.
class Theme {
	// the fonts (apps/studio/fonts, added at start: Main.fonts)
	public static inline var UI = "Hanken Grotesk";
	public static inline var CODE = "Geist Mono";

	// type: sizes (points) and weights
	public static inline var TITLE = 16;
	public static inline var BODY = 13;
	public static inline var LABEL = 11.5;
	public static inline var VALUE = 11.5;
	public static inline var MEDIUM = 500;
	public static inline var SEMIBOLD = 600;

	// radii: small things, floating panels
	public static inline var R1 = 4;
	public static inline var R2 = 6;

	// the layout's sizes
	public static inline var SIDEBAR = 232;
	public static inline var HEADER = 46;
	public static inline var INSPECTOR = 248;
	public static inline var ASK = 560;
	// the canvas' room kept for the prompt bar (below), the flows' titles and captions (above)
	public static inline var ASK_SPACE = 92;
	public static inline var TITLES = 50;

	// the canvas: gaps between screens and flows, a screen's corner, the zoom's spring
	public static inline var SCREEN_GAP = 40;
	public static inline var FLOW_GAP = 170;
	public static inline var SCREEN_RADIUS = 12;
	public static inline var SPRING_STIFFNESS = 210.0;
	public static inline var SPRING_DAMPING = 29.0;

	public static final colors:Map<String, Color> = [
		// neutrals: the frame, panels, raised (floating), wells (fields), hover
		"frame" => Color.parse("#0b0b0d"),
		"panel" => Color.parse("#131316"),
		"raise" => Color.parse("#1a1a1e"),
		"well" => Color.parse("#1f1f24"),
		"hover" => Color.parse("#232328"),
		"line" => Color.parse("rgba(255, 255, 255, 0.07)"),
		"line2" => Color.parse("rgba(255, 255, 255, 0.11)"),
		"fg" => Color.parse("#ececef"),
		"fg2" => Color.parse("#a1a1aa"),
		"fg3" => Color.parse("#6b6b74"),
		"on-fg" => Color.parse("#0b0b0d"),
		"screen-bg" => Color.parse("#0e0f13"),
		"shade" => Color.parse("rgba(0, 0, 0, 0.35)"),
		// selection, focus
		"sel" => Color.parse("oklch(0.80 0.11 215)"),
		"sel-soft" => Color.parse("oklch(0.80 0.11 215 / 18%)"),
		// kinds: a dot or a badge, never a fill
		"k-screen" => Color.parse("oklch(0.80 0.11 215)"),
		"k-comp" => Color.parse("oklch(0.74 0.14 330)"),
		"k-motion" => Color.parse("oklch(0.82 0.12 80)"),
		"k-scene" => Color.parse("oklch(0.78 0.13 155)"),
		"k-video" => Color.parse("oklch(0.72 0.12 285)"),
		"error" => Color.parse("oklch(0.70 0.17 25)"),
	];

	// a token's colour
	public static inline function c(name:String):Color
		return colors.get(name);

	static inline function t(name:String):Color
		return Color.parse('var(--$name)');

	// the studio's parts by slot (markup names a slot; the look is here)
	public static final sheet:StyleSheet = {
		rules: [
			// a sidebar's item: a screen, a view; data-on: the current one
			{slot: "nav-item", style: {direction: Row, alignItems: Center, columnGap: 9, padding: [6, 8], radius: R1, color: t("fg2"), cursor: Pointer}},
			{slot: "nav-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true"], style: {background: t("raise"), color: t("fg")}},
			// a kind's badge (S: a screen), its letter dark on the hue
			{slot: "badge", style: {width: 16, height: 16, radius: 3, alignItems: Center, justify: Center, background: t("k-screen"), color: t("on-fg"),
				fontSize: 10, fontWeight: 600}},
			{slot: "badge", variant: "comp", style: {background: t("k-comp")}},
			{slot: "badge", variant: "motion", style: {background: t("k-motion")}},
			{slot: "badge", variant: "scene", style: {background: t("k-scene")}},
			{slot: "badge", variant: "video", style: {background: t("k-video")}},
			// buttons: outlined, primary (light on dark), quiet
			{slot: "button", style: {direction: Row, alignItems: Center, columnGap: 6, padding: [5, 11], radius: R1, color: t("fg2"), borderWidth: 1,
				borderColor: t("line2"), fontSize: 12.5, cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {color: t("fg"), background: t("hover")}},
			{slot: "button", variant: "primary", style: {background: t("fg"), color: t("on-fg"), borderColor: Color.TRANSPARENT, fontWeight: 500}},
			{slot: "button", variant: "primary", when: ["hover"], style: {background: t("fg2")}},
			{slot: "button", when: ["data-disabled=true"], style: {color: t("fg3"), cursor: Default}},
			// the segmented control (Design, Code)
			{slot: "seg", style: {direction: Row, columnGap: 2, padding: 2, radius: 5, background: t("well")}},
			{slot: "seg-item", style: {padding: [3, 10], radius: 3, color: t("fg3"), fontSize: 12, cursor: Pointer}},
			{slot: "seg-item", when: ["data-on=true"], style: {background: t("hover"), color: t("fg")}},
			// a value's field (the inspector's): its label in the interface's font, the value in the code's
			{slot: "field", style: {direction: Row, alignItems: Center, columnGap: 7, padding: [5, 8], radius: R1, background: t("well"), color: t("fg"),
				fontFamily: CODE, fontSize: VALUE}},
			{slot: "field", when: ["has:focus"], style: {borderWidth: 1.2, borderColor: t("sel")}},
			{slot: "field-label", style: {color: t("fg3"), fontFamily: UI, fontSize: 11, cursor: ResizeEW}},
			{slot: "field-input", style: {grow: 1, minWidth: 0, color: t("fg"), fontFamily: CODE, fontSize: VALUE}},
			{slot: "field-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "field-input", when: ["selection"], style: {background: t("sel-soft")}},
			// what floats: the inspector, the prompt bar
			{slot: "floating", style: {background: t("raise"), borderWidth: 1, borderColor: t("line"), radius: R2}},
			{slot: "ask", style: {background: t("raise"), borderWidth: 1, borderColor: t("line2"), radius: R2, shadow: Shadow.parse("0 10 30 rgba(0, 0, 0, 0.35)")}},
			// a screen on the canvas: its frame, hovered and current outlined in the selection's hue
			{slot: "screen", style: {radius: SCREEN_RADIUS, background: t("screen-bg"), borderWidth: 1, borderColor: t("line2"), overflow: Hidden, cursor: Pointer,
				shadow: Shadow.parse("0 12 30 rgba(0, 0, 0, 0.35)")}},
			{slot: "screen", when: ["hover"], style: {borderColor: t("sel"), borderWidth: 1.5}},
			{slot: "screen", when: ["data-on=true"], style: {borderColor: t("sel"), borderWidth: 1.5, cursor: Crosshair}},
		],
		light: colors,
		dark: colors,
		lengths: ["r1" => R1, "r2" => R2],
	};
}
