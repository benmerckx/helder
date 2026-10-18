package hxmc.web.widgets;

#if js
import hxmc.ui.Key;
import hxmc.view.*;
import hxmc.view.Reactive.*;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.html.KeyboardEvent;

// What the DOM's widgets share: keys as hxmc.ui's codes (Behaviour's
// vocabulary), ids, icons, and popups in the browser's top layer.
class Dom {
	static var ids = 0;

	// a fresh id for aria-controls, aria-labelledby, label's for
	public static function id():String
		return "hx" + (++ids);

	// a key event's key as hxmc.ui's code (Key: X11 KeySyms; a character's
	// unshifted code), its modifiers as Key.MOD_* bits
	public static function key(e:KeyboardEvent):Int
		return switch e.key {
			case "ArrowLeft": Key.LEFT;
			case "ArrowRight": Key.RIGHT;
			case "ArrowUp": Key.UP;
			case "ArrowDown": Key.DOWN;
			case "Home": Key.HOME;
			case "End": Key.END;
			case "PageUp": Key.PAGE_UP;
			case "PageDown": Key.PAGE_DOWN;
			case "Enter": Key.ENTER;
			case "Escape": Key.ESCAPE;
			case "Tab": Key.TAB;
			case "Backspace": Key.BACKSPACE;
			case "Delete": Key.DELETE;
			case "ContextMenu": Key.MENU;
			case " ": Key.SPACE;
			case k if (k.length == 1): k.toLowerCase().charCodeAt(0);
			case k if (k.length > 1 && k.charAt(0) == "F" && Std.parseInt(k.substr(1)) != null): Key.F1 + Std.parseInt(k.substr(1)) - 1;
			case _: 0;
		}

	public static function mods(e:Dynamic):Int
		return (e.shiftKey ? Key.MOD_SHIFT : 0) | (e.ctrlKey ? Key.MOD_CONTROL : 0) | (e.altKey ? Key.MOD_ALT : 0) | (e.metaKey ? Key.MOD_META : 0);

	// whether an element is laid out right to left
	public static function rtl(el:Element):Bool
		return el != null && window.getComputedStyle(el).direction == "rtl";

	// now in seconds (type-ahead)
	public static inline function now():Float
		return window.performance.now() / 1000;

	// focuses an element (that takes the focus), the focus ring as the keyboard's
	public static function focus(el:Null<Element>)
		if (el != null) (cast el).focus({focusVisible: true});

	// the first element inside el that takes the focus
	public static function firstFocusable(el:Element):Null<Element> {
		var f = el.querySelector("button:not([disabled]),input:not([disabled]),textarea:not([disabled]),select:not([disabled]),a[href],[tabindex]:not([tabindex='-1'])");
		return f;
	}

	// lucide's icons (ISC): their paths (c: a circle, "cx cy r")
	static final ICONS = [
		"check" => ["M20 6 9 17l-5-5"], "circle" => ["c12 12 10"], "chevron-down" => ["m6 9 6 6 6-6"], "chevron-right" => ["m9 18 6-6-6-6"],
		"chevron-left" => ["m15 18-6-6 6-6"], "x" => ["M18 6 6 18", "m6 6 12 12"], "minus" => ["M5 12h14"], "search" => ["m21 21-4.34-4.34", "c11 11 8"],
		"loader" => ["M21 12a9 9 0 1 1-6.219-8.56"], "more" => ["c12 12 1", "c19 12 1", "c5 12 1"],
		"arrow-left" => ["m12 19-7-7 7-7", "M19 12H5"], "arrow-right" => ["M5 12h14", "m12 5 7 7-7 7"], "panel-left" => ["M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z", "M9 3v18"],
		"folder" => ["M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"]
	];

	// an icon (decoration: hidden from assistive technology), slot its
	// data-slot (a theme's size and colour), filled (a circle's dot)
	public static function icon(name:String, ?slot:String, ?fill:Bool):Element {
		var svg = document.createElementNS(hxmc.web.Html.SVG_NS, "svg");
		for (a in [
			["xmlns", hxmc.web.Html.SVG_NS], ["width", "24"], ["height", "24"], ["viewBox", "0 0 24 24"], ["fill", fill == true ? "currentColor" : "none"],
			["stroke", "currentColor"], ["stroke-width", "2"], ["stroke-linecap", "round"], ["stroke-linejoin", "round"], ["aria-hidden", "true"]
		])
			svg.setAttribute(a[0], a[1]);
		if (slot != null) svg.setAttribute("data-slot", slot);
		for (p in ICONS[name]) {
			var e = document.createElementNS(hxmc.web.Html.SVG_NS, p.charAt(0) == "c" ? "circle" : "path");
			if (p.charAt(0) == "c") {
				var n = p.substr(1).split(" ");
				e.setAttribute("cx", n[0]);
				e.setAttribute("cy", n[1]);
				e.setAttribute("r", n[2]);
			} else e.setAttribute("d", p);
			svg.appendChild(e);
		}
		return svg;
	}

	// the popups shown, the last on top (Escape and presses outside go to it first)
	static final stack:Array<Popup> = [];

	// shows content in the top layer (a popover) while open() is true, by
	// anchor (an element, or a point: x, y) on side ("bottom", "top",
	// "right", "left"; flipped where there is no room), aligned "start",
	// "center" or "end", offset pixels away; Escape, a press outside it, its
	// anchor and the popups it opened call onDismiss (dismiss: false, none
	// of that: a tooltip). vars: the Radix name whose custom properties its
	// content's classes read (select: --radix-select-content-transform-origin,
	// --radix-select-trigger-width, ...-available-height). onOpen: its element,
	// once placed. Disposed with the owner it is made in.
	public static function popup(open:Void->Bool, content:Void->Any, options:PopupOptions)
		new Popup(open, content, options);

	// shows content in a modal <dialog> (the top layer, the page behind it
	// inert, the focus kept in it) while open() is true: Escape calls
	// onDismiss; onOpen: the dialog, shown (where the focus goes first)
	public static function modal(open:Void->Bool, content:Void->Any, onDismiss:Void->Void, ?onOpen:Element->Void) {
		var d:Null<js.html.DialogElement> = null, dispose:Null<Void->Void> = null, before:Null<Element> = null;
		function hide() {
			if (d == null) return;
			if (dispose != null) dispose();
			d.close();
			d.remove();
			d = null;
			// (the focus back where it was)
			if (before != null) focus(before);
		}
		effect(() -> {
			var on = open();
			untrack(() -> if (on && d == null) {
				before = cast document.activeElement;
				d = cast document.createElement("dialog");
				d.setAttribute("data-modal", "");
				d.addEventListener("cancel", (e:js.html.Event) -> {
					e.preventDefault();
					onDismiss();
				});
				document.body.appendChild(d);
				dispose = Render.render(content(), (d : Element));
				d.showModal();
				if (onOpen != null) onOpen(d);
			} else if (!on) hide());
		});
		onCleanup(hide);
	}

	// the animation clock (hxmc.ui's Clock: toasts' time) ticked on the browser's frames while anything runs on it
	public static function tick() {
		if (ticking || !hxmc.ui.Clock.active) return;
		ticking = true;
		function frame(t:Float) {
			if (hxmc.ui.Clock.tick(t / 1000)) window.requestAnimationFrame(frame) else ticking = false;
		}
		window.requestAnimationFrame(frame);
	}

	static var ticking = false;

	@:allow(hxmc.web.widgets.Popup) static function push(p:Popup) {
		if (stack.length == 0) {
			document.addEventListener("pointerdown", outside, true);
			document.addEventListener("keydown", escape);
		}
		stack.push(p);
	}

	@:allow(hxmc.web.widgets.Popup) static function pop(p:Popup) {
		stack.remove(p);
		if (stack.length == 0) {
			document.removeEventListener("pointerdown", outside, true);
			document.removeEventListener("keydown", escape);
		}
	}

	// (a press outside the popups above, and their anchors: they are dismissed, from the top)
	static function outside(e:js.html.Event) {
		var t:js.html.Node = cast e.target;
		var i = stack.length;
		while (i-- > 0) {
			var p = stack[i];
			if (p.contains(t)) return;
			if (p.options.dismiss != false && p.options.onDismiss != null) p.options.onDismiss();
		}
	}

	static function escape(e:KeyboardEvent) {
		if (e.key != "Escape" || e.defaultPrevented || stack.length == 0) return;
		var p = stack[stack.length - 1];
		if (p.options.onDismiss == null) return;
		e.preventDefault();
		p.restoreFocus = true;
		p.options.onDismiss();
	}
}

typedef PopupOptions = {
	anchor:Void->Dynamic,
	?side:String,
	?align:String,
	?offset:Float,
	?onDismiss:Void->Void,
	?onOpen:Element->Void,
	?dismiss:Bool,
	?vars:String,
	?role:String
};

// a popup shown (Dom.popup)
class Popup {
	public final options:PopupOptions;
	public var restoreFocus = false;
	var host:Null<Element>;
	var dispose:Null<Void->Void>;

	public function new(open:Void->Bool, content:Void->Any, options:PopupOptions) {
		this.options = options;
		effect(() -> {
			var on = open();
			untrack(() -> if (on && host == null) show(content) else if (!on && host != null) hide());
		});
		onCleanup(() -> if (host != null) hide());
	}

	// whether a node is the popup's, its anchor's, or a popup's above it
	public function contains(n:js.html.Node):Bool {
		var a = options.anchor();
		if (host != null && host.contains(n)) return true;
		if (Std.isOfType(a, js.html.Node) && (a : js.html.Node).contains(n)) return true;
		return false;
	}

	function show(content:Void->Any) {
		var h = document.createDivElement();
		h.setAttribute("popover", "manual");
		h.setAttribute("data-popup", "");
		document.body.appendChild(h);
		host = h;
		dispose = Render.render(content(), (h : Element));
		(cast h).showPopover();
		Dom.push(this);
		place();
		window.addEventListener("resize", place);
		window.addEventListener("scroll", place, true);
		if (options.onOpen != null) options.onOpen(h);
	}

	function hide() {
		var h = host;
		host = null;
		Dom.pop(this);
		window.removeEventListener("resize", place);
		window.removeEventListener("scroll", place, true);
		var focused = h.contains(document.activeElement);
		if (dispose != null) dispose();
		dispose = null;
		h.remove();
		// (the focus back on the anchor, as Radix's: it was in the popup, or Escape)
		var a = options.anchor();
		if ((focused || restoreFocus) && Std.isOfType(a, Element)) Dom.focus(a);
		restoreFocus = false;
	}

	// (beside the anchor on its side, flipped where there is no room, kept in the window)
	function place() {
		var h = host;
		if (h == null) return;
		var a:Dynamic = options.anchor(), side = options.side ?? "bottom", align = options.align ?? "start", gap = options.offset ?? 4.0;
		var r:Dynamic = Std.isOfType(a, Element) ? (a : Element).getBoundingClientRect() : {
			left: a.x,
			top: a.y,
			right: a.x,
			bottom: a.y,
			width: 0,
			height: 0
		};
		var w:Float = h.offsetWidth, ht:Float = h.offsetHeight, vw:Float = window.innerWidth, vh:Float = window.innerHeight;
		var rtl = Std.isOfType(a, Element) && Dom.rtl(a);
		// (a side as the line reads: right to left, start and end swap)
		if (side == "right" && rtl) side = "left" else if (side == "left" && rtl) side = "right";
		switch side {
			case "bottom" if (r.bottom + gap + ht > vh && r.top - gap - ht >= 0): side = "top";
			case "top" if (r.top - gap - ht < 0 && r.bottom + gap + ht <= vh): side = "bottom";
			case "right" if (r.right + gap + w > vw && r.left - gap - w >= 0): side = "left";
			case "left" if (r.left - gap - w < 0 && r.right + gap + w <= vw): side = "right";
			case _:
		}
		var x = 0.0, y = 0.0;
		if (side == "bottom" || side == "top") {
			y = side == "bottom" ? r.bottom + gap : r.top - gap - ht;
			var start = rtl ? r.right - w : r.left, end = rtl ? r.left : r.right - w;
			x = align == "center" ? r.left + (r.width - w) / 2 : align == "end" ? end : start;
		} else {
			x = side == "right" ? r.right + gap : r.left - gap - w;
			y = align == "center" ? r.top + (r.height - ht) / 2 : align == "end" ? r.bottom - ht : r.top;
		}
		x = Math.max(0, Math.min(x, vw - w));
		y = Math.max(0, Math.min(y, vh - ht));
		h.style.left = Math.round(x) + "px";
		h.style.top = Math.round(y) + "px";
		var c = h.firstElementChild;
		if (c != null && c.hasAttribute("data-side")) c.setAttribute("data-side", side);
		if (options.vars != null) {
			var v = "--radix-" + options.vars;
			var origin = switch side {
				case "top": "0% 100%";
				case "right": "0% 0%";
				case "left": "100% 0%";
				case _: "0% 0%";
			}
			h.style.setProperty(v + "-content-transform-origin", origin);
			h.style.setProperty(v + "-content-available-height", (side == "top" ? r.top - gap : vh - r.bottom - gap) + "px");
			h.style.setProperty(v + "-trigger-width", r.width + "px");
			h.style.setProperty(v + "-trigger-height", r.height + "px");
		}
	}
}
#end
