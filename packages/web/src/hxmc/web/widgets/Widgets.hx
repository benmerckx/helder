package hxmc.web.widgets;

#if js
import hxmc.ui.Key;
import hxmc.ui.Shortcut;
import hxmc.ui.widgets.Behaviour;
import hxmc.ui.widgets.Behaviour.MenuEntry;
import hxmc.ui.widgets.Behaviour.TypeAhead;
import hxmc.ui.widgets.Behaviour.TreeLine;
import hxmc.ui.widgets.Days;
import hxmc.ui.widgets.Days.Day;
import hxmc.ui.widgets.Toasts;
import hxmc.ui.widgets.Toasts.Toast;
// (the widgets of one definition for both: ui's, realised by the DOM's renderer)
import hxmc.ui.widgets.Widgets.Button;
import hxmc.ui.widgets.Widgets.Calendar;
import hxmc.ui.widgets.Widgets.Input;
import hxmc.ui.widgets.Widgets.SIDEBAR;
import hxmc.view.*;
import hxmc.view.Flow.*;
import hxmc.view.Reactive.*;
import hxmc.view.Signal;
import hxmc.web.widgets.Dom.*;
import js.Browser.document;
import js.Browser.window;
import js.html.Element;
import js.html.KeyboardEvent;

// a menu's item: its label, what choosing it does, a shortcut; variant
// "destructive", disabled, a separator, a heading; checked: a checkbox
// item, radio: one of a group; items: a submenu (hxmc.ui's MenuItem)
typedef MenuItem = MenuEntry;

// a range of days, its first and last (hxmc.ui's DayRange)
typedef DayRange = {from:Null<Day>, to:Null<Day>};

// hxmc.ui's widgets as the DOM's elements (import
// hxmc.web.widgets.Widgets.* in place of hxmc.ui.widgets.Widgets.*): the
// same components and props, each a real element with shadcn's markup
// (the element types shadcn and Radix use: button, input, label, a role
// where Radix uses a div; data-slot, data-state and the other data-*
// attributes, aria-*), their behaviour hxmc.ui's (Behaviour: keys, roving
// focus, type-ahead; the rest as the drawn widgets do it), popups in the
// browser's top layer (a popover; a modal <dialog>). Unstyled: the theme's
// CSS (hxmc.theme.Css, from the class lists hxmc.ui's rules come from)
// gives them shadcn's look.
class Widgets implements Markup {
	// (a prop that may be a value, a signal or a function of one: its value, tracked)
	static function read(v:Dynamic):Dynamic
		return v == null ? null : Render.read(v);

	static function on(v:Dynamic):Bool
		return read(v) == true;

	// (a key event's key, mirrored where its element is right to left)
	static function keyOf(e:KeyboardEvent):Int
		return Behaviour.mirror(Dom.key(e), Dom.rtl(cast e.currentTarget));

	// (focuses els[i] when there is one)
	static function focusIn(els:Array<Element>, i:Int)
		if (i >= 0 && i < els.length) Dom.focus(els[i]);

	// (an icon 16 pixels square, as shadcn's size-4 on one without a slot)
	static function small(svg:Element):Element {
		svg.setAttribute("width", "16");
		svg.setAttribute("height", "16");
		return svg;
	}

	// (the shortcuts of items working from anywhere in the page while mounted (within: only while the focus is in it))
	static function hotkeys(list:Array<MenuItem>, ?within:Void->Element) {
		var all = [];
		function add(l:Array<MenuItem>)
			for (it in l)
				if (it.disabled != true) {
					if (it.items != null) add(it.items) else if (it.shortcut != null) all.push({s: Shortcut.parse(it.shortcut), it: it});
				}
		add(list);
		if (all.length == 0) return;
		function down(e:KeyboardEvent) {
			if (e.defaultPrevented) return;
			if (within != null && (within() == null || !within().contains(document.activeElement))) return;
			var k = Dom.key(e), m = Dom.mods(e);
			for (h in all)
				if (h.s.matches(k, m)) {
					e.preventDefault();
					Behaviour.choose(h.it);
					return;
				}
		}
		document.addEventListener("keydown", down);
		onCleanup(() -> document.removeEventListener("keydown", down));
	}

	// a menu's content (Radix's): its items (kind: "dropdown-menu",
	// "menubar", "context-menu"; slots kind-content, -item, -checkbox-item,
	// -radio-item, -label, -separator, -shortcut, -sub-trigger,
	// -sub-content); Up and Down move the focus (separators, headings and
	// disabled items skipped), letters typed to the item they start, the
	// pointer focuses, Enter, Space or a click chooses (and close()s), Tab
	// closes; a submenu opens beside its item (the pointer on it, Right,
	// Enter, Space), Left or Escape closes it. other: a key it leaves (a
	// menu bar's Left and Right)
	static function menu(kind:String, list:Array<MenuItem>, close:Void->Void, sub:Bool, ?other:KeyboardEvent->Void):View {
		var items:Array<Element> = [], typed = new TypeAhead(), opened = signal(-1);
		var labels = [for (it in list) Behaviour.skipped(it) ? "" : it.label];
		function focused():Int
			return items.indexOf(cast document.activeElement);
		function choose(i:Int) {
			var it = list[i];
			if (it.disabled == true) return;
			if (it.items != null) {
				opened.value = i;
				return;
			}
			close();
			Behaviour.choose(it);
		}
		function key(e:KeyboardEvent) {
			var i = focused(), k = keyOf(e);
			switch k {
				case Key.DOWN | Key.UP:
					var j = Behaviour.nextEntry(list, i < 0 ? (k == Key.DOWN ? -1 : list.length) : i, k == Key.DOWN ? 1 : -1);
					if (j >= 0) focusIn(items, j);
				case Key.HOME: focusIn(items, Behaviour.nextEntry(list, -1, 1));
				case Key.END: focusIn(items, Behaviour.nextEntry(list, list.length, -1));
				case Key.ENTER | Key.SPACE if (i >= 0): choose(i);
				case Key.RIGHT if (i >= 0 && list[i].items != null): opened.value = i;
				case Key.LEFT if (sub): close();
				case Key.TAB:
					close();
					return;
				case _:
					var j = typed.find(k, Dom.mods(e), Dom.now(), labels, i);
					if (j < 0) {
						if (other != null) other(e);
						return;
					}
					focusIn(items, j);
			}
			e.preventDefault();
			e.stopPropagation();
		}
		return <div role="menu" data-slot={kind + (sub ? "-sub-content" : "-content")} data-state="open" data-side={sub ? "right" : "bottom"}
			aria-orientation="vertical" tabindex="-1" onKeyDown={key}>{[
			for (i in 0...list.length) {
				var it = list[i], off = it.disabled == true;
				if (it.separator == true) View.view(<div role="separator" aria-orientation="horizontal" data-slot={kind + "-separator"}/>);
				else if (it.heading == true) View.view(<div data-slot={kind + "-label"}>{it.label}</div>);
				else {
					var checked = it.checked != null ? () -> it.checked.value : it.radio != null ? () -> it.radio.group.value == it.radio.value : null;
					var slot = it.items != null ? "-sub-trigger" : it.checked != null ? "-checkbox-item" : it.radio != null ? "-radio-item" : "-item";
					var self:Element = null;
					View.view(<div role={it.checked != null ? "menuitemcheckbox" : it.radio != null ? "menuitemradio" : "menuitem"} data-slot={kind + slot}
						data-variant={it.variant ?? "default"} tabindex="-1" ref={n -> items[i] = self = cast n}
						aria-checked={checked == null ? null : () -> checked() ? "true" : "false"}
						data-state={checked != null ? () -> checked() ? "checked" : "unchecked" : it.items != null ? () -> opened.value == i ? "open" : "closed" : null}
						aria-haspopup={it.items != null ? "menu" : null} aria-expanded={it.items == null ? null : () -> opened.value == i ? "true" : "false"}
						aria-disabled={off ? "true" : null} data-disabled={off ? "" : null}
						onFocus={() -> self.setAttribute("data-highlighted", "")} onBlur={() -> self.removeAttribute("data-highlighted")}
						onPointerMove={() -> if (!off && document.activeElement != self) {
							Dom.focus(self);
							opened.value = it.items != null ? i : -1;
						}} onClick={() -> choose(i)}>
						{checked == null ? null : <span data-slot={kind + "-item-indicator"}><Show when={checked}>{() -> icon(it.radio != null ? "circle" : "check",
							kind + "-item-indicator-icon", it.radio != null)}</Show></span>}
						{it.label}
						{it.shortcut == null ? null : <span data-slot={kind + "-shortcut"}>{Shortcut.parse(it.shortcut).label()}</span>}
						{it.items == null ? null : icon("chevron-right", kind + "-sub-trigger-icon")}
					</div>);
				}
			}
		]}{() -> {
			// (the open submenu: beside its item, the focus on its first)
			var i = opened.value;
			if (i >= 0) untrack(() -> Dom.popup(() -> opened.value == i, () -> menu(kind, list[i].items, () -> {
				opened.value = -1;
				close();
			}, true), {
				anchor: () -> items[i],
				side: "right",
				offset: 4,
				vars: kind,
				onDismiss: () -> {
					opened.value = -1;
					focusIn(items, i);
				},
				onOpen: h -> focusIn(cast h.querySelectorAll("[role^=menuitem]:not([data-disabled])"), 0)
			}));
			null;
		}}</div>;
	}

	// (the first item of a menu's popup focused)
	static function focusFirstItem(h:Element)
		Dom.focus(h.querySelector("[role^=menuitem]:not([data-disabled])"));

	// a dropdown menu (shadcn's): an outline button, label; a click, Enter,
	// Space or Down opens its items under it, the first focused; their
	// shortcuts work from anywhere in the page
	public static function DropdownMenu(props:{label:String, items:Array<MenuItem>, ?variant:String, ?tag:String}):View {
		var open = signal(false), trigger:Element = null;
		hotkeys(props.items);
		Dom.popup(() -> open.value, () -> menu("dropdown-menu", props.items, () -> open.value = false, false), {
			anchor: () -> trigger,
			vars: "dropdown-menu",
			onDismiss: () -> open.value = false,
			onOpen: focusFirstItem
		});
		return <button type="button" id={props.tag} data-slot="button" data-variant={props.variant ?? "outline"} data-size="default" ref={n -> trigger = cast n}
			aria-haspopup="menu" aria-expanded={() -> open.value ? "true" : "false"} data-state={() -> open.value ? "open" : "closed"}
			onClick={() -> open.value = !open.peek()} onKeyDown={(e:KeyboardEvent) -> if (e.key == "ArrowDown") {
				e.preventDefault();
				open.value = true;
			}}>{props.label}{icon("chevron-down", "dropdown-menu-trigger-icon")}</button>;
	}

	// a menu bar (shadcn's): menus' titles in a row, each opening its items
	// under it (a click, Down, Enter, Space); while one is open, the pointer
	// over another opens that one; Left and Right move between the titles (from
	// an open menu: the next one opened); one Tab stop
	public static function Menubar(props:{menus:Array<{label:String, items:Array<MenuItem>}>, ?label:String, ?tag:String}):View {
		var count = props.menus.length, open = signal(-1), current = signal(0), titles:Array<Element> = [];
		for (m in props.menus)
			hotkeys(m.items);
		function step(i:Int, k:Int, reopen:Bool) {
			var j = Behaviour.rove(Behaviour.mirror(k, Dom.rtl(titles[i])), i, count, false);
			if (j < 0) return;
			current.value = j;
			focusIn(titles, j);
			if (reopen) open.value = j;
		}
		for (i in 0...count)
			Dom.popup(() -> open.value == i, () -> menu("menubar", props.menus[i].items, () -> open.value = -1, false, e -> {
				var k = Dom.key(e);
				if (k == Key.LEFT || k == Key.RIGHT) {
					e.preventDefault();
					step(i, k, true);
				}
			}), {
				anchor: () -> titles[i],
				vars: "menubar",
				offset: 8,
				onDismiss: () -> if (open.peek() == i) open.value = -1,
				onOpen: focusFirstItem
			});
		return <div id={props.tag} role="menubar" data-slot="menubar" aria-label={props.label}>{[
			for (i in 0...count)
				<button type="button" role="menuitem" data-slot="menubar-trigger" ref={n -> titles[i] = cast n} aria-haspopup="menu"
					aria-expanded={() -> open.value == i ? "true" : "false"} data-state={() -> open.value == i ? "open" : "closed"}
					tabindex={() -> current.value == i ? 0 : -1} onFocus={() -> current.value = i}
					onPointerEnter={() -> if (open.peek() >= 0 && open.peek() != i) {
						current.value = i;
						Dom.focus(titles[i]);
						open.value = i;
					}} onClick={() -> open.value = open.peek() == i ? -1 : i}
					onKeyDown={(e:KeyboardEvent) -> switch Dom.key(e) {
						case Key.LEFT | Key.RIGHT:
							e.preventDefault();
							step(i, Dom.key(e), false);
						case Key.DOWN:
							e.preventDefault();
							open.value = i;
						case _:
					}}>{props.menus[i].label}</button>
		]}</div>;
	}

	// a context menu (shadcn's): the children, with items opened by a right
	// click on them where it was pressed, or by the menu key or Shift+F10
	// when the focus is in them; their shortcuts work while it is
	public static function ContextMenu(props:{items:Array<MenuItem>, ?label:String, ?tag:String, ?children:Any}):View {
		var open = signal(false), at = {x: 0.0, y: 0.0}, self:Element = null;
		function show(x:Float, y:Float) {
			at = {x: x, y: y};
			open.value = false;
			open.value = true;
		}
		hotkeys(props.items, () -> self);
		Dom.popup(() -> open.value, () -> menu("context-menu", props.items, () -> open.value = false, false), {
			anchor: () -> at,
			side: "bottom",
			offset: 0,
			vars: "context-menu",
			onDismiss: () -> open.value = false,
			onOpen: focusFirstItem
		});
		return <div id={props.tag} data-slot="context-menu-trigger" style="display:contents" ref={n -> self = cast n}
			onContextMenu={(e:Dynamic) -> {
				e.preventDefault();
				show(e.clientX, e.clientY);
			}} onKeyDown={(e:KeyboardEvent) -> if (e.key == "ContextMenu" || (e.key == "F10" && e.shiftKey)) {
				e.preventDefault();
				var r = (cast e.target : Element).getBoundingClientRect();
				show(r.left, r.top);
			}}>{props.children}</div>;
	}

	// a select (shadcn's, Radix's) bound to a signal: the chosen option's
	// label on a button; a click, Enter or Space opens the options under
	// it, the chosen one focused; Up and Down move through them, a click,
	// Enter or Space chooses, Escape, Tab or a click outside closes; on the
	// closed button Up and Down choose the previous or next option, letters
	// typed the option they start
	public static function Select(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?label:String,
			?placeholder:String, ?tag:String}):View {
		var open = signal(false), trigger:Element = null, items:Array<Element> = [], typed = new TypeAhead();
		var shown = [for (i in 0...props.options.length) props.labels != null ? props.labels[i] : props.options[i]];
		var labelOf = (v:String) -> {
			var i = props.options.indexOf(v);
			i >= 0 ? shown[i] : props.placeholder ?? v;
		};
		function choose(v:String) {
			props.value.value = v;
			open.value = false;
		}
		Dom.popup(() -> open.value, () -> <div role="listbox" data-slot="select-content" data-state="open" data-side="bottom" aria-label={props.label}
			onKeyDown={(e:KeyboardEvent) -> {
				var i = items.indexOf(cast document.activeElement), k = Dom.key(e);
				switch k {
					case Key.DOWN: focusIn(items, i + 1);
					case Key.UP: focusIn(items, i - 1);
					case Key.HOME: focusIn(items, 0);
					case Key.END: focusIn(items, items.length - 1);
					case Key.ENTER | Key.SPACE if (i >= 0): choose(props.options[i]);
					case Key.TAB:
						open.value = false;
						return;
					case _:
						var j = typed.find(k, Dom.mods(e), Dom.now(), shown, i);
						if (j < 0) return;
						focusIn(items, j);
				}
				e.preventDefault();
			}}><div data-slot="select-viewport">{[
				for (i in 0...props.options.length) {
					var o = props.options[i], self:Element = null, sel = () -> props.value.value == o;
					<div role="option" data-slot="select-item" tabindex="-1" ref={n -> items[i] = self = cast n} aria-selected={() -> sel() ? "true" : "false"}
						data-state={() -> sel() ? "checked" : "unchecked"} onFocus={() -> self.setAttribute("data-highlighted", "")}
						onBlur={() -> self.removeAttribute("data-highlighted")} onPointerMove={() -> if (document.activeElement != self) Dom.focus(self)}
						onClick={() -> choose(o)}>
						<span data-slot="select-item-indicator"><Show when={sel}>{() -> icon("check")}</Show></span>
						<span>{shown[i]}</span>
					</div>;
				}
			]}</div></div>, {
			anchor: () -> trigger,
			vars: "select",
			onDismiss: () -> open.value = false,
			onOpen: _ -> {
				var i = props.options.indexOf(props.value.peek());
				focusIn(items, i < 0 ? 0 : i);
			}
		});
		return <button type="button" id={props.tag} role="combobox" data-slot="select-trigger" data-size="default" ref={n -> trigger = cast n}
			aria-label={props.label} aria-expanded={() -> open.value ? "true" : "false"} aria-autocomplete="none" data-state={() -> open.value ? "open" : "closed"}
			data-placeholder={() -> props.options.indexOf(props.value.value) < 0 ? "" : null} style={props.width == null ? null : 'width:${props.width}px'}
			onClick={() -> open.value = !open.peek()} onKeyDown={(e:KeyboardEvent) -> {
				var k = Dom.key(e), i = props.options.indexOf(props.value.peek());
				switch k {
					case Key.DOWN | Key.UP:
						e.preventDefault();
						var j = i + (k == Key.DOWN ? 1 : -1);
						if (j >= 0 && j < props.options.length) props.value.value = props.options[j];
					case _:
						var j = typed.find(k, Dom.mods(e), Dom.now(), shown, i);
						if (j >= 0) {
							e.preventDefault();
							props.value.value = props.options[j];
						}
				}
			}}>
			<span data-slot="select-value" style="pointer-events:none">{() -> labelOf(props.value.value)}</span>
			{icon("chevron-down", "select-trigger-icon")}
		</button>;
	}

	// a popover (shadcn's): label on an outline button opening the children under it (the first focusable focused)
	public static function PopoverButton(props:{label:String, ?open:Signal<Bool>, ?variant:String, ?tag:String, ?children:Any}):View {
		var open = props.open ?? signal(false), trigger:Element = null;
		Dom.popup(() -> open.value, () -> <div role="dialog" data-slot="popover-content" data-state="open" data-side="bottom" aria-label={props.label}
			tabindex="-1">{props.children}</div>, {
			anchor: () -> trigger,
			align: "center",
			vars: "popover",
			onDismiss: () -> open.value = false,
			onOpen: h -> Dom.focus(Dom.firstFocusable(h) ?? h.firstElementChild)
		});
		return <button type="button" id={props.tag} data-slot="button" data-variant={props.variant ?? "outline"} data-size="default" ref={n -> trigger = cast n}
			aria-haspopup="dialog" aria-expanded={() -> open.value ? "true" : "false"} data-state={() -> open.value ? "open" : "closed"}
			onClick={() -> open.value = !open.peek()}>{props.label}</button>;
	}

	// (shows after a wait while the pointer rests on, or the keyboard's focus is in, what it wraps)
	static function hovered(delay:Float, leave:Float, show:Signal<Bool>):{enter:Void->Void, exit:Void->Void, now:Bool->Void} {
		var timer = -1;
		function after(wait:Float, v:Bool) {
			if (timer >= 0) window.clearTimeout(timer);
			timer = window.setTimeout(() -> {
				timer = -1;
				show.value = v;
			}, Std.int(wait * 1000));
		}
		onCleanup(() -> if (timer >= 0) window.clearTimeout(timer));
		return {enter: () -> if (!show.peek()) after(delay, true) else after(0, true), exit: () -> after(leave, false), now: v -> {
			if (timer >= 0) window.clearTimeout(timer);
			timer = -1;
			show.value = v;
		}};
	}

	// a tooltip (shadcn's): text shown by the children (above them) once the
	// pointer has rested on them for delay seconds (0.5) or the keyboard's
	// focus is in them; hidden when it leaves or presses, or by Escape
	public static function Tooltip(props:{text:String, ?delay:Float, ?placement:String, ?tag:String, ?children:Any}):View {
		var show = signal(false), self:Element = null, h = hovered(props.delay ?? 0.5, 0, show);
		Dom.popup(() -> show.value, () -> <div role="tooltip" data-slot="tooltip-content" data-state="delayed-open" data-side="top">{props.text}</div>, {
			anchor: () -> self.firstElementChild ?? self,
			side: placementSide(props.placement ?? "above"),
			align: "center",
			offset: 0,
			dismiss: false,
			vars: "tooltip",
			onDismiss: () -> h.now(false)
		});
		return <span id={props.tag} data-slot="tooltip-trigger" style="display:contents" ref={n -> self = cast n} onPointerEnter={h.enter}
			onPointerLeave={() -> h.now(false)} onPointerDown={() -> h.now(false)}
			onFocusIn={(e:Dynamic) -> if ((cast e.target : Element).matches(":focus-visible")) h.now(true)} onFocusOut={() -> h.now(false)}>{props.children}</span>;
	}

	// (hxmc.ui's placements as sides)
	static function placementSide(p:String):String
		return switch p {
			case "above": "top";
			case "right" | "left": p;
			case _: "bottom";
		}

	// a hover card (shadcn's): content shown by the children (below) once
	// the pointer has rested on them for delay seconds (0.7), kept while it
	// is over either, hidden when it leaves both (after 0.3 seconds)
	public static function HoverCard(props:{content:Any, ?delay:Float, ?placement:String, ?tag:String, ?children:Any}):View {
		var show = signal(false), self:Element = null, h = hovered(props.delay ?? 0.7, 0.3, show);
		Dom.popup(() -> show.value, () -> <div data-slot="hover-card-content" data-state="open" data-side="bottom" onPointerEnter={h.enter}
			onPointerLeave={h.exit}>{props.content}</div>, {
			anchor: () -> self.firstElementChild ?? self,
			side: placementSide(props.placement ?? "below"),
			align: "center",
			dismiss: false,
			vars: "hover-card",
			onDismiss: () -> h.now(false)
		});
		return <span id={props.tag} data-slot="hover-card-trigger" style="display:contents" ref={n -> self = cast n} onPointerEnter={h.enter}
			onPointerLeave={h.exit}>{props.children}</span>;
	}

	// (a close button: an × in the corner)
	static function closeButton(slot:String, close:Void->Void):View
		return <button type="button" data-slot={slot} aria-label="Close" onClick={close}>{icon("x", slot + "-icon")}</button>;

	// a modal dialog (shadcn's) while open is true: its title and
	// description, then the children, over the dimmed page, the first
	// focusable focused, a close button (close: false, none); Escape, the
	// close button or a click on the backdrop closes it. width: its own
	// (pixels; else shadcn's)
	public static function Dialog(props:{open:Signal<Bool>, title:String, ?description:String, ?width:Float, ?close:Bool, ?tag:String,
			?children:Any}):View {
		var close = () -> props.open.value = false, base = props.tag ?? Dom.id();
		Dom.modal(() -> props.open.value, () -> View.view(<>
			<div data-slot="dialog-overlay" data-state="open" onClick={close}/>
			<div role="dialog" id={base} data-slot="dialog-content" data-state="open" aria-labelledby={base + "-t"}
				aria-describedby={props.description == null ? null : base + "-d"} tabindex="-1" style={props.width == null ? null : 'max-width:${props.width}px'}>
				<div data-slot="dialog-header">
					<h2 id={base + "-t"} data-slot="dialog-title">{props.title}</h2>
					{props.description == null ? null : <p id={base + "-d"} data-slot="dialog-description">{props.description}</p>}
				</div>
				{props.children}
				{props.close == false ? null : closeButton("dialog-close", close)}
			</div>
		</>), close, d -> Dom.focus(Dom.firstFocusable(d.querySelector("[role=dialog]")) ?? d.querySelector("[role=dialog]")));
		return null;
	}

	public static function DialogFooter(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="dialog-footer">{props.children}</div>;

	// an alert dialog (shadcn's): a modal asking to confirm, its cancel and
	// action buttons (the cancel focused first); Cancel or Escape closes it
	// (onCancel), the action closes it and runs onAction; a click outside does nothing
	public static function AlertDialog(props:{open:Signal<Bool>, title:String, ?description:String, ?cancel:String, ?action:String,
			?variant:String, ?onAction:Void->Void, ?onCancel:Void->Void, ?width:Float, ?tag:String, ?children:Any}):View {
		var base = props.tag ?? Dom.id();
		function cancel() {
			props.open.value = false;
			if (props.onCancel != null) props.onCancel();
		}
		function act() {
			props.open.value = false;
			if (props.onAction != null) props.onAction();
		}
		Dom.modal(() -> props.open.value, () -> View.view(<>
			<div data-slot="alert-dialog-overlay" data-state="open"/>
			<div role="alertdialog" id={base} data-slot="alert-dialog-content" data-state="open" data-size="default" aria-labelledby={base + "-t"}
				aria-describedby={props.description == null ? null : base + "-d"} tabindex="-1" style={props.width == null ? null : 'max-width:${props.width}px'}>
				<div data-slot="alert-dialog-header">
					<h2 id={base + "-t"} data-slot="alert-dialog-title">{props.title}</h2>
					{props.description == null ? null : <p id={base + "-d"} data-slot="alert-dialog-description">{props.description}</p>}
				</div>
				{props.children}
				<div data-slot="alert-dialog-footer">
					<Button tag={base + "-cancel"} label={props.cancel ?? "Cancel"} variant="outline" onClick={cancel}/>
					<Button tag={base + "-action"} label={props.action ?? "Continue"} variant={props.variant ?? "default"} onClick={act}/>
				</div>
			</div>
		</>), cancel, d -> Dom.focus(d.querySelector("[data-variant=outline]")));
		return null;
	}

	// a sheet (shadcn's): a dialog along an edge (side "right", the default, "left", "top", "bottom")
	public static function Sheet(props:{open:Signal<Bool>, title:String, ?description:String, ?side:String, ?close:Bool, ?tag:String, ?children:Any}):View {
		var close = () -> props.open.value = false, base = props.tag ?? Dom.id();
		Dom.modal(() -> props.open.value, () -> View.view(<>
			<div data-slot="sheet-overlay" data-state="open" onClick={close}/>
			<div role="dialog" id={base} data-slot="sheet-content" data-state="open" data-side={props.side ?? "right"} aria-labelledby={base + "-t"} tabindex="-1">
				<div data-slot="sheet-header">
					<h2 id={base + "-t"} data-slot="sheet-title">{props.title}</h2>
					{props.description == null ? null : <p data-slot="sheet-description">{props.description}</p>}
				</div>
				{props.children}
				{props.close == false ? null : closeButton("sheet-close", close)}
			</div>
		</>), close, d -> Dom.focus(Dom.firstFocusable(d.querySelector("[role=dialog]"))));
		return null;
	}

	public static function SheetFooter(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="sheet-footer">{props.children}</div>;

	// a drawer (shadcn's, vaul's): a sheet along an edge (direction
	// "bottom", the default, "top", "left", "right") with a handle; closed
	// as a dialog is, or by a drag towards its edge past a quarter of its
	// size, which it follows
	public static function Drawer(props:{open:Signal<Bool>, title:String, ?description:String, ?direction:String, ?tag:String, ?children:Any}):View {
		var dir = props.direction ?? "bottom", close = () -> props.open.value = false, base = props.tag ?? Dom.id();
		var across = dir == "left" || dir == "right", sign = dir == "bottom" || dir == "right" ? 1 : -1;
		var pull = signal(0.0), from = 0.0, pressed = false, dragging = false, panel:Element = null;
		function along(e:Dynamic):Float
			return (across ? e.clientX : e.clientY) * sign;
		Dom.modal(() -> props.open.value, () -> View.view(<>
			<div data-slot="drawer-overlay" data-state="open" onClick={close}/>
			<div role="dialog" id={base} data-slot="drawer-content" data-state="open" data-vaul-drawer-direction={dir} aria-labelledby={base + "-t"} tabindex="-1"
				ref={n -> panel = cast n} style={() -> pull.value == 0 ? null : 'transform:${across ? "translateX" : "translateY"}(${pull.value * sign}px)'}
				onPointerDown={(e:Dynamic) -> {
					from = along(e);
					pressed = true;
					dragging = false;
				}} onPointerMove={(e:Dynamic) -> if (pressed) {
					var d = along(e) - from;
					if (!dragging && d > 4) {
						dragging = true;
						panel.setPointerCapture(e.pointerId);
					}
					if (dragging) pull.value = Math.max(0, d);
				}} onPointerUp={() -> {
					pressed = false;
					if (dragging) {
						dragging = false;
						if (pull.peek() > (across ? panel.offsetWidth : panel.offsetHeight) / 4) close();
						pull.value = 0;
					}
				}}>
				<div data-slot="drawer-handle"/>
				<div data-slot="drawer-header">
					<h2 id={base + "-t"} data-slot="drawer-title">{props.title}</h2>
					{props.description == null ? null : <p data-slot="drawer-description">{props.description}</p>}
				</div>
				{props.children}
			</div>
		</>), close, d -> Dom.focus(Dom.firstFocusable(d.querySelector("[role=dialog]"))));
		return null;
	}

	public static function DrawerFooter(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="drawer-footer">{props.children}</div>;

	// a combobox: a text field bound to value (two ways) whose typing
	// filters options (those holding the text, any case) in a list under it
	// (shadcn's: a popover holding a command list); the focus stays in the
	// field: Down opens the list and highlights the next option, Up the
	// previous, Enter or a click chooses the highlighted one (onChoose), Enter
	// with none submits the text, Escape or a click outside closes the list
	public static function Combobox(props:{value:Signal<String>, options:Dynamic, ?placeholder:String, ?width:Float, ?label:String,
			?onChoose:String->Void, ?tag:String}):View {
		var w = props.width ?? 200.0, open = signal(false), active = signal(-1), field:Element = null, list = Dom.id();
		var matches = memo(() -> {
			var q = props.value.value.toLowerCase(), all:Array<String> = Render.read(props.options);
			[for (o in all) if (o.toLowerCase().indexOf(q) >= 0) o];
		});
		function choose(o:String) {
			batch(() -> {
				props.value.value = o;
				open.value = false;
				active.value = -1;
			});
			if (props.onChoose != null) props.onChoose(o);
		}
		Dom.popup(() -> open.value && matches.value.length > 0, () -> <div data-slot="popover-content" data-state="open" data-side="bottom"
			style={'width:${w}px;padding:0'}><div data-slot="command"><div data-slot="command-list" role="listbox" id={list} aria-label={props.label}>
				<div data-slot="command-group" role="presentation"><Index each={matches} render={(o:Signal<String>, i:Int) -> <div data-slot="command-item" role="option"
					id={list + "-" + i} aria-selected={() -> active.value == i ? "true" : "false"} data-selected={() -> active.value == i ? "true" : "false"}
					data-disabled="false" onPointerMove={() -> active.value = i} onPointerDown={(e:Dynamic) -> e.preventDefault()}
					onClick={() -> choose(o.peek())}>{o}</div>}/></div>
			</div></div></div>, {
			anchor: () -> field,
			vars: "popover",
			onDismiss: () -> open.value = false
		});
		function key(e:KeyboardEvent):Void {
			var n = matches.peek().length;
			switch Dom.key(e) {
				case Key.DOWN:
					e.preventDefault();
					if (!open.peek()) {
						open.value = true;
						active.value = n > 0 ? 0 : -1;
					} else if (n > 0) active.value = (active.peek() + 1) % n;
				case Key.UP:
					e.preventDefault();
					if (open.peek() && n > 0) active.value = active.peek() <= 0 ? n - 1 : active.peek() - 1;
				case Key.ENTER:
					var i = active.peek();
					if (open.peek() && i >= 0 && i < n) choose(matches.peek()[i]) else {
						open.value = false;
						if (props.onChoose != null) props.onChoose(props.value.peek());
					}
				case _:
			}
		}
		return <input id={props.tag} data-slot="input" role="combobox" ref={n -> field = cast n} value={props.value} placeholder={props.placeholder}
			aria-label={props.label ?? props.placeholder} aria-autocomplete="list" aria-controls={list}
			aria-expanded={() -> open.value && matches.value.length > 0 ? "true" : "false"}
			aria-activedescendant={() -> active.value >= 0 ? list + "-" + active.value : null} style={'width:${w}px'}
			onInput={(e:Dynamic) -> batch(() -> {
				props.value.value = e.target.value;
				open.value = true;
				active.value = -1;
			})} onKeyDown={key}/>;
	}

	// a command menu (shadcn's, cmdk's): a search field over groups of
	// items; only the items whose label holds the query shown, a group with
	// none hidden, separators only while the query is empty, empty's text
	// when nothing matches; one selected (the first that can be chosen as the
	// query changes, the one under the pointer), Up and Down move it, Enter or
	// a click chooses it
	public static function Command(props:{groups:Array<{?heading:String, items:Array<MenuItem>}>, ?placeholder:String, ?empty:String,
			?query:Signal<String>, ?label:String, ?tag:String}):View {
		var query = props.query ?? signal(""), base = props.tag ?? Dom.id();
		var all:Array<MenuItem> = [], groupOf:Array<Int> = [];
		for (g => group in props.groups)
			for (it in group.items) {
				all.push(it);
				groupOf.push(g);
			}
		var shown = memo(() -> {
			var q = query.value.toLowerCase();
			[for (it in all) it.separator == true ? q == "" : it.label.toLowerCase().indexOf(q) >= 0];
		});
		var choosable = memo(() -> {
			var s = shown.value;
			[for (k in 0...all.length) if (s[k] && all[k].separator != true && all[k].disabled != true) k];
		});
		var selected = signal(-1), rows:Array<Element> = [];
		effect(() -> {
			var c = choosable.value;
			selected.value = c.length > 0 ? c[0] : -1;
		});
		function select(k:Int) {
			selected.value = k;
			if (k >= 0 && rows[k] != null) (cast rows[k]).scrollIntoView({block: "nearest"});
		}
		function choose(k:Int)
			if (k >= 0 && all[k].disabled != true && all[k].onSelect != null) all[k].onSelect();
		var any = () -> Lambda.exists([for (k in 0...all.length) k], k -> shown.value[k] && all[k].separator != true);
		return <div id={props.tag} data-slot="command" onKeyDown={(e:KeyboardEvent) -> {
			var c = choosable.peek(), at = c.indexOf(selected.peek());
			switch Dom.key(e) {
				case Key.DOWN if (c.length > 0):
					e.preventDefault();
					select(c[at < 0 ? 0 : Std.int(Math.min(at + 1, c.length - 1))]);
				case Key.UP if (c.length > 0):
					e.preventDefault();
					select(c[at <= 0 ? 0 : at - 1]);
				case Key.ENTER: choose(selected.peek());
				case _:
			}
		}}>
			<div data-slot="command-input-wrapper">
				{icon("search", "command-input-icon")}
				<input data-slot="command-input" role="combobox" aria-expanded="true" aria-controls={base + "-l"} aria-label={props.label ?? props.placeholder}
					aria-activedescendant={() -> selected.value >= 0 ? base + "-" + selected.value : null} placeholder={props.placeholder} value={query}
					onInput={(e:Dynamic) -> query.value = e.target.value}/>
			</div>
			<div data-slot="command-list" role="listbox" id={base + "-l"} aria-label={props.label}>
				<Show when={() -> !any()}><div data-slot="command-empty">{props.empty ?? "No results found."}</div></Show>
				{[
					for (g => group in props.groups) {
						var mine = [for (k in 0...all.length) if (groupOf[k] == g) k];
						var visible = () -> Lambda.exists(mine, k -> shown.value[k] && all[k].separator != true);
						[
							g == 0 ? null : View.view(<Show when={() -> query.value == "" && visible()}><div data-slot="command-separator" role="separator"/></Show>),
							View.view(<Show when={visible}><div data-slot="command-group" role="presentation">
								{group.heading == null ? null : <div data-slot="command-group-heading" aria-hidden="true">{group.heading}</div>}
								<div role="group" aria-label={group.heading}>{[
									for (k in mine) {
										var it = all[k];
										it.separator == true ? View.view(<Show when={() -> shown.value[k]}><div data-slot="command-separator" role="separator"/></Show>) : View.view(<Show
											when={() -> shown.value[k]}><div data-slot="command-item" role="option" id={base + "-" + k} ref={n -> rows[k] = cast n}
												aria-selected={() -> selected.value == k ? "true" : "false"} data-selected={() -> selected.value == k ? "true" : "false"}
												data-disabled={it.disabled == true ? "true" : "false"} onPointerMove={() -> if (it.disabled != true) selected.value = k}
												onClick={() -> choose(k)}>{it.label}{it.shortcut == null ? null : <span data-slot="command-shortcut">{Shortcut.parse(it.shortcut)
													.label()}</span>}</div></Show>);
									}
								]}</div>
							</div></Show>)
						];
					}
				]}
			</div>
		</div>;
	}

	// a date chosen on an outline button opening a Calendar under it
	// (closed by a choice, Escape or a click outside); the button shows it
	// as format writes it (17 October 2026), else placeholder
	public static function DatePicker(props:{value:Signal<Null<Day>>, ?today:Day, ?firstDay:Int, ?format:Day->String, ?placeholder:String,
			?label:String, ?tag:String}):View {
		var open = signal(false), trigger:Element = null;
		var format = props.format ?? (d:Day) -> d.day + " " + Days.MONTHS[d.month - 1] + " " + d.year;
		Dom.popup(() -> open.value, () -> <div role="dialog" data-slot="popover-content" data-state="open" data-side="bottom" style="width:auto;padding:0">
			<Calendar value={props.value} today={props.today} firstDay={props.firstDay} onChoose={_ -> open.value = false}/>
		</div>, {
			anchor: () -> trigger,
			vars: "popover",
			onDismiss: () -> open.value = false,
			onOpen: h -> Dom.focus(h.querySelector("[role=grid]"))
		});
		return <button type="button" id={props.tag} data-slot="button" data-variant="outline" data-size="default" role="combobox" ref={n -> trigger = cast n}
			aria-label={props.label} aria-haspopup="dialog" aria-expanded={() -> open.value ? "true" : "false"} data-state={() -> open.value ? "open" : "closed"}
			data-empty={() -> props.value.value == null ? "true" : null} onClick={() -> open.value = !open.peek()}
			onKeyDown={(e:KeyboardEvent) -> if (e.key == "ArrowDown") {
				e.preventDefault();
				open.value = true;
			}}><span data-slot="date-picker-value" data-placeholder={() -> props.value.value == null ? "" : null}>{() -> props.value.value == null ? (props.placeholder ?? "Choose a date") : format(props.value.value)}</span></button>;
	}

	// where Toasts.show's toasts are shown: in a corner of the page
	// (placement: "bottom-right", "bottom-left", "top-right", "top-left"),
	// over everything, each with its mark, text, action and a close button;
	// the pointer over them holds their time
	public static function Toaster(props:{?placement:String, ?width:Float, ?tag:String}):View {
		var p = (props.placement ?? "bottom-right").split("-");
		var host:Element = null;
		effect(() -> {
			var n = Toasts.shown.value.length;
			untrack(() -> {
				Dom.tick();
				if (host != null) {
					if (n > 0 && !(cast host).matches(":popover-open")) (cast host).showPopover() else if (n == 0
						&& (cast host).matches(":popover-open")) (cast host).hidePopover();
				}
			});
		});
		return <section id={props.tag} aria-label="Notifications" popover="manual" data-popup="" ref={n -> host = cast n}
			style={'${p[0]}:16px;${p[1]}:16px'} onPointerEnter={() -> Toasts.paused = true} onPointerLeave={() -> Toasts.paused = false}>
			<ol data-slot="toaster" aria-live="polite" style={props.width == null ? null : 'width:${props.width}px'}>
				<For each={Toasts.shown} render={(t:Toast) -> <li data-slot="toast" data-type={t.kind} role="status">
					{t.kind == "success" || t.kind == "error" ? <span data-slot="toast-icon" aria-hidden="true">{t.kind == "success" ? "✓" : "!"}</span> : null}
					<div data-slot="toast-title">{t.text}</div>
					{t.action == null ? null : <button type="button" data-slot="toast-action" onClick={() -> {
						Toasts.close(t);
						if (t.onAction != null) t.onAction();
					}}>{t.action}</button>}
					<button type="button" data-slot="toast-close" aria-label="Close toast" onClick={() -> Toasts.close(t)}>{icon("x")}</button>
				</li>}/>
			</ol>
		</section>;
	}

	// (a double click: two clicks on one thing within 0.45 seconds)
	static function doubled():Dynamic->Bool {
		var last:Dynamic = null, at = -1e9;
		return x -> {
			var now = Dom.now(), d = last == x && now - at < 0.45;
			last = x;
			at = now;
			d;
		};
	}

	// a table (shadcn's): a header of the columns' titles (a column with
	// compare sorts by it on a click, Enter or Space, again the other way),
	// then the rows, each column's cell for each; a click selects a row, a
	// double click or Enter activates it (onActivate); Up, Down, Page Up,
	// Page Down, Home and End move the selection, the view following; a
	// column's edge in the header dragged sets its width (a double click
	// there: its own again). columns: title, width (CSS: "120px"), cell,
	// compare, numeric (at the end, figures of one width). rows: an array,
	// or a signal or function of one; height: the whole table's (scrolled)
	public static function Table<T>(props:{rows:Dynamic, columns:Array<{title:String, ?width:String, cell:T->Any, ?compare:(T, T)->Int, ?numeric:Bool}>,
			?height:Float, ?rowHeight:Float, ?selected:Signal<Null<T>>, ?onActivate:T->Void, ?label:String, ?tag:String}):View {
		var selected:Signal<Null<T>> = props.selected ?? signal(null), sortBy = signal(-1), descending = signal(false);
		var widths:Array<Signal<Null<Float>>> = [for (_ in props.columns) signal(null)], rows:Array<Element> = [], again = doubled();
		var sorted = memo(() -> {
			var list:Array<T> = Render.read(props.rows), k = sortBy.value;
			if (k < 0 || props.columns[k].compare == null) return list;
			var cmp = props.columns[k].compare, d = descending.value, out = list.copy();
			haxe.ds.ArraySort.sort(out, (a, b) -> d ? cmp(b, a) : cmp(a, b));
			return out;
		});
		function sort(k:Int)
			if (props.columns[k].compare != null) batch(() -> if (sortBy.peek() == k) descending.value = !descending.peek() else {
				sortBy.value = k;
				descending.value = false;
			});
		function activate(r:Null<T>)
			if (r != null && props.onActivate != null) props.onActivate(r);
		function key(e:KeyboardEvent) {
			var list = sorted.peek(), i = list.indexOf(selected.peek()), page = props.height == null ? 10 : Std.int(Math.max(1, props.height / 37 - 2));
			var j = switch Dom.key(e) {
				case Key.DOWN: i < 0 ? 0 : i + 1;
				case Key.UP: i < 0 ? 0 : i - 1;
				case Key.PAGE_DOWN: i + page;
				case Key.PAGE_UP: i - page;
				case Key.HOME: 0;
				case Key.END: list.length - 1;
				case Key.ENTER:
					activate(selected.peek());
					e.preventDefault();
					return;
				case _: return;
			}
			e.preventDefault();
			if (list.length == 0) return;
			j = j < 0 ? 0 : j >= list.length ? list.length - 1 : j;
			selected.value = list[j];
			if (rows[j] != null) (cast rows[j]).scrollIntoView({block: "nearest"});
		}
		return <div id={props.tag} data-slot="table-container" style={props.height == null ? null : 'max-height:${props.height}px;overflow-y:auto'}>
			<table data-slot="table" aria-label={props.label}>
				<thead data-slot="table-header"><tr data-slot="table-row">{[
					for (k in 0...props.columns.length) {
						var c = props.columns[k], cell:Element = null, from = 0.0, start = 0.0, dragging = false, edge = doubled();
						<th data-slot="table-head" ref={n -> cell = cast n} tabindex={c.compare != null ? 0 : null} data-sortable={c.compare != null ? "true" : null}
							aria-sort={() -> sortBy.value != k ? null : descending.value ? "descending" : "ascending"}
							style={() -> (widths[k].value != null ? 'width:${widths[k].value}px;' : c.width != null ? 'width:${c.width};' : "") + "position:relative"
								+ (c.numeric == true ? ";text-align:end" : "")}
							onClick={() -> sort(k)} onKeyDown={(e:KeyboardEvent) -> if (e.key == "Enter" || e.key == " ") {
								e.preventDefault();
								sort(k);
							}}>
							{c.title}
							<span data-slot="table-sort-icon" aria-hidden="true">{() -> sortBy.value == k ? (descending.value ? " ▼" : " ▲") : ""}</span>
							{k == props.columns.length - 1 ? null : <span aria-hidden="true" style="position:absolute;top:0;bottom:0;inset-inline-end:0;width:6px;cursor:ew-resize"
								onPointerDown={(e:Dynamic) -> {
									dragging = true;
									from = e.clientX;
									start = cell.offsetWidth;
									e.target.setPointerCapture(e.pointerId);
									e.stopPropagation();
								}} onPointerMove={(e:Dynamic) -> if (dragging) widths[k].value = Math.round(Math.max(24, start + (Dom.rtl(cell) ? from - e.clientX : e.clientX - from)))}
								onPointerUp={() -> dragging = false} onClick={(e:Dynamic) -> {
									e.stopPropagation();
									if (edge(k)) widths[k].value = null;
								}}/>}
						</th>;
					}
				]}</tr></thead>
				<tbody data-slot="table-body" tabindex="0" onKeyDown={key}>
					<For each={sorted} render={(r:T) -> {
						var on = () -> selected.value == r;
						<tr data-slot="table-row" aria-selected={() -> on() ? "true" : "false"} data-state={() -> on() ? "selected" : null}
							ref={n -> rows[sorted.peek().indexOf(r)] = cast n} onClick={() -> {
								if (again(r)) activate(r);
								selected.value = r;
							}}>{[
							for (c in props.columns)
								<td data-slot="table-cell" style={c.numeric == true ? "text-align:end;font-variant-numeric:tabular-nums" : null}>{c.cell(r)}</td>
						]}</tr>;
					}}/>
				</tbody>
			</table>
		</div>;
	}

	// a tree: the roots' rows and, under each open item, its children's,
	// indented by level, a triangle on the items with children; a click
	// selects an item, a click on its triangle opens or closes it, as a
	// double click does (on a leaf: onActivate, as Enter); Up and Down move
	// the selection, Right opens an item or moves to its first child, Left
	// closes it or moves to its parent, Home and End; text: an item's text,
	// for type-ahead; height: the whole tree's (scrolled)
	public static function Tree<T>(props:{roots:Dynamic, children:T->Null<Array<T>>, render:T->Any, ?text:T->String, ?expanded:Signal<Array<T>>,
			?selected:Signal<Null<T>>, ?onActivate:T->Void, ?height:Float, ?rowHeight:Float, ?label:String, ?tag:String}):View {
		var selected:Signal<Null<T>> = props.selected ?? signal(null), expanded:Signal<Array<T>> = props.expanded ?? signal([]);
		var lines = memo(() -> Behaviour.treeLines(Render.read(props.roots), props.children, expanded.value));
		var typed = new TypeAhead(), again = doubled(), rows = new Map<Int, Element>();
		function setOpen(it:T, open:Bool) {
			var cur = expanded.peek(), i = cur.indexOf(it);
			if (open == (i >= 0)) return;
			var next = cur.copy();
			if (open) next.push(it) else next.splice(i, 1);
			expanded.value = next;
		}
		function indexOf(it:Null<T>):Int {
			var ls = lines.peek();
			for (i in 0...ls.length)
				if (it != null && ls[i].item == it) return i;
			return -1;
		}
		function activate(l:TreeLine<T>)
			if (!l.leaf) setOpen(l.item, !l.open) else if (props.onActivate != null) props.onActivate(l.item);
		function key(e:KeyboardEvent) {
			var ls = lines.peek(), i = indexOf(selected.peek()), j = i, k = keyOf(e);
			switch k {
				case Key.DOWN: j = i < 0 ? 0 : i + 1;
				case Key.UP: j = i < 0 ? 0 : i - 1;
				case Key.HOME: j = 0;
				case Key.END: j = ls.length - 1;
				case Key.RIGHT: if (i >= 0 && !ls[i].leaf) {
						if (!ls[i].open) setOpen(ls[i].item, true) else j = i + 1;
					}
				case Key.LEFT: if (i >= 0) {
						if (ls[i].open) setOpen(ls[i].item, false) else if (ls[i].parent >= 0) j = ls[i].parent;
					}
				case Key.ENTER: if (i >= 0) activate(ls[i]);
				case _:
					j = props.text == null ? -1 : typed.find(k, Dom.mods(e), Dom.now(), [for (l in ls) props.text(l.item)], i);
					if (j < 0) return;
			}
			e.preventDefault();
			if (ls.length == 0 || j == i) return;
			j = j < 0 ? 0 : j >= ls.length ? ls.length - 1 : j;
			selected.value = ls[j].item;
			var el = rows[j];
			if (el != null) (cast el).scrollIntoView({block: "nearest"});
		}
		return <div id={props.tag} role="tree" data-slot="tree" aria-label={props.label} tabindex="0" onKeyDown={key}
			aria-activedescendant={() -> {
				var i = indexOf(selected.value);
				i < 0 ? null : (props.tag ?? "tree") + "-" + i;
			}} style={props.height == null ? null : 'height:${props.height}px;overflow-y:auto'}>
			<Index each={lines} render={(l:Signal<TreeLine<T>>, i:Int) -> {
				var on = () -> selected.value == l.value.item;
				<div role="treeitem" id={(props.tag ?? "tree") + "-" + i} data-slot="tree-item" ref={n -> rows[i] = cast n} aria-level={() -> l.value.level}
					aria-expanded={() -> l.value.leaf ? null : l.value.open ? "true" : "false"} aria-selected={() -> on() ? "true" : "false"}
					data-selected={() -> on() ? "true" : null} data-state={() -> l.value.leaf ? null : l.value.open ? "open" : "closed"}
					style={props.rowHeight == null ? "height:26px" : 'height:${props.rowHeight}px'} onClick={() -> {
						if (again(l.value.item)) activate(l.value);
						selected.value = l.value.item;
					}}>
					<span data-slot="tree-toggle" aria-hidden="true" style={() -> 'width:14px;margin-inline-start:${(l.value.level - 1) * 16}px'}
						onClick={(e:Dynamic) -> if (!l.value.leaf) {
							setOpen(l.value.item, !l.value.open);
							e.stopPropagation();
						}}>{() -> l.value.leaf ? "" : l.value.open ? "▾" : "▸"}</span>
					{() -> props.render(l.value.item)}
				</div>;
			}}/>
		</div>;
	}

	// a list its user reorders: an item dragged goes where a line shows it
	// will (before or after the item under the pointer); one Tab stop, the
	// active item (Up, Down, Home, End), Alt+Up and Alt+Down move it;
	// onMove: after a move, the item and its new index
	public static function Sortable<T>(props:{items:Signal<Array<T>>, render:T->Any, ?onMove:(T, Int)->Void, ?label:String, ?tag:String}):View {
		var active = signal(0), over = signal(-1), held:Null<T> = null, said = signal(""), els = new Map<Int, Element>();
		function move(item:T, to:Int) {
			var m = Behaviour.moved(props.items.peek(), item, to);
			if (m == null) return;
			active.value = m.at;
			if (m.list.indexOf(item) != props.items.peek().indexOf(item)) {
				props.items.value = m.list;
				if (props.onMove != null) props.onMove(item, m.at);
			}
			window.requestAnimationFrame(_ -> Dom.focus(els[m.at]));
		}
		function key(e:KeyboardEvent, item:T) {
			var list = props.items.peek(), i = list.indexOf(item), alt = e.altKey, k = Dom.key(e);
			if (alt && (k == Key.UP || k == Key.DOWN)) {
				move(item, k == Key.UP ? i - 1 : i + 2);
				said.value = "Moved to position " + (props.items.peek().indexOf(item) + 1) + " of " + list.length;
			} else {
				var j = Behaviour.rove(k, i, list.length);
				if (j < 0 || k == Key.LEFT || k == Key.RIGHT) return;
				active.value = j;
				Dom.focus(els[j]);
			}
			e.preventDefault();
		}
		return <div id={props.tag} role="list" data-slot="sortable" aria-label={props.label} aria-description="Alt+Up and Alt+Down move an item">
			<div aria-live="polite" style="position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)">{said}</div>
			<For each={props.items} render={(item:T) -> {
				var at = () -> props.items.value.indexOf(item);
				<div role="listitem" data-slot="sortable-item" draggable="true" ref={n -> els[untrack(at)] = cast n} tabindex={() -> at() == active.value ? 0 : -1}
					data-dragging={() -> over.value >= 0 && held == item ? "" : null} onPointerDown={() -> active.value = at()}
					onKeyDown={(e:KeyboardEvent) -> key(e, item)} onDragStart={(e:Dynamic) -> {
						held = item;
						e.dataTransfer.effectAllowed = "move";
						e.dataTransfer.setData("text/plain", "");
					}} onDragEnd={() -> {
						held = null;
						over.value = -1;
					}} onDragOver={(e:Dynamic) -> if (held != null) {
						e.preventDefault();
						var r = e.currentTarget.getBoundingClientRect();
						over.value = 2 * at() + (e.clientY > r.top + r.height / 2 ? 1 : 0);
					}} onDrop={(e:Dynamic) -> {
						e.preventDefault();
						var to = over.peek();
						over.value = -1;
						if (to >= 0 && held != null) move(held, (to >> 1) + (to & 1));
					}}>
					<span data-slot="sortable-handle" aria-hidden="true">⋮⋮</span>
					{props.render(item)}
					<Show when={() -> over.value == 2 * at()}><div data-slot="sortable-indicator" data-side="top" style="position:absolute;left:0;right:0"/></Show>
					<Show when={() -> over.value == 2 * at() + 1}><div data-slot="sortable-indicator" data-side="bottom" style="position:absolute;left:0;right:0"/></Show>
				</div>;
			}}/>
		</div>;
	}

	// a toolbar: its children in a row, their focusable ones one Tab stop
	// (the last focused, at first the first); Left and Right (wrapping),
	// Home and End move the focus between them (not out of a text field)
	public static function Toolbar(props:{?label:String, ?tag:String, ?children:Any}):View {
		var bar:Element = null;
		function items():Array<Element>
			return [for (n in bar.querySelectorAll("button,input,select,textarea,a[href],[tabindex]")) (cast n : Element)].filter(e -> e.closest("[role=toolbar]") == bar);
		function rove(k:Element)
			for (e in items())
				e.setAttribute("tabindex", e == k ? "0" : "-1");
		onMount(() -> {
			var all = items();
			if (all.length > 0) rove(all[0]);
		});
		return <div id={props.tag} role="toolbar" data-slot="toolbar" aria-label={props.label} ref={n -> bar = cast n}
			onFocusIn={(e:Dynamic) -> if (items().indexOf(e.target) >= 0) rove(e.target)} onKeyDown={(e:KeyboardEvent) -> {
				var all = items(), i = all.indexOf(cast e.target), t:Element = cast e.target;
				if (i < 0 || t.localName == "input" || t.localName == "textarea") return;
				var k = keyOf(e), j = Behaviour.rove(k, i, all.length, false);
				if (j < 0) return;
				e.preventDefault();
				rove(all[j]);
				Dom.focus(all[j]);
			}}>{props.children}</div>;
	}

	// two panes side by side (direction "row", the default) or one above the
	// other ("column"), a handle between them dragged or moved by the arrow
	// keys (10 pixels; Home and End: the bounds); size: the first pane's
	// (200), from min (0) to max (the room less min)
	public static function Split(props:{first:Any, second:Any, ?size:Signal<Float>, ?direction:String, ?min:Float, ?max:Float, ?label:String,
			?tag:String}):View {
		var row = props.direction != "column", size:Signal<Float> = props.size ?? signal(200.0), lo = props.min ?? 0.0, self:Element = null;
		var active = signal(false), grab = 0.0;
		function hi():Float {
			var room = self == null || self.offsetWidth <= 0 ? 1e9 : (row ? self.offsetWidth : self.offsetHeight) - lo;
			return Math.max(lo, props.max == null ? room : Math.min(props.max, room));
		}
		function set(v:Float)
			size.value = Math.round(Math.max(lo, Math.min(hi(), v)));
		var dir = row ? "horizontal" : "vertical";
		return <div id={props.tag} data-slot="resizable-panel-group" aria-orientation={dir} data-panel-group-direction={dir} ref={n -> self = cast n}>
			<div data-slot="resizable-panel" style={() -> 'flex:0 0 ${size.value}px;overflow:hidden'}>{props.first}</div>
			<div data-slot="resizable-handle" role="separator" tabindex="0" aria-label={props.label} aria-orientation={row ? "vertical" : "horizontal"}
				data-panel-group-direction={dir} aria-valuenow={size} aria-valuemin={lo} data-resize-handle-state={() -> active.value ? "drag" : "inactive"}
				style={row ? "cursor:ew-resize" : "cursor:ns-resize"} onPointerDown={(e:Dynamic) -> {
					active.value = true;
					e.target.setPointerCapture(e.pointerId);
					var r = self.getBoundingClientRect();
					grab = (row ? e.clientX - r.left : e.clientY - r.top) - size.peek();
				}} onPointerMove={(e:Dynamic) -> if (active.peek()) {
					var r = self.getBoundingClientRect(), at = (row ? e.clientX - r.left : e.clientY - r.top) - grab;
					set(row && Dom.rtl(self) ? r.width - at : at);
				}} onPointerUp={() -> active.value = false} onKeyDown={(e:KeyboardEvent) -> {
					var k = row ? keyOf(e) : Dom.key(e);
					var v = switch k {
						case Key.LEFT | Key.UP: size.peek() - 10;
						case Key.RIGHT | Key.DOWN: size.peek() + 10;
						case Key.HOME: lo;
						case Key.END: hi();
						case _: Math.NaN;
					}
					if (!Math.isNaN(v)) {
						e.preventDefault();
						set(v);
					}
				}}/>
			<div data-slot="resizable-panel" style="flex:1 1 0;overflow:hidden">{props.second}</div>
		</div>;
	}

	// a tag input: tags as chips before a text field in one box; Enter or a
	// comma adds what is typed (trimmed, once), Backspace in an empty field
	// takes the last one off, a chip's × takes it off; a click in the box focuses the field
	public static function TagInput(props:{tags:Signal<Array<String>>, ?placeholder:String, ?label:String, ?tag:String}):View {
		var field:js.html.InputElement = null;
		function add(text:String) {
			var v = StringTools.trim(text);
			field.value = "";
			if (v == "" || props.tags.peek().indexOf(v) >= 0) return;
			props.tags.value = props.tags.peek().concat([v]);
		}
		function remove(v:String)
			props.tags.value = props.tags.peek().filter(x -> x != v);
		return <div id={props.tag} data-slot="tag-input" onPointerDown={(e:Dynamic) -> if (e.target != field) {
				e.preventDefault();
				field.focus();
			}}>
			<ul data-slot="tag-input-list" role="list" aria-label={props.label}>
				<For each={props.tags} render={(v:String) -> <li data-slot="badge" data-variant="secondary" role="listitem">{v}<button type="button" data-slot="tag-input-remove"
					aria-label={"Remove " + v} onClick={() -> remove(v)}>×</button></li>}/>
			</ul>
			<span data-slot="tag-input-entry"><input data-slot="tag-input-field" ref={n -> field = cast n} placeholder={props.placeholder}
				aria-label={props.label ?? props.placeholder} onInput={() -> if (StringTools.endsWith(field.value, ",")) add(field.value.substr(0, field.value.length - 1))}
				onKeyDown={(e:KeyboardEvent) -> {
					var list = props.tags.peek();
					if (e.key == "Enter") {
						e.preventDefault();
						add(field.value);
					} else if (e.key == "Backspace" && field.value == "" && list.length > 0) {
						e.preventDefault();
						remove(list[list.length - 1]);
					}
				}}/></span>
		</div>;
	}

	// a colour picker: a square of saturation and brightness in the hue, a
	// strip of hues, a swatch and the colour's hex in a field (what is typed
	// there, once a CSS colour, sets it); value: an opaque colour; the square
	// and the strip are sliders for the keyboard (Shift: ten times as far)
	public static function ColorPicker(props:{value:Signal<hxmc.ui.Color>, ?size:Float, ?label:String, ?tag:String}):View {
		var size = props.size ?? 160.0, name = props.label ?? "Colour";
		var hue = signal(0.0), sat = signal(0.0), val = signal(0.0), hex = signal(""), area:Element = null, strip:Element = null;
		function load(c:hxmc.ui.Color) {
			var x = Behaviour.hsvOf(c);
			batch(() -> {
				if (x.h != null) hue.value = x.h;
				sat.value = x.s;
				val.value = x.v;
			});
		}
		function store() {
			var c = Behaviour.hsv(hue.peek(), sat.peek(), val.peek());
			if (c != props.value.peek()) props.value.value = c;
		}
		effect(() -> {
			var c = props.value.value;
			untrack(() -> {
				if (Behaviour.hsv(hue.peek(), sat.peek(), val.peek()) != c) load(c);
				var typed = hxmc.ui.Color.tryParse(StringTools.trim(hex.peek()).toLowerCase());
				if (typed == null || hxmc.ui.Color.rgb(typed) != c) hex.value = c.toHex().substr(0, 7);
			});
		});
		effect(() -> {
			var c = hxmc.ui.Color.tryParse(StringTools.trim(hex.value).toLowerCase());
			if (c != null) untrack(() -> props.value.value = hxmc.ui.Color.rgb(c));
		});
		inline function clamp(x:Float):Float
			return x < 0 ? 0 : x > 1 ? 1 : x;
		function pick(e:Dynamic, f:Float->Float->Void) {
			var r = e.currentTarget.getBoundingClientRect();
			f(clamp((e.clientX - r.left) / r.width), clamp((e.clientY - r.top) / r.height));
			store();
		}
		var pct = (x:Float) -> Math.round(x * 100);
		var draggable = (f:Float->Float->Void) -> {
			var down = false;
			return {
				d: (e:Dynamic) -> {
					down = true;
					e.currentTarget.setPointerCapture(e.pointerId);
					e.currentTarget.focus();
					pick(e, f);
				},
				m: (e:Dynamic) -> if (down) pick(e, f),
				u: () -> down = false
			};
		};
		var sv = draggable((x, y) -> batch(() -> {
			sat.value = x;
			val.value = 1 - y;
		})), hu = draggable((x, _) -> hue.value = x * 359.999);
		return <div id={props.tag} data-slot="color-picker" role="group" aria-label={name} style={'width:${size}px'}>
			<div data-slot="color-picker-area" role="slider" tabindex="0" ref={n -> area = cast n} aria-label={name + ": saturation and brightness"}
				aria-valuenow={() -> pct(sat.value)} aria-valuemin="0" aria-valuemax="100" aria-valuetext={() -> "saturation " + pct(sat.value) + "%, brightness " + pct(val.value) + "%"}
				style={() -> 'width:${size}px;height:${size}px;background:linear-gradient(to bottom,transparent,#000),linear-gradient(to right,#fff,${Behaviour.hsv(hue.value, 1, 1).toHex().substr(0, 7)})'}
				onPointerDown={sv.d} onPointerMove={sv.m} onPointerUp={sv.u} onKeyDown={(e:KeyboardEvent) -> {
					var d = e.shiftKey ? 0.1 : 0.01;
					switch Dom.key(e) {
						case Key.LEFT: sat.value = clamp(sat.peek() - d);
						case Key.RIGHT: sat.value = clamp(sat.peek() + d);
						case Key.UP: val.value = clamp(val.peek() + d);
						case Key.DOWN: val.value = clamp(val.peek() - d);
						case _: return;
					}
					e.preventDefault();
					store();
				}}>
				<div data-slot="color-picker-thumb" style={() -> 'position:absolute;width:14px;height:14px;left:${sat.value * size}px;top:${(1 - val.value) * size}px;transform:translate(-50%,-50%)'}/>
			</div>
			<div data-slot="color-picker-hue" role="slider" tabindex="0" ref={n -> strip = cast n} aria-label={name + ": hue"} aria-valuenow={() -> Math.round(hue.value)}
				aria-valuemin="0" aria-valuemax="359" aria-valuetext={() -> Math.round(hue.value) + "°"}
				style={'width:${size}px;height:12px;background:linear-gradient(to right,#f00,#ff0,#0f0,#0ff,#00f,#f0f,#f00)'} onPointerDown={hu.d} onPointerMove={hu.m}
				onPointerUp={hu.u} onKeyDown={(e:KeyboardEvent) -> {
					var d = e.shiftKey ? 10 : 1;
					switch Dom.key(e) {
						case Key.LEFT | Key.DOWN: hue.value = Math.max(0, hue.peek() - d);
						case Key.RIGHT | Key.UP: hue.value = Math.min(359, hue.peek() + d);
						case Key.HOME: hue.value = 0;
						case Key.END: hue.value = 359;
						case _: return;
					}
					e.preventDefault();
					store();
				}}>
				<div data-slot="color-picker-thumb" data-hue="" style={() -> 'position:absolute;width:14px;height:14px;left:${hue.value / 360 * size}px;top:50%;transform:translate(-50%,-50%);background:${Behaviour.hsv(hue.value, 1, 1).toHex().substr(0, 7)}'}/>
			</div>
			<div data-slot="color-picker-row">
				<div data-slot="color-picker-swatch" style={() -> 'flex-shrink:0;width:36px;height:36px;background:${props.value.value.toHex().substr(0, 7)}'}/>
				<div style="flex:1" dir="ltr"><Input value={hex} label={name + ": hex"}/></div>
			</div>
		</div>;
	}

	// --- the third batch: Field, ButtonGroup, InputGroup, Empty, Item, AspectRatio, ScrollArea, NativeSelect, Carousel, NavigationMenu, Sidebar, charts ---

	// an input group (shadcn's): an InputGroupInput with addons in one box;
	// a click on an addon (not on its button) focuses the input
	public static function InputGroup(props:{?label:String, ?disabled:Dynamic, ?children:Any, ?tag:String}):View
		return <div id={props.tag} role="group" data-slot="input-group" aria-label={props.label} data-disabled={() -> on(props.disabled) ? "true" : null}>
			{props.children}
		</div>;

	// align: "inline-start" (the default), "inline-end", "block-start", "block-end"
	public static function InputGroupAddon(props:{?align:String, ?children:Any, ?tag:String}):View {
		var a = props.align ?? "inline-start";
		return <div id={props.tag} role="group" data-slot="input-group-addon" data-align={a} data-variant={a} onClick={(e:Dynamic) -> {
			var t:Element = e.target, self:Element = e.currentTarget;
			if (t.closest("button") != null || self.parentElement == null) return;
			var input = self.parentElement.querySelector("[data-slot=input-group-control]");
			if (input != null) Dom.focus(cast input);
		}}>{props.children}</div>;
	}

	public static function InputGroupText(props:{?text:String, ?children:Any, ?tag:String}):View
		return <span id={props.tag} data-slot="input-group-text">{props.children ?? props.text}</span>;

	// a select the platform's own (shadcn's NativeSelect: a <select>, its
	// options the browser's menu), bound to a signal
	public static function NativeSelect(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?label:String,
			?disabled:Dynamic, ?tag:String}):View {
		var self:Null<js.html.SelectElement> = null;
		effect(() -> {
			var v = props.value.value;
			if (self != null) self.value = v;
		});
		return <div data-slot="native-select-wrapper">
			<select id={props.tag} data-slot="native-select" data-size="default" aria-label={props.label} disabled={() -> on(props.disabled)}
				style={props.width == null ? null : 'width:${props.width}px'} ref={n -> {
					self = cast n;
					self.value = props.value.peek();
				}} onChange={(e:Dynamic) -> props.value.value = e.target.value}>{[
				for (i in 0...props.options.length)
					<option data-slot="native-select-option" value={props.options[i]}>{props.labels != null ? props.labels[i] : props.options[i]}</option>
			]}</select>
			{icon("chevron-down", "native-select-icon")}
		</div>;
	}

	// a carousel (shadcn's, Embla's look): slides in a row (vertical: a
	// column) through a viewport, index the slide at its start; Previous and
	// Next (disabled at the ends unless loop), Left and Right (vertical: Up
	// and Down; right to left mirrored) move it
	public static function Carousel(props:{slides:Array<Any>, ?index:Signal<Int>, ?orientation:String, ?loop:Bool, ?label:String, ?tag:String}):View {
		var index = props.index ?? signal(0), count = props.slides.length, loop = props.loop == true;
		var o = props.orientation == "vertical" ? "vertical" : "horizontal", vertical = o == "vertical";
		var items:Array<Element> = [], track:Null<Element> = null;
		function go(i:Int)
			if (count > 0) index.value = loop ? (i % count + count) % count : i < 0 ? 0 : i >= count ? count - 1 : i;
		// (the track moved by the slide's offset from the first's)
		effect(() -> {
			var i = index.value;
			if (track == null || items[i] == null) return;
			var d = vertical ? items[0].offsetTop - items[i].offsetTop : items[0].offsetLeft - items[i].offsetLeft;
			track.style.transform = vertical ? 'translate3d(0,${d}px,0)' : 'translate3d(${d}px,0,0)';
		});
		var prevOff = () -> !loop && index.value <= 0, nextOff = () -> !loop && index.value >= count - 1;
		function nav(slot:String, label:String, glyph:String, off:Void->Bool, d:Int):View
			return <button type="button" data-slot={slot} data-orientation={o} aria-label={label} disabled={off} onClick={() -> go(index.peek() + d)}>
				{icon(glyph)}
			</button>;
		return <div id={props.tag} data-slot="carousel" role="region" aria-roledescription="carousel" aria-label={props.label ?? "Carousel"} data-orientation={o}
			onKeyDown={(e:KeyboardEvent) -> {
				var k = vertical ? Dom.key(e) : keyOf(e);
				var d = k == (vertical ? Key.UP : Key.LEFT) ? -1 : k == (vertical ? Key.DOWN : Key.RIGHT) ? 1 : 0;
				if (d == 0) return;
				e.preventDefault();
				go(index.peek() + d);
			}}>
			<div data-slot="carousel-content">
				<div data-slot="carousel-track" data-orientation={o} ref={n -> track = cast n} style="transition:transform .25s ease">{[
					for (i in 0...count)
						<div data-slot="carousel-item" role="group" aria-roledescription="slide" aria-label={'${i + 1} of $count'} data-orientation={o}
							ref={n -> items[i] = cast n}>{props.slides[i]}</div>
				]}</div>
			</div>
			{nav("carousel-previous", "Previous slide", "arrow-left", prevOff, -1)}
			{nav("carousel-next", "Next slide", "arrow-right", nextOff, 1)}
		</div>;
	}

	// a navigation menu (shadcn's, Radix's): a row of triggers whose panels
	// (render) open in a viewport under the menu, and links (onSelect); a
	// click, Enter, Space or Down opens a panel (its first focusable focused
	// by the keys), the pointer onto another trigger while one is open
	// switches; Left and Right (mirrored) move between the items, Home and
	// End; Escape closes, the focus back on the trigger
	public static function NavigationMenu(props:{items:Array<{label:String, ?render:Void->Any, ?onSelect:Void->Void}>, ?open:Signal<Int>, ?label:String,
			?tag:String}):View {
		var items = props.items, count = items.length, open = props.open ?? signal(-1), triggers:Array<Element> = [], root:Element = null, byKeys = false;
		function show(i:Int, keys:Bool) {
			byKeys = keys;
			open.value = i;
		}
		function key(e:KeyboardEvent, i:Int) {
			var it = items[i], k = keyOf(e);
			switch k {
				case Key.ENTER | Key.SPACE | Key.DOWN:
					if (it.render == null && k == Key.DOWN) return;
					e.preventDefault();
					if (it.render != null) show(open.peek() == i && k != Key.DOWN ? -1 : i, true) else if (it.onSelect != null) it.onSelect();
				case Key.ESCAPE if (open.peek() >= 0):
					e.preventDefault();
					open.value = -1;
				case _:
					var j = Behaviour.rove(k, i, count, false);
					if (j < 0) return;
					e.preventDefault();
					focusIn(triggers, j);
			}
		}
		Dom.popup(() -> open.value >= 0, () -> <div data-slot="navigation-menu-viewport" data-state="open" data-orientation="horizontal"
			onKeyDown={(e:KeyboardEvent) -> if (e.key == "Escape") {
				e.preventDefault();
				var i = open.peek();
				open.value = -1;
				focusIn(triggers, i);
			}}>{() -> {
				var i = open.value;
				i >= 0 && items[i].render != null ? <div data-slot="navigation-menu-content" data-state="open" data-orientation="horizontal">{items[i].render()}</div> : null;
			}}</div>, {
			anchor: () -> root,
			offset: 0,
			onDismiss: () -> open.value = -1,
			onOpen: h -> if (byKeys) Dom.focus(Dom.firstFocusable(h))
		});
		return <nav id={props.tag} data-slot="navigation-menu" aria-label={props.label ?? "Main"} data-orientation="horizontal" data-viewport="true"
			ref={n -> root = cast n}>
			<div style="position:relative">
				<ul data-slot="navigation-menu-list" data-orientation="horizontal">{[
					for (i in 0...count) {
						var it = items[i], state = () -> open.value == i ? "open" : "closed";
						<li data-slot="navigation-menu-item">{
							it.render != null ? <button type="button" data-slot="navigation-menu-trigger" data-state={state} aria-expanded={() -> open.value == i ? "true" : "false"}
								ref={n -> triggers[i] = cast n} onClick={() -> show(open.peek() == i ? -1 : i, false)}
								onPointerEnter={() -> if (open.peek() >= 0 && open.peek() != i) show(i, false)} onKeyDown={(e:KeyboardEvent) -> key(e, i)}>
								{it.label}{" "}{icon("chevron-down", "navigation-menu-trigger-icon")}
							</button> : <a data-slot="navigation-menu-link" href="#" ref={n -> triggers[i] = cast n} onClick={(e:Dynamic) -> {
								e.preventDefault();
								if (it.onSelect != null) it.onSelect();
							}} onKeyDown={(e:KeyboardEvent) -> key(e, i)}>{it.label}</a>
						}</li>;
					}
				]}</ul>
			</div>
		</nav>;
	}

	// --- shadcn's Sidebar ---

	// a sidebar's layout (shadcn's SidebarProvider): open shared with its
	// Sidebar and SidebarTrigger; Mod+B toggles it from anywhere
	public static function SidebarProvider(props:{?open:Signal<Bool>, ?children:Any, ?tag:String}):View {
		var open = props.open ?? signal(true), mod = Shortcut.parse("Mod+B");
		function down(e:KeyboardEvent)
			if (!e.defaultPrevented && mod.matches(Dom.key(e), Dom.mods(e))) {
				e.preventDefault();
				open.value = !open.peek();
			}
		document.addEventListener("keydown", down);
		onCleanup(() -> document.removeEventListener("keydown", down));
		return <div id={props.tag} data-slot="sidebar-wrapper" data-state={() -> open.value ? "expanded" : "collapsed"}>
			{Provider({context: SIDEBAR, value: open, children: props.children})}
		</div>;
	}

	// a sidebar (shadcn's): side "left" or "right", variant "sidebar",
	// "floating" or "inset", collapsible "offcanvas", "icon" or "none";
	// shadcn's gap (its width in flow), container and inner box
	public static function Sidebar(props:{?side:String, ?variant:String, ?collapsible:String, ?label:String, ?children:Any, ?tag:String}):View {
		var open = use(SIDEBAR) ?? signal(true), collapsible = props.collapsible ?? "offcanvas";
		var variant = props.variant ?? "sidebar", side = props.side ?? "left";
		var expanded = () -> collapsible == "none" || open.value;
		return <div id={props.tag} data-slot="sidebar" data-state={() -> expanded() ? "expanded" : "collapsed"} data-collapsible={() -> expanded() ? "" : collapsible}
			data-variant={variant} data-side={side}>
			<div data-slot="sidebar-gap" data-variant={variant}/>
			<nav data-slot="sidebar-container" data-side={side} data-variant={variant} aria-label={props.label ?? "Sidebar"}>
				<div data-slot="sidebar-inner" data-sidebar="sidebar">{props.children}</div>
			</nav>
		</div>;
	}

	// --- charts (shadcn's Chart's look, recharts' kinds) ---

	// (a scale's top: the value rounded up to 1, 2, 2.5 or 5 times a power of ten)
	static function niceMax(v:Float):Float {
		if (!(v > 0)) return 1;
		var p = Math.pow(10, Math.floor(Math.log(v) / Math.log(10)));
		for (m in [1.0, 2.0, 2.5, 5.0, 10.0])
			if (m * p >= v - 1e-9) return m * p;
		return 10 * p;
	}

	// (a series' colour: its own, else the theme's --chart-N by data-series)
	static function seriesStyle(c:Null<hxmc.ui.Color>, prop:String):Null<String>
		return c == null ? null : prop + ":" + c.toHex().substr(0, 7);

	// (a chart's frame: the y axis's ticks and the grid, the plot, the x
	// axis's labels, the legend; the category under the pointer in shadcn's
	// tooltip, each series' value)
	static function chartFrame(tag:Null<String>, labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:hxmc.ui.Color}>, w:Float, h:Float,
			top:Float, plot:View, hover:Signal<Int>, label:Null<String>, format:Float->String):View {
		var n = labels.length, axis = 40.0;
		return <div id={tag} data-slot="chart" role="img" aria-label={label ?? "Chart"} style="align-items:flex-start">
			<div style="display:flex">
				<div data-slot="chart-y-axis" style={'position:relative;width:${axis}px;height:${h}px'}>{[
					for (t in 0...5)
						<span data-slot="chart-tick" style={'position:absolute;right:6px;top:${h - t / 4 * h - 7}px;line-height:14px'}>{format(top * t / 4)}</span>
				]}</div>
				<div data-slot="chart-plot" style={'position:relative;width:${w}px;height:${h}px'} onPointerMove={(e:Dynamic) -> {
					var r = (e.currentTarget : Element).getBoundingClientRect(), i = n == 0 ? -1 : Std.int((e.clientX - r.left) / (w / n));
					hover.value = i >= 0 && i < n ? i : -1;
				}} onPointerLeave={() -> hover.value = -1}>
					{[for (t in 0...5) <div data-slot="chart-grid" style={'position:absolute;left:0;width:${w}px;top:${h - t / 4 * h}px;height:1px'}/>]}
					{plot}
					<Show when={() -> hover.value >= 0}>{() -> {
						var i = hover.value;
						<div data-slot="chart-tooltip" style={'position:absolute;top:4px;left:${Math.min(w - 120, (i + 0.5) * w / n + 8)}px'}>
							<div data-slot="chart-tooltip-label">{labels[i]}</div>
							<div style="display:grid;gap:6px">{[
								for (k in 0...series.length)
									<div data-slot="chart-tooltip-item">
										<div data-slot="chart-tooltip-indicator" data-series={Std.string(k % 5 + 1)} style={seriesStyle(series[k].color, "background-color")}/>
										<div style="display:flex;flex:1;justify-content:space-between;align-items:center;line-height:1">
											<span data-slot="chart-tooltip-name">{series[k].name}</span>
											<span data-slot="chart-tooltip-value">{format(series[k].values[i])}</span>
										</div>
									</div>
							]}</div>
						</div>;
					}}</Show>
				</div>
			</div>
			<div data-slot="chart-x-axis" style={'display:flex;margin-left:${axis}px;width:${w}px'}>{[
				for (l in labels) <span data-slot="chart-tick" style="flex:1 1 0;text-align:center">{l}</span>
			]}</div>
			<div data-slot="chart-legend" style={'margin-left:${axis}px;width:${w}px'}>{[
				for (k in 0...series.length)
					<div data-slot="chart-legend-item">
						<div data-slot="chart-legend-swatch" data-series={Std.string(k % 5 + 1)} style={seriesStyle(series[k].color, "background-color")}/>{series[k].name}
					</div>
			]}</div>
		</div>;
	}

	// a bar chart: categories along the x axis, a bar per series in each on
	// a scale from 0 to a round top; the pointer over a category shows its values
	public static function BarChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:hxmc.ui.Color}>, ?width:Float,
			?height:Float, ?max:Float, ?format:Float->String, ?label:String, ?tag:String}):View {
		var w = props.width ?? 300.0, h = props.height ?? 160.0, n = props.labels.length, hover = signal(-1), series = props.series;
		var top = props.max ?? niceMax(Lambda.fold(series, (s, m) -> Math.max(m, Lambda.fold(s.values, Math.max, 0.0)), 0.0));
		var format = props.format ?? Behaviour.plain, slot = n == 0 ? 0.0 : w / n;
		var barW = series.length == 0 ? 0.0 : slot * 0.7 / series.length;
		var plot = <div style={'position:absolute;left:0;top:0;width:${w}px;height:${h}px;display:flex'}>{[
			for (i in 0...n)
				<div role="group" aria-label={props.labels[i] + ": " + [for (s in series) s.name + " " + format(s.values[i])].join(", ")}
					style={'width:${slot}px;height:${h}px;display:flex;justify-content:center;align-items:flex-end'}>{[
					for (k in 0...series.length)
						<div data-slot="chart-bar" data-series={Std.string(k % 5 + 1)} data-active={() -> hover.value == i ? "true" : null}
							style={'width:${barW}px;height:${Math.max(0, Math.min(1, series[k].values[i] / top)) * h}px' + (series[k].color == null ? "" : ";" + seriesStyle(series[k].color, "background-color"))}/>
				]}</div>
		]}</div>;
		return chartFrame(props.tag, props.labels, series, w, h, top, plot, hover, props.label, format);
	}

	// a line chart: a line per series through its values, on BarChart's
	// scale and frame; a dot on each line at the category under the pointer
	public static function LineChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:hxmc.ui.Color}>, ?width:Float,
			?height:Float, ?max:Float, ?format:Float->String, ?label:String, ?tag:String}):View
		return seriesChart(props, false);

	// an area chart: LineChart's lines, each filled faintly down to the axis
	public static function AreaChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:hxmc.ui.Color}>, ?width:Float,
			?height:Float, ?max:Float, ?format:Float->String, ?label:String, ?tag:String}):View
		return seriesChart(props, true);

	// (LineChart's and AreaChart's: a line per series, filled under it for an area)
	static function seriesChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:hxmc.ui.Color}>, ?width:Float,
			?height:Float, ?max:Float, ?format:Float->String, ?label:String, ?tag:String}, area:Bool):View {
		var w = props.width ?? 300.0, h = props.height ?? 160.0, n = props.labels.length, hover = signal(-1), series = props.series;
		var top = props.max ?? niceMax(Lambda.fold(series, (s, m) -> Math.max(m, Lambda.fold(s.values, Math.max, 0.0)), 0.0));
		var format = props.format ?? Behaviour.plain, slot = n == 0 ? 0.0 : w / n;
		var px = (i:Int) -> (i + 0.5) * slot, py = (v:Float) -> h - Math.max(0, Math.min(1, v / top)) * h;
		var plot = <div style={'position:absolute;left:0;top:0;width:${w}px;height:${h}px'}>{[
			for (k in 0...series.length) {
				var svg = document.createElementNS(hxmc.web.Html.SVG_NS, "svg");
				for (a in [["viewBox", '0 0 $w $h'], ["width", '$w'], ["height", '$h'], ["data-slot", area ? "chart-area" : "chart-line"], ["data-series", Std.string(k % 5 + 1)],
					["aria-hidden", "true"], ["style", "position:absolute;left:0;top:0" + (series[k].color == null ? "" : ";" + seriesStyle(series[k].color, "color"))]])
					svg.setAttribute(a[0], a[1]);
				var path = document.createElementNS(hxmc.web.Html.SVG_NS, "path");
				var d = [for (i in 0...n) (i == 0 ? "M" : "L") + Math.fround(px(i) * 100) / 100 + " " + Math.fround(py(series[k].values[i]) * 100) / 100].join(" ");
				path.setAttribute("d", d);
				// (an area's: the line's points closed along the axis, filled faintly)
				if (area && n > 0) {
					var under = document.createElementNS(hxmc.web.Html.SVG_NS, "path");
					under.setAttribute("d", 'M${Math.fround(px(0) * 100) / 100} $h ${d.substr(1)} L${Math.fround(px(n - 1) * 100) / 100} $h Z');
					under.setAttribute("fill", "currentColor");
					under.setAttribute("fill-opacity", "0.4");
					svg.appendChild(under);
				}
				for (a in [["fill", "none"], ["stroke", "currentColor"], ["stroke-width", "2"], ["stroke-linejoin", "round"], ["stroke-linecap", "round"]])
					path.setAttribute(a[0], a[1]);
				svg.appendChild(path);
				[
					(svg : Any),
					<Show when={() -> hover.value >= 0}>{() -> <div data-slot="chart-dot" data-series={Std.string(k % 5 + 1)}
						style={'position:absolute;width:8px;height:8px;border-radius:4px;left:${px(hover.value) - 4}px;top:${py(series[k].values[hover.value]) - 4}px'
							+ (series[k].color == null ? "" : ";" + seriesStyle(series[k].color, "background-color"))}/>}</Show>
				];
			}
		]}</div>;
		return chartFrame(props.tag, props.labels, series, w, h, top, plot, hover, props.label, format);
	}

	// a pie chart: a slice per value clockwise from the top, its share of
	// the circle its share of the total; a donut with inner (its hole's
	// radius, a fraction); the pointer over a slice shows its name and value
	public static function PieChart(props:{slices:Array<{name:String, value:Float, ?color:hxmc.ui.Color}>, ?size:Float, ?inner:Float, ?format:Float->String,
			?label:String, ?tag:String}):View {
		var size = props.size ?? 200.0, slices = props.slices, hover = signal(-1), format = props.format ?? Behaviour.plain;
		var total = Lambda.fold(slices, (sl, t) -> t + Math.max(0, sl.value), 0.0);
		var c = size / 2, r = size / 2 - 1, ri = Math.max(0, Math.min(1, props.inner ?? 0)) * r;
		var ends = [], at = 0.0;
		for (sl in slices) {
			var from = at;
			at += total > 0 ? Math.max(0, sl.value) / total : 0;
			ends.push({from: from, to: at});
		}
		function num(v:Float):String
			return Std.string(Math.fround(v * 100) / 100);
		function point(t:Float, rad:Float):String
			return num(c + rad * Math.sin(t * 2 * Math.PI)) + " " + num(c - rad * Math.cos(t * 2 * Math.PI));
		function path(from:Float, to:Float):String {
			if (to - from >= 1 - 1e-9)
				return ri > 0 ? 'M${point(0, r)} A$r $r 0 1 1 ${point(0.5, r)} A$r $r 0 1 1 ${point(0, r)} M${point(0, ri)} A$ri $ri 0 1 0 ${point(0.5, ri)} A$ri $ri 0 1 0 ${point(0, ri)} Z' : 'M${point(0, r)} A$r $r 0 1 1 ${point(0.5, r)} A$r $r 0 1 1 ${point(0, r)} Z';
			var large = to - from > 0.5 ? 1 : 0;
			return ri > 0 ? 'M${point(from, r)} A$r $r 0 $large 1 ${point(to, r)} L${point(to, ri)} A$ri $ri 0 $large 0 ${point(from, ri)} Z' : 'M$c $c L${point(from, r)} A$r $r 0 $large 1 ${point(to, r)} Z';
		}
		var svg = document.createElementNS(hxmc.web.Html.SVG_NS, "svg");
		for (a in [["viewBox", '0 0 $size $size'], ["width", '$size'], ["height", '$size'], ["style", "position:absolute;left:0;top:0"]])
			svg.setAttribute(a[0], a[1]);
		var paths:Array<Element> = [];
		for (k in 0...slices.length)
			if (ends[k].to > ends[k].from) {
				var p = document.createElementNS(hxmc.web.Html.SVG_NS, "path");
				for (a in [["d", path(ends[k].from, ends[k].to)], ["fill", "currentColor"], ["fill-rule", "evenodd"], ["data-slot", "chart-slice"],
					["data-series", Std.string(k % 5 + 1)], ["role", "img"], ["aria-label", slices[k].name + ": " + format(slices[k].value)]])
					p.setAttribute(a[0], a[1]);
				if (slices[k].color != null) p.setAttribute("style", seriesStyle(slices[k].color, "color"));
				p.addEventListener("pointerenter", () -> hover.value = k);
				p.addEventListener("pointerleave", () -> if (hover.peek() == k) hover.value = -1);
				paths[k] = p;
				svg.appendChild(p);
			}
		effect(() -> {
			var h = hover.value;
			for (k in 0...paths.length)
				if (paths[k] != null) if (h == k) paths[k].setAttribute("data-active", "true") else paths[k].removeAttribute("data-active");
		});
		return <div id={props.tag} data-slot="chart" role="img" aria-label={props.label ?? "Chart"} style="align-items:center">
			<div data-slot="chart-plot" style={'position:relative;width:${size}px;height:${size}px'}>
				{(svg : Any)}
				<Show when={() -> hover.value >= 0}>{() -> {
					var k = hover.value;
					<div data-slot="chart-tooltip" style="position:absolute;top:4px;left:4px;display:flex;align-items:center;gap:6px">
						<div data-slot="chart-tooltip-indicator" data-series={Std.string(k % 5 + 1)} style={seriesStyle(slices[k].color, "background-color")}/>
						<span data-slot="chart-tooltip-label">{slices[k].name}</span>
						<span data-slot="chart-tooltip-value">{format(slices[k].value)}</span>
					</div>;
				}}</Show>
			</div>
			<div data-slot="chart-legend" style={'flex-wrap:wrap;width:${Math.max(size, 240)}px'}>{[
				for (k in 0...slices.length)
					<div data-slot="chart-legend-item">
						<div data-slot="chart-legend-swatch" data-series={Std.string(k % 5 + 1)} style={seriesStyle(slices[k].color, "background-color")}/>{slices[k].name}
					</div>
			]}</div>
		</div>;
	}
}
#end
