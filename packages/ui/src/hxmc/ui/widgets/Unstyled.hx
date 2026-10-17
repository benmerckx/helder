package hxmc.ui.widgets;

import hxmc.ui.*;

// The widgets' looks where no theme applies (Rules.addBase): the geometry
// their interaction needs and what keeps them legible, in the text's
// colour (currentColor) — an outline round a control, a visible checked
// state, a switch's thumb on its side. A theme (StyleSheet) starts from
// none of these, as shadcn's from Tailwind's preflight.
class Unstyled {
	// (installed when a widget is first made)
	public static function install() {
		if (installed) return;
		installed = true;
		Rules.addBase("widgets", rules());
	}

	static var installed = false;

	static function rules():Array<Rule> {
		var line = Color.parse("currentColor"), faint = Color.parse("currentColor/30"), half = Color.parse("currentColor/50");
		var canvas = Color.parse("Canvas"), canvasText = Color.parse("CanvasText");
		return [
			{slot: "button", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 6, padding: [4, 10], borderWidth: 1, borderColor: line, cursor: Pointer}},
			{slot: "button", size: "sm", style: {padding: [2, 8]}},
			{slot: "button", size: "lg", style: {padding: [6, 14]}},
			{slot: "button", size: "icon", style: {padding: 4}},
			{slot: "button", variant: "link", style: {borderWidth: 0, textDecoration: (TextDecoration.Underline : Int)}},
			{slot: "button", when: ["disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "toggle", style: {direction: Row, alignItems: Center, justify: Center, columnGap: 6, padding: [4, 10], borderWidth: 1, borderColor: faint, cursor: Pointer}},
			{slot: "toggle", when: ["data-state=on"], style: {borderColor: line, background: faint}},
			{slot: "toggle", when: ["disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "input", style: {padding: [4, 6], borderWidth: 1, borderColor: line}},
			{slot: "input", when: ["placeholder"], style: {color: half}},
			{slot: "input", when: ["disabled"], style: {opacity: 0.5}},
			{slot: "textarea", style: {padding: [4, 6], borderWidth: 1, borderColor: line}},
			{slot: "textarea", when: ["placeholder"], style: {color: half}},
			{slot: "checkbox", style: {width: 16, height: 16, borderWidth: 1, borderColor: line, alignItems: Center, justify: Center, cursor: Pointer}},
			{slot: "checkbox", when: ["disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "checkbox-indicator", style: {alignItems: Center, justify: Center}},
			{slot: "switch", style: {width: 32, height: 18, padding: 1, borderWidth: 1, borderColor: line, direction: Row, alignItems: Center, cursor: Pointer}},
			{slot: "switch", when: ["disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "switch-thumb", style: {width: 14, height: 14, radius: 7, background: half}},
			{slot: "switch", when: ["data-state=checked"], style: {justify: End}},
			{slot: "switch-thumb", when: ["data-state=checked"], style: {background: line}},
			{slot: "label", when: ["disabled"], style: {opacity: 0.5}},
			{slot: "card", style: {direction: Column, rowGap: 12, padding: 12, borderWidth: 1, borderColor: faint}},
			{slot: "card-header", style: {direction: Column, rowGap: 4}},
			{slot: "card-title", style: {fontWeight: 600}},
			{slot: "card-description", style: {opacity: 0.7}},
			{slot: "card-content", style: {direction: Column}},
			{slot: "card-footer", style: {direction: Row, alignItems: Center, columnGap: 8}},
			{slot: "badge", style: {direction: Row, alignItems: Center, columnGap: 4, padding: [0, 6], borderWidth: 1, borderColor: line}},
			{slot: "textarea", when: ["disabled"], style: {opacity: 0.5}},
			{slot: "radio-group", style: {rowGap: 6}},
			{slot: "radio-group-item", style: {width: 16, height: 16, radius: 8, borderWidth: 1, borderColor: line, alignItems: Center, justify: Center}},
			{slot: "radio-group-item", when: ["disabled"], style: {opacity: 0.5}},
			{slot: "tabs", style: {rowGap: 8}},
			{slot: "tabs-list", style: {direction: Row, columnGap: 4, borders: [0, 0, 1, 0], borderColor: faint}},
			{slot: "tabs-trigger", style: {padding: [4, 10], borders: [0, 0, 2, 0], cursor: Pointer, opacity: 0.7}},
			{slot: "tabs-trigger", when: ["data-state=active"], style: {borderColor: line, opacity: 1}},
			{slot: "slider", style: {cursor: Pointer}},
			{slot: "slider", when: ["disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "slider-track", style: {height: 4, radius: 2, background: faint}},
			{slot: "slider-range", style: {background: line}},
			{slot: "slider-thumb", style: {radius: 8, background: line}},
			{slot: "progress", style: {height: 8, radius: 4, background: faint}},
			{slot: "progress-indicator", style: {background: line}},
			{slot: "separator", style: {background: faint, alignSelf: Stretch, shrink: 0}},
			{slot: "separator", when: ["data-orientation=horizontal"], style: {height: 1}},
			{slot: "separator", when: ["data-orientation=vertical"], style: {width: 1}},
			{slot: "skeleton", style: {radius: 4, background: Color.parse("currentColor/10")}},
			{slot: "alert", style: {direction: Column, rowGap: 2, padding: [8, 12], borderWidth: 1, borderColor: faint}},
			{slot: "alert", variant: "destructive", style: {borderColor: line}},
			{slot: "alert-title", style: {fontWeight: 500}},
			{slot: "alert-description", style: {opacity: 0.8}},
			{slot: "select-trigger", style: {direction: Row, alignItems: Center, justify: SpaceBetween, columnGap: 8, padding: [4, 8], borderWidth: 1, borderColor: line, cursor: Pointer}},
			{slot: "select-content", style: {padding: 2, borderWidth: 1, borderColor: line, background: canvas, color: canvasText}},
			{slot: "select-item", style: {direction: Row, alignItems: Center, padding: [4, 28, 4, 8], cursor: Pointer}},
			{slot: "select-item", when: ["focus"], style: {background: faint}},
			{slot: "select-item-indicator", style: {position: Absolute, right: 8, alignItems: Center, justify: Center}},
			{slot: "dropdown-menu-content", style: {minWidth: 128, padding: 2, borderWidth: 1, borderColor: line, background: canvas, color: canvasText}},
			{slot: "dropdown-menu-item", style: {direction: Row, alignItems: Center, justify: SpaceBetween, columnGap: 24, padding: [4, 8], cursor: Pointer}},
			{slot: "dropdown-menu-item", when: ["focus"], style: {background: faint}},
			{slot: "dropdown-menu-shortcut", style: {opacity: 0.6}},
			{slot: "context-menu-content", style: {minWidth: 128, padding: 2, borderWidth: 1, borderColor: line, background: canvas, color: canvasText}},
			{slot: "context-menu-item", style: {direction: Row, alignItems: Center, justify: SpaceBetween, columnGap: 24, padding: [4, 8], cursor: Pointer}},
			{slot: "context-menu-item", when: ["focus"], style: {background: faint}},
			{slot: "context-menu-shortcut", style: {opacity: 0.6}},
			{slot: "menubar-content", style: {minWidth: 128, padding: 2, borderWidth: 1, borderColor: line, background: canvas, color: canvasText}},
			{slot: "menubar-item", style: {direction: Row, alignItems: Center, justify: SpaceBetween, columnGap: 24, padding: [4, 8], cursor: Pointer}},
			{slot: "menubar-item", when: ["focus"], style: {background: faint}},
			{slot: "menubar-shortcut", style: {opacity: 0.6}},
			{slot: "menubar", style: {direction: Row, columnGap: 2}},
			{slot: "menubar-trigger", style: {padding: [2, 8], cursor: Pointer}},
			{slot: "menubar-trigger", when: ["data-state=open"], style: {background: faint}},
			{slot: "tooltip-content", style: {padding: [2, 6], background: canvasText, color: canvas, fontSize: 12}},
			{slot: "dialog-overlay", style: {background: Color.rgba(0x000000, 0.5)}},
			{slot: "dialog-content", style: {direction: Column, rowGap: 12, padding: 16, borderWidth: 1, borderColor: canvasText, background: canvas, color: canvasText}},
			{slot: "dialog-header", style: {direction: Column, rowGap: 4}},
			{slot: "dialog-title", style: {fontWeight: 600}},
			{slot: "dialog-description", style: {opacity: 0.7}},
			{slot: "dialog-footer", style: {direction: Row, justify: End, columnGap: 8}},
			{slot: "dialog-close", style: {position: Absolute, top: 12, right: 12, padding: 2, cursor: Pointer, opacity: 0.7}},
			{slot: "dialog-close", when: ["hover"], style: {opacity: 1}},
			{slot: "collapsible-trigger", style: {direction: Row, alignItems: Center, columnGap: 6, padding: [4, 2], cursor: Pointer}},
			{slot: "collapsible-content", style: {padding: [4, 0, 4, 20]}},
			{slot: "accordion-item", style: {borders: [0, 0, 1, 0], borderColor: faint}},
			{slot: "accordion-trigger", style: {direction: Row, alignItems: Center, columnGap: 16, padding: [8, 0], cursor: Pointer}},
			{slot: "accordion-trigger", when: ["hover"], style: {textDecoration: (TextDecoration.Underline : Int)}},
			{slot: "accordion-content", style: {padding: [0, 0, 8, 0]}},
			{slot: "toggle-group", style: {direction: Row, alignSelf: Start, borderWidth: 1, borderColor: line}},
			{slot: "toggle-group-item", style: {padding: [4, 10], cursor: Pointer}},
			{slot: "toggle-group-item", size: "sm", style: {padding: [2, 8]}},
			{slot: "toggle-group-item", size: "lg", style: {padding: [6, 14]}},
			{slot: "toggle-group-item", when: ["data-state=on"], style: {background: faint}},
			{slot: "breadcrumb-list", style: {direction: Row, wrap: true, alignItems: Center, columnGap: 6}},
			{slot: "breadcrumb-item", style: {direction: Row, alignItems: Center}},
			{slot: "breadcrumb-link", style: {textDecoration: (TextDecoration.Underline : Int), cursor: Pointer}},
			{slot: "pagination-content", style: {direction: Row, alignItems: Center, columnGap: 4}},
			{slot: "pagination-link", style: {direction: Row, alignItems: Center, justify: Center, minWidth: 32, padding: [4, 10], borderWidth: 1, borderColor: Color.TRANSPARENT, cursor: Pointer}},
			{slot: "pagination-link", when: ["data-active"], style: {borderColor: line}},
			{slot: "pagination-link", when: ["disabled"], style: {opacity: 0.5, cursor: Default}},
			{slot: "pagination-ellipsis", style: {padding: [4, 6]}}
		];
	}
}
