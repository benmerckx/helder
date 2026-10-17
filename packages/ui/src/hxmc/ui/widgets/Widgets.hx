package hxmc.ui.widgets;

import hxmc.ui.*;
import hxmc.view.*;
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
typedef TreeRow<T> = {item:T, level:Int, parent:Int, leaf:Bool, open:Bool};

// Components for markup (import hxmc.ui.widgets.Widgets.*): built with
// hxmc.view, styled plainly (props override the look), in
// Theme.current's colours; their colours and the switch's knob move with
// Motion's transitions
class Widgets implements Markup {
	// (the theme: read inside reactive values, so that they follow it)
	static inline function t():Theme
		return Theme.current.value;

	// a button: label or children; a primary one is filled
	public static function Button(props:{?label:String, ?onClick:Void->Void, ?primary:Bool, ?children:View, ?tag:String}):View {
		var hover = signal(false), down = signal(false);
		var primary = props.primary == true;
		var bg = () -> primary ? (down.value ? t().accentPressed : hover.value ? t().accentHover : t().accent) : (down.value ? t().controlPressed : hover.value ? t().controlHover : t().control);
		return <view tag={props.tag ?? "button"} role="button" focusable cursor="pointer" padding="6 14" radius={6} border-width={primary ? 0 : 1} border-color={() -> t().border} background={Motion.color(bg)}
			color={() -> primary ? t().onAccent : t().text} align-items="center" onPointerEnter={_ -> hover.value = true}
			onPointerLeave={_ -> {
				hover.value = false;
				down.value = false;
			}} onPointerDown={_ -> down.value = true} onPointerUp={_ -> down.value = false}
			onClick={_ -> if (props.onClick != null) props.onClick()}
			onKeyDown={e -> if ((e.key == Key.ENTER || e.key == Key.SPACE) && props.onClick != null) {
				e.preventDefault();
				props.onClick();
			}}>
			{props.label}{props.children}
		</view>;
	}

	// a checkbox bound to a signal, with its label; while mixed is true,
	// neither checked nor not (a dash; ARIA's mixed), checked when clicked
	public static function Checkbox(props:{checked:Signal<Bool>, ?mixed:Signal<Bool>, ?label:String, ?tag:String}):View {
		var mixed = () -> props.mixed != null && props.mixed.value;
		// (mixed: checked once clicked)
		var toggle = () -> batch(() -> {
			var was = props.mixed != null && props.mixed.peek();
			if (was) props.mixed.value = false;
			props.checked.value = was || !props.checked.peek();
		});
		return <view tag={props.tag ?? "checkbox"} role="checkbox" checked={() -> mixed() ? ("mixed" : Dynamic) : props.checked.value} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE) {
				e.preventDefault();
				toggle();
			}}>
			<view width={16} height={16} radius={4} border-width={1.5} border-color={Motion.color(() -> props.checked.value || mixed() ? t().accentHover : t().mark)}
				background={Motion.color(() -> props.checked.value || mixed() ? t().accent : t().control)} align-items="center" justify="center">
				<view width={8} height={() -> mixed() ? 2 : 8} radius={() -> mixed() ? 1 : 2}
					background={Motion.color(() -> props.checked.value || mixed() ? t().onAccent : Theme.clear(t().onAccent))}/>
			</view>
			{props.label}
		</view>;
	}

	// a switch (Toggle: Flow has the control flow Switch) bound to a signal, with its label
	public static function Toggle(props:{on:Signal<Bool>, ?label:String, ?tag:String}):View {
		var toggle = () -> props.on.value = !props.on.value;
		return <view tag={props.tag ?? "switch"} role="switch" checked={() -> props.on.value} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE || e.key == Key.ENTER) {
				e.preventDefault();
				toggle();
			}}>
			<view width={36} height={20} radius={10} padding={2} direction="row"
				background={Motion.color(() -> props.on.value ? t().accent : t().track)}>
				<view width={Motion.transition(() -> props.on.value ? 16 : 0)}/>
				<view width={16} height={16} radius={8} background={() -> t().knob} shadow="0 1 2 #00000040"/>
			</view>
			{props.label}
		</view>;
	}

	// a slider bound to a signal: from min to max (0 to 1), in steps (0: any
	// value), width pixels wide (160); dragged, clicked, or moved with the
	// arrow keys (a step, or a twentieth), Home and End
	public static function Slider(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?label:String, ?tag:String}):View {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0, w = props.width ?? 160.0;
		var knob = 16.0;
		function set(v:Float) {
			v = Math.max(lo, Math.min(hi, v));
			// (to the step, without the binary fractions' noise: 0.6, not 0.6000000000000001)
			if (step > 0) v = Math.max(lo, Math.min(hi, Math.fround((lo + Math.fround((v - lo) / step) * step) * 1e9) / 1e9));
			props.value.value = v;
		}
		var frac = () -> hi > lo ? (props.value.value - lo) / (hi - lo) : 0.0;
		// (right to left: the minimum at the right)
		function at(e:Event) {
			var n = e.current, x = n.localX(e.x, e.y);
			if (n.rtl()) x = w - x;
			set(lo + (x - knob / 2) / (w - knob) * (hi - lo));
		}
		var keyStep = step > 0 ? step : (hi - lo) / 20;
		return <view tag={props.tag ?? "slider"} role="slider" label={props.label} value-now={() -> props.value.value} value-min={lo} value-max={hi}
			width={w} height={knob + 4} focusable cursor="pointer" justify="center"
			onPointerDown={e -> at(e)} onPointerMove={e -> if (e.current.pressed) at(e)}
			onKeyDown={e -> switch e.key {
				case Key.LEFT | Key.DOWN | Key.RIGHT | Key.UP:
					e.preventDefault();
					var less = e.key == Key.DOWN || (e.key == Key.LEFT) != e.current.rtl();
					set(props.value.value + (less ? -keyStep : keyStep));
				case Key.HOME:
					e.preventDefault();
					set(lo);
				case Key.END:
					e.preventDefault();
					set(hi);
				case _:
			}}>
			<view height={4} radius={2} margin={[0, knob / 2]} overflow="hidden" direction="row" background={() -> t().track}>
				<view width={() -> (frac() * 100) + "%"} background={() -> t().accent}/>
			</view>
			<view position="absolute" top={2} left={0} width={w} direction="row">
				<view width={() -> frac() * (w - knob)}/>
				<view width={knob} height={knob} radius={knob / 2} background={() -> t().knob} border-width={1} border-color={() -> t().border}
					shadow="0 1 2 #00000033"/>
			</view>
		</view>;
	}

	// a range slider: two knobs on one track, the range between them filled,
	// low no more than high; a press moves the nearer knob (then drags it)
	// and focuses it, each knob a slider for the keyboard and assistive
	// technology (Left and Down lower it, Right and Up raise it, Home and End
	// to its bounds, as far as the other knob)
	public static function RangeSlider(props:{low:Signal<Float>, high:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?label:String,
			?tag:String}):View {
		var lo = props.min ?? 0.0, hi = props.max ?? 1.0, step = props.step ?? 0.0, w = props.width ?? 160.0, tag = props.tag ?? "range";
		var knob = 16.0, dragging = -1, name = props.label ?? "Range", knobs:Array<Node> = [];
		function snap(v:Float):Float {
			v = Math.max(lo, Math.min(hi, v));
			return step > 0 ? Math.max(lo, Math.min(hi, Math.fround((lo + Math.fround((v - lo) / step) * step) * 1e9) / 1e9)) : v;
		}
		// (k: 0 the low knob, 1 the high one, each kept on its side of the other)
		function set(k:Int, v:Float) {
			v = snap(v);
			if (k == 0) props.low.value = Math.min(v, props.high.peek()) else props.high.value = Math.max(v, props.low.peek());
		}
		var frac = (v:Float) -> hi > lo ? (v - lo) / (hi - lo) : 0.0;
		// (right to left: the minimum at the right)
		function valueAt(e:Event):Float {
			var n = e.current, x = n.localX(e.x, e.y);
			if (n.rtl()) x = w - x;
			return lo + (x - knob / 2) / (w - knob) * (hi - lo);
		}
		var keyStep = step > 0 ? step : (hi - lo) / 20;
		// (a knob in a row the width of the track, after a spacer: mirrored right to left as the row is)
		function thumb(k:Int):View {
			var value = k == 0 ? props.low : props.high;
			return <view position="absolute" top={2} left={0} width={w} direction="row" pointer-events="none">
				<view width={() -> frac(value.value) * (w - knob)}/>
				<view tag={tag + (k == 0 ? "-low" : "-high")} role="slider" label={name + (k == 0 ? ": minimum" : ": maximum")} ref={n -> knobs[k] = n}
					value-now={() -> value.value} value-min={() -> k == 0 ? lo : props.low.value} value-max={() -> k == 0 ? props.high.value : hi}
					width={knob} height={knob} radius={knob / 2} focusable pointer-events="auto" background={() -> t().knob} border-width={1}
					border-color={() -> t().border} shadow="0 1 2 #00000033"
					onKeyDown={e -> switch e.key {
						case Key.LEFT | Key.DOWN | Key.RIGHT | Key.UP:
							e.preventDefault();
							var less = e.key == Key.DOWN || (e.key == Key.LEFT) != e.current.rtl();
							set(k, value.peek() + (less ? -keyStep : keyStep));
						case Key.HOME:
							e.preventDefault();
							set(k, lo);
						case Key.END:
							e.preventDefault();
							set(k, hi);
						case _:
					}}/>
			</view>;
		}
		return <view tag={tag} role="group" label={name} width={w} height={knob + 4} cursor="pointer" justify="center"
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
			<view height={4} radius={2} margin={[0, knob / 2]} direction="row" background={() -> t().track}>
				<view width={() -> frac(props.low.value) * (w - knob)}/>
				<view radius={2} background={() -> t().accent} width={() -> (frac(props.high.value) - frac(props.low.value)) * (w - knob)}/>
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
	public static function ColorPicker(props:{value:Signal<Color>, ?size:Float, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "color", size = props.size ?? 160.0, name = props.label ?? "Colour";
		var hue = signal(0.0), sat = signal(0.0), val = signal(0.0), hex = signal("");
		// (from the value: the hue kept where a grey has none)
		function load(c:Color) {
			var r = c.r / 255, g = c.g / 255, b = c.b / 255;
			var max = Math.max(r, Math.max(g, b)), d = max - Math.min(r, Math.min(g, b));
			batch(() -> {
				if (d > 0) {
					var h = max == r ? (g - b) / d : max == g ? (b - r) / d + 2 : (r - g) / d + 4;
					hue.value = (h * 60 + 360) % 360;
				}
				sat.value = max == 0 ? 0 : d / max;
				val.value = max;
			});
		}
		function store() {
			var c = hsv(hue.peek(), sat.peek(), val.peek());
			if (c != props.value.peek()) props.value.value = c;
		}
		effect(() -> {
			var c = props.value.value;
			untrack(() -> {
				if (hsv(hue.peek(), sat.peek(), val.peek()) != c) load(c);
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
		return <view tag={tag} role="group" label={name} row-gap={8} width={size}>
			<view tag={tag + "-area"} role="slider" label={name + ": saturation and brightness"} value-now={() -> pct(sat.value)} value-min={0} value-max={100}
				value-text={() -> "saturation " + pct(sat.value) + "%, brightness " + pct(val.value) + "%"} width={size} height={size} radius={4} focusable
				cursor="crosshair" background-image={() -> "linear-gradient(to right, #FFFFFF, " + hsv(hue.value, 1, 1).toHex().substr(0, 7) + ")"}
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
				<view position="absolute" left={0} top={0} right={0} bottom={0} radius={4} background-image="linear-gradient(to bottom, transparent, #000000)"/>
				<view position="absolute" left={() -> sat.value * size - 6} top={() -> (1 - val.value) * size - 6} width={12} height={12} radius={6}
					border-width={2} border-color="#FFFFFF" shadow="0 0 2 #00000099"/>
			</view>
			<view tag={tag + "-hue"} role="slider" label={name + ": hue"} value-now={() -> Math.round(hue.value)} value-min={0} value-max={359}
				value-text={() -> Math.round(hue.value) + "°"} width={size} height={14} radius={7} focusable cursor="pointer" background-image={spectrum}
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
				<view position="absolute" left={() -> hue.value / 360 * size - 7} top={0} width={14} height={14} radius={7} border-width={2} border-color="#FFFFFF"
					shadow="0 0 2 #00000099" background={() -> hsv(hue.value, 1, 1)}/>
			</view>
			<view direction="row" column-gap={8} align-items="center">
				<view tag={tag + "-swatch"} width={28} height={28} shrink={0} radius={6} border-width={1} border-color={() -> t().border}
					background={() -> props.value.value}/>
				<view grow={1} dir="ltr"><Field tag={tag + "-hex"} value={hex} label={name + ": hex"}/></view>
			</view>
		</view>;
	}

	// (an opaque colour from a hue in degrees, saturation and value from 0 to 1)
	static function hsv(h:Float, s:Float, v:Float):Color {
		var c = v * s, p = (h / 60) % 6, x = c * (1 - Math.abs(p % 2 - 1)), m = v - c;
		var r = 0.0, g = 0.0, b = 0.0;
		if (p < 1) {
			r = c;
			g = x;
		} else if (p < 2) {
			r = x;
			g = c;
		} else if (p < 3) {
			g = c;
			b = x;
		} else if (p < 4) {
			g = x;
			b = c;
		} else if (p < 5) {
			r = x;
			b = c;
		} else {
			r = c;
			b = x;
		}
		return Color.fromFloats(r + m, g + m, b + m);
	}

	// radio buttons bound to a signal: one per option (tag: the group's tag,
	// "-", the option); one stop for Tab (the checked one, else the first),
	// the arrows checking and focusing the next or previous (wrapping)
	public static function Radio(props:{value:Signal<String>, options:Array<String>, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "radio", options = props.options, nodes:Array<Node> = [];
		// (the Tab stop: the checked option, else the first)
		function stop(i:Int):Bool {
			var k = options.indexOf(props.value.value);
			return i == (k < 0 ? 0 : k);
		}
		function key(e:Event, i:Int) {
			var n = options.length;
			var j = switch mirrored(e) {
				case Key.SPACE: i;
				case Key.DOWN | Key.RIGHT: (i + 1) % n;
				case Key.UP | Key.LEFT: (i + n - 1) % n;
				case _: return;
			}
			e.preventDefault();
			props.value.value = options[j];
			focusIn(nodes, j);
		}
		return <view tag={tag} role="radiogroup" label={props.label} row-gap={6}>{[
			for (i in 0...options.length) {
				var o = options[i];
				<view tag={tag + "-" + o} role="radio" ref={n -> nodes[i] = n} checked={() -> props.value.value == o} direction="row" align-items="center"
					column-gap={8} focusable={() -> stop(i)} cursor="pointer" onClick={_ -> props.value.value = o} onKeyDown={e -> key(e, i)}>
					<view width={16} height={16} radius={8} border-width={1.5} border-color={Motion.color(() -> props.value.value == o ? t().accentHover : t().mark)}
						align-items="center" justify="center">
						<view width={8} height={8} radius={4} background={Motion.color(() -> props.value.value == o ? t().accent : Theme.clear(t().accent))}/>
					</view>
					{o}
				</view>;
			}
		]}</view>;
	}

	// tabs: a row of labels (tag: the tabs' tag, "-", the index), the
	// selected one underlined, and what render gives for it below. One stop
	// for Tab, the selected one; Left and Right (the way they point, wrapping),
	// Home and End select another and move the focus there
	public static function Tabs(props:{labels:Array<String>, selected:Signal<Int>, render:Int->Any, ?tag:String}):View {
		var tag = props.tag ?? "tabs", count = props.labels.length, tabs:Array<Node> = [];
		function key(e:Event, i:Int) {
			var j = switch mirrored(e) {
				case Key.LEFT: (i + count - 1) % count;
				case Key.RIGHT: (i + 1) % count;
				case Key.HOME: 0;
				case Key.END: count - 1;
				case Key.SPACE | Key.ENTER: i;
				case _: return;
			}
			e.preventDefault();
			props.selected.value = j;
			focusIn(tabs, j);
		}
		return <view tag={tag} row-gap={10}>
			<view role="tablist" direction="row" column-gap={4}>{[
				for (i in 0...count)
					<view tag={tag + "-" + i} role="tab" ref={n -> tabs[i] = n} selected={() -> props.selected.value == i}
						focusable={() -> props.selected.value == i} cursor="pointer" padding="6 10 0 10" row-gap={6} align-items="center"
						onClick={_ -> props.selected.value = i} onKeyDown={e -> key(e, i)}
						color={Motion.color(() -> props.selected.value == i ? t().accentText : t().secondary)}>
						{props.labels[i]}
						<view align-self="stretch" height={2} radius={1} background={Motion.color(() -> props.selected.value == i ? t().accent : Theme.clear(t().accent))}/>
					</view>
			]}</view>
			<view role="tabpanel" label={() -> props.labels[props.selected.value]}>{() -> props.render(props.selected.value)}</view>
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
		return <view tag={tag} role="grid" label={props.label} height={h} radius={6} border-width={1} border-color={() -> t().borderMuted} overflow="hidden"
			background={() -> t().control} color={() -> t().text}>
			<view tag={tag + "-head"} role="row" display="grid" grid-template-columns={template} column-gap={12} padding="0 10" height={rh} align-items="center"
				font-weight={600} color={() -> t().secondary} background={() -> t().background}>{[
				for (k in 0...props.columns.length) {
					var c = props.columns[k], cell:Null<Node> = null, from = 0.0, start = 0.0, dragging = false, clicked = -1e9;
					<view tag={tag + "-head-" + k} role="columnheader" ref={n -> cell = n} direction="row" column-gap={4} align-items="center"
						justify={c.numeric == true ? "flex-end" : "flex-start"} focusable={c.compare != null} cursor={c.compare != null ? "pointer" : "auto"} onClick={_ -> sort(k)}
						onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
							sort(k);
							e.stop();
						}}>
						{c.title}
						<text hidden color={() -> t().muted}>{() -> sortBy.value == k ? (descending.value ? "▼" : "▲") : ""}</text>
						{k == props.columns.length - 1 ? null : <view tag={tag + "-resize-" + k} position="absolute" top={0} bottom={0}
							left={() -> cell != null && cell.rtl() ? -10 : null} right={() -> cell != null && cell.rtl() ? null : -10} width={8} cursor="ew-resize"
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
			]}</view>
			<view tag={tag + "-body"} focusable ref={n -> body = n} onKeyDown={key}>
				<VirtualList each={sorted} itemHeight={rh} height={h - rh - 2} tag={tag + "-rows"} render={(item:Signal<T>, i:Int) -> {
					var hover = signal(false);
					<view tag={tag + "-row"} role="row" selected={() -> item.value != null && selected.value == item.value} display="grid"
						grid-template-columns={template} column-gap={12} padding="0 10" height={rh} align-items="center"
						background={() -> item.value != null && selected.value == item.value ? t().itemSelected : hover.value ? t().itemHover : i % 2 == 1 ? t().background : Theme.clear(t().control)}
						onPointerEnter={_ -> hover.value = true} onPointerLeave={_ -> hover.value = false}
						onClick={_ -> if (item.value != null) click(item.value)}>{[
						for (c in props.columns)
							<view role="cell" overflow="hidden" align-items={c.numeric == true ? "flex-end" : "stretch"}
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
	// text, for type-ahead (letters typed to the row they start).
	public static function Tree<T>(props:{roots:Dynamic, children:T->Null<Array<T>>, render:T->Any, ?text:T->String, ?expanded:Signal<Array<T>>,
			?selected:Signal<Null<T>>, ?onActivate:T->Void, ?height:Float, ?rowHeight:Float, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "tree", rh = props.rowHeight ?? 26.0, h = props.height ?? 240.0;
		var selected:Signal<Null<T>> = props.selected ?? signal(null);
		var expanded:Signal<Array<T>> = props.expanded ?? signal([]);
		var rows = memo(() -> {
			var out:Array<TreeRow<T>> = [], open = expanded.value;
			function add(items:Null<Array<T>>, level:Int, parent:Int) {
				if (items == null) return;
				for (it in items) {
					var kids = props.children(it);
					var leaf = kids == null || kids.length == 0;
					var isOpen = !leaf && open.indexOf(it) >= 0;
					out.push({item: it, level: level, parent: parent, leaf: leaf, open: isOpen});
					if (isOpen) add(kids, level + 1, out.length - 1);
				}
			}
			add(Render.read(props.roots), 1, -1);
			return out;
		});
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
					j = props.text == null ? -1 : typed.find(e, [for (r in rs) props.text(r.item)], i);
					if (j < 0) return;
			}
			e.stop();
			if (rs.length == 0 || j == i) return;
			j = j < 0 ? 0 : j >= rs.length ? rs.length - 1 : j;
			selected.value = rs[j].item;
			show(j);
		}
		return <view tag={tag} role="tree" label={props.label} focusable ref={n -> body = n} onKeyDown={key} height={h} radius={6} border-width={1}
			border-color={() -> t().borderMuted} overflow="hidden" background={() -> t().control} color={() -> t().text}>
			<VirtualList each={rows} itemHeight={rh} height={h - 2} tag={tag + "-rows"} render={(row:Signal<TreeRow<T>>, i:Int) -> {
				var hover = signal(false);
				var on = () -> row.value != null && selected.value == row.value.item;
				<view tag={tag + "-item"} role="treeitem" level={() -> row.value == null ? null : row.value.level}
					expanded={() -> row.value == null || row.value.leaf ? null : row.value.open} selected={on} direction="row" align-items="center"
					column-gap={4} height={rh} padding={() -> '0 8 0 ${row.value == null ? 0 : 6 + (row.value.level - 1) * 16}'}
					background={() -> on() ? t().itemSelected : hover.value ? t().itemHover : Theme.clear(t().control)}
					onPointerEnter={_ -> hover.value = true} onPointerLeave={_ -> hover.value = false}
					onClick={_ -> if (row.value != null) click(row.value)}>
					<view tag={tag + "-toggle"} width={14} align-items="center" cursor="pointer" onClick={e -> if (row.value != null && !row.value.leaf) {
						setOpen(row.value.item, !row.value.open);
						e.stop();
					}}>{arrow(() -> row.value == null || row.value.leaf ? "" : row.value.open ? "▾" : "▸")}</view>
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
		var line = () -> hover.value || active.value ? 2 : 1;
		return <view tag={tag} direction={row ? "row" : "column"} ref={n -> self = n} grow={1} min-width={0} min-height={0} overflow="hidden">
			<view tag={tag + "-first"} basis={() -> size.value} grow={0} shrink={0} min-width={0} min-height={0} overflow="hidden">{props.first}</view>
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
				<view width={row ? (line : Dynamic) : "100%"} height={row ? "100%" : (line : Dynamic)}
					background={Motion.color(() -> hover.value || active.value ? t().accent : t().borderMuted)}/>
			</view>
			<view tag={tag + "-second"} grow={1} shrink={1} basis={0} min-width={0} min-height={0} overflow="hidden">{props.second}</view>
		</view>;
	}

	// a month's days in a grid of six weeks (Monday first; firstDay: 0 for
	// Sunday), the month and year above between arrows to the months before
	// and after. The grid takes the focus: the arrows move its marked day (a
	// day, a week), Page Up and Down a month, Home and End to the week's ends,
	// the month shown following it; a click, Enter or Space chooses the day
	// (value, onChoose). today is marked (by default the system's).
	public static function Calendar(props:{value:Signal<Null<Day>>, ?today:Day, ?firstDay:Int, ?onChoose:Day->Void, ?label:String,
			?tag:String}):View {
		var tag = props.tag ?? "calendar", first = props.firstDay ?? 1;
		var now = Date.now();
		var today = props.today ?? {year: now.getFullYear(), month: now.getMonth() + 1, day: now.getDate()};
		var start = props.value.peek() ?? today;
		var cursor = signal(Days.of(start));
		var shown = memo(() -> {
			var d = Days.day(cursor.value);
			return {year: d.year, month: d.month};
		});
		// (the grid's first day: the week day first before the month's first)
		var gridStart = () -> {
			var s = shown.value, f = Days.of({year: s.year, month: s.month, day: 1});
			return f - ((Days.weekday(f) - first + 7) % 7);
		};
		function choose(n:Int) {
			cursor.value = n;
			var d = Days.day(n);
			props.value.value = d;
			if (props.onChoose != null) props.onChoose(d);
		}
		function month(delta:Int) {
			var d = Days.day(cursor.peek());
			var m = d.month - 1 + delta, y = d.year + Math.floor(m / 12);
			m = ((m % 12) + 12) % 12 + 1;
			cursor.value = Days.of({year: y, month: m, day: Std.int(Math.min(d.day, Days.length(y, m)))});
		}
		function key(e:Event) {
			var c = cursor.peek(), wd = (Days.weekday(c) - first + 7) % 7;
			switch mirrored(e) {
				case Key.LEFT: cursor.value = c - 1;
				case Key.RIGHT: cursor.value = c + 1;
				case Key.UP: cursor.value = c - 7;
				case Key.DOWN: cursor.value = c + 7;
				case Key.HOME: cursor.value = c - wd;
				case Key.END: cursor.value = c + 6 - wd;
				case Key.PAGE_UP: month(-1);
				case Key.PAGE_DOWN: month(1);
				case Key.ENTER | Key.SPACE: choose(c);
				case _: return;
			}
			e.preventDefault();
		}
		var names = [for (k in 0...7) Days.WEEKDAYS[(k + first) % 7]];
		var chosen = (n:Int) -> {
			var v = props.value.value;
			return v != null && Days.of(v) == n;
		};
		return <view tag={tag} row-gap={6} padding={8} radius={8} border-width={1} border-color={() -> t().borderMuted} background={() -> t().control}
			color={() -> t().text}>
			<view direction="row" align-items="center" justify="space-between">
				<view tag={tag + "-previous"} role="button" label="Previous month" cursor="pointer" padding="2 8" radius={4} onClick={_ -> month(-1)}>‹</view>
				<text tag={tag + "-month"} font-weight={600}>{() -> Days.MONTHS[shown.value.month - 1] + " " + shown.value.year}</text>
				<view tag={tag + "-next"} role="button" label="Next month" cursor="pointer" padding="2 8" radius={4} onClick={_ -> month(1)}>›</view>
			</view>
			<view tag={tag + "-grid"} role="table" label={() -> Days.MONTHS[shown.value.month - 1] + " " + shown.value.year} focusable row-gap={2}
				onKeyDown={key}>
				<view role="row" display="grid" grid-template-columns="repeat(7, 32px)" color={() -> t().muted} font-size={11}>{[
					for (n in names)
						<view role="columnheader" align-items="center">{n}</view>
				]}</view>
				{[
					for (w in 0...6)
						<view role="row" display="grid" grid-template-columns="repeat(7, 32px)">{[
							for (k in 0...7) {
								var at = () -> gridStart() + w * 7 + k;
								var inMonth = () -> Days.day(at()).month == shown.value.month;
								<view tag={tag + "-day"} role="cell" label={() -> {
									var d = Days.day(at());
									d.day + " " + Days.MONTHS[d.month - 1] + " " + d.year;
								}} selected={() -> chosen(at())} height={28} align-items="center" justify="center" radius={14} cursor="pointer"
									border-width={() -> cursor.value == at() ? 1.5 : 0} border-color={() -> t().accent}
									background={() -> chosen(at()) ? t().accent : Days.of(today) == at() ? t().itemSelected : Theme.clear(t().control)}
									color={() -> chosen(at()) ? t().onAccent : inMonth() ? t().text : t().muted} onClick={_ -> choose(at())}>
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
	// format (by default "17 October 2026"), else placeholder
	public static function DatePicker(props:{value:Signal<Null<Day>>, ?today:Day, ?firstDay:Int, ?format:Day->String, ?placeholder:String,
			?label:String, ?tag:String}):View {
		var tag = props.tag ?? "date", open = signal(false);
		var format = props.format ?? (d:Day) -> d.day + " " + Days.MONTHS[d.month - 1] + " " + d.year;
		var self:Null<Node> = null;
		return <view tag={tag} role="combobox" label={props.label} expanded={() -> open.value} focusable cursor="pointer" direction="row"
			align-items="center" column-gap={8} padding="6 10" radius={6} border-width={1} border-color={() -> t().border} background={() -> t().control}
			ref={n -> self = n} onClick={_ -> open.value = !open.value} onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE || e.key == Key.DOWN) {
				open.value = true;
				e.preventDefault();
			}}>
			<text color={() -> props.value.value == null ? t().muted : t().text}>{() -> props.value.value == null ? (props.placeholder ?? "Choose a date") : format(props.value.value)}</text>
			<Popover open={open} placement="below" onDismiss={() -> open.value = false}
				onOpen={p -> {
					var g = p.find(tag + "-calendar-grid");
					if (g != null && g.ui != null) g.ui.setFocus(g);
				}}>
				<Calendar tag={tag + "-calendar"} value={props.value} today={props.today} firstDay={props.firstDay}
					onChoose={_ -> {
						open.value = false;
						if (self != null && self.ui != null) self.ui.setFocus(self);
					}}/>
			</Popover>
		</view>;
	}

	// a progress bar: value from 0 to 1 (a signal, a function or a number);
	// null: not known (indeterminate: a bar sliding across, every 1.5
	// seconds, on the Clock; no value for assistive technology)
	public static function Progress(props:{value:Dynamic, ?width:Float, ?label:String, ?tag:String}):View {
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
		return <view tag={props.tag ?? "progress"} role="progressbar" label={props.label} value-now={() -> known() ? frac() : null} value-min={0} value-max={1}
			width={props.width ?? 160} height={8} radius={4} overflow="hidden" direction="row" background={() -> t().subtle}>
			<view width={() -> (frac() * 100) + "%"} background={() -> t().accent}/>
			{() -> known() ? null : <view tag="progress-slide" position="absolute" top={0} bottom={0} width="40%" left={() -> ((phase.value * 1.4 - 0.4) * 100) + "%"}
				background={() -> t().accent}/>}
		</view>;
	}

	// a select bound to a signal: the chosen option's label (labels, else
	// the option) on a button; a click, Enter or Space opens the options
	// under it, the chosen one focused; Up and Down move through them, a
	// click, Enter or Space chooses, Escape, Tab or a click outside closes.
	// On the closed button Up and Down choose the previous or next option.
	public static function Select(props:{value:Signal<String>, options:Array<String>, ?labels:Array<String>, ?width:Float, ?label:String, ?tag:String}):View {
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
		var typed = new TypeAhead(), shown = [for (i in 0...props.options.length) props.labels != null ? props.labels[i] : props.options[i]];
		return <view tag={tag} role="combobox" label={props.label} expanded={() -> open.value} focusable cursor="pointer" direction="row" align-items="center"
			justify="space-between" column-gap={8} width={w} padding="6 10" radius={6} border-width={1} border-color={() -> t().border} background={() -> t().control}
			onClick={_ -> open.value = !open.value}
			onKeyDown={e -> switch e.key {
				case Key.ENTER | Key.SPACE:
					open.value = true;
					e.stop();
				case Key.DOWN:
					e.preventDefault();
					step(1);
				case Key.UP:
					e.preventDefault();
					step(-1);
				case _:
					// (typed: the option it starts, chosen)
					var j = typed.find(e, shown, props.options.indexOf(props.value.peek()));
					if (j >= 0) {
						props.value.value = props.options[j];
						e.stop();
					}
			}}>
			{() -> labelOf(props.value.value)}
			<text color={() -> t().muted} hidden>▾</text>
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={_ -> focusItem(props.options.indexOf(props.value.peek()))}>
				<view tag={tag + "-list"} role="listbox" label={props.label} min-width={w} padding={4} radius={6} border-width={1} border-color={() -> t().borderMuted}
					background={() -> t().control} color={() -> t().text} shadow="0 4 12 #00000026">{[
					for (i in 0...props.options.length) {
						var o = props.options[i], hover = signal(false);
						<view tag={tag + "-" + o} role="option" selected={() -> props.value.value == o} ref={n -> items[i] = n} focusable cursor="pointer" padding="5 8"
							radius={4} background={() -> props.value.value == o ? t().itemSelected : hover.value ? t().itemHover : Theme.clear(t().control)}
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
									var j = typed.find(e, shown, i);
									if (j >= 0) {
										focusItem(j);
										e.stop();
									}
							}}>
							{props.labels != null ? props.labels[i] : o}
						</view>;
					}
				]}</view>
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
	// Control+A selects them all. A double click or Enter: onActivate
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
					var j = typed.find(e, shown, i);
					if (j < 0) return;
					move(j, 0);
			}
			e.stop();
		}
		return <view tag={tag} role="listbox" label={props.label} multiselectable={multiple} width={props.width} height={props.height}
			overflow={props.height == null ? "visible" : "scroll"} padding={4} radius={6} border-width={1} border-color={() -> t().borderMuted}
			background={() -> t().control} color={() -> t().text}>{[
			for (i in 0...options.length) {
				var o = options[i], hover = signal(false);
				<view tag={tag + "-" + o} role="option" ref={n -> nodes[i] = n} selected={() -> props.selected.value.contains(o)} focusable={() -> active.value == i}
					cursor="pointer" padding="5 8" radius={4} shrink={0}
					background={() -> props.selected.value.contains(o) ? t().itemSelected : hover.value ? t().itemHover : Theme.clear(t().control)}
					onPointerEnter={_ -> hover.value = true} onPointerLeave={_ -> hover.value = false}
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
	// move, the item and its new index
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
			var list = props.items.peek().copy(), from = list.indexOf(item);
			if (from < 0 || to < 0 || to > list.length) return;
			list.splice(from, 1);
			if (to > from) to--;
			list.insert(to, item);
			active.value = to;
			if (to != from) {
				props.items.value = list;
				if (props.onMove != null) props.onMove(item, to);
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
		return <view tag={tag} role="list" label={props.label} description="Alt+Up and Alt+Down move an item" row-gap={4}>
			<view tag={tag + "-live"} position="absolute" width={0} height={0} overflow="hidden" live="polite"><text>{said}</text></view>
			<For each={props.items} render={(item:T) -> {
				var at = () -> props.items.value.indexOf(item), entry:{item:T, node:Null<Node>} = {item: item, node: null};
				refs.push(entry);
				onCleanup(() -> refs.remove(entry));
				<view role="listitem" ref={n -> entry.node = n} drag-data={item} focusable={() -> at() == active.value}
					cursor={() -> held.value ? "grabbing" : "grab"} onDragStart={_ -> held.value = true} onDragEnd={_ -> held.value = false}
					direction="row" align-items="center" column-gap={8} padding="6 10" radius={6} border-width={1} border-color={() -> t().borderMuted}
					background={() -> t().control}
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
					<text hidden color={() -> t().muted}>⋮⋮</text>
					{props.render(item)}
					<view position="absolute" left={0} right={0} top={-3} height={2} radius={1} background={() -> t().accent}
						display={() -> over.value == 2 * at() ? "flex" : "none"}/>
					<view position="absolute" left={0} right={0} bottom={-3} height={2} radius={1} background={() -> t().accent}
						display={() -> over.value == 2 * at() + 1 ? "flex" : "none"}/>
				</view>;
			}}/>
		</view>;
	}

	// a toolbar: its children in a row, its focusable ones (as they are
	// when it is shown) one Tab stop, the last focused (at first the first);
	// Left and Right (the way they point, wrapping), Home and End move the
	// focus between them (not out of a text field's text)
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
		onMount(() -> {
			function walk(n:Node)
				for (c in n.children) {
					if (c.focusable) items.push(c) else walk(c);
				}
			if (bar != null) walk(bar);
			rove(0);
		});
		return <view tag={props.tag ?? "toolbar"} role="toolbar" label={props.label} ref={n -> bar = n} direction="row" align-items="center" column-gap={4}
			onPointerDown={(e:Event) -> {
				var j = itemOf(e.target);
				if (j >= 0) rove(j);
			}}
			onFocusIn={(e:Event) -> {
				var j = itemOf(e.target);
				if (j >= 0) rove(j);
			}}
			onKeyDown={(e:Event) -> {
				var i = itemOf(e.target), n = items.length;
				if (i < 0 || Std.isOfType(e.target, EditableText)) return;
				var j = switch mirrored(e) {
					case Key.LEFT: (i + n - 1) % n;
					case Key.RIGHT: (i + 1) % n;
					case Key.HOME: 0;
					case Key.END: n - 1;
					case _: return;
				}
				e.preventDefault();
				rove(j);
				focusIn(items, j);
			}}>{props.children}</view>;
	}

	// a menu button: label; a click, Enter, Space or Down opens its items
	// under it (the first focused), each a label and what choosing it does
	// (and a shortcut: shown, and choosing it from anywhere in the window);
	// Up and Down move through them, a click, Enter or Space chooses (and
	// closes), Escape, Tab or a click outside closes
	public static function Menu(props:{label:String, items:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, ?tag:String}):View {
		var tag = props.tag ?? "menu";
		var open = signal(false);
		var items:Array<Node> = [];
		return <view tag={tag} role="button" expanded={() -> open.value} focusable cursor="pointer" padding="6 14" radius={6} border-width={1}
			border-color={() -> t().border} background={() -> t().control} direction="row" column-gap={6} onClick={_ -> open.value = !open.value}
			onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE || e.key == Key.DOWN) {
				open.value = true;
				e.stop();
			}}>
			{props.label}
			<text color={() -> t().muted} hidden>▾</text>
			{hotkeys(props.items, false)}
			<Popover open={open} placement="below" onDismiss={() -> open.value = false} onOpen={_ -> focusIn(items, 0)}>
				{menuItems(tag, props.label, props.items, open, items)}
			</Popover>
		</view>;
	}

	// a menu bar: a row of menus' titles, each opening its items (as Menu's)
	// under it on a click, Down, Enter or Space; while one is open, the
	// pointer over another title opens that one instead; Left and Right move
	// between the titles the way they point (from an open menu: the next one
	// opened, wrapping);
	// Escape closes it, the focus back on its title. One stop for Tab: the
	// title last moved to. The items' shortcuts work from anywhere in the window.
	public static function Menubar(props:{menus:Array<{label:String, items:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>}>, ?label:String,
			?tag:String}):View {
		var tag = props.tag ?? "menubar", count = props.menus.length;
		var opens = [for (m in props.menus) signal(false)], titles:Array<Node> = [], current = signal(0);
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
		return <view tag={tag} role="menubar" label={props.label} direction="row" column-gap={2}>{[
			for (i in 0...count) {
				var m = props.menus[i], items:Array<Node> = [], hover = signal(false);
				<view tag={tag + "-" + i} role="menuitem" ref={n -> titles[i] = n} expanded={() -> opens[i].value} focusable={() -> current.value == i}
					cursor="pointer" onFocus={_ -> current.value = i} padding="4 10" radius={4}
					background={() -> opens[i].value ? t().itemSelected : hover.value ? t().itemHover : Theme.clear(t().control)}
					onPointerEnter={_ -> {
						hover.value = true;
						if (anyOpen() && !opens[i].peek()) {
							current.value = i;
							focusIn(titles, i);
							show(i);
						}
					}} onPointerLeave={_ -> hover.value = false} onClick={_ -> show(opens[i].peek() ? -1 : i)}
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
					<Popover open={opens[i]} placement="below" onDismiss={() -> if (opens[i].peek()) show(-1)} onOpen={_ -> focusIn(items, 0)}>
						<view onKeyDown={e -> if (e.key == Key.LEFT || e.key == Key.RIGHT) {
							step(i, e.key == Key.RIGHT, true);
							e.stop();
						}}>{menuItems(tag + "-" + i, m.label, m.items, opens[i], items)}</view>
					</Popover>
				</view>;
			}
		]}</view>;
	}

	// a context menu: the children, with items (as Menu's) opened by a right
	// click on them where it was pressed, or by the menu key or Shift+F10
	// when the focus is in them (at their top left, the first item focused);
	// a press elsewhere, Escape or Tab closes it. The items' shortcuts work
	// while the focus is in the children.
	public static function ContextMenu(props:{items:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, ?label:String, ?tag:String, ?children:Any}):View {
		var tag = props.tag ?? "context-menu";
		var open = signal(false);
		var items:Array<Node> = [];
		var self:Node = null, atX = 0.0, atY = 0.0;
		function show(x:Float, y:Float) {
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
			<Popover open={open} at={() -> {x: atX, y: atY}} onDismiss={() -> open.value = false} onOpen={_ -> focusIn(items, 0)}>
				{menuItems(tag, props.label, props.items, open, items)}
			</Popover>
		</view>;
	}

	// a segmented control: one of options, chosen among buttons joined in a
	// row (a radio group: one Tab stop, the chosen one; Left and Right, the
	// way they point, wrapping, and Home and End choose another)
	public static function SegmentedControl(props:{value:Signal<String>, options:Array<String>, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "segments", options = props.options, nodes:Array<Node> = [], n = options.length;
		function stop(i:Int):Bool {
			var k = options.indexOf(props.value.value);
			return i == (k < 0 ? 0 : k);
		}
		function key(e:Event, i:Int) {
			var j = switch mirrored(e) {
				case Key.SPACE | Key.ENTER: i;
				case Key.RIGHT | Key.DOWN: (i + 1) % n;
				case Key.LEFT | Key.UP: (i + n - 1) % n;
				case Key.HOME: 0;
				case Key.END: n - 1;
				case _: return;
			}
			e.preventDefault();
			props.value.value = options[j];
			focusIn(nodes, j);
		}
		return <view tag={tag} role="radiogroup" label={props.label} direction="row" padding={2} column-gap={2} radius={8} background={() -> t().track}
			align-self="start">{[
			for (i in 0...n) {
				var o = options[i], on = () -> props.value.value == o;
				<view tag={tag + "-" + i} role="radio" ref={n -> nodes[i] = n} checked={on} focusable={() -> stop(i)} cursor="pointer" padding="4 12" radius={6}
					background={Motion.color(() -> on() ? t().control : Theme.clear(t().control))} color={() -> on() ? t().text : t().secondary}
					shadow={() -> on() ? "0 1px 2px rgba(0,0,0,0.15)" : null} onClick={_ -> props.value.value = o} onKeyDown={e -> key(e, i)}>{o}</view>;
			}
		]}</view>;
	}

	// breadcrumbs: the path to where one is, each step but the last a link
	// (chosen by a click or Enter: onSelect with its index), the last the
	// current one, in a navigation landmark; the separators decoration
	public static function Breadcrumbs(props:{items:Array<String>, onSelect:Int->Void, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "crumbs", items = props.items;
		return <view tag={tag} role="navigation" label={props.label ?? "Breadcrumb"} direction="row" align-items="center" column-gap={6}>{[
			for (i in 0...items.length) {
				var last = i == items.length - 1;
				[
					last ? <text tag={tag + "-" + i} current color={() -> t().text}>{items[i]}</text> : {
						var hover = signal(false);
						<view tag={tag + "-" + i} role="link" focusable cursor="pointer" color={() -> t().accentText}
							text-decoration={() -> hover.value ? (TextDecoration.Underline : Int) : 0} onPointerEnter={_ -> hover.value = true}
							onPointerLeave={_ -> hover.value = false} onClick={_ -> props.onSelect(i)} onKeyDown={e -> if (e.key == Key.ENTER) {
								e.preventDefault();
								props.onSelect(i);
							}}>{items[i]}</view>;
					},
					last ? null : <text hidden color={() -> t().muted}>/</text>
				];
			}
		]}</view>;
	}

	// pagination: Previous, the pages (the first, the last, the current one
	// and its neighbours, "…" for the rest, a page instead where it hides only
	// one), Next, in a navigation landmark; pages count from 1, the current
	// page's button marked current
	public static function Pagination(props:{page:Signal<Int>, count:Int, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "pages", count = props.count;
		function go(p:Int)
			if (p >= 1 && p <= count) props.page.value = p;
		// (the buttons in order, 0 for a gap)
		function shown():Array<Int> {
			var p = props.page.value, out:Array<Int> = [];
			for (i in 1...count + 1)
				if (i == 1 || i == count || Math.abs(i - p) <= 1 || (i == 2 && p == 4) || (i == count - 1 && p == count - 3)) {
					if (out.length > 0 && i - out[out.length - 1] > 1) out.push(0);
					out.push(i);
				}
			return out;
		}
		function button(label:Void->String, tagged:String, onClick:Void->Void, ?current:Void->Bool, ?disabled:Void->Bool):View {
			var hover = signal(false);
			var cur = () -> current != null && current(), off = () -> disabled != null && disabled();
			return <view tag={tagged} role="button" focusable={() -> !off()} disabled={off} current={cur} cursor={() -> off() ? "default" : "pointer"}
				padding="4 10" radius={6} min-width={32} align-items="center" border-width={1}
				border-color={() -> cur() ? t().accent : hover.value && !off() ? t().border : Theme.clear(t().border)}
				background={() -> cur() ? t().accent : t().background} color={() -> cur() ? t().onAccent : off() ? t().muted : t().text}
				onPointerEnter={_ -> hover.value = true} onPointerLeave={_ -> hover.value = false} onClick={_ -> if (!off()) onClick()}
				onKeyDown={e -> if ((e.key == Key.ENTER || e.key == Key.SPACE) && !off()) {
					e.preventDefault();
					onClick();
				}}>{label}</view>;
		}
		return <view tag={tag} role="navigation" label={props.label ?? "Pages"} direction="row" align-items="center" column-gap={4}>
			{button(() -> "Previous", tag + "-prev", () -> go(props.page.peek() - 1), null, () -> props.page.value <= 1)}
			<Index each={shown} render={(p:Signal<Int>, _) -> <view direction="row">
				<Show when={() -> p.value == 0} fallback={button(() -> Std.string(p.value), tag + "-page", () -> go(p.peek()), () -> props.page.value == p.value)}>
					<text hidden padding="4 6" color={() -> t().muted}>…</text>
				</Show>
			</view>}/>
			{button(() -> "Next", tag + "-next", () -> go(props.page.peek() + 1), null, () -> props.page.value >= count)}
		</view>;
	}

	// the items' shortcuts (local: while the focus is in the parent)
	static function hotkeys(list:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, local:Bool):Array<Any>
		return [for (it in list) if (it.shortcut != null) UiFlow.Hotkey({keys: it.shortcut, action: it.onSelect, local: local})];

	// an event's key, Left and Right swapped where it is right to left (the
	// way they point, in a mirrored row or grid)
	static function mirrored(e:Event):Int
		return e.key != Key.LEFT && e.key != Key.RIGHT || !e.current.rtl() ? e.key : e.key == Key.LEFT ? Key.RIGHT : Key.LEFT;

	// focuses nodes[i] if it is shown
	static function focusIn(nodes:Array<Node>, i:Int)
		if (i >= 0 && i < nodes.length && nodes[i].ui != null) nodes[i].ui.setFocus(nodes[i]);

	// a menu's panel of items (their nodes into nodes): Up and Down move
	// through them, letters typed to the one they start, a click, Enter or
	// Space chooses one (and sets open to false), Tab closes
	static function menuItems(tag:String, label:Null<String>, list:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, open:Signal<Bool>, nodes:Array<Node>):View {
		var typed = new TypeAhead(), labels = [for (it in list) it.label];
		return <view tag={tag + "-items"} role="menu" label={label} min-width={140} padding={4} radius={6} border-width={1} border-color={() -> t().borderMuted}
			background={() -> t().control} color={() -> t().text} shadow="0 4 12 #00000026">{[
			for (i in 0...list.length) {
				var it = list[i], hover = signal(false);
				function choose() {
					open.value = false;
					it.onSelect();
				}
				<view tag={tag + "-" + i} role="menuitem" ref={n -> nodes[i] = n} focusable cursor="pointer" padding="5 8" radius={4} direction="row"
					justify="space-between" column-gap={24}
					background={() -> hover.value ? t().itemHover : Theme.clear(t().control)} onPointerEnter={_ -> hover.value = true}
					onPointerLeave={_ -> hover.value = false} onClick={_ -> choose()}
					onKeyDown={e -> switch e.key {
						case Key.DOWN:
							focusIn(nodes, i + 1);
							e.stop();
						case Key.UP:
							focusIn(nodes, i - 1);
							e.stop();
						case Key.ENTER | Key.SPACE:
							choose();
							e.stop();
						case Key.TAB: open.value = false;
						case _:
							var j = typed.find(e, labels, i);
							if (j >= 0) {
								focusIn(nodes, j);
								e.stop();
							}
					}}>
					{it.label}
					{it.shortcut == null ? null : <text color={() -> t().muted}>{Shortcut.parse(it.shortcut).label()}</text>}
				</view>;
			}
		]}</view>;
	}

	// a tooltip: text shown by the children (above them) once the pointer
	// has rested on them for delay seconds (0.5), hidden when it leaves or
	// presses, or by Escape
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
				<view role="tooltip" padding="4 8" radius={4} background={() -> t().tooltip} color={() -> t().onTooltip} font-size={12}>{props.text}</view>
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
			children: <view role="dialog" label={props.title} width={props.width ?? 360} padding={20} row-gap={12} radius={10} background={() -> t().control}
				color={() -> t().text} shadow="0 10 30 #00000040">
				<text font-size={17} font-weight={600}>{props.title}</text>
				{props.children}
			</view>
		});

	// a combobox: a text field bound to value (two ways) whose typing
	// filters options (those containing the text, in either case; options
	// may be a signal) in a list under it. The focus stays in the field:
	// Down opens the list and highlights the next option, Up the previous;
	// Enter or a click chooses the highlighted one (the field takes its
	// text; onChoose gets it), Enter with none highlighted submits the text
	// as it is (onChoose), Escape or a click outside closes the list.
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
		f.semantics.role = hxmc.ui.access.Role.ComboBox;
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6, width: w});
		themed(f);
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
				case Key.UP:
					e.stop();
					var n = matches.peek().length;
					if (open.peek() && n > 0) highlight(active.peek() <= 0 ? n - 1 : active.peek() - 1);
				case Key.ESCAPE if (open.peek()):
					// (only the list closes: not a dialog it is in)
					e.preventDefault();
					open.value = false;
				case _:
			}}>
			{f}
			<Popover open={() -> open.value && matches.value.length > 0} placement="below" onDismiss={() -> open.value = false}>
				<scroll tag={tag + "-list"} role="listbox" label={props.label} width={w} max-height={240} padding={4} radius={6} border-width={1}
					border-color={() -> t().borderMuted} background={() -> t().control} color={() -> t().text} shadow="0 4 12 #00000026">
					<Index each={matches} render={(o:Signal<String>, i:Int) -> <view tag={tag + "-option"} role="option" selected={() -> active.value == i}
						ref={n -> options[i] = n} cursor="pointer" padding="5 8" radius={4}
						background={() -> active.value == i ? t().itemSelected : Theme.clear(t().control)} onPointerEnter={_ -> active.value = i}
						onClick={_ -> choose(o.peek())}>{() -> o.value}</view>}/>
				</scroll>
			</Popover>
		</view>;
	}

	// a disclosure: its label on a button (an arrow turning with it) that
	// shows or hides the children under it, by a click, Enter or Space; open
	// (a signal; closed at first) says which
	public static function Disclosure(props:{label:String, ?open:Signal<Bool>, ?tag:String, ?children:Any}):View {
		var open = props.open ?? signal(false), tag = props.tag ?? "disclosure";
		return <view tag={tag}>
			{summary(tag, props.label, () -> open.value, () -> open.value = !open.peek())}
			<Show when={open}><view tag={tag + "-content"} padding="4 0 4 20">{props.children}</view></Show>
		</view>;
	}

	// an accordion: sections, each a disclosure, at most one open: open is
	// its index (-1: none; a signal); opening one closes the other
	public static function Accordion(props:{sections:Array<{label:String, render:Void->Any}>, ?open:Signal<Int>, ?tag:String}):View {
		var open = props.open ?? signal(-1), tag = props.tag ?? "accordion";
		return <view tag={tag} row-gap={2}>{[
			for (i in 0...props.sections.length) {
				var s = props.sections[i];
				<view tag={tag + "-" + i}>
					{summary(tag + "-" + i, s.label, () -> open.value == i, () -> open.value = open.peek() == i ? -1 : i)}
					<Show when={() -> open.value == i}><view tag={tag + "-" + i + "-content"} padding="4 0 4 20">{s.render()}</view></Show>
				</view>;
			}
		]}</view>;
	}

	// (a disclosure's button)
	static function summary(tag:String, label:String, isOpen:Void->Bool, flip:Void->Void):View
		return <view tag={tag + "-summary"} role="button" expanded={isOpen} focusable cursor="pointer" direction="row" align-items="center" column-gap={6}
			padding="4 2" radius={4} onClick={_ -> flip()} onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
				e.preventDefault();
				flip();
			}}>
			<view width={12}>{arrow(() -> isOpen() ? "▾" : "▸")}</view>
			{label}
		</view>;

	// where Toasts.show's toasts are shown: in a corner of the window
	// (placement: "bottom-right", "bottom-left", "top-right", "top-left"),
	// over everything, width wide (320); each with its mark, text, action
	// and a close button. They do not take the focus; the pointer over them
	// holds their time.
	public static function Toaster(props:{?placement:String, ?width:Float, ?tag:String}):View {
		var tag = props.tag ?? "toaster";
		function mark(kind:String):String
			return kind == "success" ? t().success : kind == "error" ? t().danger : t().accent;
		// (a live region, always there and of no size, saying the newest toast: assistive technology announces it)
		return <view tag={tag + "-live"} position="absolute" width={0} height={0} overflow="hidden" live="polite">
			<text>{() -> {
				var shown = Toasts.shown.value;
				shown.length == 0 ? "" : shown[shown.length - 1].text;
			}}</text>
			<Popover open={() -> Toasts.shown.value.length > 0} placement={props.placement ?? "bottom-right"} gap={16} tag={tag}>
			<view tag={tag + "-list"} width={props.width ?? 320.0} row-gap={8} onPointerEnter={_ -> Toasts.paused = true}
				onPointerLeave={_ -> Toasts.paused = false}>
				<For each={Toasts.shown} render={(toast:Toast) -> <view tag="toast" role="group" label={toast.text} direction="row" align-items="center"
					column-gap={10} padding="10 12" radius={8} background={() -> t().tooltip} color={() -> t().onTooltip} shadow="0 4 12 #00000033">
					<view width={4} height={20} radius={2} background={() -> mark(toast.kind)}/>
					<text grow={1}>{toast.text}</text>
					{toast.action == null ? null : <view tag="toast-action" role="button" focusable cursor="pointer" padding="2 6" radius={4}
						color={() -> t().accentHover} onClick={_ -> {
							Toasts.close(toast);
							if (toast.onAction != null) toast.onAction();
						}}>{toast.action}</view>}
					<view tag="toast-close" role="button" label="Close" focusable cursor="pointer" padding="0 4" color={() -> t().muted}
						onClick={_ -> Toasts.close(toast)}>×</view>
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
	public static function NumberField(props:{value:Signal<Float>, ?min:Float, ?max:Float, ?step:Float, ?width:Float, ?format:Float->String,
			?label:String, ?tag:String}):View {
		var tag = props.tag ?? "number", step = props.step ?? 1.0, w = props.width ?? 120.0;
		var min = props.min ?? Math.NEGATIVE_INFINITY, max = props.max ?? Math.POSITIVE_INFINITY;
		var format = props.format ?? plain;
		var editing = false;
		var f = new TextField(format(props.value.peek()));
		f.tag = tag;
		f.semantics.role = hxmc.ui.access.Role.SpinButton;
		f.semantics.label = props.label;
		if (Math.isFinite(min)) f.semantics.valueMin = min;
		if (Math.isFinite(max)) f.semantics.valueMax = max;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6, grow: 1, minWidth: 0});
		themed(f);
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
			return <view tag={tag + (n > 0 ? "-up" : "-down")} role="button" label={label} cursor="pointer" grow={1} justify="center" align-items="center"
				padding="0 6" font-size={9} color={() -> t().muted} onClick={_ -> stepBy(n)}>{glyph}</view>;
		return <view tag={tag + "-box"} direction="row" align-items="stretch" column-gap={2} width={w} onKeyDown={e -> switch e.key {
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
			<view row-gap={1}>
				{arrow("Increase", "▲", 1)}
				{arrow("Decrease", "▼", -1)}
			</view>
		</view>;
	}

	// (a number as it is, to ten decimals: 0.1 + 0.2 shown as 0.3)
	static function plain(v:Float):String {
		var s = Std.string(Math.fround(v * 1e10) / 1e10);
		return StringTools.endsWith(s, ".0") ? s.substr(0, s.length - 2) : s;
	}

	// a text area bound to a signal (two ways), rows lines high (3); a right
	// click (or the menu key) opens its edit menu
	public static function Area(props:{value:Signal<String>, ?rows:Int, ?placeholder:String, ?label:String, ?tag:String}):View {
		var f = new TextArea(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.rows = props.rows ?? 3;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6});
		themed(f);
		f.onChange = s -> props.value.value = s;
		effect(() -> f.setText(props.value.value));
		return editMenu(f, props.tag ?? "area");
	}

	// (a text field in a context menu of its edits: cut, copy, paste, select all)
	static function editMenu(f:EditableText, tag:String):View
		return <ContextMenu tag={tag + "-menu"} label="Edit" items={[
			{label: "Cut", onSelect: () -> f.cut(), shortcut: "Mod+X"},
			{label: "Copy", onSelect: () -> f.copy(), shortcut: "Mod+C"},
			{label: "Paste", onSelect: () -> f.paste(), shortcut: "Mod+V"},
			{label: "Select All", onSelect: () -> f.selectAll(), shortcut: "Mod+A"}
		]}>{f}</ContextMenu>;

	// (a text field's colours from the theme, following it)
	// (a disclosure's arrow, a tree's or a summary's: hidden from assistive
	// technology, muted; closed, to the line's end)
	static function arrow(shown:Void->String):Node {
		var n = new Arrow("");
		n.semantics = {hidden: true};
		effect(() -> n.text = shown());
		effect(() -> n.style.color = Color.parse(t().muted));
		return n;
	}

	static function themed(f:EditableText)
		effect(() -> {
			var th = t();
			f.style.background = Color.parse(th.control);
			f.style.borderColor = Color.parse(th.border);
			f.placeholderColor = Color.parse(th.placeholder);
			f.selectionColor = Color.parse(th.selection);
			f.caretColor = Color.parse(th.caret);
			f.markDirty();
		});

	// a text field bound to a signal (two ways); a right click (or the menu
	// key) opens its edit menu; password: its text shown as dots, not copied
	// or cut, a password field for assistive technology
	public static function Field(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?password:Bool, ?tag:String}):View {
		var f = new TextField(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		if (props.password == true) f.secret = true;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6});
		themed(f);
		f.onChange = s -> props.value.value = s;
		f.onSubmit = props.onSubmit;
		effect(() -> f.setText(props.value.value));
		return editMenu(f, props.tag ?? "field");
	}

	// a tag input: tags as chips before a text field in one box; Enter or a
	// comma adds what is typed (trimmed, once), Backspace in an empty field
	// takes the last one off, a chip's × takes it off; a click in the box
	// focuses the field. The chips a list, each × a button named for its tag
	public static function TagInput(props:{tags:Signal<Array<String>>, ?placeholder:String, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "tags";
		var f = new TextField("");
		f.tag = tag + "-field";
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [2, 2]});
		effect(() -> {
			var th = t();
			f.placeholderColor = Color.parse(th.placeholder);
			f.selectionColor = Color.parse(th.selection);
			f.caretColor = Color.parse(th.caret);
			f.markDirty();
		});
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
		return <view tag={tag} direction="row" wrap align-items="center" gap={4} padding="3 4" radius={6} border-width={1}
			border-color={() -> t().border} background={() -> t().control} cursor="text"
			onPointerDown={(e:Event) -> if (e.target != f && f.ui != null) {
				f.ui.setFocus(f);
				e.preventDefault();
			}}>
			<view role="list" label={props.label} direction="row" wrap gap={4}>
				<For each={props.tags} render={(v:String) -> <view tag={tag + "-" + v} role="listitem" label={v} direction="row" align-items="center" gap={2}
					padding="1 2 1 8" radius={4} background={() -> t().itemSelected} color={() -> t().text}>
					{v}
					<view tag={tag + "-" + v + "-remove"} role="button" label={"Remove " + v} cursor="pointer" padding="0 4" radius={3}
						color={() -> t().secondary} onClick={_ -> remove(v)}>×</view>
				</view>}/>
			</view>
			<view grow={1} min-width={60}>{editMenu(f, tag)}</view>
		</view>;
	}
}

// a disclosure's arrow: closed (▸), it points to the line's end, right to
// left the other way (as Chromium's disclosure-closed marker)
private class Arrow extends TextNode {
	override function shownText():String
		return text == "▸" && rtl() ? "◂" : text;
}

// type-ahead in a list (a select's, a menu's): letters and digits typed
// within a second of each other make a prefix, the item it starts found
// from the one after (the same letter again: the next with it), case aside
private class TypeAhead {
	var prefix = "";
	var at = -1e9;

	public function new() {}

	// the item's index for a key typed at item from, else -1
	public function find(e:Event, labels:Array<String>, from:Int):Int {
		if (e.mods & (Key.MOD_CONTROL | Key.MOD_META | Key.MOD_ALT) != 0) return -1;
		var k = e.key;
		if (k >= "A".code && k <= "Z".code) k += 32;
		if (!(k >= "a".code && k <= "z".code || k >= "0".code && k <= "9".code)) return -1;
		var now = Ui.now(), c = String.fromCharCode(k);
		prefix = now - at < 1 && prefix != c ? prefix + c : c;
		at = now;
		var n = labels.length, start = prefix.length > 1 ? from : from + 1;
		for (j in 0...n) {
			var i = ((start + j) % n + n) % n;
			if (StringTools.startsWith(labels[i].toLowerCase(), prefix)) return i;
		}
		return -1;
	}
}
