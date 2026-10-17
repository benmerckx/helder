package hxmc.web.widgets;

#if js
import hxmc.ui.Key;
import hxmc.ui.Shortcut;
import hxmc.ui.widgets.Behaviour;
import hxmc.ui.widgets.Days;
import hxmc.ui.widgets.Toasts;
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

	// a button (shadcn's): its label or children; variant "default",
	// "destructive", "outline", "secondary", "ghost" or "link", size
	// "default", "xs", "sm", "lg", "icon"...; disabled (a Bool, a signal or
	// a function of one)
	public static function Button(props:{?label:Dynamic, ?onClick:Void->Void, ?variant:String, ?size:String, ?disabled:Dynamic, ?children:View,
			?tag:String}):View
		return <button type="button" id={props.tag} data-slot="button" data-variant={props.variant ?? "default"} data-size={props.size ?? "default"}
			disabled={() -> on(props.disabled)} onClick={() -> if (props.onClick != null) props.onClick()}>{props.label}{props.children}</button>;

	// a toggle (shadcn's): a button pressed or not, bound to a signal
	public static function Toggle(props:{pressed:Signal<Bool>, ?label:String, ?variant:String, ?size:String, ?disabled:Dynamic, ?children:View,
			?tag:String}):View
		return <button type="button" id={props.tag} data-slot="toggle" data-variant={props.variant ?? "default"} data-size={props.size ?? "default"}
			aria-pressed={() -> props.pressed.value ? "true" : "false"} data-state={() -> props.pressed.value ? "on" : "off"}
			disabled={() -> on(props.disabled)} data-disabled={() -> on(props.disabled) ? "" : null}
			onClick={() -> props.pressed.value = !props.pressed.peek()}>{props.label}{props.children}</button>;

	// a checkbox (shadcn's, Radix's) bound to a signal, with its label;
	// mixed: neither checked nor not (indeterminate), checked when clicked
	public static function Checkbox(props:{checked:Signal<Bool>, ?mixed:Signal<Bool>, ?label:String, ?disabled:Dynamic, ?invalid:Dynamic,
			?tag:String}):View {
		var id = props.tag ?? Dom.id();
		var mixed = () -> props.mixed != null && props.mixed.value;
		var state = () -> mixed() ? "indeterminate" : props.checked.value ? "checked" : "unchecked";
		function toggle()
			batch(() -> {
				var was = props.mixed != null && props.mixed.peek();
				if (was) props.mixed.value = false;
				props.checked.value = was || !props.checked.peek();
			});
		var box = <button type="button" role="checkbox" id={id} data-slot="checkbox" aria-checked={() -> mixed() ? "mixed" : props.checked.value ? "true" : "false"}
			data-state={state} disabled={() -> on(props.disabled)} data-disabled={() -> on(props.disabled) ? "" : null}
			aria-invalid={() -> on(props.invalid) ? "true" : null} onClick={toggle}>
			<Show when={() -> state() != "unchecked"}>
				<span data-slot="checkbox-indicator" data-state={state} style="pointer-events:none">{() -> icon(mixed() ? "minus" : "check", "checkbox-icon")}</span>
			</Show>
		</button>;
		return props.label == null ? box : <div data-slot="checkbox-field">{box}<label data-slot="label" htmlFor={id}>{props.label}</label></div>;
	}

	// a switch (shadcn's, Radix's) bound to a signal, with its label; size "default" or "sm"
	public static function Switch(props:{checked:Signal<Bool>, ?label:String, ?disabled:Dynamic, ?size:String, ?tag:String}):View {
		var id = props.tag ?? Dom.id();
		var state = () -> props.checked.value ? "checked" : "unchecked";
		var track = <button type="button" role="switch" id={id} data-slot="switch" data-size={props.size ?? "default"}
			aria-checked={() -> props.checked.value ? "true" : "false"} data-state={state} disabled={() -> on(props.disabled)}
			data-disabled={() -> on(props.disabled) ? "" : null} onClick={() -> props.checked.value = !props.checked.peek()}>
			<span data-slot="switch-thumb" data-state={state}/>
		</button>;
		return props.label == null ? track : <div data-slot="switch-field">{track}<label data-slot="label" htmlFor={id}>{props.label}</label></div>;
	}

	// a label (shadcn's): its text or children; htmlFor: the control's id
	public static function Label(props:{?text:String, ?disabled:Dynamic, ?children:Any, ?htmlFor:String, ?tag:String}):View
		return <label id={props.tag} data-slot="label" htmlFor={props.htmlFor} data-disabled={() -> on(props.disabled) ? "true" : null}>{props.children ?? props.text}</label>;

	// a badge (shadcn's): variant "default", "secondary", "destructive", "outline", "ghost", "link"
	public static function Badge(props:{?label:String, ?variant:String, ?children:View, ?tag:String}):View
		return <span id={props.tag} data-slot="badge" data-variant={props.variant ?? "default"}>{props.label}{props.children}</span>;

	// a card (shadcn's) and its parts
	public static function Card(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="card">{props.children}</div>;

	public static function CardHeader(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="card-header">{props.children}</div>;

	public static function CardTitle(props:{?text:String, ?children:Any, ?tag:String}):View
		return <div id={props.tag} data-slot="card-title">{props.children ?? props.text}</div>;

	public static function CardDescription(props:{?text:String, ?children:Any, ?tag:String}):View
		return <div id={props.tag} data-slot="card-description">{props.children ?? props.text}</div>;

	public static function CardAction(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="card-action">{props.children}</div>;

	public static function CardContent(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="card-content">{props.children}</div>;

	public static function CardFooter(props:{?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="card-footer">{props.children}</div>;

	// a separator (shadcn's, Radix's): horizontal or vertical; decorative (the default) or not
	public static function Separator(props:{?orientation:String, ?decorative:Bool, ?tag:String}):View {
		var o = props.orientation ?? "horizontal";
		return <div id={props.tag} data-slot="separator" data-orientation={o} role={props.decorative == false ? "separator" : "none"}
			aria-orientation={props.decorative == false && o == "vertical" ? "vertical" : null}/>;
	}

	// a skeleton (shadcn's): a placeholder of a size (pixels or CSS), else its children's
	public static function Skeleton(props:{?width:Dynamic, ?height:Dynamic, ?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="skeleton" style={{width: props.width, height: props.height}}>{props.children}</div>;

	// an alert (shadcn's): variant "default" or "destructive"; its title and description
	public static function Alert(props:{?variant:String, ?children:View, ?tag:String}):View
		return <div id={props.tag} data-slot="alert" role="alert" data-variant={props.variant ?? "default"}>{props.children}</div>;

	public static function AlertTitle(props:{?text:String, ?children:Any, ?tag:String}):View
		return <div id={props.tag} data-slot="alert-title">{props.children ?? props.text}</div>;

	public static function AlertDescription(props:{?text:String, ?children:Any, ?tag:String}):View
		return <div id={props.tag} data-slot="alert-description">{props.children ?? props.text}</div>;

	// a key or keys (shadcn's Kbd)
	public static function Kbd(props:{?text:String, ?children:Any, ?tag:String}):View
		return <kbd id={props.tag} data-slot="kbd">{props.children ?? props.text}</kbd>;

	// a spinner (shadcn's): a loading circle turning (the theme's animate-spin)
	public static function Spinner(props:{?label:String, ?tag:String}):Any {
		var svg = icon("loader", "spinner");
		svg.setAttribute("role", "status");
		svg.setAttribute("aria-label", props.label ?? "Loading");
		svg.removeAttribute("aria-hidden");
		if (props.tag != null) svg.id = props.tag;
		return svg;
	}

	// an avatar (shadcn's): an image, else its fallback (initials)
	public static function Avatar(props:{?src:Dynamic, fallback:String, ?label:String, ?size:String, ?tag:String}):View
		return <span id={props.tag} data-slot="avatar" data-size={props.size ?? "default"} role="img" aria-label={props.label ?? props.fallback}>
			{() -> read(props.src) == null ? <span data-slot="avatar-fallback">{props.fallback}</span> : <img data-slot="avatar-image" src={read(props.src)} alt=""/>}
		</span>;

	// (a key event's key, mirrored where its element is right to left)
	static function keyOf(e:KeyboardEvent):Int
		return Behaviour.mirror(Dom.key(e), Dom.rtl(cast e.currentTarget));

	// (focuses els[i] when there is one)
	static function focusIn(els:Array<Element>, i:Int)
		if (i >= 0 && i < els.length) Dom.focus(els[i]);

	// a radio group (shadcn's, Radix's) bound to a signal: a radio button
	// per option, labelled (labels, else the option); one Tab stop (the
	// checked one, else the first), the arrows checking and focusing the
	// next or previous (wrapping)
	public static function RadioGroup(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?disabled:Dynamic, ?label:String,
			?tag:String}):View {
		var options = props.options, items:Array<Element> = [], base = props.tag ?? Dom.id();
		function stop(i:Int):Bool {
			var k = options.indexOf(props.value.value);
			return i == (k < 0 ? 0 : k);
		}
		function key(e:KeyboardEvent, i:Int) {
			if (on(props.disabled)) return;
			var k = keyOf(e), j = k == Key.SPACE ? i : Behaviour.rove(k, i, options.length);
			if (j < 0 || k == Key.HOME || k == Key.END) return;
			e.preventDefault();
			props.value.value = options[j];
			focusIn(items, j);
		}
		return <div id={props.tag} role="radiogroup" data-slot="radio-group" aria-label={props.label} data-disabled={() -> on(props.disabled) ? "" : null}>{[
			for (i in 0...options.length) {
				var o = options[i], id = base + "-" + i, text = props.labels != null && props.labels[i] != null ? props.labels[i] : o;
				var state = () -> props.value.value == o ? "checked" : "unchecked";
				<div data-slot="radio-group-option">
					<button type="button" role="radio" id={id} data-slot="radio-group-item" ref={n -> items[i] = cast n} aria-checked={() -> state() == "checked" ? "true" : "false"}
						data-state={state} tabindex={() -> stop(i) ? 0 : -1} disabled={() -> on(props.disabled)} data-disabled={() -> on(props.disabled) ? "" : null}
						onClick={() -> props.value.value = o} onKeyDown={(e:KeyboardEvent) -> key(e, i)}>
						<Show when={() -> state() == "checked"}><span data-slot="radio-group-indicator" data-state="checked">{() -> icon("circle", "radio-group-icon", true)}</span></Show>
					</button>
					<label data-slot="label" htmlFor={id}>{text}</label>
				</div>;
			}
		]}</div>;
	}

	// a slider (shadcn's, Radix's) bound to a signal: from min to max (0 to
	// 1), in steps (0: any value); dragged, clicked, or moved with the arrow
	// keys, Home and End; width: the slider's (pixels), else its theme's
	public static function Slider(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?disabled:Dynamic, ?label:String,
			?tag:String}):View {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0;
		var pct = () -> hi > lo ? (props.value.value - lo) / (hi - lo) * 100 : 0.0;
		var thumb:Element = null;
		return rail(props.tag, props.width, props.disabled, v -> {
			var x = Behaviour.snap(lo + v * (hi - lo), lo, hi, step);
			props.value.value = x;
			Dom.focus(thumb);
		}, () -> 0, [
			View.view(<span data-slot="slider-range" data-orientation="horizontal" style={() -> 'left:0%;right:${100 - pct()}%'}/>)
		], [
			View.view(<span style={() -> 'transform:translateX(-50%);position:absolute;left:calc(${pct()}% + ${8 - pct() * 0.16}px)'}>
				<span data-slot="slider-thumb" role="slider" ref={n -> thumb = cast n} tabindex={() -> on(props.disabled) ? null : 0} aria-label={props.label}
					aria-valuemin={lo} aria-valuemax={hi} aria-valuenow={props.value} aria-orientation="horizontal" data-orientation="horizontal"
					data-disabled={() -> on(props.disabled) ? "" : null} onKeyDown={(e:KeyboardEvent) -> if (!on(props.disabled)) {
						var v = Behaviour.slide(keyOf(e), props.value.peek(), lo, hi, step);
						if (v != null) {
							e.preventDefault();
							props.value.value = v;
						}
					}}/>
			</span>)
		]);
	}

	// (a slider's root and track; set: a press or drag at a fraction along it, the knob it moves (pick))
	static function rail(tag:Null<String>, width:Null<Float>, disabled:Dynamic, set:Float->Void, pick:Void->Int, track:Array<View>, thumbs:Array<View>):View {
		var root:Element = null, dragging = false;
		function at(e:Dynamic) {
			var r = root.getBoundingClientRect(), f = r.width > 0 ? (e.clientX - r.left) / r.width : 0;
			if (Dom.rtl(root)) f = 1 - f;
			set(Math.max(0, Math.min(1, f)));
		}
		return <span id={tag} data-slot="slider" data-orientation="horizontal" ref={n -> root = cast n} style={width == null ? null : 'width:${width}px'}
			data-disabled={() -> on(disabled) ? "" : null} aria-disabled={() -> on(disabled) ? "true" : null}
			onPointerDown={(e:Dynamic) -> if (!on(disabled) && e.button == 0) {
				dragging = true;
				root.setPointerCapture(e.pointerId);
				e.preventDefault();
				at(e);
			}} onPointerMove={(e:Dynamic) -> if (dragging) at(e)} onPointerUp={() -> dragging = false}>
			<span data-slot="slider-track" data-orientation="horizontal">{track}</span>
			{thumbs}
		</span>;
	}

	// a range slider: two knobs on one track, low no more than high; a press
	// moves the nearer knob (then drags it) and focuses it
	public static function RangeSlider(props:{low:Signal<Float>, high:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?label:String,
			?tag:String}):View {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0, name = props.label ?? "Range";
		var knobs:Array<Element> = [], dragging = -1;
		var pct = (v:Float) -> hi > lo ? (v - lo) / (hi - lo) * 100 : 0.0;
		function set(k:Int, v:Float) {
			v = Behaviour.snap(v, lo, hi, step);
			if (k == 0) props.low.value = Math.min(v, props.high.peek()) else props.high.value = Math.max(v, props.low.peek());
		}
		function knob(k:Int):View {
			var value = k == 0 ? props.low : props.high;
			return <span style={() -> 'transform:translateX(-50%);position:absolute;left:calc(${pct(value.value)}% + ${8 - pct(value.value) * 0.16}px)'}>
				<span data-slot="slider-thumb" role="slider" tabindex="0" ref={n -> knobs[k] = cast n} aria-label={name + (k == 0 ? ": minimum" : ": maximum")}
					aria-valuenow={value} aria-valuemin={() -> k == 0 ? lo : props.low.value} aria-valuemax={() -> k == 0 ? props.high.value : hi}
					aria-orientation="horizontal" data-orientation="horizontal" onKeyDown={(e:KeyboardEvent) -> {
						var v = Behaviour.slide(keyOf(e), value.peek(), lo, hi, step);
						if (v != null) {
							e.preventDefault();
							set(k, v);
						}
					}}/>
			</span>;
		}
		return <div role="group" aria-label={name}>{rail(props.tag, props.width, false, f -> {
			var v = lo + f * (hi - lo);
			if (dragging < 0) {
				var dl = Math.abs(v - props.low.peek()), dh = Math.abs(v - props.high.peek());
				dragging = dl < dh || (dl == dh && v < props.low.peek()) ? 0 : 1;
				window.addEventListener("pointerup", () -> dragging = -1, {once: true});
			}
			set(dragging, v);
			Dom.focus(knobs[dragging]);
		}, () -> dragging, [
			View.view(<span data-slot="slider-range" data-orientation="horizontal" style={() -> 'left:${pct(props.low.value)}%;right:${100 - pct(props.high.value)}%'}/>)
		], [knob(0), knob(1)])}</div>;
	}

	// tabs (shadcn's, Radix's): a row of labels and what render gives for
	// the selected one; one Tab stop, Left and Right (the way they point,
	// wrapping), Home and End select another and move the focus there;
	// variant "default" or "line"
	public static function Tabs(props:{labels:Array<String>, selected:Signal<Int>, render:Int->Any, ?variant:String, ?tag:String}):View {
		var count = props.labels.length, tabs:Array<Element> = [], base = props.tag ?? Dom.id();
		function key(e:KeyboardEvent, i:Int) {
			var k = keyOf(e), j = k == Key.SPACE || k == Key.ENTER ? i : Behaviour.rove(k, i, count, false);
			if (j < 0) return;
			e.preventDefault();
			props.selected.value = j;
			focusIn(tabs, j);
		}
		return <div id={props.tag} data-slot="tabs" data-orientation="horizontal">
			<div role="tablist" aria-orientation="horizontal" data-slot="tabs-list" data-variant={props.variant ?? "default"} data-orientation="horizontal">{[
				for (i in 0...count)
					<button type="button" role="tab" id={base + "-t" + i} aria-controls={base + "-p"} ref={n -> tabs[i] = cast n} data-slot="tabs-trigger"
						aria-selected={() -> props.selected.value == i ? "true" : "false"} data-state={() -> props.selected.value == i ? "active" : "inactive"}
						data-orientation="horizontal" tabindex={() -> props.selected.value == i ? 0 : -1} onClick={() -> props.selected.value = i}
						onKeyDown={(e:KeyboardEvent) -> key(e, i)}>{props.labels[i]}</button>
			]}</div>
			<div role="tabpanel" id={base + "-p"} aria-labelledby={() -> base + "-t" + props.selected.value} data-slot="tabs-content" data-state="active"
				data-orientation="horizontal" tabindex="0">{() -> props.render(props.selected.value)}</div>
		</div>;
	}

	// a progress bar (shadcn's, Radix's): value from 0 to 1; null: not known (a bar sliding across)
	public static function Progress(props:{value:Dynamic, ?width:Float, ?label:String, ?tag:String}):View {
		var known = () -> read(props.value) != null;
		var frac = () -> {
			var v:Null<Float> = read(props.value);
			v == null ? 0.0 : v < 0 ? 0.0 : v > 1 ? 1.0 : v;
		};
		return <div id={props.tag} data-slot="progress" role="progressbar" aria-label={props.label} aria-valuemin="0" aria-valuemax="100"
			aria-valuenow={() -> known() ? Math.round(frac() * 100) : null} data-state={() -> known() ? (frac() >= 1 ? "complete" : "loading") : "indeterminate"}
			style={props.width == null ? null : 'width:${props.width}px'}>
			{() -> known() ? <div data-slot="progress-indicator" style={() -> 'transform:translateX(-${100 - frac() * 100}%)'}/> : <div
				data-slot="progress-indicator" data-state="indeterminate" style="position:absolute;width:40%"
				ref={n -> (cast n).animate([{left: "-40%"}, {left: "100%"}], {duration: 1500, iterations: Math.POSITIVE_INFINITY})}/>}
		</div>;
	}

	// a toggle group (shadcn's, Radix's): one of options chosen among joined
	// toggles (one Tab stop, the chosen one; the arrows, Home and End choose
	// another); variant "default" or "outline", size "default", "sm" or "lg"
	public static function ToggleGroup(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?variant:String, ?size:String,
			?label:String, ?tag:String}):View {
		var variant = props.variant ?? "default", size = props.size ?? "default", options = props.options, items:Array<Element> = [];
		function stop(i:Int):Bool {
			var k = options.indexOf(props.value.value);
			return i == (k < 0 ? 0 : k);
		}
		return <div id={props.tag} role="group" data-slot="toggle-group" aria-label={props.label} data-variant={variant} data-size={size} data-spacing="0" style="--gap:0">{[
			for (i in 0...options.length) {
				var o = options[i], sel = () -> props.value.value == o;
				<button type="button" role="radio" data-slot="toggle-group-item" ref={n -> items[i] = cast n} data-variant={variant} data-size={size} data-spacing="0"
					aria-checked={() -> sel() ? "true" : "false"} data-state={() -> sel() ? "on" : "off"} tabindex={() -> stop(i) ? 0 : -1}
					onClick={() -> props.value.value = o} onKeyDown={(e:KeyboardEvent) -> {
						var k = keyOf(e), j = k == Key.SPACE || k == Key.ENTER ? i : Behaviour.rove(k, i, options.length);
						if (j >= 0) {
							e.preventDefault();
							props.value.value = options[j];
							focusIn(items, j);
						}
					}}>{props.labels != null && props.labels[i] != null ? props.labels[i] : o}</button>;
			}
		]}</div>;
	}

	// a collapsible (shadcn's): its label on a button (an arrow turning with it) showing or hiding the children
	public static function Collapsible(props:{label:String, ?open:Signal<Bool>, ?tag:String, ?children:Any}):View {
		var open = props.open ?? signal(false), base = props.tag ?? Dom.id(), state = () -> open.value ? "open" : "closed";
		return <div id={props.tag} data-slot="collapsible" data-state={state}>
			<button type="button" data-slot="collapsible-trigger" aria-controls={base + "-c"} aria-expanded={() -> open.value ? "true" : "false"} data-state={state}
				onClick={() -> open.value = !open.peek()}><span data-slot="collapsible-icon" aria-hidden="true">{() -> open.value ? "▾" : "▸"}</span>{props.label}</button>
			<Show when={open}><div id={base + "-c"} data-slot="collapsible-content" data-state="open">{props.children}</div></Show>
		</div>;
	}

	// an accordion (shadcn's, Radix's): sections, at most one open (open: its index, -1 none)
	public static function Accordion(props:{sections:Array<{label:String, render:Void->Any}>, ?open:Signal<Int>, ?tag:String}):View {
		var open = props.open ?? signal(-1), base = props.tag ?? Dom.id();
		return <div id={props.tag} data-slot="accordion" data-orientation="vertical">{[
			for (i in 0...props.sections.length) {
				var s = props.sections[i], state = () -> open.value == i ? "open" : "closed";
				<div data-slot="accordion-item" data-state={state} data-orientation="vertical">
					<h3 data-orientation="vertical" data-state={state} style="display:flex">
						<button type="button" id={base + "-t" + i} aria-controls={base + "-c" + i} aria-expanded={() -> open.value == i ? "true" : "false"} data-state={state}
							data-orientation="vertical" data-slot="accordion-trigger" onClick={() -> open.value = open.peek() == i ? -1 : i}>
							{s.label}{icon("chevron-down", "accordion-trigger-icon")}
						</button>
					</h3>
					<Show when={() -> open.value == i}><div id={base + "-c" + i} role="region" aria-labelledby={base + "-t" + i} data-slot="accordion-content"
						data-state="open" data-orientation="vertical">{s.render()}</div></Show>
				</div>;
			}
		]}</div>;
	}

	// a breadcrumb (shadcn's): the path, each step but the last a link (onSelect with its index), the last the current page
	public static function Breadcrumb(props:{items:Array<String>, onSelect:Int->Void, ?label:String, ?tag:String}):View {
		var items = props.items;
		return <nav id={props.tag} aria-label={props.label ?? "breadcrumb"} data-slot="breadcrumb"><ol data-slot="breadcrumb-list">{[
			for (i in 0...items.length)
				i == items.length - 1 ? View.view(<li data-slot="breadcrumb-item"><span data-slot="breadcrumb-page" role="link" aria-disabled="true"
					aria-current="page">{items[i]}</span></li>) : View.view(<>
					<li data-slot="breadcrumb-item"><a data-slot="breadcrumb-link" href="#" onClick={(e:Dynamic) -> {
						e.preventDefault();
						props.onSelect(i);
					}}>{items[i]}</a></li>
					<li data-slot="breadcrumb-separator" role="presentation" aria-hidden="true">{icon("chevron-right")}</li>
				</>)
		]}</ol></nav>;
	}

	// pagination (shadcn's): Previous, the pages (the first, the last, the
	// current one and its neighbours, an ellipsis for the rest), Next; pages from 1
	public static function Pagination(props:{page:Signal<Int>, count:Int, ?label:String, ?tag:String}):View {
		function go(p:Int)
			if (p >= 1 && p <= props.count) props.page.value = p;
		function edge(prev:Bool):View
			return <li data-slot="pagination-item"><a data-slot={prev ? "pagination-previous" : "pagination-next"} data-variant="ghost" data-size="default" href="#"
				aria-label={prev ? "Go to previous page" : "Go to next page"}
				aria-disabled={() -> (prev ? props.page.value <= 1 : props.page.value >= props.count) ? "true" : null}
				onClick={(e:Dynamic) -> {
					e.preventDefault();
					go(props.page.peek() + (prev ? -1 : 1));
				}}>{prev ? [icon("chevron-left"), View.view(<span>Previous</span>)] : [View.view(<span>Next</span>), icon("chevron-right")]}</a></li>;
		return <nav id={props.tag} role="navigation" aria-label={props.label ?? "pagination"} data-slot="pagination"><ul data-slot="pagination-content">
			{edge(true)}
			<Index each={() -> Behaviour.pages(props.page.value, props.count)} render={(p:Signal<Int>, _) -> <li data-slot="pagination-item">
				<Show when={() -> p.value == 0} fallback={<a data-slot="pagination-link" data-variant="ghost" data-size="icon" href="#"
					aria-current={() -> props.page.value == p.value ? "page" : null} data-active={() -> props.page.value == p.value ? "true" : null}
					onClick={(e:Dynamic) -> {
						e.preventDefault();
						go(p.peek());
					}}>{p}</a>}><span data-slot="pagination-ellipsis" aria-hidden="true">{icon("more")}</span></Show>
			</li>}/>
			{edge(false)}
		</ul></nav>;
	}

	// an input (shadcn's): a text field bound to a signal (two ways);
	// password: its text as dots; invalid: aria-invalid; disabled
	public static function Input(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?password:Bool,
			?invalid:Dynamic, ?disabled:Dynamic, ?type:String, ?tag:String}):View
		return <input id={props.tag} data-slot="input" type={props.password == true ? "password" : props.type ?? "text"} value={props.value}
			placeholder={props.placeholder} aria-label={props.label} aria-invalid={() -> on(props.invalid) ? "true" : null}
			disabled={() -> on(props.disabled)} onInput={(e:Dynamic) -> props.value.value = e.target.value}
			onKeyDown={(e:KeyboardEvent) -> if (e.key == "Enter" && props.onSubmit != null) props.onSubmit(props.value.peek())}/>;

	// a textarea (shadcn's) bound to a signal (two ways), rows lines high
	public static function Textarea(props:{value:Signal<String>, ?rows:Int, ?placeholder:String, ?label:String, ?invalid:Dynamic, ?disabled:Dynamic,
			?tag:String}):View
		return <textarea id={props.tag} data-slot="textarea" rows={props.rows} value={props.value} placeholder={props.placeholder}
			aria-label={props.label} aria-invalid={() -> on(props.invalid) ? "true" : null} disabled={() -> on(props.disabled)}
			onInput={(e:Dynamic) -> props.value.value = e.target.value}/>;
}
#end
