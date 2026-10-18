package hxmc.ui.widgets;

import hxmc.ui.*;
import hxmc.view.*;
import hxmc.ui.widgets.Behaviour.TypeAhead;
import hxmc.ui.view.*;
import hxmc.view.Reactive.*;
import hxmc.view.Signal;
import hxmc.ui.view.Motion;
import hxmc.view.Flow.*;
import hxmc.ui.view.UiFlow.*;
import hxmc.ui.widgets.Days;
import hxmc.ui.widgets.Toasts;
import hxmc.ui.access.AccessTree;

// a tree's visible row: its item, depth (from 1), parent's row (-1: a root), whether it has no children, is open
typedef TreeRow<T> = Behaviour.TreeLine<T>;

// a range of days (Calendar's range): its first and last (null: not chosen yet)
typedef DayRange = {from:Null<Day>, to:Null<Day>};

// a menu's item: its label, what choosing it does, a shortcut (shown, and
// choosing it from the window); variant "destructive" (shadcn's: for a
// theme), disabled (not chosen, skipped by the keys), or a separator
// (a menu's item: what choosing it does, a shortcut; a separator, a heading;
// checked: a checkbox item toggling it, radio: one of a group setting it;
// items: a submenu; Behaviour's MenuEntry, shared with the DOM's widgets)
typedef MenuItem = Behaviour.MenuEntry;

// Components for markup (import hxmc.ui.widgets.Widgets.*): built with
// hxmc.view, unstyled: behaviour, semantics and the geometry their
// interaction needs, their nodes' slots, states, variants and sizes (as
// shadcn's) for a theme's rules (Rules, StyleSheet): with none, no look
// at all (as React Aria's); props and an instance's own style override it.
// ui's renderer's only: in a page's markup (the DOM's renderer) each is
// hxmc.web.widgets.Widgets' of the same name (shadcn's markup), where it has one
@:renderer(hxmc.ui.view.NodeRenderer, hxmc.web.DomRenderer => hxmc.web.widgets.Widgets)
class Widgets implements Markup {
	// (a prop that may be a value, a signal or a function of one: its value, read where a reactive value tracks it)
	static function read(v:Dynamic):Dynamic
		return v == null ? null : Std.isOfType(v, Signal) ? (v : Signal<Dynamic>).value : Reflect.isFunction(v) ? v() : v;

	// (a check mark and a dash, lucide's: drawn in the text's colour)
	static final CHECK = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>');
	static final CIRCLE = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/></svg>');
	static final CHEVRON = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>');
	static final X = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>');
	static final LOADER = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-6.219-8.56"/></svg>');
	static final SEARCH = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21 21-4.34-4.34"/><circle cx="11" cy="11" r="8"/></svg>');
	static final CHEVRON_RIGHT = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>');
	static final CHEVRON_LEFT = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>');
	static final ARROW_LEFT = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m12 19-7-7 7-7"/><path d="M19 12H5"/></svg>');
	static final ARROW_RIGHT = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="m12 5 7 7-7 7"/></svg>');
	static final ARROW_UP = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 7-7 7 7"/><path d="M12 19V5"/></svg>');
	static final ARROW_DOWN = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14"/><path d="m19 12-7 7-7-7"/></svg>');
	static final MORE = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/></svg>');
	static final PANEL_LEFT = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="18" x="3" y="3" rx="2"/><path d="M9 3v18"/></svg>');
	static final MINUS = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/></svg>');

	// a button (shadcn's): its label or children; variant "default" (the
	// main action), "destructive", "outline", "secondary", "ghost" or
	// "link", size "default", "sm", "lg" or "icon" (slot "button"; a
	// theme's looks); disabled (a Bool, a signal or
	// a function of one): not focusable, clicks and keys ignored,
	// data-disabled for the theme
	@:widget({
		props: {
			label: "its text",
			onClick: "called when it is clicked, or pressed with Enter or Space",
			variant: "its look: default (the main action), destructive, outline, secondary, ghost or link",
			size: "default, xs, sm, lg, or a square icon one: icon, icon-xs, icon-sm, icon-lg",
			disabled: "a Bool, a signal or a function of one: not focusable, its clicks and keys ignored"
		},
		variants: ["default", "destructive", "outline", "secondary", "ghost", "link"],
		sizes: ["default", "xs", "sm", "lg", "icon", "icon-xs", "icon-sm", "icon-lg"],
		keys: {"Enter, Space": "clicks it"}
	})
	@:neutral public static function Button(props:{?label:String, ?onClick:Void->Void, ?variant:String, ?size:String, ?disabled:Dynamic, ?children:View,
			?style:States->StyleProps, ?tag:String}):View {
		var disabled = () -> read(props.disabled) == true;
		var press = () -> if (!disabled() && props.onClick != null) props.onClick();
		return <view:button tag={props.tag ?? "button"} id={props.tag} slot="button" states={props.style} variant={props.variant ?? "default"}
			size={props.size ?? "default"} role="button" focusable={() -> !disabled()} disabled={disabled} data-disabled={disabled} onPress={_ -> press()}>
			{props.label}{props.children}
		</view:button>;
	}

	// a toggle (shadcn's): a button pressed or not, bound to a signal;
	// variant "default" or "outline", size "default", "sm" or "lg" (slot
	// "toggle", data-state "on" or "off"; ARIA's pressed button)
	@:widget({
		props: {
			pressed: "a signal of whether it is pressed, flipped when it is clicked, or pressed with Enter or Space",
			label: "its text",
			variant: "its look: default or outline",
			size: "default, sm or lg",
			disabled: "a Bool, a signal or a function of one: not focusable, its clicks and keys ignored"
		},
		variants: ["default", "outline"],
		sizes: ["default", "sm", "lg"],
		keys: {"Enter, Space": "presses or releases it"}
	})
	@:neutral public static function Toggle(props:{pressed:Signal<Bool>, ?label:String, ?variant:String, ?size:String, ?disabled:Dynamic, ?children:View,
			?style:States->StyleProps, ?tag:String}):View {
		var disabled = () -> read(props.disabled) == true;
		var flip = () -> if (!disabled()) props.pressed.value = !props.pressed.peek();
		return <view:button tag={props.tag ?? "toggle"} id={props.tag} slot="toggle" states={props.style} variant={props.variant ?? "default"}
			size={props.size ?? "default"} role="button" pressed={() -> props.pressed.value} data-state={() -> props.pressed.value ? "on" : "off"}
			focusable={() -> !disabled()} disabled={disabled} data-disabled={disabled} onPress={_ -> flip()}>
			{props.label}{props.children}
		</view:button>;
	}

	// a checkbox (shadcn's) bound to a signal, with its label; while mixed
	// is true, neither checked nor not (a dash; ARIA's mixed), checked when
	// clicked. Slots "checkbox" (data-state "checked", "unchecked" or
	// "indeterminate") and "checkbox-indicator" (shown when not unchecked),
	// the label a "label", the two in a row "checkbox-field"
	@:widget({
		props: {
			checked: "a signal of whether it is checked, flipped when it or its label is clicked, or with Space",
			mixed: "a signal: while true, neither checked nor not (a dash); checked and cleared when it is clicked",
			label: "its text beside it, and its name for assistive technology",
			disabled: "a Bool, a signal or a function of one: not focusable, its clicks and keys ignored",
			invalid: "a Bool, a signal or a function of one: aria-invalid, for the theme"
		},
		keys: {"Space": "checks or unchecks it (checks it when mixed)"}
	})
	@:neutral public static function Checkbox(props:{checked:Signal<Bool>, ?mixed:Signal<Bool>, ?label:String, ?disabled:Dynamic, ?invalid:Dynamic,
			?style:States->StyleProps, ?tag:String}):View {
		var mixed = () -> props.mixed != null && props.mixed.value;
		var disabled = () -> read(props.disabled) == true;
		var state = () -> mixed() ? "indeterminate" : props.checked.value ? "checked" : "unchecked";
		// (mixed: checked once clicked)
		var toggle = () -> if (!disabled()) batch(() -> {
			var was = props.mixed != null && props.mixed.peek();
			if (was) props.mixed.value = false;
			props.checked.value = was || !props.checked.peek();
		});
		// (its indicator centred, as a <button>'s content; Enter not a press, as Radix's)
		var box = <view:button tag={props.tag ?? "checkbox"} id={props.tag} slot="checkbox" states={props.style} role="checkbox" label={props.label}
			align-items="center" justify="center" checked={() -> mixed() ? ("mixed" : Dynamic) : props.checked.value} data-state={state}
			focusable={() -> !disabled()} disabled={disabled} data-disabled={disabled} aria-invalid={() -> read(props.invalid) == true ? "true" : null}
			onKeyDown={e -> if (e.key == Key.ENTER) e.preventDefault()} onPress={_ -> toggle()}>
			<Show when={() -> state() != "unchecked"}>
				<view:span slot="checkbox-indicator" data-state={state}>
					<icon slot="checkbox-icon" name={() -> mixed() ? "minus" : "check"} hidden/>
				</view:span>
			</Show>
		</view:button>;
		// (its label pressed: it pressed, the label not the box's: the box named by its label prop)
		return props.label == null ? box : <view slot="checkbox-field" direction="row" align-items="center">
			{box}<text:label slot="label" data-disabled={disabled} hidden onClick={_ -> toggle()}>{props.label}</text:label>
		</view>;
	}

	// a switch (shadcn's) bound to a signal, with its label: slots "switch"
	// and "switch-thumb", data-state "checked" or "unchecked" on both (the
	// thumb's place by its state's rules); size "default" or "sm" (and data-size);
	// the label a "label", the two in a row "switch-field"
	@:widget({
		props: {
			checked: "a signal of whether it is on, flipped when it or its label is clicked, or with Space or Enter",
			label: "its text beside it, and its name for assistive technology",
			disabled: "a Bool, a signal or a function of one: not focusable, its clicks and keys ignored",
			size: "default or sm"
		},
		sizes: ["default", "sm"],
		keys: {"Space, Enter": "turns it on or off"}
	})
	@:neutral public static function Switch(props:{checked:Signal<Bool>, ?label:String, ?disabled:Dynamic, ?size:String, ?style:States->StyleProps, ?tag:String}):View {
		var disabled = () -> read(props.disabled) == true;
		var state = () -> props.checked.value ? "checked" : "unchecked";
		var toggle = () -> if (!disabled()) props.checked.value = !props.checked.peek();
		var track = <view:button tag={props.tag ?? "switch"} id={props.tag} slot="switch" states={props.style} size={props.size ?? "default"} role="switch"
			label={props.label} checked={() -> props.checked.value} data-state={state} focusable={() -> !disabled()} disabled={disabled}
			data-disabled={disabled} onPress={_ -> toggle()}>
			<view:span slot="switch-thumb" size={props.size ?? "default"} data-state={state}/>
		</view:button>;
		return props.label == null ? track : <view slot="switch-field" direction="row" align-items="center">
			{track}<text:label slot="label" data-disabled={disabled} hidden onClick={_ -> toggle()}>{props.label}</text:label>
		</view>;
	}

	// a label (shadcn's): its text or children (slot "label")
	@:widget({
		props: {
			text: "its text, when it has no children",
			disabled: "a Bool, a signal or a function of one: dimmed by the theme (data-disabled)",
			htmlFor: "the id of the control it names, in a page (a <label>'s for)",
			children: "its content, in place of text"
		}
	})
	@:neutral public static function Label(props:{?text:String, ?disabled:Dynamic, ?children:Any, ?htmlFor:String, ?style:States->StyleProps, ?tag:String}):View {
		return <text:label tag={props.tag ?? "label"} id={props.tag} slot="label" html-for={props.htmlFor} states={props.style}
			data-disabled={() -> read(props.disabled) == true ? "true" : null}>{props.children ?? props.text}</text:label>;
	}

	// a badge (shadcn's): its label or children; variant "default",
	// "secondary", "destructive", "outline", "ghost" or "link" (slot "badge")
	@:widget({
		props: {
			label: "its text",
			variant: "its look: default, secondary, destructive, outline, ghost or link"
		},
		variants: ["default", "secondary", "destructive", "outline", "ghost", "link"]
	})
	@:neutral public static function Badge(props:{?label:String, ?variant:String, ?children:View, ?style:States->StyleProps, ?tag:String}):View {
		return <view:span tag={props.tag ?? "badge"} id={props.tag} slot="badge" states={props.style} variant={props.variant ?? "default"}>{props.label}{props.children}</view:span>;
	}


	// a card (shadcn's) and its parts, each its children: slots "card",
	// "card-header", "card-title", "card-description", "card-action",
	// "card-content", "card-footer"
	@:widget({
		props: {
			children: "its parts: a CardHeader, a CardContent, a CardFooter"
		}
	})
	@:neutral public static function Card(props:{?children:View, ?style:States->StyleProps, ?tag:String}):View {
		return <view tag={props.tag ?? "card"} id={props.tag} slot="card" states={props.style}>{props.children}</view>;
	}

	@:widget({
		props: {
			children: "its CardTitle, CardDescription and CardAction"
		},
		part: "Card"
	})
	@:neutral public static function CardHeader(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "card-header"} id={props.tag} slot="card-header">{props.children}</view>;

	@:widget({
		props: {
			text: "its text, when it has no children (a heading for assistive technology)",
			children: "its content, in place of text"
		},
		part: "Card"
	})
	@:neutral public static function CardTitle(props:{?text:String, ?children:Any, ?tag:String}):View
		return <text:div tag={props.tag ?? "card-title"} id={props.tag} slot="card-title" role="heading">{props.children ?? props.text}</text:div>;

	@:widget({
		props: {
			text: "its text, under the title, when it has no children",
			children: "its content, in place of text"
		},
		part: "Card"
	})
	@:neutral public static function CardDescription(props:{?text:String, ?children:Any, ?tag:String}):View
		return <text:div tag={props.tag ?? "card-description"} id={props.tag} slot="card-description">{props.children ?? props.text}</text:div>;

	@:widget({
		props: {
			children: "its content: a button or a link at the header's end, beside the title"
		},
		part: "Card"
	})
	@:neutral public static function CardAction(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "card-action"} id={props.tag} slot="card-action">{props.children}</view>;

	@:widget({
		props: {
			children: "the card's body"
		},
		part: "Card"
	})
	@:neutral public static function CardContent(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "card-content"} id={props.tag} slot="card-content">{props.children}</view>;

	@:widget({
		props: {
			children: "its content at the card's foot, in a row: its actions"
		},
		part: "Card"
	})
	@:neutral public static function CardFooter(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "card-footer"} id={props.tag} slot="card-footer">{props.children}</view>;

	// a separator (shadcn's): a line across, orientation "horizontal" (the
	// default) or "vertical" (slot "separator", data-orientation); not
	// decorative: a separator for assistive technology
	@:widget({
		props: {
			orientation: "horizontal (the default: a line across) or vertical (a line down)",
			decorative: "false: a separator for assistive technology; else (the default) hidden from it"
		}
	})
	@:neutral public static function Separator(props:{?orientation:String, ?decorative:Bool, ?tag:String}):View {
		var o = props.orientation ?? "horizontal";
		return props.decorative == false ? <view tag={props.tag ?? "separator"} id={props.tag} slot="separator" role="separator" data-orientation={o}
			aria-orientation={o == "vertical" ? "vertical" : null}/> : <view tag={props.tag ?? "separator"} id={props.tag} slot="separator" data-orientation={o} hidden/>;
	}

	// a skeleton (shadcn's): a placeholder where content is still coming,
	// its size the props' or its children's (slot "skeleton")
	@:widget({
		props: {
			width: "its width (pixels or a length), else its children's",
			height: "its height (pixels or a length), else its children's",
			children: "content giving it its size, hidden from assistive technology"
		}
	})
	@:neutral public static function Skeleton(props:{?width:Dynamic, ?height:Dynamic, ?children:View, ?tag:String}):View {
		return <view tag={props.tag ?? "skeleton"} id={props.tag} slot="skeleton" width={props.width} height={props.height} hidden>{props.children}</view>;
	}

	// an alert (shadcn's): a callout of its children, variant "default" or
	// "destructive"; its title and description (slots "alert",
	// "alert-title", "alert-description")
	@:widget({
		props: {
			variant: "its look: default or destructive",
			children: "its AlertTitle and AlertDescription"
		},
		variants: ["default", "destructive"]
	})
	@:neutral public static function Alert(props:{?variant:String, ?children:View, ?style:States->StyleProps, ?tag:String}):View {
		return <view tag={props.tag ?? "alert"} id={props.tag} slot="alert" states={props.style} variant={props.variant ?? "default"} live="assertive">{props.children}</view>;
	}

	@:widget({
		props: {
			text: "its text, when it has no children",
			children: "its content, in place of text"
		},
		part: "Alert"
	})
	@:neutral public static function AlertTitle(props:{?text:String, ?children:Any, ?tag:String}):View
		return <text:div tag={props.tag ?? "alert-title"} id={props.tag} slot="alert-title">{props.children ?? props.text}</text:div>;

	@:widget({
		props: {
			text: "its text, under the title, when it has no children",
			children: "its content, in place of text"
		},
		part: "Alert"
	})
	@:neutral public static function AlertDescription(props:{?text:String, ?children:Any, ?tag:String}):View
		return <text:div tag={props.tag ?? "alert-description"} id={props.tag} slot="alert-description">{props.children ?? props.text}</text:div>;

	// a slider (shadcn's) bound to a signal: from min to max (0 to 1), in
	// steps (0: any value); dragged, clicked (the value where the pointer is
	// along it, as Radix's), or moved with the arrow keys (a step, or a
	// twentieth), Home and End; disabled: none of them. Slots "slider",
	// "slider-track", "slider-range" and "slider-thumb", data-orientation
	// "horizontal" (Radix's; the thumb placed along the track by the value,
	// within it at whatever size its rules give it, the range in the track's flow);
	// width: the slider's, else its rules'
	@:widget({
		props: {
			value: "a signal of its value, set by a drag, a click along it or the keys",
			min: "its least value (0)",
			max: "its greatest value (1)",
			step: "the steps its value snaps to (0: any value)",
			width: "its width, else its rules'",
			disabled: "a Bool, a signal or a function of one: not focusable, its pointer and keys ignored",
			label: "its name for assistive technology"
		},
		keys: {
			"Left, Right (mirrored right to left)": "lowers or raises it by a step (a twentieth of the range without one)",
			"Down, Up": "lowers or raises it by a step (a twentieth of the range without one)",
			"Home, End": "sets it to min or max"
		}
	})
	public static function Slider(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?disabled:Dynamic, ?label:String,
			?style:States->StyleProps, ?tag:String}):View {
		var disabled = () -> read(props.disabled) == true;
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0;
		function set(v:Float)
			props.value.value = Behaviour.snap(v, lo, hi, step);
		var frac = () -> hi > lo ? (props.value.value - lo) / (hi - lo) : 0.0;
		// (right to left: the minimum at the right)
		function at(e:Event) {
			if (disabled()) return;
			var n = e.current, x = n.localX(e.x, e.y);
			if (n.width <= 0) return;
			if (n.rtl()) x = n.width - x;
			set(lo + x / n.width * (hi - lo));
		}
		return <view tag={props.tag ?? "slider"} slot="slider" data-orientation="horizontal" ref={n -> States.apply(n, props.style)} role="slider" label={props.label} value-now={() -> props.value.value} value-min={lo}
			value-max={hi} width={props.width} focusable={() -> !disabled()} disabled={disabled} data-disabled={disabled} justify="center"
			onPointerDown={e -> at(e)} onPointerMove={e -> if (e.current.pressed) at(e)}
			onKeyDown={e -> if (!disabled()) {
				var v = Behaviour.slide(mirrored(e), props.value.peek(), lo, hi, step);
				if (v != null) {
					e.preventDefault();
					props.value.value = v;
				}
			}}>
			<view slot="slider-track" data-orientation="horizontal" overflow="hidden" direction="row">
				<view slot="slider-range" data-orientation="horizontal" position="relative" width={() -> (frac() * 100) + "%"}/>
			</view>
			{along(frac, <view slot="slider-thumb" data-orientation="horizontal" shrink={0}/>)}
		</view>;
	}

	// (a thumb along a slider's track, a fraction f of the way: between two
	// spacers sharing the room it leaves, f and 1 - f of it; mirrored right
	// to left as the row is)
	static function along(f:Void->Float, thumb:View):View
		return <view position="absolute" top={0} bottom={0} left={0} right={0} direction="row" align-items="center" pointer-events="none">
			<view grow={f} shrink={0} basis={0}/>
			{thumb}
			<view grow={() -> 1 - f()} shrink={0} basis={0}/>
		</view>;

	// a range slider: two knobs on one track, the range between them filled,
	// low no more than high; a press moves the nearer knob (then drags it)
	// and focuses it, each knob a slider for the keyboard and assistive
	// technology (Left and Down lower it, Right and Up raise it, Home and End
	// to its bounds, as far as the other knob). The slider's slots, a thumb
	// each knob; width: the slider's, else its rules'
	@:widget({
		props: {
			low: "a signal of the range's low end, no more than high",
			high: "a signal of the range's high end, no less than low",
			min: "its least value (0)",
			max: "its greatest value (1)",
			step: "the steps the values snap to (0: any value)",
			width: "its width, else its rules'",
			label: "its name for assistive technology (Range), each knob's with minimum or maximum after it"
		},
		keys: {
			"Left, Right (mirrored right to left)": "lowers or raises the focused knob by a step (a twentieth of the range without one), as far as the other",
			"Down, Up": "lowers or raises the focused knob by a step (a twentieth of the range without one), as far as the other",
			"Home, End": "the focused knob to min or max, as far as the other"
		}
	})
	public static function RangeSlider(props:{low:Signal<Float>, high:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?label:String,
			?tag:String}):View {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0, tag = props.tag ?? "range";
		var dragging = -1, name = props.label ?? "Range", knobs:Array<Node> = [];
		function snap(v:Float):Float
			return Behaviour.snap(v, lo, hi, step);
		// (k: 0 the low knob, 1 the high one, each kept on its side of the other)
		function set(k:Int, v:Float) {
			v = snap(v);
			if (k == 0) props.low.value = Math.min(v, props.high.peek()) else props.high.value = Math.max(v, props.low.peek());
		}
		var frac = (v:Float) -> hi > lo ? (v - lo) / (hi - lo) : 0.0;
		// (right to left: the minimum at the right)
		function valueAt(e:Event):Float {
			var n = e.current, x = n.localX(e.x, e.y), w = Math.max(1, n.width);
			if (n.rtl()) x = w - x;
			return lo + x / w * (hi - lo);
		}
		function thumb(k:Int):View {
			var value = k == 0 ? props.low : props.high;
			return along(() -> frac(value.value), <view tag={tag + (k == 0 ? "-low" : "-high")} slot="slider-thumb" data-orientation="horizontal" role="slider" label={name + (k == 0 ? ": minimum" : ": maximum")} ref={n -> knobs[k] = n}
					value-now={() -> value.value} value-min={() -> k == 0 ? lo : props.low.value} value-max={() -> k == 0 ? props.high.value : hi}
					shrink={0} focusable pointer-events="auto"
					onKeyDown={e -> {
						var v = Behaviour.slide(mirrored(e), value.peek(), lo, hi, step);
						if (v != null) {
							e.preventDefault();
							set(k, v);
						}
					}}/>);
		}
		return <view tag={tag} slot="slider" data-orientation="horizontal" role="group" label={name} width={props.width} justify="center"
			onPointerDown={e -> {
				var v = valueAt(e);
				// (the nearer knob; where they meet, the one that can move that way)
				var dl = Math.abs(v - props.low.peek()), dh = Math.abs(v - props.high.peek());
				dragging = dl < dh || (dl == dh && v < props.low.peek()) ? 0 : 1;
				set(dragging, v);
				var n = knobs[dragging];
				if (n != null && n.ui != null) {
					n.ui.setFocus(n, false);
					e.preventDefault();
				}
			}}
			onPointerMove={e -> if (e.current.pressed && dragging >= 0) set(dragging, valueAt(e))}
			onPointerUp={_ -> dragging = -1}>
			<view slot="slider-track" data-orientation="horizontal" overflow="hidden" direction="row">
				<view width={() -> (frac(props.low.value) * 100) + "%"}/>
				<view slot="slider-range" data-orientation="horizontal" position="relative" width={() -> ((frac(props.high.value) - frac(props.low.value)) * 100) + "%"}/>
			</view>
			{thumb(0)}
			{thumb(1)}
		</view>;
	}

	// a colour picker: a square of saturation (to the right) and brightness
	// (up) in the hue, a strip of hues under it, a swatch and the colour's
	// hex in a field (left to right; what is typed there, once it is a CSS
	// colour, sets it); value: an opaque colour. The square and the strip
	// are sliders for the keyboard: Left and Right move the saturation or
	// the hue, Up and Down the brightness, Shift ten times as far
	@:widget({
		props: {
			value: "a signal of its colour, opaque: set by the square, the hue strip or a CSS colour typed in its field",
			size: "the side of its square and the width of the whole, in pixels (160)",
			label: "its name for assistive technology (Colour), its parts' with what each sets after it"
		},
		keys: {
			"Left, Right": "on the square, less or more saturation; on the strip, a lower or higher hue",
			"Down, Up": "on the square, less or more brightness; on the strip, a lower or higher hue",
			"Home, End": "on the strip, the first or last hue",
			"Shift": "with the arrows, ten times as far"
		}
	})
	public static function ColorPicker(props:{value:Signal<Color>, ?size:Float, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "color", size = props.size ?? 160.0, name = props.label ?? "Colour";
		var hue = signal(0.0), sat = signal(0.0), val = signal(0.0), hex = signal("");
		// (from the value: the hue kept where a grey has none)
		function load(c:Color) {
			var o = Behaviour.hsvOf(c);
			batch(() -> {
				// (grey: the hue kept)
				if (o.h != null) hue.value = o.h;
				sat.value = o.s;
				val.value = o.v;
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
				// (not while what is typed there already says it: "#0f0" stays)
				var typed = Color.tryParse(StringTools.trim(hex.peek()).toLowerCase());
				if (typed == null || Color.rgb(typed) != c) hex.value = c.toHex().substr(0, 7);
			});
		});
		effect(() -> {
			var c = Color.tryParse(StringTools.trim(hex.value).toLowerCase());
			if (c != null) untrack(() -> props.value.value = Color.rgb(c));
		});
		function clamp(x:Float):Float
			return x < 0 ? 0 : x > 1 ? 1 : x;
		function area(e:Event) {
			var n = e.current;
			batch(() -> {
				sat.value = clamp(n.localX(e.x, e.y) / size);
				val.value = 1 - clamp(n.localY(e.x, e.y) / size);
			});
			store();
		}
		function strip(e:Event) {
			hue.value = clamp(e.current.localX(e.x, e.y) / size) * 359.999;
			store();
		}
		function pct(x:Float):Int
			return Math.round(x * 100);
		var spectrum = "linear-gradient(to right, #FF0000, #FFFF00, #00FF00, #00FFFF, #0000FF, #FF00FF, #FF0000)";
		return <view tag={tag} slot="color-picker" role="group" label={name} width={size}>
			<view tag={tag + "-area"} role="slider" label={name + ": saturation and brightness"} value-now={() -> pct(sat.value)} value-min={0} value-max={100}
				value-text={() -> "saturation " + pct(sat.value) + "%, brightness " + pct(val.value) + "%"} slot="color-picker-area" width={size} height={size} focusable
				background-image={() -> "linear-gradient(to right, #FFFFFF, " + Behaviour.hsv(hue.value, 1, 1).toHex().substr(0, 7) + ")"}
				onPointerDown={e -> area(e)} onPointerMove={e -> if (e.current.pressed) area(e)}
				onKeyDown={e -> {
					var d = e.mods & Key.MOD_SHIFT != 0 ? 0.1 : 0.01;
					switch e.key {
						case Key.LEFT: sat.value = clamp(sat.peek() - d);
						case Key.RIGHT: sat.value = clamp(sat.peek() + d);
						case Key.UP: val.value = clamp(val.peek() + d);
						case Key.DOWN: val.value = clamp(val.peek() - d);
						case _: return;
					}
					e.preventDefault();
					store();
				}}>
				<view slot="color-picker-area-shade" position="absolute" left={0} top={0} right={0} bottom={0}
					background-image="linear-gradient(to bottom, transparent, #000000)"/>
				<view slot="color-picker-thumb" position="absolute" left={() -> sat.value * size} top={() -> (1 - val.value) * size}
					transform="translate(-50%, -50%)"/>
			</view>
			<view tag={tag + "-hue"} role="slider" label={name + ": hue"} value-now={() -> Math.round(hue.value)} value-min={0} value-max={359}
				value-text={() -> Math.round(hue.value) + "°"} slot="color-picker-hue" width={size} focusable background-image={spectrum}
				onPointerDown={e -> strip(e)} onPointerMove={e -> if (e.current.pressed) strip(e)}
				onKeyDown={e -> {
					var d = e.mods & Key.MOD_SHIFT != 0 ? 10 : 1;
					switch e.key {
						case Key.LEFT | Key.DOWN: hue.value = Math.max(0, hue.peek() - d);
						case Key.RIGHT | Key.UP: hue.value = Math.min(359, hue.peek() + d);
						case Key.HOME: hue.value = 0;
						case Key.END: hue.value = 359;
						case _: return;
					}
					e.preventDefault();
					store();
				}}>
				<view slot="color-picker-thumb" data-hue="" position="absolute" left={() -> hue.value / 360 * size} top="50%"
					transform="translate(-50%, -50%)" background={() -> Behaviour.hsv(hue.value, 1, 1)}/>
			</view>
			<view slot="color-picker-row" direction="row" align-items="center">
				<view tag={tag + "-swatch"} slot="color-picker-swatch" shrink={0} background={() -> props.value.value}/>
				<view grow={1} dir="ltr"><Input tag={tag + "-hex"} value={hex} label={name + ": hex"}/></view>
			</view>
		</view>;
	}


	// a radio group (shadcn's) bound to a signal: a radio button per option
	// (tag: the group's tag, "-", the option), labelled with it (labels, else
	// the option); one stop for Tab (the checked one, else the first), the
	// arrows checking and focusing the next or previous (wrapping); disabled:
	// none of them. Slots "radio-group", "radio-group-item" (data-state
	// "checked" or "unchecked") and "radio-group-indicator" (shown when
	// checked), each label a "label", an item and its label in a row
	// "radio-group-option"
	@:widget({
		props: {
			value: "a signal of the checked option",
			options: "the options' values, a radio button each",
			labels: "each option's label, else the option",
			disabled: "a Bool, a signal or a function of one: none of them focusable, their clicks and keys ignored",
			label: "its name for assistive technology"
		},
		keys: {
			"Down, Right (mirrored right to left)": "checks and focuses the next option, wrapping",
			"Up, Left (mirrored right to left)": "checks and focuses the previous option, wrapping",
			"Home, End": "checks and focuses the first or last option",
			"Space": "checks the focused option"
		}
	})
	@:neutral public static function RadioGroup(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?disabled:Dynamic, ?label:String,
			?style:States->StyleProps, ?tag:String}):View {
		var tag = props.tag ?? "radio", options = props.options, items:Array<Part> = [];
		var disabled = () -> read(props.disabled) == true;
		// (the Tab stop: the checked option, else the first)
		function stop(i:Int):Bool {
			var k = options.indexOf(props.value.value);
			return i == (k < 0 ? 0 : k);
		}
		// (Enter not a press, as Radix's)
		function key(e:Event, i:Int) {
			var n = options.length;
			if (e.key == Key.ENTER) e.preventDefault();
			if (disabled()) return;
			var k = mirroredKey(e), j = k == Key.SPACE ? i : Behaviour.rove(k, i, n);
			if (j < 0) return;
			e.preventDefault();
			props.value.value = options[j];
			focusPart(items, j);
		}
		return <view tag={tag} id={props.tag} slot="radio-group" states={props.style} role="radiogroup" label={props.label} data-disabled={disabled}>{[
			for (i in 0...options.length) {
				var o = options[i], text = props.labels != null && props.labels[i] != null ? props.labels[i] : o;
				var state = () -> props.value.value == o ? "checked" : "unchecked";
				var check = () -> if (!disabled()) props.value.value = o;
				<view slot="radio-group-option" direction="row" align-items="center">
					<view:button tag={tag + "-" + o} slot="radio-group-item" role="radio" label={text} align-items="center" justify="center" ref={p -> items[i] = p}
						checked={() -> props.value.value == o} data-state={state} focusable={() -> stop(i) && !disabled()} disabled={disabled} data-disabled={disabled}
						onKeyDown={e -> key(e, i)} onPress={_ -> check()}>
						<Show when={() -> state() == "checked"}>
							<view:span slot="radio-group-indicator" data-state={state}>
								<icon slot="radio-group-icon" name="circle-filled" hidden/>
							</view:span>
						</Show>
					</view:button>
					<text:label slot="label" data-disabled={disabled} hidden onClick={_ -> check()}>{text}</text:label>
				</view>;
			}
		]}</view>;
	}

	// tabs (shadcn's): a row of labels (tag: the tabs' tag, "-", the index)
	// and what render gives for the selected one below. One stop for Tab,
	// the selected one; Left and Right (the way they point, wrapping), Home
	// and End select another and move the focus there. Slots "tabs",
	// "tabs-list", "tabs-trigger" (data-state "active" or "inactive") and
	// "tabs-content", all data-orientation "horizontal" (Radix's); the tabs a
	// group, the list and its triggers of variant (shadcn's "default", a
	// pill; "line", underlined)
	@:widget({
		props: {
			labels: "the tabs' labels, a tab each",
			selected: "a signal of the selected tab's index, set by a click or the keys",
			render: "what to show below for a tab's index, called when it is selected",
			variant: "the list's look: default (the selected tab a raised pill) or line (underlined)"
		},
		variants: ["default", "line"],
		keys: {
			"Left, Right (mirrored right to left)": "selects and focuses the previous or next tab, wrapping",
			"Home, End": "selects and focuses the first or last tab",
			"Enter, Space": "selects the focused tab"
		}
	})
	public static function Tabs(props:{labels:Array<String>, selected:Signal<Int>, render:Int->Any, ?variant:String, ?style:States->StyleProps,
			?tag:String}):View {
		var variant = props.variant ?? "default";
		var tag = props.tag ?? "tabs", count = props.labels.length, tabs:Array<Node> = [];
		function key(e:Event, i:Int) {
			var k = mirrored(e), j = k == Key.SPACE || k == Key.ENTER ? i : Behaviour.rove(k, i, count, false);
			if (j < 0) return;
			e.preventDefault();
			props.selected.value = j;
			focusIn(tabs, j);
		}
		return <view tag={tag} slot="tabs" group="tabs" data-orientation="horizontal" ref={n -> States.apply(n, props.style)}>
			<view slot="tabs-list" variant={variant} data-variant={variant} data-orientation="horizontal" role="tablist">{[
				for (i in 0...count)
					<view tag={tag + "-" + i} slot="tabs-trigger" variant={variant} data-orientation="horizontal" role="tab" ref={n -> tabs[i] = n} selected={() -> props.selected.value == i}
						data-state={() -> props.selected.value == i ? "active" : "inactive"} focusable={() -> props.selected.value == i}
						onClick={_ -> props.selected.value = i} onKeyDown={e -> key(e, i)}>
						{props.labels[i]}
					</view>
			]}</view>
			<view slot="tabs-content" data-orientation="horizontal" role="tabpanel" label={() -> props.labels[props.selected.value]}>{() -> props.render(props.selected.value)}</view>
		</view>;
	}

	// a table: a header of the columns' titles (a column with compare sorts
	// by it on a click, Enter or Space, again the other way; an arrow tells
	// which), then the rows (a VirtualList: only those in view are made),
	// each column's cell for each; a click selects a row (selected), a
	// double click or Enter activates it (onActivate); Up, Down, Page Up,
	// Page Down, Home and End move the selection, the view following. A
	// column's edge in the header dragged sets its width (a double click
	// there: its own again).
	// columns: a title, a width (a grid track: "1fr" by default, "120px",
	// "auto"), what a row's cell shows (cell), compare (sortable), numeric
	// (its title and cells at the end, figures of one width: tabular-nums). rows:
	// an array, or a signal or function of one; height: the whole table's.
	// Slots (shadcn's) "table", "table-header", "table-body", "table-row"
	// (data-state "selected"), "table-head" and "table-cell"; rows rowHeight
	// high (28), whatever the theme pads
	@:widget({
		props: {
			rows: "its rows: an array, or a signal or function of one",
			columns: "its columns, each a title, a width (a grid track: 1fr by default, 120px, auto), cell (what a row's cell shows), compare (a sort order: the column sorts by it from its header) and numeric (its title and cells at the end, figures of one width)",
			height: "the whole table's height, its header's included; its rows scroll past it",
			rowHeight: "each row's height, the header's too",
			selected: "a signal of the selected row (null: none)",
			onActivate: "called with a row when it is double clicked, or Enter is pressed with it selected",
			label: "its name for assistive technology"
		},
		keys: {
			"Up, Down": "select the row before or after, the view following",
			"Page Up, Page Down": "select the row a page before or after",
			"Home, End": "select the first or last row",
			"Enter": "activates the selected row (onActivate); on a sortable column's header, sorts by it, again the other way",
			"Space": "on a sortable column's header, sorts by it, again the other way"
		}
	})
	public static function Table<T>(props:{rows:Dynamic, columns:Array<{title:String, ?width:String, cell:T->Any, ?compare:(T, T)->Int, ?numeric:Bool}>,
			?height:Float, ?rowHeight:Float, ?selected:Signal<Null<T>>, ?onActivate:T->Void, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "table", rh = props.rowHeight ?? 28.0, h = props.height ?? 240.0;
		var selected:Signal<Null<T>> = props.selected ?? signal(null);
		var sortBy = signal(-1), descending = signal(false);
		// (a column dragged to a width: pixels, else its own track)
		var widths:Array<Signal<Null<Float>>> = [for (c in props.columns) signal(null)];
		var template = () -> [for (k in 0...props.columns.length) widths[k].value != null ? widths[k].value + "px" : props.columns[k].width ?? "1fr"].join(" ");
		var sorted = memo(() -> {
			var rows:Array<T> = Render.read(props.rows);
			var k = sortBy.value;
			if (k < 0 || props.columns[k].compare == null) return rows;
			var cmp = props.columns[k].compare, d = descending.value;
			var out = rows.copy();
			// (stable: rows that compare equal keep their order)
			haxe.ds.ArraySort.sort(out, (a, b) -> d ? cmp(b, a) : cmp(a, b));
			return out;
		});
		function sort(k:Int)
			if (props.columns[k].compare != null) batch(() -> {
				if (sortBy.peek() == k) descending.value = !descending.peek() else {
					sortBy.value = k;
					descending.value = false;
				}
			});
		var body:Null<Node> = null;
		// (the selected row's index brought into the rows' view)
		function show(i:Int) {
			var list = body == null ? null : body.find(tag + "-rows");
			if (list == null || list.ui == null) return;
			var top = i * rh, view = list.height;
			if (top < list.scrollY) list.ui.scrollTo(list, 0, top) else if (top + rh > list.scrollY + view) list.ui.scrollTo(list, 0, top + rh - view);
		}
		function activate(r:Null<T>)
			if (r != null && props.onActivate != null) props.onActivate(r);
		var lastClick:Null<T> = null, lastAt = -1e9;
		function click(r:T) {
			var now = Ui.now();
			if (lastClick == r && now - lastAt < 0.45) activate(r);
			lastClick = r;
			lastAt = now;
			selected.value = r;
		}
		function key(e:Event) {
			var rows = sorted.peek(), i = rows.indexOf(selected.peek()), page = Std.int(Math.max(1, Math.floor((h - rh) / rh) - 1));
			var j = switch e.key {
				case Key.DOWN: i < 0 ? 0 : i + 1;
				case Key.UP: i < 0 ? 0 : i - 1;
				case Key.PAGE_DOWN: i + page;
				case Key.PAGE_UP: i - page;
				case Key.HOME: 0;
				case Key.END: rows.length - 1;
				case Key.ENTER:
					activate(selected.peek());
					e.stop();
					return;
				case _: return;
			}
			e.stop();
			if (rows.length == 0) return;
			j = j < 0 ? 0 : j >= rows.length ? rows.length - 1 : j;
			selected.value = rows[j];
			show(j);
		}
		return <view tag={tag} slot="table" role="grid" label={props.label} height={h} overflow="hidden">
			<view slot="table-header"><view tag={tag + "-head"} slot="table-row" role="row" display="grid" grid-template-columns={template} height={rh}>{[
				for (k in 0...props.columns.length) {
					var c = props.columns[k], cell:Null<Node> = null, from = 0.0, start = 0.0, dragging = false, clicked = -1e9;
					<view tag={tag + "-head-" + k} slot="table-head" role="columnheader" ref={n -> cell = n} height="100%" direction="row" align-items="center"
						justify={c.numeric == true ? "flex-end" : "flex-start"} focusable={c.compare != null} data-sortable={c.compare != null} onClick={_ -> sort(k)}
						onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
							sort(k);
							e.stop();
						}}>
						{c.title}
						<text slot="table-sort-icon" hidden>{() -> sortBy.value == k ? (descending.value ? "▼" : "▲") : ""}</text>
						{k == props.columns.length - 1 ? null : <view tag={tag + "-resize-" + k} position="absolute" top={0} bottom={0}
							left={() -> cell != null && cell.rtl() ? 0 : null} right={() -> cell != null && cell.rtl() ? null : 0} width={6} cursor="ew-resize"
							onPointerDown={e -> {
								dragging = true;
								from = e.x;
								start = cell.width;
								e.stop();
							}} onPointerMove={e -> if (dragging) widths[k].value = Math.round(Math.max(24, start + (cell.rtl() ? from - e.x : e.x - from)))}
							onPointerUp={_ -> dragging = false} onClick={e -> {
								var now = Ui.now();
								if (now - clicked < 0.45) widths[k].value = null;
								clicked = now;
								e.stop();
							}}></view>}
					</view>;
				}
			]}</view></view>
			<view tag={tag + "-body"} slot="table-body" focusable ref={n -> body = n} onKeyDown={key}>
				<VirtualList each={sorted} itemHeight={rh} height={h - rh - 2} tag={tag + "-rows"} render={(item:Signal<T>, i:Int) -> {
					var on = () -> item.value != null && selected.value == item.value;
					<view tag={tag + "-row"} slot="table-row" role="row" selected={on} data-state={() -> on() ? "selected" : null} display="grid"
						grid-template-columns={template} height={rh} onClick={_ -> if (item.value != null) click(item.value)}>{[
						for (c in props.columns)
							<view slot="table-cell" role="cell" overflow="hidden" justify="center" align-items={c.numeric == true ? "flex-end" : "stretch"}
								font-variant-numeric={c.numeric == true ? "tabular-nums" : null}>{() -> item.value == null ? null : c.cell(item.value)}</view>
					]}</view>;
				}}/>
			</view>
		</view>;
	}

	// a tree: the roots' rows and, under each open item, its children's,
	// indented by level, a triangle on the items with children
	// (children(item): null or empty, a leaf); the rows are a VirtualList's
	// (only those in view are made). A click selects an item (selected), a
	// click on its triangle opens or closes it, as a double click does (on a
	// leaf, it activates it: onActivate, as Enter does); Up and Down move
	// the selection, Right opens an item or moves to its first child, Left
	// closes it or moves to its parent, Home and End, the view following.
	// roots: an array, or a signal or function of one; expanded: the open
	// items (none by default); height: the whole tree's; text: an item's
	// text, for type-ahead (letters typed to the row they start). Slots
	// "tree", "tree-item" (data-selected; data-state "open" or "closed" on an
	// item with children; indented by its level) and "tree-toggle"
	@:widget({
		props: {
			roots: "its top items: an array, or a signal or function of one",
			children: "a function of an item giving its children (null or empty: a leaf)",
			render: "a function of an item giving what its row shows",
			text: "a function of an item giving its text, for type-ahead",
			expanded: "a signal of the open items (none by default)",
			selected: "a signal of the selected item (null: none)",
			onActivate: "called with a leaf when it is double clicked, or Enter is pressed with it selected",
			height: "the whole tree's height; its rows scroll past it",
			rowHeight: "each row's height",
			label: "its name for assistive technology"
		},
		keys: {
			"Up, Down": "select the item before or after, the view following",
			"Home, End": "select the first or last item",
			"Right": "opens the selected item, or once open selects its first child (Left right to left)",
			"Left": "closes the selected item, or selects its parent (Right right to left)",
			"Enter": "opens or closes the selected item, or activates it when a leaf (onActivate)",
			"letters, digits": "with text, select the next item whose text starts with what was typed"
		}
	})
	public static function Tree<T>(props:{roots:Dynamic, children:T->Null<Array<T>>, render:T->Any, ?text:T->String, ?expanded:Signal<Array<T>>,
			?selected:Signal<Null<T>>, ?onActivate:T->Void, ?height:Float, ?rowHeight:Float, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "tree", rh = props.rowHeight ?? 26.0, h = props.height ?? 240.0;
		var selected:Signal<Null<T>> = props.selected ?? signal(null);
		var expanded:Signal<Array<T>> = props.expanded ?? signal([]);
		var rows = memo(() -> Behaviour.treeLines(Render.read(props.roots), props.children, expanded.value));
		function setOpen(it:T, open:Bool) {
			var cur = expanded.peek(), i = cur.indexOf(it);
			if (open == (i >= 0)) return;
			var next = cur.copy();
			if (open) next.push(it) else next.splice(i, 1);
			expanded.value = next;
		}
		function indexOf(it:Null<T>):Int {
			var rs = rows.peek();
			if (it != null)
				for (i in 0...rs.length)
					if (rs[i].item == it) return i;
			return -1;
		}
		var body:Null<Node> = null;
		// (a row's index brought into the view)
		function show(i:Int) {
			var list = body == null ? null : body.find(tag + "-rows");
			if (list == null || list.ui == null) return;
			var top = i * rh, view = list.height;
			if (top < list.scrollY) list.ui.scrollTo(list, 0, top) else if (top + rh > list.scrollY + view) list.ui.scrollTo(list, 0, top + rh - view);
		}
		function activate(r:Null<TreeRow<T>>) {
			if (r == null) return;
			if (!r.leaf) setOpen(r.item, !r.open) else if (props.onActivate != null) props.onActivate(r.item);
		}
		var lastClick:Null<T> = null, lastAt = -1e9;
		function click(r:TreeRow<T>) {
			var now = Ui.now();
			if (lastClick == r.item && now - lastAt < 0.45) activate(r);
			lastClick = r.item;
			lastAt = now;
			selected.value = r.item;
		}
		var typed = new TypeAhead();
		function key(e:Event) {
			var rs = rows.peek(), i = indexOf(selected.peek()), j = i;
			switch mirrored(e) {
				case Key.DOWN: j = i < 0 ? 0 : i + 1;
				case Key.UP: j = i < 0 ? 0 : i - 1;
				case Key.HOME: j = 0;
				case Key.END: j = rs.length - 1;
				case Key.RIGHT:
					if (i >= 0 && !rs[i].leaf) {
						if (!rs[i].open) setOpen(rs[i].item, true) else j = i + 1;
					}
				case Key.LEFT:
					if (i >= 0) {
						if (rs[i].open) setOpen(rs[i].item, false) else if (rs[i].parent >= 0) j = rs[i].parent;
					}
				case Key.ENTER:
					if (i >= 0) activate(rs[i]);
				case _:
					j = props.text == null ? -1 : typed.find(e.key, e.mods, Ui.now(), [for (r in rs) props.text(r.item)], i);
					if (j < 0) return;
			}
			e.stop();
			if (rs.length == 0 || j == i) return;
			j = j < 0 ? 0 : j >= rs.length ? rs.length - 1 : j;
			selected.value = rs[j].item;
			show(j);
		}
		return <view tag={tag} slot="tree" role="tree" label={props.label} focusable ref={n -> body = n} onKeyDown={key} height={h} overflow="hidden">
			<VirtualList each={rows} itemHeight={rh} height={h - 2} tag={tag + "-rows"} render={(row:Signal<TreeRow<T>>, i:Int) -> {
				var on = () -> row.value != null && selected.value == row.value.item;
				<view tag={tag + "-item"} slot="tree-item" role="treeitem" level={() -> row.value == null ? null : row.value.level}
					expanded={() -> row.value == null || row.value.leaf ? null : row.value.open} selected={on} data-selected={() -> on() ? "true" : null}
					data-state={() -> row.value == null || row.value.leaf ? null : row.value.open ? "open" : "closed"} height={rh}
					onClick={_ -> if (row.value != null) click(row.value)}>
					<view tag={tag + "-toggle"} slot="tree-toggle" width={14} shrink={0} margin={() -> '0 0 0 ${row.value == null ? 0 : (row.value.level - 1) * 16}'}
						align-items="center" onClick={e -> if (row.value != null && !row.value.leaf) {
						setOpen(row.value.item, !row.value.open);
						e.stop();
					}}><Show when={() -> row.value != null && !row.value.leaf}>{icon(CHEVRON_RIGHT, "tree-toggle-icon", () -> row.value != null && row.value.open ? "rotate(90deg)" : "none", true)}</Show></view>
					{() -> row.value == null ? null : props.render(row.value.item)}
				</view>;
			}}/>
		</view>;
	}

	// two panes side by side (direction "row", the default) or one above
	// the other ("column"), a divider between them: dragged, or moved by
	// the arrow keys (10 pixels; Home and End: to the bounds) while focused
	// (ARIA's separator, its value the first pane's size). size: the first
	// pane's (a signal; 200 by default), from min (0) to max (the room less
	// min); the second pane takes the rest. It fills its parent (grow 1).
	// Slots as shadcn's Resizable: "resizable-panel-group", "resizable-panel"
	// and "resizable-handle" (the line in the divider:
	// data-panel-group-direction "horizontal" or "vertical",
	// data-resize-handle-state "inactive", "hover" or "drag")
	@:widget({
		props: {
			first: "the first pane's content: on the left (on the right right to left), or above",
			second: "the second pane's content: it takes the rest",
			size: "a signal of the first pane's size, in pixels",
			direction: "row (side by side, the default) or column (one above the other)",
			min: "the first pane's least size",
			max: "the first pane's greatest size (by default the room less min)",
			label: "the divider's name for assistive technology"
		},
		keys: {
			"Left, Up": "shrink the first pane by 10 pixels (Right, not Left, right to left)",
			"Right, Down": "grow the first pane by 10 pixels (Left, not Right, right to left)",
			"Home, End": "the first pane to its least or greatest size"
		}
	})
	public static function Split(props:{first:Any, second:Any, ?size:Signal<Float>, ?direction:String, ?min:Float, ?max:Float, ?label:String,
			?tag:String}):View {
		var tag = props.tag ?? "split", row = props.direction != "column";
		var size:Signal<Float> = props.size ?? signal(200.0);
		var lo = props.min ?? 0.0, grip = 6.0;
		var self:Null<Node> = null;
		function hi():Float {
			var room = self == null || self.width <= 0 ? 1e9 : (row ? self.width : self.height) - grip - lo;
			return Math.max(lo, props.max == null ? room : Math.min(props.max, room));
		}
		function set(v:Float)
			size.value = Math.round(Math.max(lo, Math.min(hi(), v)));
		// (where in the divider it was grabbed)
		var grab = 0.0;
		var hover = signal(false), active = signal(false);
		return <view tag={tag} slot="resizable-panel-group" direction={row ? "row" : "column"} ref={n -> self = n} grow={1} min-width={0} min-height={0}
			overflow="hidden">
			<view tag={tag + "-first"} slot="resizable-panel" basis={() -> size.value} grow={0} shrink={0} min-width={0} min-height={0} overflow="hidden">{props.first}</view>
			<view tag={tag + "-divider"} role="separator" label={props.label} value-now={() -> size.value} value-min={lo} value-max={() -> {
				size.value;
				hi();
			}} focusable cursor={row ? "ew-resize" : "ns-resize"} width={row ? (grip : Dynamic) : "auto"} height={row ? "auto" : (grip : Dynamic)} shrink={0}
				align-items="center" justify="center" onPointerEnter={_ -> hover.value = true} onPointerLeave={_ -> hover.value = false}
				onPointerDown={e -> {
					grab = row ? e.localX : e.localY;
					active.value = true;
				}} onPointerUp={_ -> active.value = false}
				onPointerMove={e -> if (active.peek() && self != null) {
					var at = (row ? self.localX(e.x, e.y) : self.localY(e.x, e.y)) - grab;
					// (right to left, the first pane on the right)
					set(row && self.rtl() ? self.width - grip - at : at);
				}}
				onKeyDown={e -> {
					var v = switch row ? mirrored(e) : e.key {
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
				}}>
				<view slot="resizable-handle" data-panel-group-direction={row ? "horizontal" : "vertical"}
					data-resize-handle-state={() -> active.value ? "drag" : hover.value ? "hover" : "inactive"} align-self="stretch"/>
			</view>
			<view tag={tag + "-second"} slot="resizable-panel" grow={1} shrink={1} basis={0} min-width={0} min-height={0} overflow="hidden">{props.second}</view>
		</view>;
	}

	// a month's days in a grid of six weeks (Monday first; firstDay: 0 for
	// Sunday), the month and year above between arrows to the months before
	// and after. The grid takes the focus: the arrows move its marked day (a
	// day, a week), Page Up and Down a month, Home and End to the week's ends,
	// the month shown following it; a click, Enter or Space chooses the day
	// (value, onChoose); with range, a range is chosen instead: a first day,
	// then its last (one before the first starts it again), the days between
	// selected. today is marked (by default the system's). Slots
	// (shadcn's calendar's parts) "calendar", "calendar-nav" (its arrows
	// "calendar-button-previous" and "calendar-button-next"),
	// "calendar-caption-label", "calendar-weekdays",
	// "calendar-weekday", "calendar-week" and "calendar-day" (data-selected,
	// data-today, data-outside, data-focused, and in a range data-range-start,
	// data-range-middle, data-range-end: "true")
	@:widget({
		props: {
			value: "a signal of the chosen day (a Day: year, month from 1, day; null: none), the month shown at first",
			range: "a signal of a chosen range (from and to, each a Day or null), chosen in place of value",
			today: "the day marked as today (by default the system's)",
			firstDay: "the weeks' first day: 1 Monday (the default), 0 Sunday, to 6 Saturday",
			onChoose: "called with a day when it is chosen",
			label: "not used: the grid is named by the month shown"
		},
		keys: {
			"Left, Right": "move the marked day a day back or on (swapped right to left), the month shown following",
			"Up, Down": "move the marked day a week back or on",
			"Home, End": "move the marked day to its week's first or last day",
			"Page Up, Page Down": "move the marked day a month back or on (its last day where it is shorter)",
			"Enter, Space": "choose the marked day; on a month arrow, show the month before or after"
		}
	})
	public static function Calendar(props:{?value:Signal<Null<Day>>, ?range:Signal<DayRange>, ?today:Day, ?firstDay:Int, ?onChoose:Day->Void,
			?label:String, ?tag:String}):View {
		var tag = props.tag ?? "calendar", first = props.firstDay ?? 1;
		var now = Date.now();
		var today = props.today ?? {year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate()};
		var value = props.value ?? signal(null), range = props.range;
		var start = value.peek() ?? (range == null ? null : range.peek().from) ?? today;
		var cursor = signal(Days.of(start));
		// (the cursor's day marked focused while the grid has the focus, as react-day-picker's)
		var focused = signal(false);
		var shown = memo(() -> {
			var d = Days.day(cursor.value);
			return {year: d.year, month: d.month};
		});
		// (the grid's first day: the week day first before the month's first)
		var gridStart = () -> Behaviour.gridStart(shown.value.year, shown.value.month, first);
		function choose(n:Int) {
			cursor.value = n;
			var d = Days.day(n);
			if (range != null) {
				var r = range.peek();
				range.value = r.from == null || r.to != null || n < Days.of(r.from) ? {from: d, to: null} : {from: r.from, to: d};
			} else value.value = d;
			if (props.onChoose != null) props.onChoose(d);
		}
		function month(delta:Int)
			cursor.value = Behaviour.addMonths(cursor.peek(), delta);
		function key(e:Event) {
			var c = cursor.peek(), k = mirrored(e), to = Behaviour.calendarKey(k, c, first);
			if (to != null) cursor.value = to else switch k {
				case Key.PAGE_UP: month(-1);
				case Key.PAGE_DOWN: month(1);
				case Key.ENTER | Key.SPACE: choose(c);
				case _: return;
			}
			e.preventDefault();
		}
		var names = [for (k in 0...7) Days.WEEKDAYS[(k + first) % 7]];
		var chosen = (n:Int) -> {
			if (range != null) {
				var r = range.value;
				return r.from != null && (r.to == null ? Days.of(r.from) == n : n >= Days.of(r.from) && n <= Days.of(r.to));
			}
			var v = value.value;
			return v != null && Days.of(v) == n;
		};
		// (a range's ends and middle)
		var edge = (n:Int, start:Bool) -> {
			var r = range == null ? null : range.value;
			var d = r == null ? null : start ? r.from : r.to;
			return d != null && Days.of(d) == n ? "true" : null;
		};
		var middle = (n:Int) -> {
			var r = range == null ? null : range.value;
			return r != null && r.from != null && r.to != null && n > Days.of(r.from) && n < Days.of(r.to) ? "true" : null;
		};
		return <view tag={tag} slot="calendar">
			<view slot="calendar-nav">
				<view tag={tag + "-previous"} slot="calendar-button-previous" variant="ghost" size="icon" role="button" label="Previous month" focusable onClick={_ -> month(-1)}
					onKeyDown={e -> pressKeys(e, () -> month(-1))}>{icon(CHEVRON_LEFT, "calendar-button-icon")}</view>
				<text tag={tag + "-month"} slot="calendar-caption-label">{() -> Days.MONTHS[shown.value.month - 1] + " " + shown.value.year}</text>
				<view tag={tag + "-next"} slot="calendar-button-next" variant="ghost" size="icon" role="button" label="Next month" focusable onClick={_ -> month(1)}
					onKeyDown={e -> pressKeys(e, () -> month(1))}>{icon(CHEVRON_RIGHT, "calendar-button-icon")}</view>
			</view>
			<view tag={tag + "-grid"} role="table" label={() -> Days.MONTHS[shown.value.month - 1] + " " + shown.value.year} focusable onKeyDown={key}
				onFocus={_ -> focused.value = true} onBlur={_ -> focused.value = false}>
				<view slot="calendar-weekdays" role="row" display="grid" grid-template-columns="repeat(7, 32px)">{[
					for (n in names)
						<view slot="calendar-weekday" role="columnheader" text-align="center">{n}</view>
				]}</view>
				{[
					for (w in 0...6)
						<view slot="calendar-week" role="row" display="grid" grid-template-columns="repeat(7, 32px)">{[
							for (k in 0...7) {
								var at = () -> gridStart() + w * 7 + k;
								var inMonth = () -> Days.day(at()).month == shown.value.month;
								<view tag={tag + "-day"} role="cell" label={() -> {
									var d = Days.day(at());
									d.day + " " + Days.MONTHS[d.month - 1] + " " + d.year;
								}} slot="calendar-day" selected={() -> chosen(at())} data-selected={() -> chosen(at()) ? "true" : null}
									data-today={() -> Days.of(today) == at() ? "true" : null} data-outside={() -> inMonth() ? null : "true"}
									data-focused={() -> focused.value && cursor.value == at() ? "true" : null} data-range-start={() -> edge(at(), true)}
									data-range-end={() -> edge(at(), false)} data-range-middle={() -> middle(at())} onClick={_ -> choose(at())}>
									{() -> "" + Days.day(at()).day}
								</view>;
							}
						]}</view>
				]}
			</view>
		</view>;
	}

	// a date chosen on a button that opens a Calendar under it (closed by a
	// choice, Escape or a click outside); the button shows it as written by
	// format (by default "17 October 2026"), else placeholder. As shadcn's
	// date picker: the button an outline "button" (data-empty "true" with no
	// date), the calendar in a "popover-content"
	@:widget({
		props: {
			value: "a signal of the chosen day (a Day: year, month from 1, day; null: none)",
			today: "the day the calendar marks as today (by default the system's)",
			firstDay: "the weeks' first day: 1 Monday (the default), 0 Sunday, to 6 Saturday",
			format: "a function of a day giving its text on the button (by default 17 October 2026)",
			placeholder: "the button's text with no date",
			label: "its name for assistive technology"
		},
		keys: {
			"Enter, Space": "on the button, open the calendar, its grid focused; in the calendar, choose the marked day, closing it",
			"Down": "on the button, opens the calendar",
			"Left, Right, Up, Down, Home, End, Page Up, Page Down": "in the calendar, move its marked day as Calendar's do",
			"Escape": "closes the calendar, the focus back on the button"
		}
	})
	public static function DatePicker(props:{value:Signal<Null<Day>>, ?today:Day, ?firstDay:Int, ?format:Day->String, ?placeholder:String,
			?label:String, ?tag:String}):View {
		var tag = props.tag ?? "date", open = signal(false);
		var format = props.format ?? (d:Day) -> d.day + " " + Days.MONTHS[d.month - 1] + " " + d.year;
		var self:Null<Node> = null;
		return <view tag={tag} slot="button" variant="outline" size="default" role="combobox" label={props.label} expanded={() -> open.value}
			data-state={() -> open.value ? "open" : "closed"} data-empty={() -> props.value.value == null ? "true" : null} focusable justify="start"
			ref={n -> self = n} onClick={_ -> open.value = !open.value} onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE || e.key == Key.DOWN) {
				open.value = true;
				e.preventDefault();
			}}>
			<text slot="date-picker-value" data-placeholder={() -> props.value.value == null}>{() -> props.value.value == null ? (props.placeholder ?? "Choose a date") : format(props.value.value)}</text>
			<Popover open={open} placement="below" onDismiss={() -> open.value = false}
				onOpen={p -> {
					var g = p.find(tag + "-calendar-grid");
					if (g != null && g.ui != null) g.ui.setFocus(g);
				}}>
				<view slot="popover-content" data-state="open" padding={0} ref={n -> Rules.keep(n, ["padding"])}><Calendar tag={tag + "-calendar"} value={props.value} today={props.today} firstDay={props.firstDay}
					onChoose={_ -> {
						open.value = false;
						if (self != null && self.ui != null) self.ui.setFocus(self);
					}}/></view>
			</Popover>
		</view>;
	}

	// a progress bar (shadcn's): value from 0 to 1 (a signal, a function or a
	// number); null: not known (indeterminate: a bar sliding across, every
	// 1.5 seconds, on the Clock; no value for assistive technology). Slots
	// "progress" and "progress-indicator" (data-state "indeterminate" when
	// sliding; known, moved left by what is not done, translateX(-40%) at
	// 0.6, as shadcn's: as wide as the bar by its rules); width: the
	// bar's, else its rules'
	@:widget({
		props: {
			value: "how much is done, from 0 to 1: a number, a signal or a function of one; null: not known (a bar sliding across)",
			width: "the bar's width (else its rules')",
			label: "its name for assistive technology"
		}
	})
	public static function Progress(props:{value:Dynamic, ?width:Float, ?label:String, ?style:States->StyleProps, ?tag:String}):View {
		var known = () -> Render.read(props.value) != null;
		var frac = () -> {
			var v:Null<Float> = Render.read(props.value);
			v == null ? 0.0 : v < 0 ? 0.0 : v > 1 ? 1.0 : v;
		};
		var phase = signal(0.0), running = false, stopped = false;
		effect(() -> if (!known() && !running) {
			running = true;
			var start = -1.0;
			Clock.add(now -> {
				if (stopped || untrack(known)) return running = false;
				if (start < 0) start = now;
				phase.value = ((now - start) % 1.5) / 1.5;
				return true;
			});
		});
		onCleanup(() -> stopped = true);
		return <view tag={props.tag ?? "progress"} ref={n -> States.apply(n, props.style)} role="progressbar" label={props.label} value-now={() -> known() ? frac() : null} value-min={0} value-max={1}
			slot="progress" width={props.width} overflow="hidden" direction="row">
			<view slot="progress-indicator" transform={() -> "translateX(" + (-(1 - frac()) * 100) + "%)"}/>
			{() -> known() ? null : <view tag="progress-slide" slot="progress-indicator" data-state="indeterminate" position="absolute" top={0} bottom={0}
				width="40%" left={() -> ((phase.value * 1.4 - 0.4) * 100) + "%"}/>}
		</view>;
	}

	// a select bound to a signal: the chosen option's label (labels, else
	// the option) on a button, placeholder while the value is none of the
	// options (data-placeholder); a click, Enter or Space opens the options
	// under it, the chosen one focused; Up and Down move through them, a
	// click, Enter or Space chooses, Escape, Tab or a click outside closes.
	// On the closed button Up and Down choose the previous or next option;
	// the pointer over an option focuses it. Native where its host is (Ui.hostOf
	// "select": by default drawn on desktop) and the window's platform has
	// menus: the options a native menu under it, the chosen one checked. Slots (shadcn's)
	// "select-trigger" (data-state "open" or "closed", data-size), "select-value",
	// "select-content", "select-item" (data-state "checked" or "unchecked")
	// and "select-item-indicator" (shown when checked)
	@:widget({
		props: {
			value: "a signal of the chosen option",
			options: "the options' values",
			labels: "what each option shows (else the option itself)",
			width: "the button's width, and the list's least (else its content's)",
			placeholder: "what the button shows while the value is none of the options",
			size: "\"default\" or \"sm\" (data-size)",
			label: "its name for assistive technology"
		},
		keys: {
			"Enter, Space": "on the button, open the options, the chosen one focused; on an option, choose it and close them",
			"Up, Down": "on the button, choose the option before or after; in the options, move the focus through them",
			"Home, End": "in the options, to the first or last",
			"letters, digits": "on the button, choose the next option whose label starts with what was typed; in the options, focus it",
			"Escape, Tab": "close the options"
		}
	})
	public static function Select(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?size:String, ?placeholder:String,
			?label:String, ?style:States->StyleProps, ?tag:String}):View
		return select(props, false);

	// (Select's and NativeSelect's: native, the trigger shadcn's native-select, its icon native-select-icon;
	// unstyled, 160 wide)
	static function select(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?size:String, ?placeholder:String,
			?label:String, ?style:States->StyleProps, ?tag:String}, native:Bool):View {
		Rules.addBase("select", [{slot: "select-trigger", style: {width: 160}}, {slot: "native-select", style: {width: 160}}]);
		var tag = props.tag ?? "select", w = props.width;
		var open = signal(false);
		var items:Array<Node> = [];
		var labelOf = (v:String) -> {
			var i = props.options.indexOf(v);
			i < 0 && props.placeholder != null ? props.placeholder : i >= 0 && props.labels != null ? props.labels[i] : v;
		};
		function choose(v:String) {
			props.value.value = v;
			open.value = false;
		}
		function focusItem(i:Int)
			if (i >= 0 && i < items.length && items[i].ui != null) items[i].ui.setFocus(items[i]);
		function step(d:Int) {
			var i = props.options.indexOf(props.value.peek()) + d;
			if (i >= 0 && i < props.options.length) props.value.value = props.options[i];
		}
		var typed = new TypeAhead(), shown = [for (i in 0...props.options.length) props.labels != null ? props.labels[i] : props.options[i]];
		var self:Null<Node> = null;
		// (opened: the platform's menu where native, else the drawn list)
		function show() {
			var ui = self == null ? null : self.ui;
			if (ui != null && ui.hostOf(self, "select") == Native) {
				var current = props.value.peek();
				var menu:Array<PlatformMenuItem> = [for (i in 0...props.options.length) {id: i, label: shown[i], checked: props.options[i] == current}];
				if (ui.platform.menu(menu, self.absX, self.absY + self.height, id -> if (id >= 0) props.value.value = props.options[id])) return;
			}
			open.value = true;
		}
		return <view tag={tag} slot={native ? "native-select" : "select-trigger"} data-size={props.size ?? "default"} size={props.size ?? "default"}
			data-placeholder={() -> props.placeholder != null && props.options.indexOf(props.value.value) < 0 ? "" : null} ref={n -> {
			self = n;
			States.apply(n, props.style);
		}} role="combobox" label={props.label} expanded={() -> open.value}
			data-state={() -> open.value ? "open" : "closed"} focusable width={w} onClick={_ -> if (open.peek()) open.value = false else show()}
			onKeyDown={e -> switch e.key {
				case Key.ENTER | Key.SPACE:
					show();
					e.stop();
				case Key.DOWN:
					e.preventDefault();
					step(1);
				case Key.UP:
					e.preventDefault();
					step(-1);
				case _:
					// (typed: the option it starts, chosen)
					var j = typed.find(e.key, e.mods, Ui.now(), shown, props.options.indexOf(props.value.peek()));
					if (j >= 0) {
						props.value.value = props.options[j];
						e.stop();
					}
			}}>
			<text slot="select-value">{() -> labelOf(props.value.value)}</text>
			{native ? icon(CHEVRON, "native-select-icon") : <image slot="select-trigger-icon" src={CHEVRON} hidden/>}
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={_ -> focusItem(props.options.indexOf(props.value.peek()))}>
				<view tag={tag + "-list"} slot="select-content" data-state="open" role="listbox" label={props.label} min-width={() -> {
					open.value;
					w ?? (self == null ? 0.0 : self.width);
				}}><view slot="select-viewport">{[
					for (i in 0...props.options.length) {
						var o = props.options[i], state = () -> props.value.value == o ? "checked" : "unchecked";
						<view tag={tag + "-" + o} slot="select-item" data-state={state} role="option" selected={() -> props.value.value == o} ref={n -> items[i] = n}
							focusable onPointerEnter={_ -> focusItem(i)} onClick={_ -> choose(o)}
							onKeyDown={e -> switch e.key {
								case Key.DOWN:
									focusItem(i + 1);
									e.stop();
								case Key.UP:
									focusItem(i - 1);
									e.stop();
								case Key.HOME:
									focusItem(0);
									e.stop();
								case Key.END:
									focusItem(props.options.length - 1);
									e.stop();
								case Key.ENTER | Key.SPACE:
									choose(o);
									e.stop();
								case Key.TAB: open.value = false;
								case _:
									var j = typed.find(e.key, e.mods, Ui.now(), shown, i);
									if (j >= 0) {
										focusItem(j);
										e.stop();
									}
							}}>
							{props.labels != null ? props.labels[i] : o}
							<view slot="select-item-indicator" display={() -> state() == "checked" ? "flex" : "none"}>
								<image src={CHECK} width="100%" height="100%" hidden/>
							</view>
						</view>;
					}
				]}</view></view>
			</Popover>
		</view>;
	}

	// a list box: the options in a column (labels: what each shows), the
	// selection in selected (multiple: any number of them, else at most
	// one), height: scrolled past it. One Tab stop, the active option (the
	// first selected at first); Up, Down, Home, End and letters typed move
	// it, selecting it, and so does a click; with multiple, Shift extends
	// the selection from where it began (or a Shift click), Control moves
	// without selecting, Space (or a Control click) adds or takes away one,
	// Control+A selects them all. A double click or Enter: onActivate. Slots
	// "listbox" and "listbox-option" (aria-selected "true" or "false")
	@:widget({
		props: {
			selected: "a signal of the selected options, in the options' order",
			options: "the options' values",
			labels: "what each option shows (else the option itself)",
			multiple: "any number of options selected (else at most one)",
			height: "its height: the options scroll past it (else all shown)",
			width: "its width",
			onActivate: "called with an option when it is double clicked, or Enter is pressed on it",
			label: "its name for assistive technology"
		},
		keys: {
			"Up, Down": "move to the option before or after, selecting it",
			"Page Up, Page Down": "move a page up or down, selecting",
			"Home, End": "move to the first or last option, selecting it",
			"letters, digits": "move to the next option whose label starts with what was typed, selecting it",
			"Shift with a move": "with multiple, extend the selection from where it began",
			"Control with a move": "with multiple, move without selecting",
			"Space": "with multiple, add or take away the focused option; else select it",
			"Control+A": "with multiple, select them all",
			"Enter": "activates the focused option (onActivate)"
		}
	})
	public static function Listbox(props:{selected:Signal<Array<String>>, options:Array<String>, ?labels:Array<String>, ?multiple:Bool, ?height:Float,
			?width:Float, ?onActivate:String->Void, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "listbox", options = props.options, multiple = props.multiple == true, nodes:Array<Node> = [];
		var shown = [for (i in 0...options.length) props.labels != null ? props.labels[i] : options[i]];
		var first = options.indexOf(props.selected.peek()[0]);
		var active = signal(first < 0 ? 0 : first), anchor = first < 0 ? 0 : first, typed = new TypeAhead();
		// (the selection kept in the options' order)
		function range(a:Int, b:Int)
			props.selected.value = [for (i in (a < b ? a : b)...(a < b ? b : a) + 1) options[i]];
		function toggle(i:Int) {
			var now = props.selected.peek();
			props.selected.value = [for (o in options) if ((o == options[i]) != now.contains(o)) o];
			anchor = i;
		}
		function select(i:Int) {
			range(i, i);
			anchor = i;
		}
		function move(i:Int, mods:Int) {
			if (i < 0 || i >= options.length) return;
			if (multiple && mods & Key.MOD_SHIFT != 0) range(anchor, i) else if (!multiple || mods & (Key.MOD_CONTROL | Key.MOD_META) == 0) select(i);
			active.value = i;
			focusIn(nodes, i);
		}
		var lastAt = -1e9, last = -1;
		function click(e:Event, i:Int) {
			var now = Ui.now();
			if (multiple && e.mods & Key.MOD_SHIFT != 0) range(anchor, i) else if (multiple && e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0) toggle(i) else select(i);
			active.value = i;
			if (last == i && now - lastAt < 0.45 && props.onActivate != null) props.onActivate(options[i]);
			last = i;
			lastAt = now;
		}
		function key(e:Event, i:Int) {
			var page = props.height == null ? options.length : Std.int(Math.max(1, Math.floor(props.height / 28) - 1));
			switch e.key {
				case Key.DOWN: move(i + 1, e.mods);
				case Key.UP: move(i - 1, e.mods);
				case Key.PAGE_DOWN: move(Std.int(Math.min(i + page, options.length - 1)), e.mods);
				case Key.PAGE_UP: move(Std.int(Math.max(i - page, 0)), e.mods);
				case Key.HOME: move(0, e.mods);
				case Key.END: move(options.length - 1, e.mods);
				case Key.SPACE: multiple ? toggle(i) : select(i);
				case Key.ENTER: if (props.onActivate != null) props.onActivate(options[i]);
				case "a".code | "A".code if (multiple && e.mods & (Key.MOD_CONTROL | Key.MOD_META) != 0): props.selected.value = options.copy();
				case _:
					var j = typed.find(e.key, e.mods, Ui.now(), shown, i);
					if (j < 0) return;
					move(j, 0);
			}
			e.stop();
		}
		return <view tag={tag} slot="listbox" role="listbox" label={props.label} multiselectable={multiple} width={props.width} height={props.height}
			overflow={props.height == null ? "visible" : "scroll"}>{[
			for (i in 0...options.length) {
				var o = options[i];
				<view tag={tag + "-" + o} slot="listbox-option" role="option" ref={n -> nodes[i] = n} selected={() -> props.selected.value.contains(o)}
					aria-selected={() -> props.selected.value.contains(o) ? "true" : "false"} focusable={() -> active.value == i} shrink={0}
					onPointerDown={_ -> active.value = i} onClick={e -> click(e, i)} onKeyDown={e -> key(e, i)}>
					{shown[i]}
				</view>;
			}
		]}</view>;
	}

	// a list its user reorders (items: distinct values, a signal of their
	// array, each shown by render): an item dragged goes where a line shows
	// it will, before or after the item under the pointer (by its halves;
	// Escape cancels); one Tab stop, the active item (Up, Down, Home and End
	// move it), Alt+Up and Alt+Down move it in the list. onMove: after a
	// move, the item and its new index. Slots "sortable", "sortable-item"
	// (data-dragging while one is held), "sortable-handle" and
	// "sortable-indicator" (data-side "top" or "bottom", shown where a drop goes)
	@:widget({
		props: {
			items: "a signal of the items (distinct values) in their order, changed by a move",
			render: "a function of an item giving what it shows",
			onMove: "called after a move with the item and its new index",
			label: "its name for assistive technology"
		},
		keys: {
			"Up, Down": "move the focus to the item before or after",
			"Home, End": "move the focus to the first or last item",
			"Alt+Up, Alt+Down": "move the focused item up or down the list, said to assistive technology",
			"Escape": "cancels a drag"
		}
	})
	public static function Sortable<T>(props:{items:Signal<Array<T>>, render:T->Any, ?onMove:(T, Int)->Void, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "sortable", active = signal(0), refs:Array<{item:T, node:Null<Node>}> = [], said = signal("");
		// (where a drop goes: 2 * the item's index, plus 1 after it; -1: nowhere), whether one is dragged
		var over = signal(-1), held = signal(false);
		function nodeOf(item:T):Null<Node> {
			for (r in refs)
				if (r.item == item) return r.node;
			return null;
		}
		function focus(item:T) {
			var n = nodeOf(item);
			if (n != null && n.ui != null) n.ui.setFocus(n);
		}
		// (to: the index it goes before, in the list as it is)
		function move(item:T, to:Int) {
			var from = props.items.peek().indexOf(item), m = Behaviour.moved(props.items.peek(), item, to);
			if (m == null) return;
			active.value = m.at;
			if (m.at != from) {
				props.items.value = m.list;
				if (props.onMove != null) props.onMove(item, m.at);
			}
			focus(item);
		}
		function key(e:Event, item:T) {
			var list = props.items.peek(), i = list.indexOf(item), alt = e.mods & Key.MOD_ALT != 0;
			switch e.key {
				case Key.UP | Key.DOWN if (alt):
					move(item, e.key == Key.UP ? i - 1 : i + 2);
					// (said: where it went, its text as assistive technology names it)
					var n = nodeOf(item), at = props.items.peek().indexOf(item);
					if (at != i && n != null) said.value = "Moved " + AccessTree.textOf(n) + " to position " + (at + 1) + " of " + list.length;
				case Key.UP | Key.DOWN | Key.HOME | Key.END:
					var j = e.key == Key.UP ? i - 1 : e.key == Key.DOWN ? i + 1 : e.key == Key.HOME ? 0 : list.length - 1;
					if (j < 0 || j >= list.length) return;
					active.value = j;
					focus(list[j]);
				case _: return;
			}
			e.preventDefault();
		}
		return <view tag={tag} slot="sortable" role="list" label={props.label} description="Alt+Up and Alt+Down move an item">
			<view tag={tag + "-live"} position="absolute" width={0} height={0} overflow="hidden" live="polite"><text>{said}</text></view>
			<For each={props.items} render={(item:T) -> {
				var at = () -> props.items.value.indexOf(item), entry:{item:T, node:Null<Node>} = {item: item, node: null};
				refs.push(entry);
				onCleanup(() -> refs.remove(entry));
				<view slot="sortable-item" role="listitem" ref={n -> entry.node = n} drag-data={item} focusable={() -> at() == active.value}
					data-dragging={() -> held.value ? "" : null} onDragStart={_ -> held.value = true} onDragEnd={_ -> held.value = false}
					onPointerDown={_ -> active.value = at()} onKeyDown={e -> key(e, item)}
					onDragOver={e -> if (props.items.peek().indexOf(e.data) >= 0) {
						e.preventDefault();
						over.value = 2 * at() + (e.localY > e.current.height / 2 ? 1 : 0);
					}}
					onDragLeave={_ -> over.value = -1}
					onDrop={e -> {
						var to = over.peek();
						over.value = -1;
						if (to >= 0) move(e.data, (to >> 1) + (to & 1));
					}}>
					<text slot="sortable-handle" hidden>⋮⋮</text>
					{props.render(item)}
					<view slot="sortable-indicator" data-side="top" position="absolute" left={0} right={0} display={() -> over.value == 2 * at() ? "flex" : "none"}/>
					<view slot="sortable-indicator" data-side="bottom" position="absolute" left={0} right={0}
						display={() -> over.value == 2 * at() + 1 ? "flex" : "none"}/>
				</view>;
			}}/>
		</view>;
	}

	// a toolbar: its children in a row, its focusable ones (as they are
	// when it is shown) one Tab stop, the last focused (at first the first);
	// Left and Right (the way they point, wrapping), Home and End move the
	// focus between them (not out of a text field's text). Slot "toolbar"
	@:widget({
		props: {
			label: "its name for assistive technology",
			children: "its content, in a row: its focusable nodes (as they are when it is shown) one Tab stop"
		},
		keys: {
			"Left, Right": "move the focus to the item before or after, wrapping (swapped right to left); not out of a text field",
			"Home, End": "move the focus to the first or last item; not out of a text field"
		}
	})
	public static function Toolbar(props:{?label:String, ?tag:String, ?children:Any}):View {
		var bar:Null<Node> = null, items:Array<Node> = [];
		function rove(k:Int)
			for (j in 0...items.length)
				items[j].focusable = j == k;
		function itemOf(n:Null<Node>):Int {
			while (n != null && n != bar) {
				var j = items.indexOf(n);
				if (j >= 0) return j;
				n = n.parent;
			}
			return -1;
		}
		// (its items: the focusable nodes in it, outermost, marked once found
		// so that the ones roving made unfocusable stay items; again before
		// each use, for those added since, the one focusable kept)
		function collect() {
			var was = [for (it in items) if (it.focusable) it][0];
			items.resize(0);
			function walk(n:Node)
				for (c in n.children) {
					if (c.focusable || c.attr("data-toolbar-item") != null) {
						c.setAttr("data-toolbar-item", "");
						items.push(c);
					} else walk(c);
				}
			if (bar != null) walk(bar);
			var k = was == null ? -1 : items.indexOf(was);
			rove(k < 0 ? 0 : k);
		}
		onMount(collect);
		return <view tag={props.tag ?? "toolbar"} slot="toolbar" role="toolbar" label={props.label} ref={n -> bar = n}
			onPointerDown={(e:Event) -> {
				collect();
				var j = itemOf(e.target);
				if (j >= 0) rove(j);
			}}
			onFocusIn={(e:Event) -> {
				collect();
				var j = itemOf(e.target);
				if (j >= 0) rove(j);
			}}
			onKeyDown={(e:Event) -> {
				collect();
				var i = itemOf(e.target), n = items.length;
				if (i < 0 || Std.isOfType(e.target, EditableText)) return;
				var j = Behaviour.rove(mirrored(e), i, n, false);
				if (j < 0) return;
				e.preventDefault();
				rove(j);
				focusIn(items, j);
			}}>{props.children}</view>;
	}

	// a dropdown menu (shadcn's): a button, label; a click, Enter, Space or
	// Down opens its items under it (the first focused), each a label and
	// what choosing it does (and a shortcut: shown, and choosing it from
	// anywhere in the window); Up and Down move through them, the pointer
	// over one focuses it, a click, Enter or Space chooses (and closes),
	// Escape, Tab or a click outside closes. The button a "button" of
	// variant (default "outline"), data-state "open" or "closed"; slots
	// "dropdown-menu-content", "dropdown-menu-item" and "dropdown-menu-shortcut"
	@:widget({
		props: {
			label: "the button's text",
			items: "its items (MenuItem), each a label, onSelect (called when it is chosen), a shortcut (shown, and choosing it from anywhere in the window), variant destructive, disabled, separator, heading, checked (a signal of a Bool: a checkbox item), radio (a group's signal and its value) or items (a submenu)",
			variant: "the button's look: outline (the default), default, destructive, secondary, ghost or link"
		},
		variants: ["default", "destructive", "outline", "secondary", "ghost", "link"],
		keys: {
			"Enter, Space": "on the button, open the menu, its first item focused; on an item, choose it, closing the menu, or open its submenu",
			"Down": "on the button, opens the menu",
			"Up, Down": "in the menu, move through its items, past separators, headings and disabled ones, wrapping",
			"Home, End": "in the menu, to its first or last item",
			"Right": "on an item with items, opens its submenu (Left right to left)",
			"Left": "in a submenu, closes it, the focus back on its item (Right right to left)",
			"letters, digits": "focus the next item whose label starts with what was typed",
			"Escape": "closes a submenu, else the menu, the focus back on the button",
			"Tab": "closes the menu"
		}
	})
	public static function DropdownMenu(props:{label:String, items:Array<MenuItem>, ?variant:String,
			?style:States->StyleProps, ?tag:String}):View {
		var tag = props.tag ?? "menu";
		var open = signal(false);
		var items:Array<Node> = [];
		return <view tag={tag} slot="button" ref={n -> States.apply(n, props.style)} variant={props.variant ?? "outline"} size="default" role="button" expanded={() -> open.value}
			data-state={() -> open.value ? "open" : "closed"} focusable onClick={_ -> open.value = !open.value}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE || e.key == Key.DOWN) {
				open.value = true;
				e.stop();
			}}>
			{props.label}
			<image slot="dropdown-menu-trigger-icon" src={CHEVRON} hidden/>
			{hotkeys(props.items, false)}
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={_ -> focusFirst(items)}>
				{menuItems("dropdown-menu", tag, props.label, props.items, open, items)}
			</Popover>
		</view>;
	}

	// a menu bar: a row of menus' titles, each opening its items (as DropdownMenu's)
	// under it on a click, Down, Enter or Space; while one is open, the
	// pointer over another title opens that one instead; Left and Right move
	// between the titles the way they point (from an open menu: the next one
	// opened, wrapping);
	// Escape closes it, the focus back on its title. One stop for Tab: the
	// title last moved to. The items' shortcuts work from anywhere in the
	// window. The system's menu bar where native (Ui.hostOf "menubar": macOS's),
	// the drawn bar hidden then. Slots (shadcn's) "menubar", "menubar-trigger" (data-state
	// "open" or "closed"), "menubar-content", "menubar-item", "menubar-shortcut"
	@:widget({
		props: {
			menus: "its menus, each a title (label) and its items (MenuItem, as DropdownMenu's: a label, onSelect, a shortcut working from anywhere in the window, variant, disabled, separator, heading, checked, radio or items, a submenu)",
			label: "its name for assistive technology"
		},
		keys: {
			"Left, Right": "move between the titles the way they point, wrapping; from an open menu, open the next one",
			"Down, Enter, Space": "on a title, open its menu, its first item focused",
			"Up, Down": "in a menu, move through its items, past separators, headings and disabled ones, wrapping",
			"Home, End": "in a menu, to its first or last item",
			"Enter, Space": "on an item, choose it, closing the menu, or open its submenu",
			"Right": "on an item with items, opens its submenu (Left right to left)",
			"Left": "in a submenu, closes it, the focus back on its item (Right right to left)",
			"letters, digits": "in a menu, focus the next item whose label starts with what was typed",
			"Escape": "closes a submenu, else the menu, the focus back on its title",
			"Tab": "closes the menu"
		}
	})
	public static function Menubar(props:{menus:Array<{label:String, items:Array<MenuItem>}>, ?label:String,
			?tag:String}):View {
		var tag = props.tag ?? "menubar", count = props.menus.length;
		var opens = [for (m in props.menus) signal(false)], titles:Array<Node> = [], current = signal(0);
		// (the system's menu bar where native: its menus given, the drawn bar
		// hidden, its shortcuts still working; given back when it goes)
		var self:Null<Node> = null, native = signal(false);
		onMount(() -> {
			var ui = self == null ? null : self.ui;
			if (ui == null || ui.hostOf(self, "menubar") != Native) return;
			var all:Array<MenuItem> = [];
			var menus:Array<PlatformMenuItem> = [for (m in props.menus) {id: -1, label: m.label, items: nativeMenu(m.items, all)}];
			if (!ui.platform.menuBar(menus, id -> if (id >= 0 && id < all.length) chooseItem(all[id]))) return;
			native.value = true;
			var platform = ui.platform;
			onCleanup(() -> platform.menuBar([], _ -> {}));
		});
		// (menu i open, the others closed; -1: none)
		function show(i:Int)
			batch(() -> for (j in 0...count) opens[j].value = j == i);
		function anyOpen():Bool {
			for (o in opens)
				if (o.peek()) return true;
			return false;
		}
		// (to the title on the right or left, its menu opened if one was: the focus there first, out of the closing menu)
		function step(i:Int, right:Bool, open:Bool) {
			var d = right != (titles[i] != null && titles[i].rtl()) ? 1 : -1;
			var j = (i + d + count) % count;
			current.value = j;
			focusIn(titles, j);
			if (open) show(j);
		}
		return <view tag={tag} slot="menubar" role="menubar" label={props.label} ref={n -> self = n} display={() -> native.value ? "none" : "flex"}>{[
			for (i in 0...count) {
				var m = props.menus[i], items:Array<Node> = [];
				<view tag={tag + "-" + i} slot="menubar-trigger" role="menuitem" ref={n -> titles[i] = n} expanded={() -> opens[i].value}
					data-state={() -> opens[i].value ? "open" : "closed"} focusable={() -> current.value == i} onFocus={_ -> current.value = i}
					onPointerEnter={_ -> {
						if (anyOpen() && !opens[i].peek()) {
							current.value = i;
							focusIn(titles, i);
							show(i);
						}
					}} onClick={_ -> show(opens[i].peek() ? -1 : i)}
					onKeyDown={e -> switch e.key {
						case Key.LEFT | Key.RIGHT:
							step(i, e.key == Key.RIGHT, false);
							e.stop();
						case Key.DOWN | Key.ENTER | Key.SPACE:
							show(i);
							e.stop();
						case _:
					}}>
					{m.label}
					{hotkeys(m.items, false)}
					<Popover open={opens[i]} placement="below" onDismiss={() -> if (opens[i].peek()) show(-1)} onOpen={_ -> focusFirst(items)}>
						<view onKeyDown={e -> if (e.key == Key.LEFT || e.key == Key.RIGHT) {
							step(i, e.key == Key.RIGHT, true);
							e.stop();
						}}>{menuItems("menubar", tag + "-" + i, m.label, m.items, opens[i], items)}</view>
					</Popover>
				</view>;
			}
		]}</view>;
	}

	// a context menu: the children, with items (as DropdownMenu's) opened by a right
	// click on them where it was pressed, or by the menu key or Shift+F10
	// when the focus is in them (at their top left, the first item focused);
	// a press elsewhere, Escape or Tab closes it. The items' shortcuts work
	// while the focus is in the children. Native where the window's platform
	// has menus (Ui.hostOf "context-menu": Windows' and macOS's), the same
	// items chosen alike. Slots (shadcn's)
	// "context-menu-content", "context-menu-item", "context-menu-shortcut"
	@:widget({
		popup: true,
		props: {
			items: "its items (MenuItem, as DropdownMenu's: a label, onSelect, a shortcut working while the focus is in the children, variant, disabled, separator, heading, checked, radio or items, a submenu)",
			label: "its menu's name for assistive technology",
			children: "what it is the menu of: a right click on them opens it where pressed"
		},
		keys: {
			"Menu, Shift+F10": "with the focus in the children, open the menu at their top left, its first item focused",
			"Up, Down": "in the menu, move through its items, past separators, headings and disabled ones, wrapping",
			"Home, End": "in the menu, to its first or last item",
			"Enter, Space": "on an item, choose it, closing the menu, or open its submenu",
			"Right": "on an item with items, opens its submenu (Left right to left)",
			"Left": "in a submenu, closes it, the focus back on its item (Right right to left)",
			"letters, digits": "in the menu, focus the next item whose label starts with what was typed",
			"Escape": "closes a submenu, else the menu",
			"Tab": "closes the menu"
		}
	})
	public static function ContextMenu(props:{items:Array<MenuItem>, ?label:String, ?tag:String, ?children:Any}):View {
		var tag = props.tag ?? "context-menu";
		var open = signal(false);
		var items:Array<Node> = [];
		var self:Node = null, atX = 0.0, atY = 0.0;
		function show(x:Float, y:Float) {
			var ui = self.ui;
			if (ui != null && ui.hostOf(self, "context-menu") == Native) {
				var all:Array<MenuItem> = [];
				if (ui.platform.menu(nativeMenu(props.items, all), x, y, id -> if (id >= 0 && id < all.length) chooseItem(all[id]))) return;
			}
			atX = x;
			atY = y;
			// (open again where it was asked: a second right click moves it)
			open.value = false;
			open.value = true;
		}
		return <view tag={tag} ref={n -> self = n}
			onPointerDown={e -> if (e.button == 3) {
				show(e.x, e.y);
				// (the focus stays in the menu)
				e.preventDefault();
				e.stop();
			} else open.value = false}
			onKeyDown={e -> if (e.key == Key.MENU || (e.key == Key.F10 && e.mods & Key.MOD_SHIFT != 0)) {
				show(self.absX, self.absY);
				e.stop();
			}}>
			{props.children}
			{hotkeys(props.items, true)}
			<Popover open={open} at={() -> {x: atX, y: atY}} onDismiss={() -> open.value = false} onOpen={_ -> focusFirst(items)}>
				{menuItems("context-menu", tag, props.label, props.items, open, items)}
			</Popover>
		</view>;
	}

	// (a menu's items as a native menu's, each chosen one's id its place in all)
	static function nativeMenu(items:Array<MenuItem>, all:Array<MenuItem>):Array<PlatformMenuItem>
		return [
			for (it in items) {
				var id = all.length;
				all.push(it);
				var checked = it.checked != null ? it.checked.peek() : it.radio != null ? it.radio.group.peek() == it.radio.value : null;
				({
					id: id,
					label: it.label,
					shortcut: it.shortcut == null ? null : Shortcut.parse(it.shortcut).label(),
					keys: it.shortcut == null ? null : Shortcut.parse(it.shortcut),
					disabled: it.disabled == true || it.heading == true,
					checked: checked,
					separator: it.separator,
					items: it.items == null ? null : nativeMenu(it.items, all)
				} : PlatformMenuItem);
			}
		];

	// (an item chosen from a native menu: as from the drawn one)
	static function chooseItem(it:MenuItem)
		if (it.disabled != true && it.items == null) Behaviour.choose(it);

	// a toggle group (shadcn's): one of options (labels: what each shows),
	// chosen among toggles joined in a row (a radio group: one Tab stop, the
	// chosen one; Left and Right, the way they point, wrapping, and Home and
	// End choose another); variant "default" or "outline", size "default",
	// "sm" or "lg". Slots "toggle-group" and "toggle-group-item" (data-state
	// "on" or "off"), each with the variant and size
	@:widget({
		props: {
			value: "a signal of the chosen option",
			options: "the options' values",
			labels: "what each option shows (else the option itself)",
			variant: "its toggles' look: default or outline",
			size: "default, sm or lg",
			label: "its name for assistive technology"
		},
		variants: ["default", "outline"],
		sizes: ["default", "sm", "lg"],
		keys: {
			"Left, Right": "choose the option before or after, wrapping (swapped right to left)",
			"Up, Down": "choose the option before or after, wrapping",
			"Home, End": "choose the first or last option",
			"Enter, Space": "choose the focused option"
		}
	})
	@:neutral public static function ToggleGroup(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?variant:String, ?size:String,
			?label:String, ?tag:String}):View {
		var variant = props.variant ?? "default", size = props.size ?? "default";
		var tag = props.tag ?? "segments", options = props.options, items:Array<Part> = [], n = options.length;
		function stop(i:Int):Bool {
			var k = options.indexOf(props.value.value);
			return i == (k < 0 ? 0 : k);
		}
		function key(e:Event, i:Int) {
			var k = mirroredKey(e), j = k == Key.SPACE || k == Key.ENTER ? i : Behaviour.rove(k, i, n);
			if (j < 0) return;
			e.preventDefault();
			props.value.value = options[j];
			focusPart(items, j);
		}
		return <view tag={tag} id={props.tag} slot="toggle-group" variant={variant} size={size} data-spacing="0" role="radiogroup" label={props.label}>{[
			for (i in 0...n) {
				var o = options[i], on = () -> props.value.value == o;
				<view:button tag={tag + "-" + i} slot="toggle-group-item" variant={variant} size={size} data-spacing="0" role="radio" ref={p -> items[i] = p}
					checked={on} data-state={() -> on() ? "on" : "off"} focusable={() -> stop(i)} onPress={_ -> props.value.value = o}
					onKeyDown={e -> key(e, i)}>{props.labels != null && props.labels[i] != null ? props.labels[i] : o}</view:button>;
			}
		]}</view>;
	}

	// a breadcrumb (shadcn's): the path to where one is, each step but the
	// last a link (chosen by a click or Enter: onSelect with its index), the
	// last the current page, in a navigation landmark; the separators (a
	// chevron, the way the line reads) decoration. Slots "breadcrumb",
	// "breadcrumb-list", "breadcrumb-item", "breadcrumb-link",
	// "breadcrumb-page", "breadcrumb-separator"
	@:widget({
		props: {
			items: "the steps' texts, from the first to the current page",
			onSelect: "called with a step's index when it is clicked, or Enter is pressed on it (all but the last)",
			label: "its landmark's name"
		},
		keys: {"Enter": "on a step, chooses it (onSelect)"}
	})
	public static function Breadcrumb(props:{items:Array<String>, onSelect:Int->Void, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "crumbs", items = props.items;
		return <view tag={tag} slot="breadcrumb" role="navigation" label={props.label ?? "breadcrumb"}>
			<view slot="breadcrumb-list">{[
				for (i in 0...items.length) {
					var last = i == items.length - 1;
					[
						<view slot="breadcrumb-item">{last ? <text tag={tag + "-" + i} slot="breadcrumb-page" current>{items[i]}</text> : <text tag={tag + "-" + i}
							slot="breadcrumb-link" role="link" focusable onClick={_ -> props.onSelect(i)} onKeyDown={e -> if (e.key == Key.ENTER) {
								e.preventDefault();
								props.onSelect(i);
							}}>{items[i]}</text>}</view>,
						last ? null : <view slot="breadcrumb-separator" hidden>{icon(CHEVRON_RIGHT, "breadcrumb-separator-icon", null, true)}</view>
					];
				}
			]}</view>
		</view>;
	}

	// pagination (shadcn's): Previous, the pages (the first, the last, the
	// current one and its neighbours, "…" for the rest, a page instead where
	// it hides only one), Next, in a navigation landmark; pages count from
	// 1, the current page's button marked current. Slots "pagination",
	// "pagination-content", "pagination-item", "pagination-link" (size "icon"
	// for a page, "default" for Previous and Next; data-active on the
	// current page's, data-disabled on Previous on the first, Next on the
	// last) and "pagination-ellipsis"
	@:widget({
		props: {
			page: "a signal of the current page, from 1",
			count: "the number of pages",
			label: "its landmark's name"
		},
		keys: {"Enter, Space": "on a button, go to its page (Previous and Next: the page before or after)"}
	})
	public static function Pagination(props:{page:Signal<Int>, count:Int, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "pages", count = props.count;
		function go(p:Int)
			if (p >= 1 && p <= count) props.page.value = p;
		// (the buttons in order, 0 for a gap)
		function shown():Array<Int>
			return Behaviour.pages(props.page.value, count);
		function button(label:Any, tagged:String, size:String, onClick:Void->Void, ?current:Void->Bool, ?disabled:Void->Bool, slot = "pagination-link"):View {
			var cur = () -> current != null && current(), off = () -> disabled != null && disabled();
			return <view slot="pagination-item"><view tag={tagged} slot={slot} size={size} role="button" focusable={() -> !off()} disabled={off}
				data-disabled={off} current={cur} data-active={() -> cur() ? "true" : null} onClick={_ -> if (!off()) onClick()}
				onKeyDown={e -> if ((e.key == Key.ENTER || e.key == Key.SPACE) && !off()) {
					e.preventDefault();
					onClick();
				}}>{label}</view></view>;
		}
		return <view tag={tag} slot="pagination" role="navigation" label={props.label ?? "pagination"}>
			<view slot="pagination-content">
				{button([icon(CHEVRON_LEFT, "pagination-icon"), "Previous"], tag + "-prev", "default", () -> go(props.page.peek() - 1), null, () -> props.page.value <= 1, "pagination-previous")}
				<Index each={shown} render={(p:Signal<Int>, _) -> <view direction="row">
					<Show when={() -> p.value == 0} fallback={button(() -> Std.string(p.value), tag + "-page", "icon", () -> go(p.peek()),
						() -> props.page.value == p.value)}>
						<view slot="pagination-ellipsis" hidden>{icon(MORE, "pagination-ellipsis-icon")}</view>
					</Show>
				</view>}/>
				{button(["Next", icon(CHEVRON_RIGHT, "pagination-icon")], tag + "-next", "default", () -> go(props.page.peek() + 1), null, () -> props.page.value >= count, "pagination-next")}
			</view>
		</view>;
	}

	// the items' shortcuts (local: while the focus is in the parent)
	static function hotkeys(list:Array<MenuItem>, local:Bool):Array<Any> {
		var out:Array<Any> = [];
		for (it in list) {
			if (it.disabled == true) continue;
			if (it.items != null) out = out.concat(hotkeys(it.items, local));
			else if (it.shortcut != null && (it.onSelect != null || it.checked != null || it.radio != null))
				out.push(UiFlow.Hotkey({
					keys: it.shortcut,
					action: () -> Behaviour.choose(it),
					local: local
				}));
		}
		return out;
	}

	// focuses the first of nodes that takes the focus
	static function focusFirst(nodes:Array<Node>)
		for (i in 0...nodes.length)
			if (nodes[i] != null && nodes[i].focusable) {
				focusIn(nodes, i);
				return;
			}

	// an event's key, Left and Right swapped where it is right to left (the
	// way they point, in a mirrored row or grid)
	static function mirrored(e:Event):Int
		return Behaviour.mirror(e.key, e.current.rtl());

	// (a button's keys: Enter and Space press it)
	static function pressKeys(e:Event, press:Void->Void)
		if (e.key == Key.ENTER || e.key == Key.SPACE) {
			e.preventDefault();
			press();
		}

	// focuses nodes[i] if it is shown
	static function focusIn(nodes:Array<Node>, i:Int)
		if (i >= 0 && i < nodes.length && nodes[i].ui != null) nodes[i].ui.setFocus(nodes[i]);

	// (a neutral widget's: the key mirrored right to left by the part
	// listening. In a page the event's current and its Part's methods used
	// opaquely: through Event's field, the interface or by name untyped, they
	// would keep ui's Event, each Part's, a Node's and its nodes, in a page)
	static function mirroredKey(e:Event):Int
		return Behaviour.mirror(e.key, #if js js.Syntax.code("{0}.current.rtl()", e) #else e.current.rtl() #end);

	// (a neutral widget's: parts[i], after a key)
	static function focusPart(parts:Array<Part>, i:Int)
		if (i >= 0 && i < parts.length && parts[i] != null) #if js js.Syntax.code("{0}.focus(true)", parts[i]) #else parts[i].focus() #end;

	// a menu's panel of items (their nodes into nodes): Up and Down move
	// through them (wrapping), Home and End to the first and last, letters
	// typed to the one they start, the pointer over
	// one focuses it, a click, Enter or Space chooses one (and closes the
	// menu: root, else open), Tab closes; separators, headings and disabled
	// items skipped. A checkbox item toggles its signal, a radio item sets its
	// group's; an item with items opens them beside it (a submenu: the
	// pointer resting on it, Right, Enter or Space; Left or Escape closes it,
	// the focus back on it). Slots: kind, "-content" (a submenu's
	// "-sub-content"), "-item" (variant; data-disabled; a checkbox or radio
	// item's data-state "checked" or "unchecked"), "-item-indicator",
	// "-checkbox-item", "-radio-item", "-label" (a heading), "-sub-trigger"
	// (data-state "open" or "closed"), "-shortcut", "-separator"
	static function menuItems(kind:String, tag:String, label:Null<String>, list:Array<MenuItem>,
			open:Signal<Bool>, nodes:Array<Node>, ?root:Signal<Bool>, ?content:String):View {
		var typed = new TypeAhead(), labels = [for (it in list) Behaviour.skipped(it) ? "" : it.label];
		var close = root ?? open;
		// (a submenu closed with its menu)
		if (root != null) effect(() -> if (!root.value) untrack(() -> open.value = false));
		// (the next item that can be chosen, the way d goes, wrapping)
		function move(from:Int, d:Int) {
			var n = list.length, j = from;
			for (_ in 0...n) {
				j = (j + d + n) % n;
				if (!Behaviour.skipped(list[j])) {
					focusIn(nodes, j);
					return;
				}
			}
		}
		return <view tag={tag + "-items"} slot={kind + (content ?? "-content")} data-state="open" role="menu" label={label}>{[
			for (i in 0...list.length) {
				var it = list[i], off = it.disabled == true;
				if (it.separator == true) <view slot={kind + "-separator"} role="separator" hidden/>;
				else if (it.heading == true) <text slot={kind + "-label"} role="heading">{it.label}</text>;
				else {
					var sub = it.items == null ? null : signal(false), subNodes:Array<Node> = [];
					var checked = it.checked != null ? () -> it.checked.value : it.radio != null ? () -> it.radio.group.value == it.radio.value : null;
					function choose()
						if (!off) {
							if (sub != null) {
								sub.value = true;
								return;
							}
							close.value = false;
							Behaviour.choose(it);
						}
					var slot = sub != null ? "-sub-trigger" : it.checked != null ? "-checkbox-item" : it.radio != null ? "-radio-item" : "-item";
					<view tag={tag + "-" + i} slot={kind + slot} variant={it.variant ?? "default"}
						role={it.checked != null ? "menuitemcheckbox" : it.radio != null ? "menuitemradio" : "menuitem"}
						checked={checked == null ? null : checked} data-state={checked != null ? () -> checked() ? "checked" : "unchecked" : sub != null ? () -> sub.value ? "open" : "closed" : null}
						expanded={sub == null ? null : () -> sub.value} ref={n -> nodes[i] = n} focusable={!off} disabled={off} data-disabled={off}
						onPointerEnter={_ -> if (!off) {
							focusIn(nodes, i);
							if (sub != null) sub.value = true;
						}}
						onClick={_ -> choose()}
						onKeyDown={e -> switch mirrored(e) {
							case Key.DOWN:
								move(i, 1);
								e.stop();
							case Key.UP:
								move(i, -1);
								e.stop();
							case Key.HOME:
								move(-1, 1);
								e.stop();
							case Key.END:
								move(list.length, -1);
								e.stop();
							case Key.ENTER | Key.SPACE | Key.RIGHT if (sub != null):
								sub.value = true;
								focusFirst(subNodes);
								e.stop();
							case Key.ENTER | Key.SPACE:
								choose();
								e.stop();
							case Key.TAB: close.value = false;
							case _:
								var j = typed.find(e.key, e.mods, Ui.now(), labels, i);
								if (j >= 0) {
									focusIn(nodes, j);
									e.stop();
								}
						}}>
						{checked == null ? null : <view slot={kind + "-item-indicator"} hidden>
							<Show when={checked}><image slot={kind + "-item-indicator-icon"} src={it.radio != null ? CIRCLE : CHECK} hidden/></Show>
						</view>}
						{it.label}
						{it.shortcut == null ? null : <text slot={kind + "-shortcut"}>{Shortcut.parse(it.shortcut).label()}</text>}
						{sub == null ? null : [
							<image slot={kind + "-sub-trigger-icon"} src={CHEVRON_RIGHT} hidden/>,
							<Popover open={sub} placement="right" onDismiss={() -> sub.value = false}>
								<view onKeyDown={e -> if (mirrored(e) == Key.LEFT || e.key == Key.ESCAPE) {
									sub.value = false;
									focusIn(nodes, i);
									e.preventDefault();
									e.stop();
								}}>{menuItems(kind, tag + "-" + i, it.label, it.items, sub, subNodes, close, "-sub-content")}</view>
							</Popover>
						]}
					</view>;
				}
			}
		]}</view>;
	}


	// a tooltip: text shown by the children (above them) once the pointer
	// has rested on them for delay seconds (0.5), hidden when it leaves or
	// presses, or by Escape (slot "tooltip-content", shadcn's)
	@:widget({
		popup: true,
		props: {
			text: "its text",
			delay: "the seconds the pointer rests on the children before it shows",
			placement: "where it shows: above (the default), below, right or left, flipped where it does not fit",
			children: "what shows it: the pointer resting on them, or the keyboard's focus in them"
		},
		keys: {
			"Tab": "into the children, shows it after delay; out of them, hides it",
			"Escape": "hides it"
		}
	})
	public static function Tooltip(props:{text:String, ?delay:Float, ?placement:String, ?tag:String, ?children:Any}):View {
		var show = signal(false), over = 0;
		var delay = props.delay ?? 0.5;
		function enter() {
			var mine = ++over, start = -1.0;
			// (from the clock's next tick: its last may be long past)
			Clock.add(now -> {
				if (mine != over) return false;
				if (start < 0) start = now;
				if (now - start < delay) return true;
				show.value = true;
				return false;
			});
		}
		function leave() {
			over++;
			show.value = false;
		}
		// (also while the keyboard's focus is in it)
		return <view tag={props.tag} onPointerEnter={_ -> enter()} onPointerLeave={_ -> leave()} onPointerDown={_ -> leave()}
			onFocusIn={e -> if (e.current.ui != null && e.current.ui.focusVisible) enter()} onFocusOut={_ -> leave()}>
			{props.children}
			<Popover open={show} placement={props.placement ?? "above"} tag="tooltip" onDismiss={leave}>
				<view slot="tooltip-content" data-state="open" role="tooltip">{props.text}</view>
			</Popover>
		</view>;
	}

	// a modal dialog (shadcn's) while open is true: its title and
	// description, then the children, on a panel over the dimmed window,
	// its first focusable node focused, a close button (an ×, last; close:
	// false, none); Escape, the close button or a click on the backdrop
	// closes it (open set to false). Slots "dialog-overlay", "dialog-content",
	// "dialog-header", "dialog-title", "dialog-description", "dialog-close";
	// DialogFooter's "dialog-footer"
	@:widget({
		props: {
			open: "a signal of whether it is shown, set to false when it closes",
			title: "its heading, and its name for assistive technology",
			description: "a line of text under the title",
			width: "its panel's width in pixels (360)",
			close: "false: no close button",
			children: "its body, under the title: fields, then a DialogFooter"
		},
		keys: {
			"Tab, Shift+Tab": "moves the focus to the next or previous node in it, wrapping: it stays inside",
			"Escape": "closes it",
			"Enter, Space": "on the close button: closes it"
		}
	})
	public static function Dialog(props:{open:Signal<Bool>, title:String, ?description:String, ?width:Float, ?close:Bool, ?tag:String,
			?children:Any}):Any {
		var close = () -> props.open.value = false;
		return Popover({
			open: props.open,
			modal: true,
			slot: "dialog-overlay",
			onDismiss: close,
			tag: props.tag ?? "dialog",
			children: <view slot="dialog-content" data-state="open" role="dialog" label={props.title} width={props.width ?? 360}>
				<view slot="dialog-header">
					<text slot="dialog-title" role="heading">{props.title}</text>
					{props.description == null ? null : <text slot="dialog-description">{props.description}</text>}
				</view>
				{props.children}
				{props.close == false ? null : <view tag={(props.tag ?? "dialog") + "-close"} slot="dialog-close" role="button" label="Close" focusable
					onClick={_ -> close()} onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
						e.preventDefault();
						close();
					}}><image slot="dialog-close-icon" src={X}/></view>}
			</view>
		});
	}

	@:widget({
		props: {
			children: "its buttons, at the dialog's foot"
		},
		part: "Dialog"
	})
	public static function DialogFooter(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "dialog-footer"} slot="dialog-footer">{props.children}</view>;

	// an alert dialog (shadcn's): a modal asking to confirm while open is
	// true: its title and description, the children, then the cancel and
	// action buttons (labels cancel, default "Cancel", and action, default
	// "Continue"; the action's variant default "default", "destructive" for
	// a deletion), the cancel button focused first. Cancel or Escape closes
	// it (onCancel), the action closes it and runs onAction; a click outside
	// does nothing. Slots "alert-dialog-overlay", "alert-dialog-content"
	// (data-size, a group: group/alert-dialog-content), "alert-dialog-header", "alert-dialog-title", "alert-dialog-description",
	// "alert-dialog-footer"; the buttons "button"s
	@:widget({
		props: {
			open: "a signal of whether it is shown, set to false when it closes",
			title: "its heading, the question, and its name for assistive technology",
			description: "a line of text under the title",
			cancel: "the cancel button's label (Cancel)",
			action: "the action button's label (Continue)",
			variant: "the action button's look: default, or destructive for a deletion (a button's variants)",
			onAction: "called when the action button closes it",
			onCancel: "called when the cancel button or Escape closes it",
			width: "its panel's width in pixels (360)",
			size: "\"default\" or \"sm\" (data-size: a small one's header centred, its buttons side by side)",
			children: "more content, between the description and the buttons"
		},
		variants: ["default", "destructive", "outline", "secondary", "ghost", "link"],
		keys: {
			"Tab, Shift+Tab": "moves the focus between its buttons, wrapping: it stays inside",
			"Escape": "cancels it (onCancel)",
			"Enter, Space": "presses the focused button (the cancel button at first)"
		}
	})
	public static function AlertDialog(props:{open:Signal<Bool>, title:String, ?description:String, ?cancel:String, ?action:String,
			?variant:String, ?onAction:Void->Void, ?onCancel:Void->Void, ?width:Float, ?size:String, ?tag:String, ?children:Any}):Any {
		var tag = props.tag ?? "alert-dialog", size = props.size ?? "default";
		function cancel() {
			props.open.value = false;
			if (props.onCancel != null) props.onCancel();
		}
		function act() {
			props.open.value = false;
			if (props.onAction != null) props.onAction();
		}
		return Popover({
			open: props.open,
			modal: true,
			slot: "alert-dialog-overlay",
			onDismiss: cancel,
			dismissOnOutside: false,
			// (the focus on Cancel, as Radix's: the safe choice under Enter)
			onOpen: p -> {
				var c = p.find(tag + "-cancel");
				if (c != null && c.ui != null) c.ui.setFocus(c, false);
			},
			tag: tag,
			// (its size the parts' too: their group-data-[size=...] rules)
			children: <view slot="alert-dialog-content" data-state="open" data-size={size} size={size} group="alert-dialog-content" role="alertdialog" label={props.title}
				width={props.width ?? 360}>
				<view slot="alert-dialog-header" size={size}>
					<text slot="alert-dialog-title" role="heading" size={size}>{props.title}</text>
					{props.description == null ? null : <text slot="alert-dialog-description">{props.description}</text>}
				</view>
				{props.children}
				<view slot="alert-dialog-footer" direction="row" size={size}>
					<Button tag={tag + "-cancel"} label={props.cancel ?? "Cancel"} variant="outline" onClick={cancel}/>
					<Button tag={tag + "-action"} label={props.action ?? "Continue"} variant={props.variant ?? "default"} onClick={act}/>
				</view>
			</view>
		});
	}

	// a sheet (shadcn's): a dialog along an edge of the window (side
	// "right", the default, "left", "top" or "bottom"), its title,
	// description and the children, a close button (close: false, none);
	// modal, closed as a dialog is. Slots "sheet-overlay", "sheet-content"
	// (data-side), "sheet-header", "sheet-title", "sheet-description",
	// "sheet-close"; SheetFooter's "sheet-footer"
	@:widget({
		props: {
			open: "a signal of whether it is shown, set to false when it closes",
			title: "its heading, and its name for assistive technology",
			description: "a line of text under the title",
			side: "the window's edge it is along: right (the default), left, top or bottom",
			close: "false: no close button",
			children: "its body, under the title: fields, then a SheetFooter"
		},
		keys: {
			"Tab, Shift+Tab": "moves the focus to the next or previous node in it, wrapping: it stays inside",
			"Escape": "closes it",
			"Enter, Space": "on the close button: closes it"
		}
	})
	public static function Sheet(props:{open:Signal<Bool>, title:String, ?description:String, ?side:String, ?close:Bool, ?tag:String,
			?children:Any}):Any {
		var side = props.side ?? "right", close = () -> props.open.value = false, tag = props.tag ?? "sheet";
		var across = side == "left" || side == "right";
		return Popover({
			open: props.open,
			modal: true,
			slot: "sheet-overlay",
			onDismiss: close,
			tag: tag,
			children: <view slot="sheet-content" data-state="open" data-side={side} role="dialog" label={props.title} position="absolute"
				top={side == "bottom" ? null : 0} bottom={side == "top" ? null : 0} left={side == "right" ? null : 0} right={side == "left" ? null : 0}
				width={across ? "75%" : null} max-width={across ? 384 : null}>
				<view slot="sheet-header">
					<text slot="sheet-title" role="heading">{props.title}</text>
					{props.description == null ? null : <text slot="sheet-description">{props.description}</text>}
				</view>
				{props.children}
				{props.close == false ? null : <view tag={tag + "-close"} slot="sheet-close" role="button" label="Close" focusable onClick={_ -> close()}
					onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
						e.preventDefault();
						close();
					}}><image slot="sheet-close-icon" src={X}/></view>}
			</view>
		});
	}

	@:widget({
		props: {
			children: "its buttons, at the sheet's foot"
		},
		part: "Sheet"
	})
	public static function SheetFooter(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "sheet-footer"} slot="sheet-footer">{props.children}</view>;

	// a drawer (shadcn's, vaul's): a sheet along an edge (direction
	// "bottom", the default, "top", "left" or "right") with a handle, its
	// title, description and the children; modal, closed as a dialog is or
	// by a drag towards its edge past a quarter of its size, which it
	// follows (less: back in place). Slots "drawer-overlay", "drawer-content"
	// (data-vaul-drawer-direction), "drawer-handle", "drawer-header",
	// "drawer-title", "drawer-description"; DrawerFooter's "drawer-footer"
	@:widget({
		props: {
			open: "a signal of whether it is shown, set to false when it closes",
			title: "its heading, and its name for assistive technology",
			description: "a line of text under the title",
			direction: "the window's edge it comes from: bottom (the default), top, left or right",
			children: "its body, under the title: content, then a DrawerFooter"
		},
		keys: {
			"Tab, Shift+Tab": "moves the focus to the next or previous node in it, wrapping: it stays inside",
			"Escape": "closes it"
		}
	})
	public static function Drawer(props:{open:Signal<Bool>, title:String, ?description:String, ?direction:String, ?tag:String, ?children:Any}):Any {
		var dir = props.direction ?? "bottom", tag = props.tag ?? "drawer", close = () -> props.open.value = false;
		var across = dir == "left" || dir == "right", sign = dir == "bottom" || dir == "right" ? 1 : -1;
		var pull = signal(0.0), from = 0.0, dragging = false;
		function along(e:Event):Float
			return (across ? e.x : e.y) * sign;
		return Popover({
			open: props.open,
			modal: true,
			slot: "drawer-overlay",
			onDismiss: close,
			tag: tag,
			children: <view tag={tag + "-content"} slot="drawer-content" group="drawer-content" data-state="open" data-vaul-drawer-direction={dir} role="dialog" label={props.title}
				position="absolute" top={dir == "bottom" ? null : 0} bottom={dir == "top" ? null : 0} left={dir == "right" ? null : 0}
				right={dir == "left" ? null : 0} width={across ? "75%" : null} max-width={across ? 384 : null}
				transform={() -> pull.value == 0 ? "none" : (across ? "translateX(" : "translateY(") + (pull.value * sign) + "px)"}
				onPointerDown={e -> {
					from = along(e);
					dragging = false;
				}}
				onPointerMove={e -> if (e.current.pressed || dragging) {
					var d = along(e) - from;
					// (a drag past a few pixels, not a click)
					if (!dragging && d > 4) dragging = true;
					if (dragging) pull.value = Math.max(0, d);
				}}
				onPointerUp={e -> if (dragging) {
					dragging = false;
					var size = across ? e.current.width : e.current.height;
					if (pull.peek() > size / 4) close();
					pull.value = 0;
				}}>
				<view slot="drawer-handle" hidden/>
				<view slot="drawer-header">
					<text slot="drawer-title" role="heading">{props.title}</text>
					{props.description == null ? null : <text slot="drawer-description">{props.description}</text>}
				</view>
				{props.children}
			</view>
		});
	}

	@:widget({
		props: {
			children: "its buttons, at the drawer's foot"
		},
		part: "Drawer"
	})
	public static function DrawerFooter(props:{?children:View, ?tag:String}):View
		return <view tag={props.tag ?? "drawer-footer"} slot="drawer-footer">{props.children}</view>;

	// a popover (shadcn's Popover, its trigger an outline button): label on
	// the button, a click, Enter or Space opens the children under it (the
	// first focusable focused) or closes them, Escape or a click outside closes; open (a
	// signal) says whether it is. Slots "popover-trigger" (the button, a
	// "button" of variant, data-state "open" or "closed") and
	// "popover-content" (data-state, data-side "bottom")
	@:widget({
		props: {
			label: "the button's text, and the popover's name for assistive technology",
			open: "a signal of whether the popover is shown (its own when not given)",
			variant: "the button's look: outline (the default), default, destructive, secondary, ghost or link",
			children: "the popover's content, under the button"
		},
		variants: ["default", "destructive", "outline", "secondary", "ghost", "link"],
		keys: {
			"Enter, Space": "opens it, its first focusable node focused, or closes it",
			"Escape": "closes it"
		}
	})
	public static function PopoverButton(props:{label:String, ?open:Signal<Bool>, ?variant:String, ?style:States->StyleProps, ?tag:String, ?children:Any}):View {
		var open = props.open ?? signal(false), tag = props.tag ?? "popover";
		return <view tag={tag} slot="button" ref={n -> States.apply(n, props.style)} variant={props.variant ?? "outline"} size="default" role="button" expanded={() -> open.value}
			data-state={() -> open.value ? "open" : "closed"} focusable onClick={_ -> open.value = !open.peek()}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
				open.value = !open.peek();
				e.stop();
			}}>
			{props.label}
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={p -> {
				var f = @:privateAccess Ui.firstFocusable(p);
				if (f != null) p.ui.setFocus(f);
			}}>
				<view tag={tag + "-content"} slot="popover-content" data-state="open" data-side="bottom" role="dialog" label={props.label}>{props.children}</view>
			</Popover>
		</view>;
	}

	// a hover card (shadcn's): the children, and content shown by them
	// (below) once the pointer has rested on them for delay seconds (0.7)
	// or the keyboard's focus came into them, kept while it is over either,
	// hidden when it leaves both (after 0.3 seconds), the focus leaves, or by
	// Escape (slot "hover-card-content")
	@:widget({
		popup: true,
		props: {
			content: "what the card shows",
			delay: "the seconds the pointer rests on the children before the card shows (0.7)",
			placement: "where the card goes: below (the default), above, right or left",
			children: "what the pointer rests on to show the card"
		},
		keys: {"Tab": "into the children: shows the card (after delay); out of them: hides it", "Escape": "hides the card"}
	})
	public static function HoverCard(props:{content:Any, ?delay:Float, ?placement:String, ?tag:String, ?children:Any}):View {
		var show = signal(false), over = 0, delay = props.delay ?? 0.7;
		// (show or hide after a wait: the last asked wins)
		function after(wait:Float, v:Bool) {
			var mine = ++over, start = -1.0;
			Clock.add(now -> {
				if (mine != over) return false;
				if (start < 0) start = now;
				if (now - start < wait) return true;
				show.value = v;
				return false;
			});
		}
		// (also while the keyboard's focus is in it, as Radix's)
		return <view tag={props.tag} onPointerEnter={_ -> if (!show.peek()) after(delay, true) else over++}
			onPointerLeave={_ -> after(0.3, false)} onFocusIn={e -> if (e.current.ui != null && e.current.ui.focusVisible) after(delay, true)}
			onFocusOut={_ -> after(0.3, false)}>
			{props.children}
			<Popover open={show} placement={props.placement ?? "below"} tag="hover-card" onDismiss={() -> {
				over++;
				show.value = false;
			}}>
				<view slot="hover-card-content" data-state="open" onPointerEnter={_ -> over++} onPointerLeave={_ -> after(0.3, false)}>{props.content}</view>
			</Popover>
		</view>;
	}

	// an avatar (shadcn's): an image, else its fallback (initials) while
	// there is none. Slots "avatar", "avatar-image" and "avatar-fallback"
	@:widget({
		props: {
			src: "its image (an Image or an Svg), a signal or a function of one; null: the fallback",
			fallback: "the text shown while there is no image: initials",
			label: "its name for assistive technology (the fallback)"
		}
	})
	public static function Avatar(props:{?src:Dynamic, fallback:String, ?label:String, ?tag:String}):View {
		return <view tag={props.tag ?? "avatar"} slot="avatar" role="img" label={props.label ?? props.fallback} overflow="hidden">
			{() -> read(props.src) == null ? <view slot="avatar-fallback" hidden><text>{props.fallback}</text></view> : <image slot="avatar-image"
				src={props.src} fit="cover" width="100%" height="100%" hidden/>}
		</view>;
	}

	// a key or keys as typed (shadcn's Kbd: slot "kbd"), e.g. "⌘K" or a Shortcut's label
	@:widget({
		props: {
			text: "the key or keys as typed, e.g. ⌘K",
			children: "its content, instead of text"
		}
	})
	@:neutral public static function Kbd(props:{?text:String, ?children:Any, ?tag:String}):View {
		return <text:kbd tag={props.tag ?? "kbd"} id={props.tag} slot="kbd">{props.children ?? props.text}</text:kbd>;
	}

	// a spinner (shadcn's): a loading circle turning once a second while
	// shown, on the Clock (slot "spinner"; an indeterminate progress bar for
	// assistive technology, label "Loading")
	@:widget({
		props: {
			label: "its name for assistive technology (Loading)"
		}
	})
	public static function Spinner(props:{?label:String, ?tag:String}):View {
		var turn = signal(0.0), stopped = false;
		Clock.add(now -> {
			if (stopped) return false;
			turn.value = (now % 1) * 360;
			return true;
		});
		onCleanup(() -> stopped = true);
		return <view tag={props.tag ?? "spinner"} slot="spinner" role="progressbar" label={props.label ?? "Loading"}>
			<image src={LOADER} width="100%" height="100%" transform={() -> "rotate(" + turn.value + "deg)"}/>
		</view>;
	}

	// a combobox: a text field bound to value (two ways) whose typing
	// filters options (those containing the text, in either case; options
	// may be a signal) in a list under it. The focus stays in the field:
	// Down opens the list and highlights the next option, Up the previous;
	// Enter or a click chooses the highlighted one (the field takes its
	// text; onChoose gets it), Enter with none highlighted submits the text
	// as it is (onChoose), Escape or a click outside closes the list.
	// Slots (shadcn's: a Popover holding a Command) "popover-content"
	// (data-side), "command", "command-list", "command-group" and
	// "command-item" (data-selected "true"), the field Input's
	@:widget({
		props: {
			value: "a signal of the field's text, set as it is typed or an option is chosen",
			options: "the options' texts, or a signal of them: those holding the text, in any case, listed",
			placeholder: "the text shown while the field is empty",
			width: "its width in pixels, the list's too (200)",
			label: "its name for assistive technology (the placeholder)",
			onChoose: "called with an option's text when it is chosen, or the text as it is when Enter submits it"
		},
		keys: {
			"Down": "opens the list, else highlights the next option, wrapping",
			"Up": "while the list is open: highlights the previous option, wrapping",
			"Enter": "chooses the highlighted option, else submits the text as it is",
			"Escape": "closes the list",
			"Left, Right, Home, End, Backspace, Mod+A, Mod+C, Mod+X, Mod+V, Mod+Z": "edit the text, as an input's"
		}
	})
	public static function Combobox(props:{value:Signal<String>, options:Dynamic, ?placeholder:String, ?width:Float, ?label:String,
			?onChoose:String->Void, ?tag:String}):View {
		var tag = props.tag ?? "combobox", w = props.width ?? 200.0;
		var open = signal(false), active = signal(-1);
		var options:Array<Node> = [];
		var matches = memo(() -> {
			var q = props.value.value.toLowerCase(), all:Array<String> = Render.read(props.options);
			[for (o in all) if (o.toLowerCase().indexOf(q) >= 0) o];
		});
		var f = new TextField(props.value.peek());
		f.tag = tag;
		f.placeholder = props.placeholder ?? "";
		f.slot = "input";
		f.semantics.role = hxmc.ui.access.Role.ComboBox;
		f.semantics.label = props.label ?? props.placeholder;
		f.style.width = w;
		effect(() -> f.setText(props.value.value));
		effect(() -> f.semantics.expanded = open.value && matches.value.length > 0);
		function choose(o:String) {
			batch(() -> {
				props.value.value = o;
				open.value = false;
				active.value = -1;
			});
			// (the caret after the chosen text)
			f.select(o.length, o.length);
			if (f.ui != null) f.ui.setFocus(f);
			if (props.onChoose != null) props.onChoose(o);
		}
		function highlight(i:Int) {
			active.value = i;
			if (i >= 0 && i < options.length && options[i] != null && options[i].ui != null) options[i].ui.scrollIntoView(options[i]);
		}
		f.onChange = s -> batch(() -> {
			props.value.value = s;
			open.value = true;
			active.value = -1;
		});
		f.onSubmit = s -> {
			var m = matches.peek(), i = active.peek();
			if (open.peek() && i >= 0 && i < m.length) choose(m[i]) else {
				open.value = false;
				if (props.onChoose != null) props.onChoose(s);
			}
		};
		return <view tag={tag + "-box"} width={w} onKeyDown={e -> switch e.key {
				case Key.DOWN:
					e.stop();
					var n = matches.peek().length;
					if (!open.peek()) {
						open.value = true;
						highlight(n > 0 ? 0 : -1);
					} else if (n > 0) highlight((active.peek() + 1) % n);
				case Key.UP if (open.peek()):
					e.stop();
					var n = matches.peek().length;
					if (n > 0) highlight(active.peek() <= 0 ? n - 1 : active.peek() - 1);
				case Key.ESCAPE if (open.peek()):
					// (only the list closes: not a dialog it is in)
					e.preventDefault();
					open.value = false;
				case _:
			}}>
			{f}
			<Popover open={() -> open.value && matches.value.length > 0} placement="below" onDismiss={() -> open.value = false}>
				<view tag={tag + "-content"} slot="popover-content" data-state="open" data-side="bottom" width={w} padding={0}
					ref={n -> Rules.keep(n, ["padding"])}><view slot="command">
					<scroll tag={tag + "-list"} slot="command-list" role="listbox" label={props.label}><view slot="command-group">
						<Index each={matches} render={(o:Signal<String>, i:Int) -> <view tag={tag + "-option"} slot="command-item" role="option"
							selected={() -> active.value == i} data-selected={() -> active.value == i ? "true" : null} ref={n -> options[i] = n}
							onPointerEnter={_ -> active.value = i} onClick={_ -> choose(o.peek())}>{() -> o.value}</view>}/>
					</view></scroll>
				</view></view>
			</Popover>
		</view>;
	}

	// a command menu (shadcn's, cmdk's): a search field over groups of items,
	// each a label, what choosing it does and a shortcut (shown); only the
	// items whose label holds the query (in any case) shown, a group with
	// none hidden, separators only while the query is empty, empty's text
	// (default "No results found.") when nothing matches. One item is
	// selected: the first that can be chosen as the query changes, the one
	// under the pointer; Up and Down move it (stopping at the ends; Home and
	// End stay the field's); Enter or a click chooses it. Slots
	// "command", "command-input-wrapper", "command-input-icon",
	// "command-input", "command-list", "command-empty", "command-group",
	// "command-group-heading", "command-item" (data-selected and
	// data-disabled "true"), "command-shortcut", "command-separator"
	@:widget({
		props: {
			groups: "its groups, each a heading and items (a menu's: a label, onSelect, a shortcut shown, disabled, a separator)",
			placeholder: "the search field's text while it is empty",
			empty: "the text shown when no item matches (No results found.)",
			query: "a signal of the search field's text (its own when not given)",
			label: "its name for assistive technology (the placeholder)"
		},
		keys: {
			"Down": "selects the next item that can be chosen, stopping at the last",
			"Up": "selects the previous item that can be chosen, stopping at the first",
			"Enter": "chooses the selected item",
			"Left, Right, Home, End, Backspace, Mod+A, Mod+C, Mod+X, Mod+V, Mod+Z": "edit the query, as an input's"
		}
	})
	public static function Command(props:{groups:Array<{?heading:String, items:Array<MenuItem>}>, ?placeholder:String, ?empty:String,
			?query:Signal<String>, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "command", query = props.query ?? signal("");
		// (every item, group by group, by its place in all of them)
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
		var selected = signal(-1), rows:Array<Node> = [];
		effect(() -> {
			var c = choosable.value;
			selected.value = c.length > 0 ? c[0] : -1;
		});
		function select(k:Int) {
			selected.value = k;
			if (k >= 0 && rows[k] != null && rows[k].ui != null) rows[k].ui.scrollIntoView(rows[k]);
		}
		function choose(k:Int) {
			if (k < 0 || all[k].disabled == true) return;
			if (all[k].onSelect != null) all[k].onSelect();
		}
		var f = new TextField(query.peek());
		f.tag = tag + "-input";
		f.slot = "command-input";
		f.placeholder = props.placeholder ?? "";
		f.semantics.role = hxmc.ui.access.Role.ComboBox;
		f.semantics.label = props.label ?? props.placeholder;
		f.semantics.expanded = true;
		effect(() -> f.setText(query.value));
		f.onChange = s -> query.value = s;
		f.onSubmit = _ -> choose(selected.peek());
		var anyShown = () -> {
			var s = shown.value;
			for (k in 0...all.length)
				if (s[k] && all[k].separator != true) return true;
			return false;
		};
		return <view tag={tag} slot="command" onKeyDown={e -> {
			var c = choosable.peek(), at = c.indexOf(selected.peek());
			switch e.key {
				case Key.DOWN if (c.length > 0):
					e.stop();
					select(c[at < 0 ? 0 : Std.int(Math.min(at + 1, c.length - 1))]);
				case Key.UP if (c.length > 0):
					e.stop();
					select(c[at <= 0 ? 0 : at - 1]);
				case _:
			}
		}}>
			<view tag={tag + "-input-wrapper"} slot="command-input-wrapper" direction="row" align-items="center">
				<image slot="command-input-icon" src={SEARCH} hidden/>
				{f}
			</view>
			<scroll tag={tag + "-list"} slot="command-list" role="listbox" label={props.label}>
				<Show when={() -> !anyShown()}><view tag={tag + "-empty"} slot="command-empty">{props.empty ?? "No results found."}</view></Show>
				{[
					for (g => group in props.groups) {
						var mine = [for (k in 0...all.length) if (groupOf[k] == g) k];
						var visible = () -> Lambda.exists(mine, k -> shown.value[k] && all[k].separator != true);
						[
							g == 0 ? null : <Show when={() -> query.value == "" && visible()}><view slot="command-separator" hidden/></Show>,
							<Show when={visible}>
								<view tag={tag + "-group-" + g} slot="command-group" role="group" label={group.heading}>
									{group.heading == null ? null : <text slot="command-group-heading" hidden>{group.heading}</text>}
									{[
										for (k in mine) {
											var it = all[k];
											it.separator == true ? <Show when={() -> shown.value[k]}><view slot="command-separator" hidden/></Show> : <Show when={() -> shown.value[k]}>
												<view tag={tag + "-item-" + k} slot="command-item" role="option" direction="row" align-items="center"
													selected={() -> selected.value == k} data-selected={() -> selected.value == k ? "true" : null}
													data-disabled={it.disabled == true ? "true" : null} disabled={it.disabled == true} ref={n -> rows[k] = n}
													onPointerEnter={_ -> if (it.disabled != true) selected.value = k} onClick={_ -> choose(k)}>
													<text grow={1}>{it.label}</text>
													{it.shortcut == null ? null : <text slot="command-shortcut">{Shortcut.parse(it.shortcut).label()}</text>}
												</view>
											</Show>;
										}
									]}
								</view>
							</Show>
						];
					}
				]}
			</scroll>
		</view>;
	}

	// a one-time code field (shadcn's InputOTP, input-otp's): length
	// slots of one character each (digits only unless digits is false),
	// in groups (sizes; a separator between), over which a text field is laid,
	// transparent: typing fills the next slot, Backspace empties the last, a
	// paste fills the next ones; what does not fit or is not allowed is
	// dropped. The caret stays at the end (as input-otp's): the arrows,
	// Home and End do nothing, a click puts it back there. onComplete gets the code once every slot is filled. Slots
	// "input-otp" (data-disabled), "input-otp-group", "input-otp-slot"
	// (data-active "true" on the slot typing goes to while focused),
	// "input-otp-caret" (in the active slot while it is empty),
	// "input-otp-separator"
	@:widget({
		props: {
			value: "a signal of the code typed, what is not allowed or does not fit dropped",
			length: "the number of slots, a character each",
			groups: "the groups' sizes, a separator between (one group of all)",
			digits: "false: any character allowed, not only digits",
			onComplete: "called with the code once every slot is filled",
			label: "its name for assistive technology (One-time code)",
			disabled: "a Bool, a signal or a function of one: not focusable or typed in"
		},
		keys: {
			"0 to 9": "fill the next slot (any character when digits is false)",
			"Backspace": "empties the last filled slot",
			"Mod+V": "pastes into the next slots, what does not fit dropped",
			"Left, Right, Home, End": "nothing: the caret stays at the end"
		}
	})
	public static function InputOTP(props:{value:Signal<String>, length:Int, ?groups:Array<Int>, ?digits:Bool, ?onComplete:String->Void, ?label:String,
			?disabled:Dynamic, ?tag:String}):View {
		var tag = props.tag ?? "otp", n = props.length, digits = props.digits != false;
		var groups = props.groups ?? [n];
		function allowed(s:String):String
			return Behaviour.code(s, n, digits);
		var f = new TextField(allowed(props.value.peek()));
		f.tag = tag + "-input";
		f.semantics.label = props.label ?? "One-time code";
		// (drawn, never the platform's editor: the slots show its text)
		f.host = Drawn;
		// (drawing nothing: its text in the slots, its focus the active slot's; to assistive technology the field)
		f.style.width = "100%";
		f.style.height = "100%";
		f.style.color = Color.TRANSPARENT;
		f.style.outlineStyle = None;
		f.caretColor = Color.TRANSPARENT;
		f.selectionColor = Color.TRANSPARENT;
		var focused = States.of(f).focused;
		effect(() -> {
			var v = allowed(props.value.value);
			untrack(() -> {
				f.setText(v);
				f.select(v.length, v.length);
			});
		});
		f.onChange = s -> {
			var v = allowed(s), was = props.value.peek();
			props.value.value = v;
			// (what was dropped: gone from the field too, the caret at the end)
			f.setText(v);
			f.select(v.length, v.length);
			if (v.length == n && was.length < n && props.onComplete != null) props.onComplete(v);
		};
		// (the caret kept at the end: the keys that would move it taken, a click undone)
		var keys = f.onKeyDown;
		f.onKeyDown = e -> switch e.key {
			case Key.LEFT | Key.RIGHT | Key.UP | Key.DOWN | Key.HOME | Key.END:
				e.preventDefault();
			case _:
				keys(e);
		};
		var down = f.onPointerDown;
		f.onPointerDown = e -> {
			down(e);
			f.select(f.text.length, f.text.length);
		};
		invalidAndDisabled(f, null, props.disabled);
		var chars = () -> [for (c in new haxe.iterators.StringIteratorUnicode(props.value.value)) String.fromCharCode(c)];
		var active = () -> focused.value ? Std.int(Math.min(chars().length, n - 1)) : -1;
		var slots = [], k = 0;
		for (g => size in groups) {
			if (g > 0) slots.push(<view slot="input-otp-separator" role="separator"><image slot="input-otp-separator-icon" src={MINUS} hidden/></view>);
			var cells = [];
			for (_ in 0...size) {
				var i = k++;
				cells.push(<view tag={tag + "-slot-" + i} slot="input-otp-slot" data-active={() -> active() == i ? "true" : null} hidden>
					<text>{() -> i < chars().length ? chars()[i] : ""}</text>
					<Show when={() -> active() == i && i >= chars().length}><view slot="input-otp-caret"/></Show>
				</view>);
			}
			slots.push(<view slot="input-otp-group" direction="row" align-items="center">{cells}</view>);
		}
		return <view tag={tag} slot="input-otp" direction="row" align-items="center" data-disabled={() -> read(props.disabled) == true}>
			{slots}
			<view position="absolute" left={0} top={0} right={0} bottom={0}>{f}</view>
		</view>;
	}

	// a collapsible (shadcn's): its label on a button (an arrow turning
	// with it) that shows or hides the children under it, by a click, Enter
	// or Space; open (a signal; closed at first) says which. Slots
	// "collapsible", "collapsible-trigger" and "collapsible-content", each
	// with data-state "open" or "closed"
	@:widget({
		props: {
			label: "the trigger's text",
			open: "a signal of whether the children are shown (its own, closed at first, when not given)",
			children: "what it shows or hides, under the trigger"
		},
		keys: {"Enter, Space": "opens or closes it"}
	})
	public static function Collapsible(props:{label:String, ?open:Signal<Bool>, ?tag:String, ?children:Any}):View {
		var open = props.open ?? signal(false), tag = props.tag ?? "disclosure";
		var state = () -> open.value ? "open" : "closed";
		return <view tag={tag} slot="collapsible" data-state={state}>
			{trigger(tag + "-summary", "collapsible-trigger", state, () -> open.value = !open.peek(),
				[icon(CHEVRON_RIGHT, "collapsible-icon", () -> open.value ? "rotate(90deg)" : "none", true), props.label])}
			<Show when={open}><view tag={tag + "-content"} slot="collapsible-content" data-state="open">{props.children}</view></Show>
		</view>;
	}

	// an accordion (shadcn's): sections, at most one open: open is its index
	// (-1: none; a signal); a section's trigger, its label and a chevron
	// (turned when open), opens it and closes the other; Up and Down move
	// between the triggers (wrapping), Home and End to the first and last,
	// as Radix's. Slots "accordion",
	// "accordion-item", "accordion-trigger" and "accordion-content", each
	// item's with data-state "open" or "closed"
	@:widget({
		props: {
			sections: "its sections, each a label and render (a function giving its content)",
			open: "a signal of the open section's index, -1 for none (its own when not given)"
		},
		keys: {
			"Enter, Space": "on a section's trigger: opens it and closes the other, or closes it when open",
			"Up, Down": "to the trigger before or after, wrapping",
			"Home, End": "to the first or last trigger"
		}
	})
	public static function Accordion(props:{sections:Array<{label:String, render:Void->Any}>, ?open:Signal<Int>, ?tag:String}):View {
		var open = props.open ?? signal(-1), tag = props.tag ?? "accordion", count = props.sections.length;
		// (Up and Down between the triggers, wrapping; Home and End to the first and last)
		function key(e:Event) {
			var ts = [for (i in 0...count) e.current.find(tag + "-" + i + "-summary")], i = ts.indexOf(e.target);
			var j = i < 0 ? -1 : switch e.key {
				case Key.DOWN: (i + 1) % count;
				case Key.UP: (i + count - 1) % count;
				case Key.HOME: 0;
				case Key.END: count - 1;
				case _: -1;
			}
			if (j < 0) return;
			e.preventDefault();
			focusIn(ts, j);
		}
		return <view tag={tag} slot="accordion" onKeyDown={key}>{[
			for (i in 0...props.sections.length) {
				var s = props.sections[i], state = () -> open.value == i ? "open" : "closed";
				<view tag={tag + "-" + i} slot="accordion-item" data-state={state}>
					{trigger(tag + "-" + i + "-summary", "accordion-trigger", state, () -> open.value = open.peek() == i ? -1 : i, [
						<text grow={1}>{s.label}</text>,
						<image slot="accordion-trigger-icon" src={CHEVRON} hidden transform={() -> open.value == i ? "rotate(180deg)" : "none"}/>
					])}
					<Show when={() -> open.value == i}><view tag={tag + "-" + i + "-content"} slot="accordion-content" data-state="open">{s.render()}</view></Show>
				</view>;
			}
		]}</view>;
	}

	// (a collapsible's or an accordion's button: expanded, data-state)
	static function trigger(tag:String, slot:String, state:Void->String, flip:Void->Void, children:Array<Any>):View
		return <view tag={tag} slot={slot} role="button" expanded={() -> state() == "open"} data-state={state} focusable onClick={_ -> flip()}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
				e.preventDefault();
				flip();
			}}>{children}</view>;

	// where Toasts.show's toasts are shown: in a corner of the window
	// (placement: "bottom-right", "bottom-left", "top-right", "top-left"),
	// over everything, width wide (320); each with its mark, text, action
	// and a close button (Enter and Space press them; Escape closes the toast
	// the focus is in). They do not take the focus; the pointer over them
	// holds their time.
	@:widget({
		props: {
			placement: "the window's corner they are in: bottom-right (the default), bottom-left, top-right or top-left",
			width: "the toasts' width in pixels (320)"
		},
		keys: {"Enter, Space": "on a toast's action or close button: presses it", "Escape": "closes the toast the focus is in"}
	})
	public static function Toaster(props:{?placement:String, ?width:Float, ?tag:String}):View {
		var tag = props.tag ?? "toaster";
		// (a live region, always there and of no size, saying the newest toast: assistive technology announces it)
		return <view tag={tag + "-live"} position="absolute" width={0} height={0} overflow="hidden" live="polite">
			<text>{() -> {
				var shown = Toasts.shown.value;
				shown.length == 0 ? "" : shown[shown.length - 1].text;
			}}</text>
			<Popover open={() -> Toasts.shown.value.length > 0} placement={props.placement ?? "bottom-right"} gap={16} tag={tag}>
			<view tag={tag + "-list"} slot="toaster" width={props.width ?? 320.0} onPointerEnter={_ -> Toasts.paused = true}
				onPointerLeave={_ -> Toasts.paused = false}>
				<For each={Toasts.shown} render={(toast:Toast) -> <view tag="toast" slot="toast" data-type={toast.kind} role="group" label={toast.text}
					onKeyDown={e -> if (e.key == Key.ESCAPE) {
						e.preventDefault();
						Toasts.close(toast);
					}}>
					{toast.kind == "success" || toast.kind == "error" ? <text slot="toast-icon" hidden>{toast.kind == "success" ? "✓" : "!"}</text> : null}
					<text slot="toast-title" grow={1}>{toast.text}</text>
					{toast.action == null ? null : {
						var act = () -> {
							Toasts.close(toast);
							if (toast.onAction != null) toast.onAction();
						};
						<view tag="toast-action" slot="toast-action" role="button" focusable onClick={_ -> act()} onKeyDown={e -> pressKeys(e, act)}>{toast.action}</view>;
					}}
					<view tag="toast-close" slot="toast-close" role="button" label="Close" focusable onClick={_ -> Toasts.close(toast)}
						onKeyDown={e -> pressKeys(e, () -> Toasts.close(toast))}>×</view>
				</view>}/>
			</view>
		</Popover>
		</view>;
	}

	// a number field bound to a signal: its value as text (format; else as
	// it is, steps' rounding errors left out). Typed in, the value follows what
	// parses; Enter or the focus leaving puts it within min and max and
	// shows it formatted. Up and Down, or the buttons beside it, step it
	// (Page Up and Page Down: ten steps). A spin button to assistive
	// technology.
	@:widget({
		props: {
			value: "a signal of its number, following what is typed while it parses",
			min: "the least it can be, once committed (no limit)",
			max: "the most it can be, once committed (no limit)",
			step: "what Up, Down and the buttons add or take off (1)",
			width: "its width in pixels, the buttons' too (120)",
			format: "its number as text (as it is, rounded to ten decimals)",
			label: "its name for assistive technology"
		},
		keys: {
			"Up, Down": "steps it up or down",
			"Page Up, Page Down": "steps it up or down by ten steps",
			"Enter": "puts it within min and max, shown formatted (as the focus leaving does)",
			"Left, Right, Home, End, Backspace, Mod+A, Mod+C, Mod+X, Mod+V, Mod+Z": "edit the text, as an input's"
		}
	})
	public static function NumberField(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?format:Float->String,
			?label:String, ?tag:String}):View {
		var tag = props.tag ?? "number", step = props.step ?? 1.0, w = props.width ?? 120.0;
		var min = props.min ?? Math.NEGATIVE_INFINITY, max = props.max ?? Math.POSITIVE_INFINITY;
		var format = props.format ?? Behaviour.plain;
		var editing = false;
		var f = new TextField(format(props.value.peek()));
		f.tag = tag;
		f.semantics.role = hxmc.ui.access.Role.SpinButton;
		f.semantics.label = props.label;
		if (Math.isFinite(min)) f.semantics.valueMin = min;
		if (Math.isFinite(max)) f.semantics.valueMax = max;
		f.slot = "input";
		f.style.set({grow: 1, minWidth: 0});
		inline function clamp(v:Float):Float
			return v < min ? min : v > max ? max : v;
		effect(() -> {
			var v = props.value.value;
			f.semantics.valueNow = v;
			f.semantics.valueText = format(v);
			if (!editing) f.setText(format(v));
		});
		function commit() {
			editing = false;
			var v = clamp(props.value.peek());
			if (v != props.value.peek()) props.value.value = v;
			f.setText(format(v));
		}
		function stepBy(n:Float) {
			editing = false;
			var v = clamp(props.value.peek() + n * step);
			if (v != props.value.peek()) props.value.value = v else f.setText(format(v));
		}
		f.onChange = s -> {
			var v = Std.parseFloat(StringTools.trim(s));
			editing = true;
			if (!Math.isNaN(v)) props.value.value = v;
		};
		f.onSubmit = _ -> commit();
		// (after the field's own: its caret and composition)
		var blur = f.onBlur;
		f.onBlur = e -> {
			if (blur != null) blur(e);
			commit();
		};
		function arrow(label:String, glyph:String, n:Float):View
			return <view tag={tag + (n > 0 ? "-up" : "-down")} slot={n > 0 ? "number-field-increment" : "number-field-decrement"} role="button" label={label}
				grow={1} onClick={_ -> stepBy(n)}>{glyph}</view>;
		return <view tag={tag + "-box"} slot="number-field" direction="row" align-items="stretch" width={w} onKeyDown={e -> switch e.key {
				case Key.UP:
					e.stop();
					stepBy(1);
				case Key.DOWN:
					e.stop();
					stepBy(-1);
				case Key.PAGE_UP:
					e.stop();
					stepBy(10);
				case Key.PAGE_DOWN:
					e.stop();
					stepBy(-10);
				case _:
			}}>
			{f}
			<view slot="number-field-steppers">
				{arrow("Increase", "▲", 1)}
				{arrow("Decrease", "▼", -1)}
			</view>
		</view>;
	}


	// a textarea (shadcn's): a text area bound to a signal (two ways), rows
	// lines high (3); a right click (or the menu key) opens its edit menu;
	// invalid and disabled as an input's (slot "textarea")
	@:widget({
		props: {
			value: "a signal of its text, set as it is typed (and shown when set)",
			rows: "its height in lines (3)",
			placeholder: "the text shown while it is empty",
			label: "its name for assistive technology (the placeholder)",
			invalid: "a Bool, a signal or a function of one: aria-invalid, for the theme",
			disabled: "a Bool, a signal or a function of one: not focusable or edited"
		},
		keys: {
			"Enter": "types a new line",
			"Left, Right": "move the caret (Shift: extending the selection; Control or Alt: by words)",
			"Up, Down": "move the caret a line, keeping its column",
			"Home, End": "go to the line's start or end (Mod: the text's)",
			"Backspace, Delete": "delete before or after the caret (Control or Alt: a word)",
			"Mod+A": "selects all",
			"Mod+C, Mod+X, Mod+V": "copy, cut and paste",
			"Mod+Z": "undoes",
			"Mod+Shift+Z, Mod+Y": "redo",
			"Menu, Shift+F10": "opens its edit menu"
		}
	})
	public static function Textarea(props:{value:Signal<String>, ?rows:Int, ?placeholder:String, ?label:String, ?invalid:Dynamic, ?disabled:Dynamic,
			?style:States->StyleProps, ?tag:String}):View {
		var f = new TextArea(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.slot = "textarea";
		States.apply(f, props.style);
		f.rows = props.rows ?? 3;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.onChange = s -> props.value.value = s;
		effect(() -> f.setText(props.value.value));
		invalidAndDisabled(f, props.invalid, props.disabled);
		return editMenu(f, props.tag ?? "textarea");
	}

	// (an input's or a textarea's aria-invalid and disabled, following their props)
	static function invalidAndDisabled(f:EditableText, invalid:Dynamic, disabled:Dynamic) {
		effect(() -> f.setAttr("aria-invalid", read(invalid) == true ? "true" : null));
		effect(() -> {
			var off = read(disabled) == true;
			f.setAttr("disabled", off ? "" : null);
			f.focusable = !off;
			f.semantics.disabled = off;
		});
	}

	// (a text field in a context menu of its edits: cut, copy, paste, select all)
	static function editMenu(f:EditableText, tag:String):View
		return <ContextMenu tag={tag + "-menu"} label="Edit" items={[
			{label: "Cut", onSelect: () -> f.cut(), shortcut: "Mod+X"},
			{label: "Copy", onSelect: () -> f.copy(), shortcut: "Mod+C"},
			{label: "Paste", onSelect: () -> f.paste(), shortcut: "Mod+V"},
			{label: "Select All", onSelect: () -> f.selectAll(), shortcut: "Mod+A"}
		]}>{f}</ContextMenu>;

	// (an icon, lucide's, in a slot of its own (a theme's to size and colour;
	// unstyled, 16 pixels), hidden from assistive technology; turned by
	// transform; mirrored: right to left the other way, as a disclosure's arrow)
	static function icon(svg:Svg, slot:String, ?transform:Void->String, mirrored = false):Node {
		Rules.addBase("icons", [
			for (s in ["calendar-button-icon", "tree-toggle-icon", "breadcrumb-separator-icon", "collapsible-icon", "sidebar-trigger-icon",
				"navigation-menu-trigger-icon", "carousel-icon", "pagination-icon", "pagination-ellipsis-icon"])
				{slot: s, style: s == "breadcrumb-separator-icon" || s == "navigation-menu-trigger-icon" ? {width: 12, height: 12} : {width: 16, height: 16}}
		]);
		var n = mirrored ? new Mirrored() : new ImageNode();
		n.svg = svg;
		n.slot = slot;
		n.semantics = {hidden: true};
		n.style.shrink = 0;
		if (transform != null) effect(() -> n.style.transform = Transform.parse(transform()));
		return n;
	}

	// an input (shadcn's): a text field bound to a signal (two ways); a
	// right click (or the menu key) opens its edit menu; password: its text
	// shown as dots, not copied or cut, a password field for assistive
	// technology; invalid: aria-invalid; disabled: not focusable or edited
	// (slot "input"; its placeholder's colour a "placeholder" rule's)
	@:widget({
		props: {
			value: "a signal of its text, set as it is typed (and shown when set)",
			placeholder: "the text shown while it is empty",
			label: "its name for assistive technology (the placeholder)",
			onSubmit: "called with its text on Enter",
			password: "true: its text shown as dots, not copied or cut",
			invalid: "a Bool, a signal or a function of one: aria-invalid, for the theme",
			disabled: "a Bool, a signal or a function of one: not focusable or edited"
		},
		keys: {
			"Enter": "submits it (onSubmit)",
			"Left, Right": "move the caret (Shift: extending the selection; Control or Alt: by words)",
			"Home, End": "go to the start or end",
			"Backspace, Delete": "delete before or after the caret (Control or Alt: a word)",
			"Mod+A": "selects all",
			"Mod+C, Mod+X, Mod+V": "copy, cut and paste (a password: paste only)",
			"Mod+Z": "undoes",
			"Mod+Shift+Z, Mod+Y": "redo",
			"Menu, Shift+F10": "opens its edit menu"
		}
	})
	public static function Input(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?password:Bool,
			?invalid:Dynamic, ?disabled:Dynamic, ?style:States->StyleProps, ?tag:String}):View
		return textInput(props, "input");

	// (an Input's field, its slot "input", or "input-group-control" in an InputGroup)
	static function textInput(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?password:Bool,
			?invalid:Dynamic, ?disabled:Dynamic, ?style:States->StyleProps, ?tag:String}, slot:String):View {
		var f = new TextField(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.slot = slot;
		States.apply(f, props.style);
		if (props.password == true) f.secret = true;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.onChange = s -> props.value.value = s;
		f.onSubmit = props.onSubmit;
		effect(() -> f.setText(props.value.value));
		invalidAndDisabled(f, props.invalid, props.disabled);
		return editMenu(f, props.tag ?? "input");
	}

	// a tag input: tags as chips before a text field in one box; Enter or a
	// comma adds what is typed (trimmed, once), Backspace in an empty field
	// takes the last one off, a chip's × takes it off; a click in the box
	// focuses the field. The chips a list, each × a button named for its tag
	@:widget({
		props: {
			tags: "a signal of its tags, in order",
			placeholder: "the field's text while it is empty",
			label: "its field's and its list's name for assistive technology (the field's: the placeholder)"
		},
		keys: {
			"Enter, Comma": "adds what is typed as a tag, trimmed, unless it is empty or there already",
			"Backspace": "in an empty field: takes the last tag off",
			"Left, Right, Home, End, Mod+A, Mod+C, Mod+X, Mod+V, Mod+Z": "edit the text, as an input's",
			"Menu, Shift+F10": "opens its edit menu"
		}
	})
	public static function TagInput(props:{tags:Signal<Array<String>>, ?placeholder:String, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "tags";
		var f = new TextField("");
		f.tag = tag + "-field";
		f.slot = "tag-input-field";
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		function add(text:String) {
			var v = StringTools.trim(text);
			f.setText("");
			if (v == "" || props.tags.peek().indexOf(v) >= 0) return;
			props.tags.value = props.tags.peek().concat([v]);
		}
		function remove(v:String)
			props.tags.value = props.tags.peek().filter(x -> x != v);
		f.onSubmit = add;
		f.onChange = text -> if (StringTools.endsWith(text, ",")) add(text.substr(0, text.length - 1));
		// (Backspace in an empty field: the last tag, before the field's own keys)
		var keys = f.onKeyDown;
		f.onKeyDown = (e:Event) -> {
			var list = props.tags.peek();
			if (e.key == Key.BACKSPACE && f.text == "" && list.length > 0) {
				remove(list[list.length - 1]);
				e.stop();
			} else if (keys != null) keys(e);
		};
		return <view tag={tag} slot="tag-input" direction="row" wrap align-items="center" onPointerDown={(e:Event) -> if (e.target != f && f.ui != null) {
				f.ui.setFocus(f);
				e.preventDefault();
			}}>
			<view slot="tag-input-list" role="list" label={props.label} direction="row" wrap>
				<For each={props.tags} render={(v:String) -> <view tag={tag + "-" + v} slot="badge" variant="secondary" role="listitem" label={v}>
					{v}
					<view tag={tag + "-" + v + "-remove"} slot="tag-input-remove" role="button" label={"Remove " + v} onClick={_ -> remove(v)}>×</view>
				</view>}/>
			</view>
			<view slot="tag-input-entry" grow={1}>{editMenu(f, tag)}</view>
		</view>;
	}

	// --- forms and layouts: shadcn's Field, ButtonGroup, InputGroup, Empty and Item ---

	// a field (shadcn's): a label, a control and its description or error
	// together, a group to assistive technology; orientation "vertical" (the
	// default: the label above), "horizontal" (beside) or "responsive";
	// invalid (a Bool, a signal or a function of one) sets data-invalid for
	// the theme. Slot "field" (data-orientation, data-invalid). Its parts:
	// FieldLabel, FieldContent, FieldDescription, FieldError; around fields,
	// FieldSet (with a FieldLegend), FieldGroup and FieldSeparator
	@:widget({
		props: {
			orientation: "where its label goes: vertical (above), horizontal (beside) or responsive",
			invalid: "a Bool, a signal or a function of one: data-invalid for the theme (an error shown)",
			label: "its name for assistive technology",
			children: "its FieldLabel, control, FieldContent, FieldDescription or FieldError"
		},
		variants: ["vertical", "horizontal", "responsive"]
	})
	@:neutral public static function Field(props:{?orientation:String, ?invalid:Dynamic, ?label:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "field"} id={props.tag} slot="field" role="group" label={props.label} data-orientation={props.orientation ?? "vertical"}
			variant={props.orientation ?? "vertical"} data-invalid={() -> read(props.invalid) == true ? "true" : null}>{props.children}</view>;

	@:widget({
		props: {
			text: "its text, when it has no children",
			children: "its content, in place of text: a control and its text, for a checkbox's or a switch's label",
			htmlFor: "the id of the control it names, in a page (a <label>'s for)"
		},
		part: "Field"
	})
	@:neutral public static function FieldLabel(props:{?text:String, ?children:Any, ?htmlFor:String, ?tag:String}):View
		return <view:label tag={props.tag ?? "field-label"} id={props.tag} slot="field-label" html-for={props.htmlFor}>{props.children ?? props.text}</view:label>;

	@:widget({
		props: {
			children: "its FieldLabel and FieldDescription, beside a control in a horizontal field"
		},
		part: "Field"
	})
	@:neutral public static function FieldContent(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "field-content"} id={props.tag} slot="field-content">{props.children}</view>;

	@:widget({
		props: {
			text: "its text, when it has no children",
			children: "its content, in place of text"
		},
		part: "Field"
	})
	@:neutral public static function FieldDescription(props:{?text:String, ?children:Any, ?tag:String}):View
		return <text:p tag={props.tag ?? "field-description"} id={props.tag} slot="field-description">{props.children ?? props.text}</text:p>;

	@:widget({
		props: {
			text: "the error, shown while it is not null nor empty (a signal or a function of one); announced at once to assistive technology (live assertive)",
			tag: "its node's tag (Node.find, tests)"
		},
		part: "Field"
	})
	@:neutral public static function FieldError(props:{text:Dynamic, ?tag:String}):View
		return <Show when={() -> {
			var t:Null<String> = read(props.text);
			t != null && t != "";
		}}><text:div tag={props.tag ?? "field-error"} id={props.tag} slot="field-error" live="assertive">{() -> (read(props.text) : String)}</text:div></Show>;

	@:widget({
		props: {
			label: "its name for assistive technology (its legend's text)",
			children: "its FieldLegend, FieldDescription and fields"
		},
		part: "Field"
	})
	@:neutral public static function FieldSet(props:{?label:String, ?children:Any, ?tag:String}):View
		return <view:fieldset tag={props.tag ?? "field-set"} id={props.tag} slot="field-set" role="group" label={props.label}>{props.children}</view:fieldset>;

	@:widget({
		props: {
			text: "its text",
			variant: "legend (the default, a set's heading) or label (as a field's label)"
		},
		variants: ["legend", "label"],
		part: "Field"
	})
	@:neutral public static function FieldLegend(props:{text:String, ?variant:String, ?tag:String}):View
		return <text:legend tag={props.tag ?? "field-legend"} id={props.tag} slot="field-legend" role="heading" variant={props.variant ?? "legend"}>{props.text}</text:legend>;

	@:widget({
		props: {
			children: "its fields and sets, one under another"
		},
		part: "Field"
	})
	@:neutral public static function FieldGroup(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "field-group"} id={props.tag} slot="field-group" group="field-group">{props.children}</view>;

	@:widget({
		props: {
			text: "a word in the line (\"or\"), none when not given"
		},
		part: "Field"
	})
	@:neutral public static function FieldSeparator(props:{?text:String, ?tag:String}):View
		return <view tag={props.tag ?? "field-separator"} id={props.tag} slot="field-separator" data-content={props.text != null ? "true" : null}>
			<view slot="separator" role="separator" data-orientation="horizontal" position="absolute" left={0} right={0} top="50%"/>
			{props.text == null ? null : <text slot="field-separator-content">{props.text}</text>}
		</view>;

	// a button group (shadcn's): buttons (and selects, inputs, text) side by
	// side in one shape, a group to assistive technology; orientation
	// "horizontal" (the default) or "vertical". Slot "button-group"
	// (data-orientation); its parts ButtonGroupText and ButtonGroupSeparator
	@:widget({
		props: {
			orientation: "horizontal (side by side, the default) or vertical",
			label: "its name for assistive technology",
			children: "its buttons, selects, inputs, ButtonGroupText and ButtonGroupSeparator"
		},
		variants: ["horizontal", "vertical"]
	})
	@:neutral public static function ButtonGroup(props:{?orientation:String, ?label:String, ?children:Any, ?tag:String}):View {
		var o = props.orientation ?? "horizontal";
		return <view tag={props.tag ?? "button-group"} id={props.tag} slot="button-group" role="group" label={props.label} variant={o} data-orientation={o}
			direction={o == "vertical" ? "column" : "row"}>{props.children}</view>;
	}

	@:widget({
		props: {
			text: "its text, when it has no children",
			children: "its content, in place of text"
		},
		part: "ButtonGroup"
	})
	@:neutral public static function ButtonGroupText(props:{?text:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "button-group-text"} id={props.tag} slot="button-group-text">{props.children ?? props.text}</view>;

	@:widget({
		props: {
			orientation: "the line's: vertical (the default, between buttons side by side) or horizontal"
		},
		part: "ButtonGroup"
	})
	@:neutral public static function ButtonGroupSeparator(props:{?orientation:String, ?tag:String}):View
		return <view tag={props.tag ?? "button-group-separator"} id={props.tag} slot="button-group-separator" data-orientation={props.orientation ?? "vertical"} hidden/>;

	// an input group (shadcn's): an InputGroupInput (or a text area) with
	// addons beside, above or under it (icons, text, buttons) in one box; a
	// click on an addon focuses the input. Slot "input-group" (data-disabled);
	// its parts InputGroupAddon (data-align "inline-start", "inline-end",
	// "block-start", "block-end"), InputGroupText, InputGroupInput (slot
	// "input-group-control")
	@:widget({
		props: {
			label: "its name for assistive technology",
			disabled: "a Bool, a signal or a function of one: data-disabled for the theme",
			children: "its InputGroupInput and InputGroupAddons"
		}
	})
	public static function InputGroup(props:{?label:String, ?disabled:Dynamic, ?children:Any, ?tag:String}):View {
		// (an addon's click: the input focused)
		function focusInput(e:Event) {
			var n:Node = e.current, input:Null<Node> = null;
			function find(m:Node)
				for (c in m.children) {
					if (input == null && c.slot == "input-group-control") input = c;
					find(c);
				}
			find(n);
			if (input != null && input.ui != null && e.target.slot != "button") input.ui.setFocus(input);
		}
		return <view tag={props.tag ?? "input-group"} slot="input-group" role="group" label={props.label} direction="row" align-items="center"
			data-disabled={() -> read(props.disabled) == true ? "true" : null} onClick={focusInput}>{props.children}</view>;
	}

	@:widget({
		props: {
			align: "where it goes: inline-start (before the input, the default), inline-end (after), block-start (above) or block-end (under)",
			children: "its icons, InputGroupText or buttons"
		},
		part: "InputGroup"
	})
	public static function InputGroupAddon(props:{?align:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "input-group-addon"} slot="input-group-addon" data-align={props.align ?? "inline-start"}
			variant={props.align ?? "inline-start"}>{props.children}</view>;

	@:widget({
		props: {
			text: "its text, when it has no children",
			children: "its content, in place of text"
		},
		part: "InputGroup"
	})
	public static function InputGroupText(props:{?text:String, ?children:Any, ?tag:String}):View
		return <text tag={props.tag ?? "input-group-text"} slot="input-group-text">{props.children ?? props.text}</text>;

	@:widget({
		props: {
			value: "a signal of its text",
			placeholder: "shown while it is empty",
			label: "its name for assistive technology (else the placeholder)",
			onSubmit: "called with its text on Enter",
			password: "true: its characters hidden",
			invalid: "a Bool, a signal or a function of one: aria-invalid for the theme",
			disabled: "a Bool, a signal or a function of one: not focusable or typed in"
		},
		part: "InputGroup"
	})
	public static function InputGroupInput(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?password:Bool,
			?invalid:Dynamic, ?disabled:Dynamic, ?style:States->StyleProps, ?tag:String}):View
		return textInput(props, "input-group-control");

	// an empty state (shadcn's): a media (an icon), a title, a description
	// and what to do (buttons), centred. Slot "empty"; its parts EmptyHeader,
	// EmptyMedia (variant "default" or "icon"), EmptyTitle, EmptyDescription,
	// EmptyContent
	@:widget({
		props: {
			children: "its EmptyHeader and EmptyContent"
		}
	})
	@:neutral public static function Empty(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "empty"} id={props.tag} slot="empty">{props.children}</view>;

	@:widget({
		props: {
			children: "its EmptyMedia, EmptyTitle and EmptyDescription"
		},
		part: "Empty"
	})
	@:neutral public static function EmptyHeader(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "empty-header"} id={props.tag} slot="empty-header">{props.children}</view>;

	@:widget({
		props: {
			variant: "default (as given) or icon (an icon in a tile)",
			children: "its image or icon"
		},
		variants: ["default", "icon"],
		part: "Empty"
	})
	@:neutral public static function EmptyMedia(props:{?variant:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "empty-media"} id={props.tag} slot="empty-icon" variant={props.variant ?? "default"} data-variant={props.variant ?? "default"}>{props.children}</view>;

	@:widget({
		props: {
			text: "its text, a heading for assistive technology"
		},
		part: "Empty"
	})
	@:neutral public static function EmptyTitle(props:{text:String, ?tag:String}):View
		return <text:div tag={props.tag ?? "empty-title"} id={props.tag} slot="empty-title" role="heading" level={2}>{props.text}</text:div>;

	@:widget({
		props: {
			text: "its text"
		},
		part: "Empty"
	})
	@:neutral public static function EmptyDescription(props:{text:String, ?tag:String}):View
		return <text:div tag={props.tag ?? "empty-description"} id={props.tag} slot="empty-description">{props.text}</text:div>;

	@:widget({
		props: {
			children: "what to do: its buttons, a link"
		},
		part: "Empty"
	})
	@:neutral public static function EmptyContent(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "empty-content"} id={props.tag} slot="empty-content">{props.children}</view>;

	// an item (shadcn's): a row of a media, a title and description, and
	// actions, variant "default", "outline" or "muted", size "default" or
	// "sm"; items in an ItemGroup (a list to assistive technology, each item
	// one of it), an ItemSeparator between. Slot "item" (data-variant,
	// data-size); its parts ItemMedia (variant "default", "icon" or "image"),
	// ItemContent, ItemTitle, ItemDescription, ItemActions, ItemHeader, ItemFooter
	@:widget({
		props: {
			variant: "its look: default, outline (a border) or muted (a background)",
			size: "default or sm",
			onClick: "called when it is clicked, or pressed with Enter or Space (then focusable, a button to assistive technology)",
			children: "its ItemMedia, ItemContent, ItemActions (and ItemHeader, ItemFooter)"
		},
		variants: ["default", "outline", "muted"],
		sizes: ["default", "sm"],
		keys: {"Enter, Space": "with onClick: clicks it"}
	})
	@:neutral public static function Item(props:{?variant:String, ?size:String, ?onClick:Void->Void, ?children:Any, ?tag:String}):View {
		var v = props.variant ?? "default", z = props.size ?? "default";
		var press = () -> if (props.onClick != null) props.onClick();
		return <view tag={props.tag ?? "item"} id={props.tag} slot="item" variant={v} size={z} data-variant={v} data-size={z} direction="row" wrap
			align-items="center" role={props.onClick != null ? "button" : "listitem"} focusable={props.onClick != null ? true : null}
			onPress={props.onClick == null ? null : _ -> press()}>
			{props.children}
		</view>;
	}

	@:widget({
		props: {
			label: "its name for assistive technology",
			children: "its Items and ItemSeparators"
		},
		part: "Item"
	})
	@:neutral public static function ItemGroup(props:{?label:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-group"} id={props.tag} slot="item-group" role="list" label={props.label}>{props.children}</view>;

	@:widget({props: {}, part: "Item"})
	@:neutral public static function ItemSeparator(props:{?tag:String}):View
		return <view tag={props.tag ?? "item-separator"} id={props.tag} slot="item-separator" data-orientation="horizontal" hidden/>;

	@:widget({
		props: {
			variant: "default (as given), icon (an icon in a tile) or image (cropped to a square)",
			children: "its icon or image"
		},
		variants: ["default", "icon", "image"],
		part: "Item"
	})
	@:neutral public static function ItemMedia(props:{?variant:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-media"} id={props.tag} slot="item-media" variant={props.variant ?? "default"} data-variant={props.variant ?? "default"}>{props.children}</view>;

	@:widget({
		props: {
			children: "its ItemTitle and ItemDescription"
		},
		part: "Item"
	})
	@:neutral public static function ItemContent(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-content"} id={props.tag} slot="item-content">{props.children}</view>;

	@:widget({
		props: {
			text: "its text, when it has no children",
			children: "its content, in place of text (a badge beside it)"
		},
		part: "Item"
	})
	@:neutral public static function ItemTitle(props:{?text:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-title"} id={props.tag} slot="item-title">{props.children ?? props.text}</view>;

	@:widget({
		props: {
			text: "its text"
		},
		part: "Item"
	})
	@:neutral public static function ItemDescription(props:{text:String, ?tag:String}):View
		return <text:p tag={props.tag ?? "item-description"} id={props.tag} slot="item-description">{props.text}</text:p>;

	@:widget({
		props: {
			children: "its buttons"
		},
		part: "Item"
	})
	@:neutral public static function ItemActions(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-actions"} id={props.tag} slot="item-actions" direction="row" align-items="center">{props.children}</view>;

	@:widget({
		props: {
			children: "what goes above its content, the whole width (an image)"
		},
		part: "Item"
	})
	@:neutral public static function ItemHeader(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-header"} id={props.tag} slot="item-header">{props.children}</view>;

	@:widget({
		props: {
			children: "what goes under its content, the whole width"
		},
		part: "Item"
	})
	@:neutral public static function ItemFooter(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "item-footer"} id={props.tag} slot="item-footer">{props.children}</view>;

	// a box kept to a ratio of width to height (shadcn's AspectRatio): as
	// wide as its parent gives it, as tall as the ratio says; its child
	// fills it. Slot "aspect-ratio"
	@:widget({
		props: {
			ratio: "width over height (16 / 9: 1.78; 1 when not given)",
			children: "what fills it: an image, a video"
		}
	})
	@:neutral public static function AspectRatio(props:{?ratio:Float, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "aspect-ratio"} id={props.tag} slot="aspect-ratio" aspect-ratio={props.ratio ?? 1.0} position="relative" overflow="hidden">
			{props.children}
		</view>;

	// a scrolled area (shadcn's ScrollArea): its children in a viewport
	// that scrolls, vertically (the default), horizontally or both, the
	// theme's thin scrollbars. Slots "scroll-area" and
	// "scroll-area-viewport" (data-orientation)
	@:widget({
		props: {
			orientation: "vertical (the default), horizontal or both",
			height: "its height",
			width: "its width",
			label: "its name for assistive technology",
			children: "what scrolls"
		}
	})
	public static function ScrollArea(props:{?orientation:String, ?height:Float, ?width:Float, ?label:String, ?children:Any, ?tag:String}):View {
		var o = props.orientation ?? "vertical";
		return <view tag={props.tag ?? "scroll-area"} slot="scroll-area" height={props.height} width={props.width} position="relative">
			<scroll tag={(props.tag ?? "scroll-area") + "-viewport"} slot="scroll-area-viewport" data-orientation={o} label={props.label} grow={1}
				min-height={0} direction={o == "horizontal" ? "row" : "column"}>{props.children}</scroll>
		</view>;
	}

	// a select the platform's own where it has one (shadcn's NativeSelect:
	// the system's picker): Select with host native, its options the
	// platform's menu (macOS, Windows), else drawn. Its props are Select's;
	// slots "native-select-wrapper", "native-select" (Select's trigger:
	// data-state, data-size), "native-select-icon", the list's Select's
	@:widget({
		props: {
			value: "a signal of the chosen option",
			options: "the options' values",
			labels: "what each option shows (else the option itself)",
			width: "the button's width (else its content's)",
			size: "\"default\" or \"sm\" (data-size)",
			label: "its name for assistive technology"
		},
		keys: {
			"Enter, Space": "opens the options (the platform's menu, else the drawn list)",
			"Up, Down": "chooses the option before or after"
		}
	})
	public static function NativeSelect(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?size:String,
			?label:String, ?tag:String}):View
		return <view host="native" slot="native-select-wrapper" position="relative">{
			select({tag: props.tag ?? "native-select", value: props.value, options: props.options, labels: props.labels, width: props.width, size: props.size,
				label: props.label}, true)
		}</view>;

	// --- charts (shadcn's Chart: its look, recharts' kinds) ---


	// (a chart's scale's top: max, else the greatest value (stacked: the greatest sum) rounded up)
	static function chartTop(series:Array<{name:String, values:Array<Float>, ?color:Color}>, n:Int, max:Null<Float>, stacked:Bool):Float {
		if (max != null) return max;
		var most = 0.0;
		for (i in 0...n) {
			var sum = 0.0;
			for (s in series) {
				var v = Math.max(0, s.values[i]);
				if (stacked) sum += v else most = Math.max(most, v);
			}
			most = Math.max(most, sum);
		}
		return Behaviour.niceMax(most);
	}

	// (unstyled, each series a colour of its own: a theme's are its tokens, --chart-1 to --chart-5)
	static function chartBase()
		Rules.addBase("chart", ([{slot: "chart-tooltip-item", style: {columnGap: 6}}, {slot: "chart-tooltip-row", style: {columnGap: 8}}]:Array<Rule>).concat(Lambda.flatten([
			for (k in 0...5) {
				var c:Color = [0xFF2563EB, 0xFF16A34A, 0xFFF59E0B, 0xFFDC2626, 0xFF7C3AED][k];
				var rules:Array<Rule> = [
					{slot: "chart-bar", when: ['data-series=${k + 1}'], style: {background: c}},
					{slot: "chart-dot", when: ['data-series=${k + 1}'], style: {background: c}},
					{slot: "chart-line", when: ['data-series=${k + 1}'], style: {color: c}},
					{slot: "chart-area", when: ['data-series=${k + 1}'], style: {color: c}},
					{slot: "chart-slice", when: ['data-series=${k + 1}'], style: {color: c}},
					{slot: "chart-legend-swatch", when: ['data-series=${k + 1}'], style: {background: c}},
					{slot: "chart-tooltip-indicator", when: ['data-series=${k + 1}'], style: {background: c, width: 8, height: 8}}
				];
				rules;
			}
		])));

	// (a chart's keys, as recharts' accessibility layer: the arrows from one category or slice
	// to the next (none shown: the first, or the last going back), Home and End, Escape none)
	static function chartKeys(e:Event, hover:Signal<Int>, n:Int) {
		var i = hover.peek();
		var next = switch Behaviour.mirror(e.key, e.current.rtl()) {
			case Key.RIGHT | Key.DOWN: i < 0 ? 0 : Std.int(Math.min(n - 1, i + 1));
			case Key.LEFT | Key.UP: i < 0 ? n - 1 : Std.int(Math.max(0, i - 1));
			case Key.HOME: 0;
			case Key.END: n - 1;
			case Key.ESCAPE: -1;
			case _: -2;
		}
		if (next == -2 || n == 0) return;
		e.preventDefault();
		hover.value = next;
	}

	// (a chart's frame: the y axis's ticks and the plot's grid lines, the
	// plot, the x axis's labels, the legend; the category under the pointer
	// (hover) shown in a tooltip, its values each series')
	static function chartFrame(tag:String, labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:Color}>, w:Float, h:Float, top:Float,
			plot:View, hover:Signal<Int>, label:Null<String>, format:Float->String):View {
		chartBase();
		var n = labels.length, axis = 40.0;
		function at(e:Event) {
			var x = e.current.localX(e.x, e.y), i = n == 0 ? -1 : Std.int(x / (w / n));
			hover.value = i >= 0 && i < n ? i : -1;
		}
		return <view tag={tag} slot="chart" role="img" label={label ?? "Chart"} align-items="start">
			<view direction="row">
				<view slot="chart-y-axis" width={axis} height={h} position="relative">{[
					for (t in 0...5)
						<text slot="chart-tick" position="absolute" right={6} top={h - t / 4 * h - 7}>{format(top * t / 4)}</text>
				]}</view>
				<view tag={tag + "-plot"} slot="chart-plot" width={w} height={h} position="relative" onPointerMove={at} onPointerLeave={_ -> hover.value = -1}
					focusable={true} onKeyDown={e -> chartKeys(e, hover, n)} onBlur={_ -> hover.value = -1}>
					{[for (t in 0...5) <view slot="chart-grid" position="absolute" left={0} width={w} top={h - t / 4 * h} height={1}/>]}
					{plot}
					<Show when={() -> hover.value >= 0}>{() -> {
						var i = hover.value;
						<view tag={tag + "-tooltip"} slot="chart-tooltip" position="absolute" top={4} left={Math.min(w - 120, (i + 0.5) * w / n + 8)}>
							<text slot="chart-tooltip-label">{labels[i]}</text>
							{[
								for (k in 0...series.length)
									<view slot="chart-tooltip-item" direction="row" align-items="center">
										<view slot="chart-tooltip-indicator" data-series={Std.string(k % 5 + 1)} background={series[k].color}/>
										<view slot="chart-tooltip-row" direction="row" align-items="center" justify="space-between" grow={1}>
											<text slot="chart-tooltip-name">{series[k].name}</text>
											<text slot="chart-tooltip-value">{format(series[k].values[i])}</text>
										</view>
									</view>
							]}
						</view>;
					}}</Show>
				</view>
			</view>
			<view slot="chart-x-axis" direction="row" margin-left={axis} width={w}>{[
				for (l in labels) <text slot="chart-tick" grow={1} basis={0} text-align="center">{l}</text>
			]}</view>
			<view slot="chart-legend" direction="row" margin-left={axis} width={w} justify="center" column-gap={16}>{[
				for (k in 0...series.length)
					<view slot="chart-legend-item" direction="row" align-items="center" column-gap={6}>
						<view slot="chart-legend-swatch" data-series={Std.string(k % 5 + 1)} width={8} height={8} background={series[k].color}/>
						<text>{series[k].name}</text>
					</view>
			]}</view>
		</view>;
	}

	// a bar chart (shadcn's Chart with recharts' BarChart): categories
	// (labels) along the x axis, a bar per series in each, its height its
	// value on a scale from 0 to a round top (max, else the greatest value's);
	// each series a colour (color, else the theme's --chart-N by its place);
	// the pointer over a category shows its values. Slots "chart", "chart-plot",
	// "chart-grid", "chart-y-axis", "chart-x-axis", "chart-tick",
	// "chart-bar" (data-series: 1 to 5), "chart-legend", "chart-legend-item",
	// "chart-legend-swatch", "chart-tooltip", "chart-tooltip-label",
	// "chart-tooltip-item", "chart-tooltip-indicator" (data-series),
	// "chart-tooltip-row", "chart-tooltip-name", "chart-tooltip-value"
	@:widget({
		props: {
			labels: "the categories, along the x axis",
			series: "each series: its name, a value per category, and its colour (else the theme's by its place)",
			width: "the plot's width (300 when not given)",
			height: "the plot's height (160 when not given)",
			max: "the scale's top (else the greatest value rounded up)",
			stacked: "the series stacked, each on the ones before it (the scale to their sums)",
			format: "a value as the axis and the tooltip show it (else as it is)",
			label: "its name for assistive technology"
		},
		keys: {
			"Left, Right, Up, Down": "shows the next or previous category's values (the plot focused)",
			"Home, End": "the first or last category's",
			"Escape": "hides them"
		}
	})
	public static function BarChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:Color}>, ?width:Float, ?height:Float,
			?max:Float, ?stacked:Bool, ?format:Float->String, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "bar-chart", w = props.width ?? 300.0, h = props.height ?? 160.0, n = props.labels.length, hover = signal(-1);
		var stacked = props.stacked == true, top = chartTop(props.series, n, props.max, stacked);
		var format = props.format ?? Behaviour.plain, series = props.series, slot = n == 0 ? 0.0 : w / n;
		var barW = series.length == 0 ? 0.0 : stacked ? slot * 0.6 : slot * 0.7 / series.length;
		var bar = (i:Int, k:Int) -> <view slot="chart-bar" data-series={Std.string(k % 5 + 1)} width={barW}
			height={Math.max(0, Math.min(1, series[k].values[i] / top)) * h} background={series[k].color} data-active={() -> hover.value == i ? "true" : null}/>;
		var plot = <view position="absolute" left={0} top={0} width={w} height={h} direction="row">{[
			for (i in 0...n)
				<view tag={tag + "-" + i} width={slot} height={h} direction="row" justify="center" align-items="end" role="group"
					label={props.labels[i] + ": " + [for (s in series) s.name + " " + format(s.values[i])].join(", ")}>
					{stacked ? <view direction="column-reverse">{[for (k in 0...series.length) bar(i, k)]}</view> : [for (k in 0...series.length) bar(i, k)]}
				</view>
		]}</view>;
		return chartFrame(tag, props.labels, series, w, h, top, plot, hover, props.label, format);
	}

	// a line chart (recharts' LineChart in shadcn's look): a line per series
	// through its values at each category, on the same scale and frame as
	// BarChart's; a dot on each line at the category under the pointer.
	// Slots as BarChart's, "chart-line" (its colour: data-series 1 to 5) and
	// "chart-dot" for its dots (their colour: data-series 1 to 5)
	@:widget({
		props: {
			labels: "the categories, along the x axis",
			series: "each series: its name, a value per category, and its colour (else the theme's by its place)",
			width: "the plot's width (300 when not given)",
			height: "the plot's height (160 when not given)",
			max: "the scale's top (else the greatest value rounded up)",
			stacked: "the series stacked, each on the ones before it (the scale to their sums)",
			format: "a value as the axis and the tooltip show it (else as it is)",
			label: "its name for assistive technology"
		},
		keys: {
			"Left, Right, Up, Down": "shows the next or previous category's values (the plot focused)",
			"Home, End": "the first or last category's",
			"Escape": "hides them"
		}
	})
	public static function LineChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:Color}>, ?width:Float, ?height:Float,
			?max:Float, ?stacked:Bool, ?format:Float->String, ?label:String, ?tag:String}):View
		return seriesChart(props, "line-chart", false);

	// an area chart (recharts' AreaChart in shadcn's look): LineChart's
	// lines, each filled faintly down to the axis. Slots as LineChart's,
	// "chart-area" for its lines (its colour: data-series 1 to 5)
	@:widget({
		props: {
			labels: "the categories, along the x axis",
			series: "each series: its name, a value per category, and its colour (else the theme's by its place)",
			width: "the plot's width (300 when not given)",
			height: "the plot's height (160 when not given)",
			max: "the scale's top (else the greatest value rounded up)",
			stacked: "the series stacked, each on the ones before it (the scale to their sums)",
			format: "a value as the axis and the tooltip show it (else as it is)",
			label: "its name for assistive technology"
		},
		keys: {
			"Left, Right, Up, Down": "shows the next or previous category's values (the plot focused)",
			"Home, End": "the first or last category's",
			"Escape": "hides them"
		}
	})
	public static function AreaChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:Color}>, ?width:Float, ?height:Float,
			?max:Float, ?stacked:Bool, ?format:Float->String, ?label:String, ?tag:String}):View
		return seriesChart(props, "area-chart", true);

	// (LineChart's and AreaChart's: a line per series, filled under it for an area)
	static function seriesChart(props:{labels:Array<String>, series:Array<{name:String, values:Array<Float>, ?color:Color}>, ?width:Float, ?height:Float,
			?max:Float, ?stacked:Bool, ?format:Float->String, ?label:String, ?tag:String}, kind:String, area:Bool):View {
		var tag = props.tag ?? kind, w = props.width ?? 300.0, h = props.height ?? 160.0, n = props.labels.length, hover = signal(-1);
		var stacked = props.stacked == true, top = chartTop(props.series, n, props.max, stacked);
		var format = props.format ?? Behaviour.plain, series = props.series, slot = n == 0 ? 0.0 : w / n;
		var px = (i:Int) -> (i + 0.5) * slot, py = (v:Float) -> h - Math.max(0, Math.min(1, v / top)) * h;
		// (each series' line at its values, stacked: on the sums before it)
		var base = [for (i in 0...n) 0.0], at = [];
		for (k in 0...series.length) {
			at.push([for (i in 0...n) (stacked ? base[i] : 0) + series[k].values[i]]);
			if (stacked) base = at[k];
		}
		inline function num(v:Float):String
			return Std.string(Math.fround(v * 100) / 100);
		var plot = <view position="absolute" left={0} top={0} width={w} height={h}>{[
			for (k in 0...series.length) {
				var d = [for (i in 0...n) (i == 0 ? "M" : "L") + num(px(i)) + " " + num(py(at[k][i]))].join(" ");
				// (an area's: the line's points closed along the axis, or back along the line under it
				// stacked, filled faintly)
				var under = stacked && k > 0 ? [for (j in 0...n) {var i = n - 1 - j; "L" + num(px(i)) + " " + num(py(at[k - 1][i]));}].join(" ") : 'L${num(px(n - 1))} $h L${num(px(0))} $h';
				var fill = !area || n == 0 ? "" : '<path d="$d $under Z" fill="currentColor" fill-opacity="0.4"/>';
				var svg = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $w $h" width="$w" height="$h">$fill<path d="$d" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>');
				[
					<image tag={tag + "-line-" + k} slot={area ? "chart-area" : "chart-line"} data-series={Std.string(k % 5 + 1)} src={svg} position="absolute" left={0} top={0} width={w}
						height={h} color={series[k].color}/>,
					<Show when={() -> hover.value >= 0}>{() -> <view slot="chart-dot" data-series={Std.string(k % 5 + 1)} position="absolute" width={8} height={8}
						radius={4} left={px(hover.value) - 4} top={py(at[k][hover.value]) - 4} background={series[k].color}/>}</Show>
				];
			}
		]}</view>;
		return chartFrame(tag, props.labels, series, w, h, top, plot, hover, props.label, format);
	}

	// a pie chart (recharts' PieChart in shadcn's look): a slice per value,
	// clockwise from the top, its share of the circle its share of the total;
	// a donut when inner (its hole's radius, a fraction of the radius) is
	// given; each slice a colour (color, else the theme's --chart-N by its
	// place); the pointer over a slice shows its name and value. Slots
	// "chart", "chart-plot", "chart-slice" (data-series: 1 to 5;
	// data-active under the pointer), "chart-legend", "chart-legend-item",
	// "chart-legend-swatch", "chart-tooltip", "chart-tooltip-label",
	// "chart-tooltip-value"
	@:widget({
		props: {
			slices: "each slice: its name, its value, and its colour (else the theme's by its place)",
			size: "the circle's diameter (200 when not given)",
			inner: "a donut's hole, its radius a fraction of the circle's (0 when not given: a pie)",
			format: "a value as the tooltip shows it (else as it is)",
			label: "its name for assistive technology"
		},
		keys: {
			"Left, Right, Up, Down": "shows the next or previous slice's values (the plot focused)",
			"Home, End": "the first or last slice's",
			"Escape": "hides them"
		}
	})
	public static function PieChart(props:{slices:Array<{name:String, value:Float, ?color:Color}>, ?size:Float, ?inner:Float, ?format:Float->String,
			?label:String, ?tag:String}):View {
		chartBase();
		var tag = props.tag ?? "pie-chart", size = props.size ?? 200.0, slices = props.slices, hover = signal(-1);
		var format = props.format ?? Behaviour.plain;
		var total = Lambda.fold(slices, (sl, t) -> t + Math.max(0, sl.value), 0.0);
		var c = size / 2, r = size / 2 - 1, ri = Math.max(0, Math.min(1, props.inner ?? 0)) * r;
		// (each slice's start and end, in turns clockwise from the top)
		var ends = [], at = 0.0;
		for (sl in slices) {
			var from = at;
			at += total > 0 ? Math.max(0, sl.value) / total : 0;
			ends.push({from: from, to: at});
		}
		inline function num(v:Float):String
			return Std.string(Math.fround(v * 100) / 100);
		function point(t:Float, rad:Float):String
			return num(c + rad * Math.sin(t * 2 * Math.PI)) + " " + num(c - rad * Math.cos(t * 2 * Math.PI));
		function path(from:Float, to:Float):String {
			// (a whole circle: two halves, an arc's ends being one point)
			if (to - from >= 1 - 1e-9)
				return ri > 0 ? 'M${point(0, r)} A$r $r 0 1 1 ${point(0.5, r)} A$r $r 0 1 1 ${point(0, r)} M${point(0, ri)} A$ri $ri 0 1 0 ${point(0.5, ri)} A$ri $ri 0 1 0 ${point(0, ri)} Z' : 'M${point(0, r)} A$r $r 0 1 1 ${point(0.5, r)} A$r $r 0 1 1 ${point(0, r)} Z';
			var large = to - from > 0.5 ? 1 : 0;
			return ri > 0 ? 'M${point(from, r)} A$r $r 0 $large 1 ${point(to, r)} L${point(to, ri)} A$ri $ri 0 $large 0 ${point(from, ri)} Z' : 'M$c $c L${point(from, r)} A$r $r 0 $large 1 ${point(to, r)} Z';
		}
		// (the slice under a point of the plot: by its angle, within the ring)
		function under(e:Event) {
			var x = e.current.localX(e.x, e.y) - c, y = e.current.localY(e.x, e.y) - c, d = Math.sqrt(x * x + y * y);
			var t = (Math.atan2(x, -y) / (2 * Math.PI) + 1) % 1, found = -1;
			if (d <= r && d >= ri)
				for (k in 0...ends.length)
					if (t >= ends[k].from && t < ends[k].to) found = k;
			hover.value = found;
		}
		return <view tag={tag} slot="chart" role="img" label={props.label ?? "Chart"} align-items="center">
			<view tag={tag + "-plot"} slot="chart-plot" width={size} height={size} position="relative" onPointerMove={under}
				onPointerLeave={_ -> hover.value = -1} focusable={true} onKeyDown={e -> chartKeys(e, hover, slices.length)} onBlur={_ -> hover.value = -1}>
				{[
					for (k in 0...slices.length)
						if (ends[k].to > ends[k].from) {
							var svg = Svg.parse('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $size $size" width="$size" height="$size"><path d="${path(ends[k].from, ends[k].to)}" fill="currentColor" fill-rule="evenodd"/></svg>');
							<image tag={tag + "-" + k} slot="chart-slice" data-series={Std.string(k % 5 + 1)} src={svg} position="absolute" left={0} top={0}
								width={size} height={size} color={slices[k].color} role="group" label={slices[k].name + ": " + format(slices[k].value)}
								data-active={() -> hover.value == k ? "true" : null}/>;
						} else null
				]}
				<Show when={() -> hover.value >= 0}>{() -> {
					var k = hover.value;
					<view tag={tag + "-tooltip"} slot="chart-tooltip" position="absolute" top={4} left={4} direction="row" align-items="center"
						column-gap={6}>
						<view slot="chart-legend-swatch" data-series={Std.string(k % 5 + 1)} width={8} height={8} background={slices[k].color}/>
						<text slot="chart-tooltip-label">{slices[k].name}</text>
						<text slot="chart-tooltip-value">{format(slices[k].value)}</text>
					</view>;
				}}</Show>
			</view>
			<view slot="chart-legend" direction="row" wrap={true} width={Math.max(size, 240)} justify="center" column-gap={16}>{[
				for (k in 0...slices.length)
					<view slot="chart-legend-item" direction="row" align-items="center" column-gap={6}>
						<view slot="chart-legend-swatch" data-series={Std.string(k % 5 + 1)} width={8} height={8} background={slices[k].color}/>
						<text>{slices[k].name}</text>
					</view>
			]}</view>
		</view>;
	}

	// --- shadcn's Sidebar ---

	// (the open sidebar's signal, for its trigger and parts: SidebarProvider's)
	static final SIDEBAR = new Context<Null<Signal<Bool>>>(null);

	// a sidebar's layout (shadcn's SidebarProvider): open, a signal (its own
	// when not given), shared with the Sidebar, SidebarTrigger and the parts
	// inside; Mod+B toggles it from anywhere in the window. Slot
	// "sidebar-wrapper" (data-state "expanded" or "collapsed")
	@:widget({
		props: {
			open: "a signal of whether the sidebar is expanded (its own when not given, true)",
			children: "its Sidebar and SidebarInset"
		},
		keys: {
			"Mod+B": "toggles the sidebar, from anywhere in the window"
		}
	})
	public static function SidebarProvider(props:{?open:Signal<Bool>, ?children:Any, ?tag:String}):View {
		var open = props.open ?? signal(true);
		return <view tag={props.tag ?? "sidebar-wrapper"} slot="sidebar-wrapper" direction="row" data-state={() -> open.value ? "expanded" : "collapsed"}>
			{UiFlow.Hotkey({keys: "Mod+B", action: () -> open.value = !open.peek()})}
			{Flow.Provider({context: SIDEBAR, value: open, children: props.children})}
		</view>;
	}

	// a sidebar (shadcn's): its side ("left", the default, or "right"),
	// variant ("sidebar", "floating" or "inset") and how it collapses
	// ("offcanvas", the default: out of view; "icon": to its icons; "none");
	// a group to a theme (its parts' rules ask for its data-collapsible).
	// Slot "sidebar" (data-state, data-collapsible while collapsed,
	// data-variant, data-side), "sidebar-gap" (holding its width in the
	// flow), "sidebar-container" (fixed beside it), "sidebar-inner"
	@:widget({
		props: {
			side: "left (the default) or right",
			variant: "sidebar (the default), floating or inset",
			collapsible: "offcanvas (the default: out of view collapsed), icon (to its icons) or none",
			label: "its name for assistive technology",
			children: "its SidebarHeader, SidebarContent and SidebarFooter"
		},
		variants: ["sidebar", "floating", "inset"],
		part: "SidebarProvider"
	})
	public static function Sidebar(props:{?side:String, ?variant:String, ?collapsible:String, ?label:String, ?children:Any, ?tag:String}):View {
		// (unstyled, an offcanvas one collapsed is out of view)
		Rules.addBase("sidebar", [{slot: "sidebar", when: ["data-collapsible=offcanvas"], style: {display: None}}]);
		var open = use(SIDEBAR) ?? signal(true), collapsible = props.collapsible ?? "offcanvas";
		var expanded = () -> collapsible == "none" || open.value;
		return <view tag={props.tag ?? "sidebar"} slot="sidebar" group="sidebar" role="navigation" label={props.label ?? "Sidebar"}
			data-state={() -> expanded() ? "expanded" : "collapsed"} data-collapsible={() -> expanded() ? null : collapsible}
			variant={props.variant ?? "sidebar"} data-variant={props.variant ?? "sidebar"} data-side={props.side ?? "left"}>
			<view slot="sidebar-gap" variant={props.variant ?? "sidebar"}/>
			<view slot="sidebar-container" variant={props.variant ?? "sidebar"} data-side={props.side ?? "left"}>
				<view slot="sidebar-inner">{props.children}</view>
			</view>
		</view>;
	}

	// the button that toggles the sidebar (shadcn's SidebarTrigger: a ghost
	// icon button). Slot "sidebar-trigger" (variant "ghost", size "icon")
	@:widget({
		props: {
			label: "its name for assistive technology (\"Toggle Sidebar\" when not given)"
		},
		keys: {
			"Enter, Space": "toggles the sidebar"
		},
		part: "SidebarProvider"
	})
	public static function SidebarTrigger(props:{?label:String, ?tag:String}):View {
		var open = use(SIDEBAR);
		var toggle = () -> if (open != null) open.value = !open.peek();
		return <view tag={props.tag ?? "sidebar-trigger"} slot="sidebar-trigger" variant="ghost" size="icon" role="button" label={props.label ?? "Toggle Sidebar"}
			focusable expanded={() -> open != null && open.value} onClick={_ -> toggle()} onKeyDown={e -> pressKeys(e, toggle)}>{icon(PANEL_LEFT, "sidebar-trigger-icon")}</view>;
	}

	@:widget({props: {children: "the page beside the sidebar"}, part: "SidebarProvider"})
	public static function SidebarInset(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-inset"} slot="sidebar-inset" grow={1}>{props.children}</view>;

	@:widget({props: {children: "what heads the sidebar"}, part: "Sidebar"})
	public static function SidebarHeader(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-header"} slot="sidebar-header">{props.children}</view>;

	@:widget({props: {children: "its groups, scrolled when they are taller than it"}, part: "Sidebar"})
	public static function SidebarContent(props:{?children:Any, ?tag:String}):View
		return <scroll tag={props.tag ?? "sidebar-content"} slot="sidebar-content" grow={1} min-height={0}>{props.children}</scroll>;

	@:widget({props: {children: "what ends the sidebar"}, part: "Sidebar"})
	public static function SidebarFooter(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-footer"} slot="sidebar-footer">{props.children}</view>;

	@:widget({props: {}, part: "Sidebar"})
	public static function SidebarSeparator(props:{?tag:String}):View
		return <view tag={props.tag ?? "sidebar-separator"} slot="sidebar-separator" role="separator"/>;

	@:widget({props: {label: "its name for assistive technology", children: "its SidebarGroupLabel and SidebarGroupContent"}, part: "Sidebar"})
	public static function SidebarGroup(props:{?label:String, ?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-group"} slot="sidebar-group" role="group" label={props.label}>{props.children}</view>;

	@:widget({props: {text: "the group's title"}, part: "Sidebar"})
	public static function SidebarGroupLabel(props:{text:String, ?tag:String}):View
		return <text tag={props.tag ?? "sidebar-group-label"} slot="sidebar-group-label">{props.text}</text>;

	@:widget({props: {children: "the group's SidebarMenu or anything"}, part: "Sidebar"})
	public static function SidebarGroupContent(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-group-content"} slot="sidebar-group-content">{props.children}</view>;

	@:widget({props: {children: "its SidebarMenuItems"}, part: "Sidebar"})
	public static function SidebarMenu(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-menu"} slot="sidebar-menu" role="list">{props.children}</view>;

	@:widget({props: {children: "its SidebarMenuButton"}, part: "Sidebar"})
	public static function SidebarMenuItem(props:{?children:Any, ?tag:String}):View
		return <view tag={props.tag ?? "sidebar-menu-item"} slot="sidebar-menu-item" role="listitem">{props.children}</view>;

	// a sidebar menu's button: its label (and children: an icon first),
	// active (a Bool, a signal or a function of one: the current page,
	// data-active), size "default", "sm" or "lg". Slot "sidebar-menu-button"
	@:widget({
		props: {
			label: "what it says (hidden by the theme when the sidebar is collapsed to its icons)",
			active: "a Bool, a signal or a function of one: the current page (data-active)",
			onClick: "what pressing it does",
			size: "default, sm or lg",
			children: "what comes before its label: an icon"
		},
		keys: {
			"Enter, Space": "presses it"
		},
		part: "Sidebar"
	})
	public static function SidebarMenuButton(props:{?label:String, ?active:Dynamic, ?onClick:Void->Void, ?size:String, ?children:Any, ?tag:String}):View {
		var press = () -> if (props.onClick != null) props.onClick();
		var active = () -> read(props.active) == true;
		return <view tag={props.tag ?? "sidebar-menu-button"} slot="sidebar-menu-button" role="button" label={props.label} size={props.size ?? "default"}
			data-size={props.size ?? "default"} current={active} data-active={() -> active() ? "true" : null} focusable direction="row" align-items="center"
			onClick={_ -> press()} onKeyDown={e -> pressKeys(e, press)}>
			{props.children}{props.label == null ? null : <text>{props.label}</text>}
		</view>;
	}

	// a navigation menu (shadcn's, after Radix's): a row of items in a
	// navigation landmark, each a trigger whose panel (render) opens under
	// the menu, or a link (onSelect); a click, Enter, Space or Down on a
	// trigger opens its panel (its first focusable focused when by the keys),
	// the pointer moving onto another trigger while one is open opens that
	// one; Left and Right move between the items (mirrored right to left,
	// wrapping), Home and End to the ends; Escape closes the panel, the focus
	// back on its trigger; a press outside closes it. Slots
	// "navigation-menu", "navigation-menu-list", "navigation-menu-item",
	// "navigation-menu-trigger" (data-state "open" or "closed"),
	// "navigation-menu-trigger-icon", "navigation-menu-link",
	// "navigation-menu-viewport" and "navigation-menu-content" (data-state)
	@:widget({
		props: {
			items: "its items: a label, and render (a function giving its panel) or onSelect (a link)",
			open: "a signal of the open panel's index, -1 for none (its own when not given)",
			label: "its landmark's name for assistive technology (\"Main\" when not given)"
		},
		keys: {
			"Enter, Space, Down": "on a trigger: opens its panel, its first focusable focused; on a link: follows it",
			"Left, Right (mirrored right to left)": "to the item before or after, wrapping",
			"Home, End": "to the first or last item",
			"Escape": "closes the panel, the focus back on its trigger"
		}
	})
	public static function NavigationMenu(props:{items:Array<{label:String, ?render:Void->Any, ?onSelect:Void->Void}>, ?open:Signal<Int>, ?label:String,
			?tag:String}):View {
		var tag = props.tag ?? "navigation-menu", items = props.items, count = items.length;
		var open = props.open ?? signal(-1), triggers:Array<Node> = [], byKeys = false;
		function show(i:Int, keys:Bool) {
			byKeys = keys;
			open.value = i;
		}
		function key(e:Event, i:Int) {
			var it = items[i], k = mirrored(e);
			switch k {
				case Key.ENTER | Key.SPACE | Key.DOWN:
					e.preventDefault();
					if (it.render != null) show(i, true) else if (k != Key.DOWN && it.onSelect != null) it.onSelect();
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
		return <view tag={tag} slot="navigation-menu" role="navigation" label={props.label ?? "Main"} data-orientation="horizontal">
			<view slot="navigation-menu-list" role="list" direction="row" data-orientation="horizontal">{[
				for (i in 0...count) {
					var it = items[i], state = () -> open.value == i ? "open" : "closed";
					<view slot="navigation-menu-item" role="listitem">{
						it.render != null ? <view tag={tag + "-" + i} slot="navigation-menu-trigger" group="" role="button" focusable expanded={() -> open.value == i}
							data-state={state} ref={n -> triggers[i] = n} onClick={_ -> show(open.peek() == i ? -1 : i, false)}
							onPointerEnter={_ -> if (open.peek() >= 0 && open.peek() != i) show(i, false)} onKeyDown={e -> key(e, i)}>
							{it.label}{icon(CHEVRON, "navigation-menu-trigger-icon")}
						</view> : <view tag={tag + "-" + i} slot="navigation-menu-link" role="link" focusable ref={n -> triggers[i] = n}
							onClick={_ -> if (it.onSelect != null) it.onSelect()} onKeyDown={e -> key(e, i)}>{it.label}</view>
					}</view>;
				}
			]}</view>
			<Popover open={() -> open.value >= 0} placement="below" onDismiss={() -> open.value = -1} onOpen={p -> if (byKeys) {
				var f = @:privateAccess Ui.firstFocusable(p);
				if (f != null) p.ui.setFocus(f);
			}}>
				<view tag={tag + "-viewport"} slot="navigation-menu-viewport" data-state="open" onKeyDown={e -> if (e.key == Key.ESCAPE) {
					e.preventDefault();
					var i = open.peek();
					open.value = -1;
					focusIn(triggers, i);
				}}>{() -> {
					var i = open.value;
					i >= 0 && items[i].render != null ? <view tag={tag + "-content"} slot="navigation-menu-content" data-state="open">{items[i].render()}</view> : null;
				}}</view>
			</Popover>
		</view>;
	}

	// a carousel (shadcn's, after Embla): slides in a row (vertical: a
	// column) shown through a viewport, index the slide at its start (a
	// signal); Previous and Next (disabled at the ends unless loop), Left
	// and Right (vertical: Up and Down) from within it, move it, the
	// viewport easing there; scrolled by a wheel or a trackpad, the slide
	// it comes to rest nearest becomes the index. A slide is the
	// viewport's width (the theme's basis may show several). Slots
	// "carousel" (data-orientation), "carousel-content" (the viewport),
	// "carousel-track", "carousel-item", "carousel-previous" and
	// "carousel-next" (each holding its button: slot "button", variant
	// "outline", size "icon")
	@:widget({
		props: {
			slides: "its slides: views or texts, in order",
			index: "a signal of the slide shown at its start (its own when not given)",
			orientation: "horizontal (the default) or vertical",
			loop: "Next on the last goes to the first, Previous on the first to the last",
			label: "its name for assistive technology (\"Carousel\" when not given)"
		},
		keys: {
			"Left, Right": "within it: the slide before or after (vertical: Up, Down)"
		},
		variants: ["horizontal", "vertical"]
	})
	public static function Carousel(props:{slides:Array<Any>, ?index:Signal<Int>, ?orientation:String, ?loop:Bool, ?label:String, ?tag:String}):View {
		// (unstyled, a slide the viewport's size)
		Rules.addBase("carousel", [{slot: "carousel-item", style: {basis: DimValue.Percent(100), minWidth: 0, minHeight: 0}}]);
		var index = props.index ?? signal(0), tag = props.tag ?? "carousel", count = props.slides.length;
		var vertical = props.orientation == "vertical", loop = props.loop == true;
		var viewport:Null<Node> = null, settling = false;
		function go(i:Int) {
			if (count == 0) return;
			index.value = loop ? (i % count + count) % count : i < 0 ? 0 : i >= count ? count - 1 : i;
		}
		// (a slide's offset in the track: where the viewport scrolls to show it at its start)
		function offset(i:Int):Float {
			var track = viewport.children[0], item = track.children[i];
			if (vertical) return item.y;
			return viewport.rtl() ? item.x + item.width - track.width : item.x;
		}
		// (the index moved: the viewport eased to its slide; not when a scroll moved it there)
		effect(() -> {
			var i = index.value;
			if (settling || viewport == null || viewport.ui == null || i >= viewport.children[0].children.length) return;
			var d = offset(i) - (vertical ? viewport.scrollY : viewport.scrollX);
			if (d != 0) viewport.ui.scrollBy(viewport, vertical ? 0 : d, vertical ? d : 0);
		});
		// (scrolled, not easing: the nearest slide the index)
		function scrolled() {
			var n = viewport;
			if (n == null || n.ui == null || @:privateAccess n.ui.scrolls.exists(n)) return;
			var at = vertical ? n.scrollY : n.scrollX, best = -1, dist = Math.POSITIVE_INFINITY;
			for (i in 0...n.children[0].children.length) {
				var d = Math.abs(offset(i) - at);
				if (d < dist) {
					dist = d;
					best = i;
				}
			}
			if (best >= 0 && best != index.peek()) {
				settling = true;
				index.value = best;
				settling = false;
			}
		}
		// (Previous and Next: icon buttons, each in its slot for the theme to place)
		function nav(t:String, slot:String, label:String, svg:Svg, disabled:Void->Bool, action:Void->Void):View
			return <view tag={t} slot={slot} data-orientation={vertical ? "vertical" : "horizontal"} variant="outline" size="icon" role="button" label={label}
				focusable={() -> !disabled()} disabled={disabled} data-disabled={disabled} onClick={_ -> if (!disabled()) action()}
				onKeyDown={e -> pressKeys(e, () -> if (!disabled()) action())}>{icon(svg, "carousel-icon")}</view>;
		var prev = vertical ? Key.UP : Key.LEFT, next = vertical ? Key.DOWN : Key.RIGHT;
		var orientation = vertical ? "vertical" : "horizontal";
		return <view tag={tag} slot="carousel" role="group" label={props.label ?? "Carousel"} data-orientation={orientation} variant={orientation}
			onKeyDown={e -> {
				// (right to left, Left is the next slide)
				var flip = !vertical && e.target != null && e.target.rtl();
				if (e.key == prev) {
					e.preventDefault();
					go(index.peek() + (flip ? 1 : -1));
				} else if (e.key == next) {
					e.preventDefault();
					go(index.peek() + (flip ? -1 : 1));
				}
			}}>
			<scroll tag={tag + "-content"} slot="carousel-content" scrollbar-width="none" ref={n -> {
				viewport = n;
				n.onScroll = scrolled;
			}}>
				<view slot="carousel-track" direction={vertical ? "column" : "row"} data-orientation={orientation}>{[
					for (i in 0...count)
						<view tag={tag + "-" + i} slot="carousel-item" role="group" label={"Slide " + (i + 1) + " of " + count} shrink={0}
							data-orientation={orientation}>{props.slides[i]}</view>
				]}</view>
			</scroll>
			{nav(tag + "-previous", "carousel-previous", "Previous slide", vertical ? ARROW_UP : ARROW_LEFT, () -> !loop && index.value <= 0, () -> go(index.peek() - 1))}
			{nav(tag + "-next", "carousel-next", "Next slide", vertical ? ARROW_DOWN : ARROW_RIGHT, () -> !loop && index.value >= count - 1, () -> go(index.peek() + 1))}
		</view>;
	}
}

// an icon that points to the line's end (a chevron: a disclosure's, a
// breadcrumb's separator), right to left the other way (as Chromium's
// disclosure-closed marker)
private class Mirrored extends ImageNode {
	override public function paintContent(canvas:Canvas, x:Float, y:Float, width:Float, height:Float) {
		if (!rtl()) return super.paintContent(canvas, x, y, width, height);
		canvas.pushTransform(-1, 0, 0, 1, 2 * x + width, 0);
		super.paintContent(canvas, x, y, width, height);
		canvas.popTransform();
	}
}

