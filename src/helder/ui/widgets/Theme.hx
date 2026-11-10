package helder.ui.widgets;

import helder.ui.*;

// helder's default look for the widgets, the studio's (apps/studio's
// Theme): near neutral darks with a hint of cool, the window's base the
// darkest, panels a step up, fields and hovers above; text in three
// greys; one blue accent for what is current or acts (the selection,
// focus, the primary button), a tint of it for the current row; hairlines
// between panels, hierarchy by weight and grey rather than boxes; dense
// (12-point type, 24-point rows, 26-point buttons), radii 4 and 6, no
// shadow but what floats. State changes at once. The fonts are named, not
// bundled: Hanken Grotesk for the interface, Geist Mono for values (an app
// adds them, or the system's stand in). Light and dark from the same
// tokens: in light the page is the lightest level and panels sit on a
// faint grey canvas, the accent a shade deeper to keep its contrast. The
// sheet's colours follow the window's appearance; c's, which markup reads
// inline, follow appearance (an app points it at its windows': UiWindow.dark).
//
// Its parts by slot (a field's and its input's variant "tall": several
// lines, as tall as the text): "panel", "section", "section-head", "nav-item"
// (data-on: current), "button" (data-on, data-disabled), "primary", "seg"
// and "seg-item", "field" with "field-label" and "field-input", "input",
// "floating", "menu-item", "kbd", "badge", "rule" (a field's data-error:
// its edge red); DataGrid's colours
// (grid-*), its editor ("grid-editor") and the code view's (code-*).
class Theme {
	public static inline var UI = "Hanken Grotesk";
	public static inline var CODE = "Geist Mono";

	public static inline var BODY = 12;
	public static inline var SMALL = 11;
	public static inline var MEDIUM = 500;

	public static inline var RADIUS = 4;
	public static inline var RADIUS_M = 6;
	public static inline var ICON = 16;
	public static inline var ICON_S = 14;

	public static inline var HEADER = 40;
	public static inline var PAD = 12;
	public static inline var ROW = 24;
	public static inline var FIELD = 24;
	public static inline var BUTTON = 26;
	public static inline var POPOVER = "0 12 32 rgba(0,0,0,0.45)";

	public static final dark:Map<String, Color> = derived([
		"canvas" => Color.parse("#0b0b0d"),
		"bg" => Color.parse("#141416"),
		"well" => Color.parse("#1c1c1f"),
		"hover" => Color.parse("#232326"),
		"active" => Color.parse("#2c2c30"),
		"on" => Color.parse("rgba(59, 130, 246, 0.16)"),
		"on-hover" => Color.parse("rgba(59, 130, 246, 0.22)"),
		"line" => Color.parse("rgba(255, 255, 255, 0.07)"),
		"edge" => Color.parse("rgba(255, 255, 255, 0.14)"),
		"fg" => Color.parse("#f0f0f2"),
		"fg2" => Color.parse("#a3a3aa"),
		"fg3" => Color.parse("#66666d"),
		"accent" => Color.parse("#3b82f6"),
		"accent-hover" => Color.parse("#4b8ef7"),
		"accent-soft" => Color.parse("rgba(59, 130, 246, 0.16)"),
		"accent-fg" => Color.parse("#ffffff"),
		"accent-ink" => Color.parse("#7eaaf8"),
		"focus" => Color.parse("rgba(59, 130, 246, 0.7)"),
		"sel" => Color.parse("#3b82f6"),
		"sel-soft" => Color.parse("rgba(59, 130, 246, 0.28)"),
		// status: kept for status, with a word beside it
		"green" => Color.parse("#a8c9a0"),
		"sand" => Color.parse("#dcc994"),
		"red" => Color.parse("#ec8383"),
		"violet" => Color.parse("#b9aee0"),
		"blue" => Color.parse("#93b0dc"),
		"teal" => Color.parse("#8cc4c4"),
		"orange" => Color.parse("#dfae8c"),
		"rose" => Color.parse("#dba7b6"),
		"edited" => Color.parse("rgba(220, 201, 148, 0.13)"),
		"added" => Color.parse("rgba(168, 201, 160, 0.10)"),
		"deleted" => Color.parse("rgba(236, 131, 131, 0.10)"),
	]);

	public static final light:Map<String, Color> = derived([
		"canvas" => Color.parse("#f3f3f5"),
		"bg" => Color.parse("#ffffff"),
		"well" => Color.parse("#f3f3f5"),
		"hover" => Color.parse("#ececef"),
		"active" => Color.parse("#e3e3e7"),
		"on" => Color.parse("rgba(37, 99, 235, 0.10)"),
		"on-hover" => Color.parse("rgba(37, 99, 235, 0.15)"),
		"line" => Color.parse("rgba(0, 0, 0, 0.08)"),
		"edge" => Color.parse("rgba(0, 0, 0, 0.14)"),
		"fg" => Color.parse("#18181b"),
		"fg2" => Color.parse("#55555e"),
		"fg3" => Color.parse("#8e8e97"),
		"accent" => Color.parse("#2563eb"),
		"accent-hover" => Color.parse("#1d58d8"),
		"accent-soft" => Color.parse("rgba(37, 99, 235, 0.10)"),
		"accent-fg" => Color.parse("#ffffff"),
		"accent-ink" => Color.parse("#1d4ed8"),
		"focus" => Color.parse("rgba(37, 99, 235, 0.6)"),
		"sel" => Color.parse("#2563eb"),
		"sel-soft" => Color.parse("rgba(37, 99, 235, 0.20)"),
		"green" => Color.parse("#2f7d3b"),
		"sand" => Color.parse("#9a7310"),
		"red" => Color.parse("#c2393a"),
		"violet" => Color.parse("#6c4fb3"),
		"blue" => Color.parse("#2f5ea8"),
		"teal" => Color.parse("#1d7676"),
		"orange" => Color.parse("#ad5a1c"),
		"rose" => Color.parse("#a84469"),
		"edited" => Color.parse("rgba(214, 160, 20, 0.14)"),
		"added" => Color.parse("rgba(47, 160, 70, 0.09)"),
		"deleted" => Color.parse("rgba(220, 50, 50, 0.07)"),
	]);

	// whether the colours given inline are the dark ones (read by c: a hole
	// that reads it follows it)
	public static var appearance:() -> Bool = () -> true;

	// (the grid's and the code view's tokens, from the ones above)
	static function derived(m:Map<String, Color>):Map<String, Color> {
		var grid = [
			"background" => "bg", "foreground" => "fg", "muted" => "fg3", "line" => "line", "header" => "bg", "header-foreground" => "fg2", "gutter" => "bg",
			"hover" => "well", "selection" => "accent-soft", "cursor" => "accent", "edited" => "edited", "added" => "added", "deleted" => "deleted",
			"skeleton" => "hover", "scrollbar" => "edge", "resize" => "accent",
		];
		for (k => v in grid) m.set("grid-" + k, m.get(v));
		var code = [
			"background" => "bg", "gutter" => "bg", "panel" => "bg", "tooltip" => "well", "current-line" => "well", "panel-border" => "line",
			"indent-guide" => "line", "whitespace" => "fg3", "foreground" => "fg", "keyword" => "violet", "tag" => "blue", "type" => "sand", "function" => "teal",
			"string" => "green", "number" => "orange", "attribute" => "rose", "comment" => "fg3", "punctuation" => "fg2", "line-number" => "fg3",
			"line-number-active" => "fg2", "cursor" => "accent", "selection" => "sel-soft", "find-match" => "accent-soft", "find-current" => "sel",
			"error" => "red", "warning" => "sand", "info" => "fg3",
		];
		for (k => v in code) m.set("code-" + k, m.get(v));
		return m;
	}

	public static function c(name:String):Color
		return (appearance() ? dark : light).get(name);

	// the one shadow, of what floats
	public static function popover():String
		return appearance() ? POPOVER : "0 10 28 rgba(0,0,0,0.14)";

	static inline function t(name:String):Color
		return Color.parse('var(--$name)');

	public static final sheet:StyleSheet = {
		rules: [
			{slot: "body", style: {background: t("canvas"), color: t("fg"), fontFamily: UI, fontSize: BODY}},
			{slot: "panel", style: {background: t("bg"), borderColor: t("line"), overflow: Hidden}},
			{slot: "rule", style: {background: t("line")}},
			{slot: "section", style: {padding: [8, PAD, PAD], rowGap: 6, borders: [1, 0, 0, 0], borderColor: t("line")}},
			{slot: "section-head", style: {direction: Row, alignItems: Center, columnGap: 6, height: ROW, color: t("fg3"), fontWeight: MEDIUM, cursor: Default}},
			{slot: "nav-item", style: {direction: Row, alignItems: Center, columnGap: 6, height: ROW, padding: [0, 8], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "nav-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true"], style: {background: t("on"), color: t("fg")}},
			{slot: "nav-item", when: ["data-on=true", "hover"], style: {background: t("on-hover")}},
			{slot: "nav-item", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: -1, outlineColor: t("focus")}},
			{slot: "button", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 5, height: BUTTON, minWidth: BUTTON, padding: [0, 7],
				radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "button", when: ["hover"], style: {color: t("fg"), background: t("hover")}},
			{slot: "button", when: ["data-on=true"], style: {color: t("accent-ink"), background: t("on")}},
			{slot: "button", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("focus")}},
			{slot: "button", when: ["data-disabled=true"], style: {color: t("fg3"), background: Color.TRANSPARENT, cursor: Default}},
			{slot: "primary", style: {direction: Row, alignItems: Center, columnGap: 5, height: BUTTON, padding: [0, 10], radius: RADIUS, background: t("accent"),
				color: t("accent-fg"), fontWeight: MEDIUM, cursor: Pointer}},
			{slot: "primary", when: ["hover"], style: {background: t("accent-hover")}},
			{slot: "primary", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 1, outlineColor: t("focus")}},
			{slot: "seg", style: {direction: Row, padding: 2, columnGap: 2, radius: RADIUS_M, background: t("well")}},
			{slot: "seg-item", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 5, height: FIELD - 2, padding: [0, 9], radius: RADIUS,
				color: t("fg3"), cursor: Pointer}},
			{slot: "seg-item", when: ["hover"], style: {color: t("fg2")}},
			{slot: "seg-item", when: ["data-on=true"], style: {background: t("on"), color: t("accent-ink")}},
			{slot: "seg-item", when: ["focus-visible"], style: {outlineWidth: 1, outlineOffset: 0, outlineColor: t("focus")}},
			{slot: "field", style: {direction: Row, alignItems: Center, columnGap: 6, minWidth: 0, height: FIELD, padding: [0, 0, 0, 8], radius: RADIUS,
				background: t("well"), borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Text}},
			{slot: "field", when: ["hover"], style: {background: t("hover")}},
			{slot: "field", when: ["has:focus"], style: {background: t("well"), borderColor: t("accent")}},
			{slot: "field", when: ["data-error=true"], style: {borderColor: t("red")}},
			// a field of several lines: as tall as its text, its label at the top
			{slot: "field", variant: "tall", style: {height: DimValue.Auto, minHeight: FIELD, alignItems: Start, padding: [3, 0, 3, 8]}},
			{slot: "field-label", style: {shrink: 0, color: t("fg3"), fontFamily: UI, fontSize: SMALL}},
			{slot: "field-input", style: {grow: 1, minWidth: 0, height: FIELD - 2, padding: [0, 8, 0, 0], color: t("fg"), fontFamily: CODE, fontSize: SMALL,
				outlineStyle: None}},
			{slot: "field-input", variant: "tall", style: {height: DimValue.Auto, fieldSizing: Content, padding: [1, 8, 1, 0]}},
			{slot: "field-input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "field-input", when: ["selection"], style: {background: t("sel-soft")}},
			{slot: "input", style: {grow: 1, minWidth: 0, color: t("fg"), outlineStyle: None}},
			{slot: "input", when: ["placeholder"], style: {color: t("fg3")}},
			{slot: "input", when: ["selection"], style: {background: t("sel-soft")}},
			{slot: "floating", style: {background: t("bg"), radius: RADIUS_M, borderWidth: 1, borderColor: t("edge"), padding: 4}},
			{slot: "menu-item", style: {direction: Row, alignItems: Center, columnGap: 8, height: ROW + 2, padding: [0, 8], radius: RADIUS, color: t("fg2"), cursor: Pointer}},
			{slot: "menu-item", when: ["hover"], style: {background: t("hover"), color: t("fg")}},
			{slot: "menu-item", when: ["focus-visible"], style: {background: t("hover"), color: t("fg")}},
			{slot: "menu-item", when: ["data-disabled=true"], style: {color: t("fg3"), background: Color.TRANSPARENT, cursor: Default}},
			{slot: "kbd", style: {color: t("fg3"), fontSize: SMALL}},
			{slot: "badge", style: {direction: Row, alignItems: Center, height: 18, padding: [0, 6], radius: RADIUS, background: t("well"), color: t("fg2"),
				fontSize: SMALL}},
			{slot: "grid-editor", style: {background: t("bg"), color: t("fg"), radius: 1, fontFamily: CODE,
				fontSize: BODY}},
			{slot: "grid-editor", when: ["selection"], style: {background: t("sel-soft")}},
		],
		light: light,
		dark: dark,
	};
}
