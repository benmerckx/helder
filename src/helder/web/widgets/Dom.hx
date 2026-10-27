package helder.web.widgets;

#if js
import helder.ui.Key;
import helder.view.*;
import helder.view.Reactive.*;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.html.KeyboardEvent;

// What the DOM's widgets share: keys as helder.ui's codes (Behaviour's
// vocabulary), ids, icons, and popups in the browser's top layer.
class Dom {
	static var ids = 0;

	// a fresh id for aria-controls, aria-labelledby, label's for
	public static function id():String
		return "hx" + (++ids);

	// a key event's key as helder.ui's code (Key: X11 KeySyms; a character's
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

	// an icon (decoration: hidden from assistive technology), slot its
	// data-slot (a theme's size and colour), filled (a circle's dot):
	// lucide's of that name (helder.ui.widgets.Icons), as the neutral icon
	public static function icon(name:String, ?slot:String, ?fill:Bool):Element {
		var svg:Element = helder.web.Neutral.icon();
		helder.web.Neutral.iconName(svg, null, name);
		if (fill == true) svg.setAttribute("fill", "currentColor");
		svg.setAttribute("aria-hidden", "true");
		if (slot != null) svg.setAttribute("data-slot", slot);
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

	// the animation clock (helder.ui's Clock: toasts' time) ticked on the browser's frames while anything runs on it
	public static function tick() {
		if (ticking || !helder.ui.Clock.active) return;
		ticking = true;
		function frame(t:Float) {
			if (helder.ui.Clock.tick(t / 1000)) window.requestAnimationFrame(frame) else ticking = false;
		}
		window.requestAnimationFrame(frame);
	}

	static var ticking = false;

	@:allow(helder.web.widgets.Popup) static function push(p:Popup) {
		if (stack.length == 0) {
			document.addEventListener("pointerdown", outside, true);
			document.addEventListener("keydown", escape);
		}
		stack.push(p);
	}

	@:allow(helder.web.widgets.Popup) static function pop(p:Popup) {
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
