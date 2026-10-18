package hxmc.web;

#if macro
import haxe.macro.Context;
#end
import haxe.macro.Expr;

// The neutral elements (hxmc.ui's view, text, scroll; view:button,
// text:p...: docs/plans/native-or-drawn.md, single-source widgets) as the
// DOM's, for DomRenderer, all at compile time: each element its DOM
// element, each attribute what it is in a page (slot, variant and size as
// data-slot, data-variant and data-size; label, checked, expanded... as
// aria-*; focusable as tabindex; id as it is, tag (ui's Node.find) none;
// StyleProps as inline style), each event the DOM's converted to ui's
// Event (only for the events a widget listens to). A name the table has
// not is an error, so that the two renderers' vocabularies stay one.
class NeutralMacro {
	#if macro
	// (the neutral elements' DOM elements: view's and text's own, and the names their view: and text: forms take)
	static final VIEWS = [
		"div", "span", "button", "label", "a", "nav", "ul", "ol", "li", "section", "header", "footer", "aside", "main", "form", "fieldset", "legend",
		"table", "thead", "tbody", "tr", "th", "td", "hr", "dialog"
	];
	static final TEXTS = ["span", "p", "h1", "h2", "h3", "h4", "h5", "h6", "label", "kbd", "strong", "em", "small", "code", "legend", "div"];

	// (attributes: their DOM names)
	public static final DATA = ["slot" => "data-slot", "variant" => "data-variant", "size" => "data-size", "html-for" => "for"];
	public static final ARIA = [
		"label" => "aria-label", "description" => "aria-description", "checked" => "aria-checked", "selected" => "aria-selected",
		"expanded" => "aria-expanded", "pressed" => "aria-pressed", "hidden" => "aria-hidden", "level" => "aria-level",
		"value-now" => "aria-valuenow", "value-min" => "aria-valuemin", "value-max" => "aria-valuemax", "value-text" => "aria-valuetext", "live" => "aria-live",
		"multiselectable" => "aria-multiselectable", "current" => "aria-current"
	];
	static final PLAIN = ["role", "id", "href", "title"];
	// (StyleProps: the CSS property, and whether a number is in px)
	public static final CSS:Map<String, {prop:String, px:Bool}> = [
		"width" => {prop: "width", px: true}, "height" => {prop: "height", px: true}, "min-width" => {prop: "min-width", px: true},
		"max-width" => {prop: "max-width", px: true}, "min-height" => {prop: "min-height", px: true}, "max-height" => {prop: "max-height", px: true},
		"position" => {prop: "position", px: false}, "top" => {prop: "top", px: true}, "left" => {prop: "left", px: true},
		"right" => {prop: "right", px: true}, "bottom" => {prop: "bottom", px: true}, "overflow" => {prop: "overflow", px: false},
		"aspect-ratio" => {prop: "aspect-ratio", px: false}, "direction" => {prop: "flex-direction", px: false},
		"align-items" => {prop: "align-items", px: false}, "justify" => {prop: "justify-content", px: false}, "grow" => {prop: "flex-grow", px: false},
		"shrink" => {prop: "flex-shrink", px: false}, "gap" => {prop: "gap", px: true}, "row-gap" => {prop: "row-gap", px: true},
		"column-gap" => {prop: "column-gap", px: true}, "opacity" => {prop: "opacity", px: false}, "z-index" => {prop: "z-index", px: false},
		"text-align" => {prop: "text-align", px: false}, "padding" => {prop: "padding", px: true}, "wrap" => {prop: "flex-wrap", px: false},
		"basis" => {prop: "flex-basis", px: true}, "pointer-events" => {prop: "pointer-events", px: false}
	];
	// (events: the DOM's, and ui's EventType)
	static final EVENTS:Map<String, {dom:String, type:String}> = [
		"onClick" => {dom: "click", type: "Click"}, "onKeyDown" => {dom: "keydown", type: "KeyDown"}, "onKeyUp" => {dom: "keyup", type: "KeyUp"},
		"onPointerDown" => {dom: "pointerdown", type: "PointerDown"}, "onPointerUp" => {dom: "pointerup", type: "PointerUp"},
		"onPointerMove" => {dom: "pointermove", type: "PointerMove"}, "onPointerEnter" => {dom: "pointerenter", type: "PointerEnter"},
		"onPointerLeave" => {dom: "pointerleave", type: "PointerLeave"}, "onFocus" => {dom: "focus", type: "Focus"},
		"onBlur" => {dom: "blur", type: "Blur"}, "onFocusIn" => {dom: "focusin", type: "FocusIn"}, "onFocusOut" => {dom: "focusout", type: "FocusOut"}
	];

	// the DOM element of a neutral one
	public static function element(tag:Expr):Expr {
		var t = literal(tag);
		// (an icon: an <svg>, its paths its name's)
		if (t == "icon") return macro @:pos(tag.pos) hxmc.web.Neutral.icon();
		var dom = domName(t, tag.pos);
		if (t == "scroll") return macro @:pos(tag.pos) {
			var el = hxmc.web.DomRenderer.createElement("div");
			(cast el : js.html.Element).style.overflow = "auto";
			el;
		};
		// (a button not a form's submit)
		if (dom == "button") return macro @:pos(tag.pos) {
			var el = hxmc.web.DomRenderer.createElement("button");
			(cast el : js.html.Element).setAttribute("type", "button");
			el;
		};
		return macro @:pos(tag.pos) hxmc.web.DomRenderer.createElement($v{dom});
	}

	// (view: div, text: span, scroll: div, view:button: button...)
	static function domName(t:String, pos:Position):String {
		switch t {
			case "view" | "scroll": return "div";
			case "text": return "span";
			case _:
		}
		var colon = t.indexOf(":"), kind = t.substr(0, colon), name = t.substr(colon + 1);
		var ok = colon > 0 && (kind == "view" && VIEWS.indexOf(name) >= 0 || kind == "text" && TEXTS.indexOf(name) >= 0);
		if (!ok) Context.error('hxmc.web: no DOM element for the neutral <$t> (NeutralMacro: view, text, scroll, view:${VIEWS.join("|")}, text:${TEXTS.join("|")})', pos);
		return name;
	}

	// an attribute set (a value or a signal's at the time)
	public static function property(el:Expr, tag:Expr, name:Expr, v:Expr):Expr {
		// (a mapped name set once: Neutral's setter called with its DOM name)
		var n = literal(name), t = literal(tag);
		var dom = mapped(t, n);
		if (n == "role" && v.expr.match(EConst(CString("button" | "link", _))) && (t == "view:button" || t == "view:a")) dom = null
		else if (dom != null) return macro @:pos(name.pos) hxmc.web.Neutral.attr($el, $v{dom}, $v);
		if (CSS.exists(n)) return macro @:pos(name.pos) hxmc.web.Neutral.css($el, $v{CSS[n].prop}, $v, $v{CSS[n].px});
		var f = setterFor(t, n, name.pos, v);
		return f == null ? macro {} : macro @:pos(name.pos) $f($el, $name, $v);
	}

	// the name a bound attribute's setter gets: a mapped one's DOM name or CSS
	// property (its setter Neutral's one for all), else the neutral name
	public static function name(tag:Expr, name:Expr):Expr {
		var n = literal(name), t = literal(tag);
		var dom = mapped(t, n);
		return macro @:pos(name.pos) $v{dom ?? (CSS.exists(n) ? CSS[n].prop : n)};
	}

	// (an attribute's DOM name when it is one set as it is: data-*, aria-*, role, id...)
	static function mapped(t:String, n:String):Null<String> {
		if (t == "icon" && n == "mirrored") return "data-mirrored";
		if (t == "icon" && n == "name" || n == "tag" || n == "role" && StringTools.endsWith(t, ":legend")) return null;
		return DATA.exists(n) ? DATA[n] : ARIA.exists(n) ? ARIA[n] : PLAIN.indexOf(n) >= 0 || StringTools.startsWith(n, "data-")
			|| StringTools.startsWith(n, "aria-") ? n : null;
	}

	// the function setting an attribute, (el, name, v): what markup binds a signal with
	public static function setter(tag:Expr, name:Expr):Expr {
		var f = setterFor(literal(tag), literal(name), name.pos);
		return f == null ? macro @:pos(name.pos) function(el:Dynamic, name:String, v:Dynamic) {} : f;
	}

	static function setterFor(tag:String, name:String, pos:Position, ?v:Expr):Null<Expr> {
		if (tag == "icon" && name == "name") return macro @:pos(pos) hxmc.web.Neutral.iconName;
		// (ui's own: Node.find's tag, a group's and a peer's markers, the CSS's slots)
		if (name == "tag" || name == "group" || name == "peer") return null;
		// (a button's or a link's own: its role, and focusable as it is; a legend's role)
		if (name == "role" && (tag == "view:button" || tag == "view:a") && v != null && v.expr.match(EConst(CString("button" | "link", _)))) return null;
		if (StringTools.endsWith(tag, ":legend") && name == "role") return null;
		// (each kind one function, (el, name, v), name the DOM's (NeutralMacro.name): Neutral)
		if (mapped(tag, name) != null) return macro @:pos(pos) hxmc.web.Neutral.attr;
		if (CSS.exists(name)) return CSS[name].px ? macro @:pos(pos) hxmc.web.Neutral.cssPx : macro @:pos(pos) hxmc.web.Neutral.cssValue;
		if (name == "focusable") return macro @:pos(pos) hxmc.web.Neutral.focusable;
		if (name == "states") return macro @:pos(pos) hxmc.web.Neutral.states;
		if (name == "disabled") return macro @:pos(pos) hxmc.web.Neutral.disabled;
		return Context.error('hxmc.web: <$tag>\'s attribute $name has no DOM form (NeutralMacro)', pos);
	}

	// a listener: the DOM's event as ui's Event; onPress a click (a button's
	// or a link's own, Enter or Space too on another element)
	public static function listen(el:Expr, tag:Expr, name:Expr, h:Expr):Expr {
		var t = literal(tag), n = literal(name);
		if (n == "onPress") {
			var native = ["view:button", "view:a"].indexOf(t) >= 0;
			return macro @:pos(name.pos) hxmc.web.Neutral.press($el, $h, $v{native});
		}
		if (!EVENTS.exists(n)) return Context.error('hxmc.web: <$t>\'s event $n has no DOM form (NeutralMacro)', name.pos);
		var e = EVENTS[n], type = e.type;
		if (e.dom == "keydown" || e.dom == "keyup") return macro @:pos(name.pos) hxmc.web.Neutral.onKey($el, $v{e.dom}, $h, hxmc.ui.Event.EventType.$type);
		return macro @:pos(name.pos) hxmc.web.Neutral.on($el, $v{e.dom}, $h, hxmc.ui.Event.EventType.$type);
	}

	static function literal(e:Expr):String
		return switch e.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("hxmc.web: a neutral element's tag and attribute names are literal", e.pos);
		}
	#end
}
