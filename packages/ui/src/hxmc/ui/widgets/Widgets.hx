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
// hxmc.ui.reactive, styled plainly (props override the look), in
// Theme.current's colours; their colours and the switch's knob move with
// Motion's transitions
class Widgets implements Markup {
	// (the theme: read inside reactive values, so that they follow it)
	static inline function t():Theme
		return Theme.current.value;

	// a button: label or children; a primary one is filled
	public static function Button(props:{?label:String, ?onClick:Void->Void, ?primary:Bool, ?children:Esx, ?tag:String}):Esx {
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
			onKeyDown={e -> if ((e.key == Key.ENTER || e.key == Key.SPACE) && props.onClick != null) props.onClick()}>
			{props.label}{props.children}
		</view>;
	}

	// a checkbox bound to a signal, with its label
	public static function Checkbox(props:{checked:Signal<Bool>, ?label:String, ?tag:String}):Esx {
		var toggle = () -> props.checked.value = !props.checked.value;
		return <view tag={props.tag ?? "checkbox"} role="checkbox" checked={() -> props.checked.value} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE) toggle()}>
			<view width={16} height={16} radius={4} border-width={1.5} border-color={Motion.color(() -> props.checked.value ? t().accentHover : t().mark)}
				background={Motion.color(() -> props.checked.value ? t().accent : t().control)} align-items="center" justify="center">
				<view width={8} height={8} radius={2} background={Motion.color(() -> props.checked.value ? t().onAccent : Theme.clear(t().onAccent))}/>
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
				background={Motion.color(() -> props.on.value ? t().accent : t().track)}>
				<view width={16} height={16} radius={8} background={() -> t().knob} shadow="0 1 2 #00000040"
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
			<view height={4} radius={2} margin={[0, knob / 2]} overflow="hidden" direction="row" background={() -> t().track}>
				<view width={() -> (frac() * 100) + "%"} background={() -> t().accent}/>
			</view>
			<view position="absolute" top={2} left={() -> frac() * (w - knob)} width={knob} height={knob} radius={knob / 2} background={() -> t().knob}
				border-width={1} border-color={() -> t().border} shadow="0 1 2 #00000033"/>
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
					<view width={16} height={16} radius={8} border-width={1.5} border-color={Motion.color(() -> props.value.value == o ? t().accentHover : t().mark)}
						align-items="center" justify="center">
						<view width={8} height={8} radius={4} background={Motion.color(() -> props.value.value == o ? t().accent : Theme.clear(t().accent))}/>
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
	// Page Down, Home and End move the selection, the view following.
	// columns: a title, a width (a grid track: "1fr" by default, "120px",
	// "auto"), what a row's cell shows (cell), compare (sortable). rows: an
	// array, or a signal or function of one; height: the whole table's.
	public static function Table<T>(props:{rows:Dynamic, columns:Array<{title:String, ?width:String, cell:T->Any, ?compare:(T, T)->Int}>,
			?height:Float, ?rowHeight:Float, ?selected:Signal<Null<T>>, ?onActivate:T->Void, ?label:String, ?tag:String}):Esx {
		var tag = props.tag ?? "table", rh = props.rowHeight ?? 28.0, h = props.height ?? 240.0;
		var selected:Signal<Null<T>> = props.selected ?? signal(null);
		var sortBy = signal(-1), descending = signal(false);
		var template = [for (c in props.columns) c.width ?? "1fr"].join(" ");
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
					var c = props.columns[k];
					<view tag={tag + "-head-" + k} role="columnheader" direction="row" column-gap={4} align-items="center" focusable={c.compare != null}
						cursor={c.compare != null ? "pointer" : "auto"} onClick={_ -> sort(k)}
						onKeyDown={e -> if (e.key == Key.ENTER || e.key == Key.SPACE) {
							sort(k);
							e.stop();
						}}>
						{c.title}
						<text hidden color={() -> t().muted}>{() -> sortBy.value == k ? (descending.value ? "▼" : "▲") : ""}</text>
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
							<view role="cell" overflow="hidden">{() -> item.value == null ? null : c.cell(item.value)}</view>
					]}</view>;
				}}/>
			</view>
		</view>;
	}

	// a progress bar: value from 0 to 1 (a signal, a function or a number)
	public static function Progress(props:{value:Dynamic, ?width:Float, ?label:String, ?tag:String}):Esx {
		var frac = () -> {
			var v:Float = Render.read(props.value);
			v < 0 ? 0.0 : v > 1 ? 1.0 : v;
		};
		return <view tag={props.tag ?? "progress"} role="progressbar" label={props.label} value-now={frac} value-min={0} value-max={1} width={props.width ?? 160} height={8} radius={4} overflow="hidden" direction="row" background={() -> t().subtle}>
			<view width={() -> (frac() * 100) + "%"} background={() -> t().accent}/>
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
			justify="space-between" column-gap={8} width={w} padding="6 10" radius={6} border-width={1} border-color={() -> t().border} background={() -> t().control}
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
							}}>
							{props.labels != null ? props.labels[i] : o}
						</view>;
					}
				]}</view>
			</Popover>
		</view>;
	}

	// a menu button: label; a click, Enter, Space or Down opens its items
	// under it (the first focused), each a label and what choosing it does
	// (and a shortcut: shown, and choosing it from anywhere in the window);
	// Up and Down move through them, a click, Enter or Space chooses (and
	// closes), Escape, Tab or a click outside closes
	public static function Menu(props:{label:String, items:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, ?tag:String}):Esx {
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

	// a context menu: the children, with items (as Menu's) opened by a right
	// click on them where it was pressed, or by the menu key or Shift+F10
	// when the focus is in them (at their top left, the first item focused);
	// a press elsewhere, Escape or Tab closes it. The items' shortcuts work
	// while the focus is in the children.
	public static function ContextMenu(props:{items:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, ?label:String, ?tag:String, ?children:Any}):Esx {
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

	// the items' shortcuts (local: while the focus is in the parent)
	static function hotkeys(list:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, local:Bool):Array<Any>
		return [for (it in list) if (it.shortcut != null) Flow.Hotkey({keys: it.shortcut, action: it.onSelect, local: local})];

	// focuses nodes[i] if it is shown
	static function focusIn(nodes:Array<Node>, i:Int)
		if (i >= 0 && i < nodes.length && nodes[i].ui != null) nodes[i].ui.setFocus(nodes[i]);

	// a menu's panel of items (their nodes into nodes): Up and Down move
	// through them, a click, Enter or Space chooses one (and sets open to
	// false), Tab closes
	static function menuItems(tag:String, label:Null<String>, list:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, open:Signal<Bool>, nodes:Array<Node>):Esx
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
					}}>
					{it.label}
					{it.shortcut == null ? null : <text color={() -> t().muted}>{Shortcut.parse(it.shortcut).label()}</text>}
				</view>;
			}
		]}</view>;

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

	// a text area bound to a signal (two ways), rows lines high (3)
	public static function Area(props:{value:Signal<String>, ?rows:Int, ?placeholder:String, ?label:String, ?tag:String}):Node {
		var f = new TextArea(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.rows = props.rows ?? 3;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6});
		themed(f);
		f.onChange = s -> props.value.value = s;
		effect(() -> f.setText(props.value.value));
		return f;
	}

	// (a text field's colours from the theme, following it)
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

	// a text field bound to a signal (two ways)
	public static function Field(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?tag:String}):Node {
		var f = new TextField(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6});
		themed(f);
		f.onChange = s -> props.value.value = s;
		f.onSubmit = props.onSubmit;
		effect(() -> f.setText(props.value.value));
		return f;
	}
}
