package hxmc.web;

#if js
import hxmc.ui.Event.EventType;
import hxmc.web.widgets.Dom;
import js.html.Element;

// What NeutralMacro's code calls in a page: a neutral element's attributes
// set, its events converted to ui's Event (the DOM's stopped and its default
// prevented when the handler says so)
class Neutral {
	// an attribute by its DOM name, as ui's setData has them: data-* absent for null and false, empty for true;
	// aria-* "true" and "false"; else Html's rules
	public static function attr(el:Dynamic, name:String, v:Dynamic) {
		// (a Bool's: JavaScript's == has "0" false)
		var bool = Std.isOfType(v, Bool);
		var s = if (StringTools.startsWith(name, "data-")) v == null || bool && v == false ? null : bool && v == true ? "" : Std.string(v)
			else if (StringTools.startsWith(name, "aria-")) v == null ? null : Std.string(v)
			else Html.attributeValue(name, v);
		if (s == null) el.removeAttribute(name) else if (el.getAttribute(name) != s) el.setAttribute(name, s);
	}

	public static function plain(el:Dynamic, name:String, v:Dynamic)
		attr(el, name, v);

	// a style property (a number in px where px; null: none)
	public static function css(el:Dynamic, prop:String, v:Dynamic, px:Bool) {
		if (v == null) {
			el.style.removeProperty(prop);
			return;
		}
		var s = px && (Std.isOfType(v, Float) || Std.isOfType(v, Int)) ? v + "px" : Std.string(v);
		// (ui's scroll overflow, and a flex direction on an element laid out as flex)
		if (prop == "overflow" && s == "scroll") s = "auto";
		if (prop == "flex-wrap") s = v == true || s == "wrap" ? "wrap" : "nowrap";
		if (prop == "flex-direction" && el.style.display == "") el.style.display = "flex";
		el.style.setProperty(prop, s);
	}

	// (a widget's style prop, a function of drawn states: a page's look is its CSS)
	public static function states(el:Dynamic, name:String, v:Dynamic)
		if (v != null) js.Syntax.code("throw new Error({0})", "hxmc.web: a widget's style prop is drawn widgets' (a page's look is its CSS)");

	// an icon: an <svg> of 24 by 24, stroked (hxmc.ui.widgets.Icons)
	public static function icon():Dynamic {
		var svg = js.Browser.document.createElementNS(Html.SVG_NS, "svg");
		for (a in [
			["xmlns", Html.SVG_NS], ["width", "24"], ["height", "24"], ["viewBox", "0 0 24 24"], ["fill", "none"], ["stroke", "currentColor"],
			["stroke-width", "2"], ["stroke-linecap", "round"], ["stroke-linejoin", "round"]
		])
			svg.setAttribute(a[0], a[1]);
		return svg;
	}

	// (its name: lucide's icon of that name, its paths)
	public static function iconName(el:Dynamic, name:String, v:Dynamic)
		el.innerHTML = v == null ? "" : hxmc.ui.widgets.Icons.markup(v);

	// focusable: in the tab order (true; a button's or a link's own), out of it (false), the element's own (null)
	public static function focusable(el:Dynamic, name:String, v:Dynamic)
		if (v == true && el.localName != "button" && el.localName != "a") el.setAttribute("tabindex", "0")
		else if (v == false) el.setAttribute("tabindex", "-1")
		else el.removeAttribute("tabindex");

	// disabled: a control's own property, else aria-disabled
	public static function disabled(el:Dynamic, name:String, v:Dynamic) {
		var on = v == true;
		if (Reflect.hasField(el, "disabled") || el.localName == "button" || el.localName == "input" || el.localName == "select" || el.localName == "textarea")
			Reflect.setField(el, "disabled", on);
		else attr(el, "aria-disabled", on ? "true" : null);
	}

	// a handler of ui's Event for a DOM event
	public static function on(el:Dynamic, dom:String, h:Dynamic, type:EventType) {
		if (h == null) return;
		el.addEventListener(dom, (e:js.html.Event) -> call(h, e, type, null));
	}

	// (a key event: its key and modifiers as ui's codes)
	public static function onKey(el:Dynamic, dom:String, h:Dynamic, type:EventType) {
		if (h == null) return;
		el.addEventListener(dom, (e:js.html.KeyboardEvent) -> call(h, e, type, Dom.key(e), Dom.mods(e)));
	}

	// a press: a click (a button's or a link's, Enter and Space theirs), else a click, or Enter or Space
	public static function press(el:Dynamic, h:Dynamic, native:Bool) {
		if (h == null) return;
		el.addEventListener("click", (e:js.html.Event) -> call(h, e, Click, null));
		if (!native) el.addEventListener("keydown", (e:js.html.KeyboardEvent) -> if (!e.defaultPrevented && (e.key == "Enter" || e.key == " ")) {
			e.preventDefault();
			call(h, e, Click, null);
		});
	}

	static function call(h:Dynamic, e:js.html.Event, type:EventType, key:Null<Int>, mods = 0) {
		var x = 0.0, y = 0.0, d:Dynamic = e;
		if (d.clientX != null) {
			x = d.clientX;
			y = d.clientY;
		}
		var ev = new NeutralEvent(type, x, y, ElementPart.of(e.currentTarget));
		if (key != null) ev.key = key;
		ev.mods = mods;
		if (d.button != null) ev.button = d.button + 1;
		(h : Dynamic->Void)(ev);
		if (ev.stopped) e.stopPropagation();
		if (ev.defaultPrevented) e.preventDefault();
	}
}

// ui's Event as a page's handlers get it (its fields; current the element
// listening as a Part, target none): ui's own would bring its nodes into a page
@:keep private class NeutralEvent {
	public final type:EventType;
	public final target:Dynamic = null;
	public final current:Dynamic;
	public final x:Float;
	public final y:Float;
	public var button = 0;
	public var key = 0;
	public var mods = 0;
	public var text = "";
	public var caret = 0;
	public var data:Dynamic = null;
	public var dropped = false;
	public var deltaX = 0.0;
	public var deltaY = 0.0;
	public var stopped = false;
	public var defaultPrevented = false;

	public function new(type, x, y, current) {
		this.type = type;
		this.current = current;
		this.x = x;
		this.y = y;
	}

	public function stop()
		stopped = true;

	public function preventDefault()
		defaultPrevented = true;
}
#end
