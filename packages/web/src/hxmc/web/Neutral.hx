package hxmc.web;

#if js
import hxmc.ui.Event;
import hxmc.web.widgets.Dom;
import js.html.Element;

// What NeutralMacro's code calls in a page: a neutral element's attributes
// set, its events converted to ui's Event (the DOM's stopped and its default
// prevented when the handler says so)
class Neutral {
	// an attribute by its DOM name (null or false: removed; aria-*'s true "true")
	public static function attr(el:Element, name:String, v:Dynamic) {
		var s = Html.attributeValue(name, v);
		if (s == null) el.removeAttribute(name) else if (el.getAttribute(name) != s) el.setAttribute(name, s);
	}

	// (a neutral attribute by its neutral name, NeutralMacro's tables: data-slot, aria-label...)
	public static function mapped(el:Dynamic, name:String, v:Dynamic)
		attr(el, NAMES[name], v);

	public static function plain(el:Dynamic, name:String, v:Dynamic)
		attr(el, name, v);

	// (a StyleProps attribute by its neutral name)
	public static function style(el:Dynamic, name:String, v:Dynamic) {
		var c = CSS[name];
		css(el, c.prop, v, c.px);
	}

	static final NAMES:Map<String, String> = hxmc.web.NeutralMacro.names();
	static final CSS:Map<String, {prop:String, px:Bool}> = hxmc.web.NeutralMacro.styles();

	// a style property (a number in px where px; null: none)
	public static function css(el:Element, prop:String, v:Dynamic, px:Bool) {
		if (v == null) {
			el.style.removeProperty(prop);
			return;
		}
		var s = px && (Std.isOfType(v, Float) || Std.isOfType(v, Int)) ? v + "px" : Std.string(v);
		// (ui's scroll overflow, and a flex direction on an element laid out as flex)
		if (prop == "overflow" && s == "scroll") s = "auto";
		if (prop == "flex-direction" && el.style.display == "") el.style.display = "flex";
		el.style.setProperty(prop, s);
	}

	// focusable: in the tab order (true), out of it (false), the element's own (null)
	public static function focusable(el:Dynamic, name:String, v:Dynamic)
		if (v == true) el.setAttribute("tabindex", "0") else if (v == false) el.setAttribute("tabindex", "-1") else el.removeAttribute("tabindex");

	// disabled: a control's own property, else aria-disabled
	public static function disabled(el:Dynamic, name:String, v:Dynamic) {
		var on = v == true;
		if (Reflect.hasField(el, "disabled") || el.localName == "button" || el.localName == "input" || el.localName == "select" || el.localName == "textarea")
			Reflect.setField(el, "disabled", on);
		else attr(el, "aria-disabled", on ? "true" : null);
	}

	// a handler of ui's Event for a DOM event
	public static function on(el:Element, dom:String, h:Dynamic, type:EventType) {
		if (h == null) return;
		el.addEventListener(dom, (e:js.html.Event) -> call(h, e, type));
	}

	// a press: a click (a button's or a link's, Enter and Space theirs), else a click, or Enter or Space
	public static function press(el:Element, h:Dynamic, native:Bool) {
		if (h == null) return;
		el.addEventListener("click", (e:js.html.Event) -> call(h, e, Click));
		if (!native) el.addEventListener("keydown", (e:js.html.KeyboardEvent) -> if (!e.defaultPrevented && (e.key == "Enter" || e.key == " ")) {
			e.preventDefault();
			call(h, e, Click);
		});
	}

	static function call(h:Dynamic, e:js.html.Event, type:EventType) {
		var x = 0.0, y = 0.0, d:Dynamic = e;
		if (d.clientX != null) {
			x = d.clientX;
			y = d.clientY;
		}
		var ev = new Event(type, null, x, y);
		if (Std.isOfType(e, js.html.KeyboardEvent)) ev.key = Dom.key(cast e);
		if (d.shiftKey != null) ev.mods = Dom.mods(e);
		if (d.button != null) ev.button = d.button + 1;
		(h : Event->Void)(ev);
		if (ev.stopped) e.stopPropagation();
		if (ev.defaultPrevented) e.preventDefault();
	}
}
#end
