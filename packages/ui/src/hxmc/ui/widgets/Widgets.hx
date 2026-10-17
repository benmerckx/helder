package hxmc.ui.widgets;

import hxmc.esx.Esx;
import hxmc.esx.Markup;
import hxmc.ui.*;
import hxmc.ui.reactive.*;
import hxmc.ui.reactive.Reactive.*;
import hxmc.ui.reactive.Signal;
import hxmc.ui.reactive.Motion;
import hxmc.ui.reactive.Flow.*;

// Components for markup (import hxmc.ui.widgets.Widgets.*): built with
// hxmc.ui.reactive, styled plainly (props override the look); their
// colours and the switch's knob move with Motion's transitions
class Widgets implements Markup {
	// a button: label or children; a primary one is filled
	public static function Button(props:{?label:String, ?onClick:Void->Void, ?primary:Bool, ?children:Esx, ?tag:String}):Esx {
		var hover = signal(false), down = signal(false);
		var primary = props.primary == true;
		var bg = () -> primary ? (down.value ? "#1d4ed8" : hover.value ? "#2563eb" : "#3b82f6") : (down.value ? "#d4d4d8" : hover.value ? "#e4e4e7" : "#ffffff");
		return <view tag={props.tag ?? "button"} role="button" focusable cursor="pointer" padding="6 14" radius={6} border-width={primary ? 0 : 1} border-color="#a1a1aa" background={Motion.color(bg)}
			color={primary ? "#ffffff" : "#18181b"} align-items="center" onPointerEnter={_ -> hover.value = true}
			onPointerLeave={_ -> {
				hover.value = false;
				down.value = false;
			}} onPointerDown={_ -> down.value = true} onPointerUp={_ -> down.value = false}
			onClick={_ -> if (props.onClick != null) props.onClick()}
			onKeyDown={e -> if ((e.key == Key.ENTER || e.key == Key.SPACE) && props.onClick != null) props.onClick()}>
			{props.label}{props.children}
		</view>;
	}

	// a checkbox bound to a signal, with its label
	public static function Checkbox(props:{checked:Signal<Bool>, ?label:String, ?tag:String}):Esx {
		var toggle = () -> props.checked.value = !props.checked.value;
		return <view tag={props.tag ?? "checkbox"} role="checkbox" checked={() -> props.checked.value} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE) toggle()}>
			<view width={16} height={16} radius={4} border-width={1.5} border-color={Motion.color(() -> props.checked.value ? "#2563eb" : "#71717a")}
				background={Motion.color(() -> props.checked.value ? "#3b82f6" : "#ffffff")} align-items="center" justify="center">
				<view width={8} height={8} radius={2} background={Motion.color(() -> props.checked.value ? "#ffffff" : "#ffffff00")}/>
			</view>
			{props.label}
		</view>;
	}

	// a switch (Toggle: Flow has the control flow Switch) bound to a signal, with its label
	public static function Toggle(props:{on:Signal<Bool>, ?label:String, ?tag:String}):Esx {
		var toggle = () -> props.on.value = !props.on.value;
		return <view tag={props.tag ?? "switch"} role="switch" checked={() -> props.on.value} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE || e.key == Key.ENTER) toggle()}>
			<view width={36} height={20} radius={10} padding={2} direction="row"
				background={Motion.color(() -> props.on.value ? "#3b82f6" : "#d4d4d8")}>
				<view width={16} height={16} radius={8} background="#ffffff" shadow="0 1 2 #00000040"
					position="relative" left={Motion.transition(() -> props.on.value ? 16 : 0)}/>
			</view>
			{props.label}
		</view>;
	}

	// a slider bound to a signal: from min to max (0 to 1), in steps (0: any
	// value), width pixels wide (160); dragged, clicked, or moved with the
	// arrow keys (a step, or a twentieth), Home and End
	public static function Slider(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?label:String, ?tag:String}):Esx {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0, w = props.width ?? 160.0;
		var knob = 16.0;
		function set(v:Float) {
			v = Math.max(lo, Math.min(hi, v));
			// (to the step, without the binary fractions' noise: 0.6, not 0.6000000000000001)
			if (step > 0) v = Math.max(lo, Math.min(hi, Math.fround((lo + Math.fround((v - lo) / step) * step) * 1e9) / 1e9));
			props.value.value = v;
		}
		var frac = () -> hi > lo ? (props.value.value - lo) / (hi - lo) : 0.0;
		function at(e:Event) {
			var n = e.current;
			set(lo + (n.localX(e.x) - knob / 2) / (w - knob) * (hi - lo));
		}
		var keyStep = step > 0 ? step : (hi - lo) / 20;
		return <view tag={props.tag ?? "slider"} role="slider" label={props.label} value-now={() -> props.value.value} value-min={lo} value-max={hi}
			width={w} height={knob + 4} focusable cursor="pointer" justify="center"
			onPointerDown={e -> at(e)} onPointerMove={e -> if (e.current.pressed) at(e)}
			onKeyDown={e -> switch e.key {
				case Key.LEFT | Key.DOWN: set(props.value.value - keyStep);
				case Key.RIGHT | Key.UP: set(props.value.value + keyStep);
				case Key.HOME: set(lo);
				case Key.END: set(hi);
				case _:
			}}>
			<view height={4} radius={2} margin={[0, knob / 2]} overflow="hidden" direction="row" background="#d4d4d8">
				<view width={() -> (frac() * 100) + "%"} background="#3b82f6"/>
			</view>
			<view position="absolute" top={2} left={() -> frac() * (w - knob)} width={knob} height={knob} radius={knob / 2} background="#ffffff"
				border-width={1} border-color="#a1a1aa" shadow="0 1 2 #00000033"/>
		</view>;
	}

	// radio buttons bound to a signal: one per option (tag: the group's tag,
	// "-", the option)
	public static function Radio(props:{value:Signal<String>, options:Array<String>, ?label:String, ?tag:String}):Esx {
		var tag = props.tag ?? "radio";
		return <view tag={tag} role="radiogroup" label={props.label} row-gap={6}>{[
			for (o in props.options)
				<view tag={tag + "-" + o} role="radio" checked={() -> props.value.value == o} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> props.value.value = o}
					onKeyDown={e -> if (e.key == Key.SPACE) props.value.value = o}>
					<view width={16} height={16} radius={8} border-width={1.5} border-color={Motion.color(() -> props.value.value == o ? "#2563eb" : "#71717a")}
						align-items="center" justify="center">
						<view width={8} height={8} radius={4} background={Motion.color(() -> props.value.value == o ? "#3b82f6" : "#3b82f600")}/>
					</view>
					{o}
				</view>
		]}</view>;
	}

	// tabs: a row of labels (tag: the tabs' tag, "-", the index), the
	// selected one underlined, and what render gives for it below
	public static function Tabs(props:{labels:Array<String>, selected:Signal<Int>, render:Int->Any, ?tag:String}):Esx {
		var tag = props.tag ?? "tabs";
		return <view tag={tag} row-gap={10}>
			<view role="tablist" direction="row" column-gap={4}>{[
				for (i in 0...props.labels.length)
					<view tag={tag + "-" + i} role="tab" selected={() -> props.selected.value == i} focusable cursor="pointer" padding="6 10 0 10" row-gap={6} align-items="center"
						onClick={_ -> props.selected.value = i} onKeyDown={e -> if (e.key == Key.SPACE || e.key == Key.ENTER) props.selected.value = i}
						color={Motion.color(() -> props.selected.value == i ? "#1d4ed8" : "#52525b")}>
						{props.labels[i]}
						<view align-self="stretch" height={2} radius={1} background={Motion.color(() -> props.selected.value == i ? "#3b82f6" : "#3b82f600")}/>
					</view>
			]}</view>
			<view role="tabpanel" label={() -> props.labels[props.selected.value]}>{() -> props.render(props.selected.value)}</view>
		</view>;
	}

	// a progress bar: value from 0 to 1 (a signal, a function or a number)
	public static function Progress(props:{value:Dynamic, ?width:Float, ?label:String, ?tag:String}):Esx {
		var frac = () -> {
			var v:Float = Render.read(props.value);
			v < 0 ? 0.0 : v > 1 ? 1.0 : v;
		};
		return <view tag={props.tag ?? "progress"} role="progressbar" label={props.label} value-now={frac} value-min={0} value-max={1} width={props.width ?? 160} height={8} radius={4} overflow="hidden" direction="row" background="#e4e4e7">
			<view width={() -> (frac() * 100) + "%"} background="#3b82f6"/>
		</view>;
	}

	// a select bound to a signal: the chosen option's label (labels, else
	// the option) on a button; a click, Enter or Space opens the options
	// under it, the chosen one focused; Up and Down move through them, a
	// click, Enter or Space chooses, Escape, Tab or a click outside closes.
	// On the closed button Up and Down choose the previous or next option.
	public static function Select(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?label:String, ?tag:String}):Esx {
		var tag = props.tag ?? "select", w = props.width ?? 160.0;
		var open = signal(false);
		var items:Array<Node> = [];
		var labelOf = (v:String) -> {
			var i = props.options.indexOf(v);
			i >= 0 && props.labels != null ? props.labels[i] : v;
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
		return <view tag={tag} role="combobox" label={props.label} expanded={() -> open.value} focusable cursor="pointer" direction="row" align-items="center"
			justify="space-between" column-gap={8} width={w} padding="6 10" radius={6} border-width={1} border-color="#a1a1aa" background="#ffffff"
			onClick={_ -> open.value = !open.value}
			onKeyDown={e -> switch e.key {
				case Key.ENTER | Key.SPACE:
					open.value = true;
					e.stop();
				case Key.DOWN: step(1);
				case Key.UP: step(-1);
				case _:
			}}>
			{() -> labelOf(props.value.value)}
			<text color="#71717a" hidden>▾</text>
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={_ -> focusItem(props.options.indexOf(props.value.peek()))}>
				<view tag={tag + "-list"} role="listbox" label={props.label} min-width={w} padding={4} radius={6} border-width={1} border-color="#d4d4d8"
					background="#ffffff" shadow="0 4 12 #00000026">{[
					for (i in 0...props.options.length) {
						var o = props.options[i], hover = signal(false);
						<view tag={tag + "-" + o} role="option" selected={() -> props.value.value == o} ref={n -> items[i] = n} focusable cursor="pointer" padding="5 8"
							radius={4} background={() -> props.value.value == o ? "#dbeafe" : hover.value ? "#f4f4f5" : "#ffffff00"}
							onPointerEnter={_ -> hover.value = true} onPointerLeave={_ -> hover.value = false} onClick={_ -> choose(o)}
							onKeyDown={e -> switch e.key {
								case Key.DOWN:
									focusItem(i + 1);
									e.stop();
								case Key.UP:
									focusItem(i - 1);
									e.stop();
								case Key.ENTER | Key.SPACE:
									choose(o);
									e.stop();
								case Key.TAB: open.value = false;
								case _:
							}}>
							{props.labels != null ? props.labels[i] : o}
						</view>;
					}
				]}</view>
			</Popover>
		</view>;
	}

	// a menu button: label; a click, Enter, Space or Down opens its items
	// under it (the first focused), each a label and what choosing it does;
	// Up and Down move through them, a click, Enter or Space chooses (and
	// closes), Escape, Tab or a click outside closes
	public static function Menu(props:{label:String, items:Array<{label:String, onSelect:Void->Void}>, ?tag:String}):Esx {
		var tag = props.tag ?? "menu";
		var open = signal(false);
		var items:Array<Node> = [];
		function focusItem(i:Int)
			if (i >= 0 && i < items.length && items[i].ui != null) items[i].ui.setFocus(items[i]);
		return <view tag={tag} role="button" expanded={() -> open.value} focusable cursor="pointer" padding="6 14" radius={6} border-width={1}
			border-color="#a1a1aa" background="#ffffff" direction="row" column-gap={6} onClick={_ -> open.value = !open.value}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE || e.key == Key.DOWN) {
				open.value = true;
				e.stop();
			}}>
			{props.label}
			<text color="#71717a" hidden>▾</text>
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={_ -> focusItem(0)}>
				<view tag={tag + "-items"} role="menu" label={props.label} min-width={140} padding={4} radius={6} border-width={1} border-color="#d4d4d8"
					background="#ffffff" shadow="0 4 12 #00000026">{[
					for (i in 0...props.items.length) {
						var it = props.items[i], hover = signal(false);
						function choose() {
							open.value = false;
							it.onSelect();
						}
						<view tag={tag + "-" + i} role="menuitem" ref={n -> items[i] = n} focusable cursor="pointer" padding="5 8" radius={4}
							background={() -> hover.value ? "#f4f4f5" : "#ffffff00"} onPointerEnter={_ -> hover.value = true}
							onPointerLeave={_ -> hover.value = false} onClick={_ -> choose()}
							onKeyDown={e -> switch e.key {
								case Key.DOWN:
									focusItem(i + 1);
									e.stop();
								case Key.UP:
									focusItem(i - 1);
									e.stop();
								case Key.ENTER | Key.SPACE:
									choose();
									e.stop();
								case Key.TAB: open.value = false;
								case _:
							}}>
							{it.label}
						</view>;
					}
				]}</view>
			</Popover>
		</view>;
	}

	// a tooltip: text shown by the children (above them) once the pointer
	// has rested on them for delay seconds (0.5), hidden when it leaves or presses
	public static function Tooltip(props:{text:String, ?delay:Float, ?placement:String, ?tag:String, ?children:Any}):Esx {
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
		return <view tag={props.tag} onPointerEnter={_ -> enter()} onPointerLeave={_ -> leave()} onPointerDown={_ -> leave()}>
			{props.children}
			<Popover open={show} placement={props.placement ?? "above"} tag="tooltip">
				<view role="tooltip" padding="4 8" radius={4} background="#27272a" color="#ffffff" font-size={12}>{props.text}</view>
			</Popover>
		</view>;
	}

	// a modal dialog while open is true: title and the children on a panel
	// over the dimmed window, its first focusable node focused; Escape or a
	// click on the backdrop closes it (open set to false)
	public static function Dialog(props:{open:Signal<Bool>, title:String, ?width:Float, ?tag:String, ?children:Any}):Any
		return Popover({
			open: props.open,
			modal: true,
			backdrop: Color.rgba(0x000000, 0.4),
			onDismiss: () -> props.open.value = false,
			tag: props.tag ?? "dialog",
			children: <view role="dialog" label={props.title} width={props.width ?? 360} padding={20} row-gap={12} radius={10} background="#ffffff"
				shadow="0 10 30 #00000040">
				<text font-size={17} font-weight={600}>{props.title}</text>
				{props.children}
			</view>
		});

	// a text area bound to a signal (two ways), rows lines high (3)
	public static function Area(props:{value:Signal<String>, ?rows:Int, ?placeholder:String, ?label:String, ?tag:String}):Node {
		var f = new TextArea(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.rows = props.rows ?? 3;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, borderColor: Color.rgb(0xA1A1AA), radius: 6, background: Color.WHITE});
		f.onChange = s -> props.value.value = s;
		effect(() -> f.setText(props.value.value));
		return f;
	}

	// a text field bound to a signal (two ways)
	public static function Field(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?tag:String}):Node {
		var f = new TextField(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, borderColor: Color.rgb(0xA1A1AA), radius: 6, background: Color.WHITE});
		f.onChange = s -> props.value.value = s;
		f.onSubmit = props.onSubmit;
		effect(() -> f.setText(props.value.value));
		return f;
	}
}
