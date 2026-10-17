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

	// a checkbox bound to a signal, with its label
	public static function Checkbox(props:{checked:Signal<Bool>, ?label:String, ?tag:String}):View {
		var toggle = () -> props.checked.value = !props.checked.value;
		return <view tag={props.tag ?? "checkbox"} role="checkbox" checked={() -> props.checked.value} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> toggle()}
			onKeyDown={e -> if (e.key == Key.SPACE) {
				e.preventDefault();
				toggle();
			}}>
			<view width={16} height={16} radius={4} border-width={1.5} border-color={Motion.color(() -> props.checked.value ? t().accentHover : t().mark)}
				background={Motion.color(() -> props.checked.value ? t().accent : t().control)} align-items="center" justify="center">
				<view width={8} height={8} radius={2} background={Motion.color(() -> props.checked.value ? t().onAccent : Theme.clear(t().onAccent))}/>
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

	// radio buttons bound to a signal: one per option (tag: the group's tag,
	// "-", the option)
	public static function Radio(props:{value:Signal<String>, options:Array<String>, ?label:String, ?tag:String}):View {
		var tag = props.tag ?? "radio";
		return <view tag={tag} role="radiogroup" label={props.label} row-gap={6}>{[
			for (o in props.options)
				<view tag={tag + "-" + o} role="radio" checked={() -> props.value.value == o} direction="row" align-items="center" column-gap={8} focusable cursor="pointer" onClick={_ -> props.value.value = o}
					onKeyDown={e -> if (e.key == Key.SPACE) {
						e.preventDefault();
						props.value.value = o;
					}}>
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
	public static function Tabs(props:{labels:Array<String>, selected:Signal<Int>, render:Int->Any, ?tag:String}):View {
		var tag = props.tag ?? "tabs";
		return <view tag={tag} row-gap={10}>
			<view role="tablist" direction="row" column-gap={4}>{[
				for (i in 0...props.labels.length)
					<view tag={tag + "-" + i} role="tab" selected={() -> props.selected.value == i} focusable cursor="pointer" padding="6 10 0 10" row-gap={6} align-items="center"
						onClick={_ -> props.selected.value = i} onKeyDown={e -> if (e.key == Key.SPACE || e.key == Key.ENTER) {
							e.preventDefault();
							props.selected.value = i;
						}}
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
			?height:Float, ?rowHeight:Float, ?selected:Signal<Null<T>>, ?onActivate:T->Void, ?label:String, ?tag:String}):View {
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

	// a tree: the roots' rows and, under each open item, its children's,
	// indented by level, a triangle on the items with children
	// (children(item): null or empty, a leaf); the rows are a VirtualList's
	// (only those in view are made). A click selects an item (selected), a
	// click on its triangle opens or closes it, as a double click does (on a
	// leaf, it activates it: onActivate, as Enter does); Up and Down move
	// the selection, Right opens an item or moves to its first child, Left
	// closes it or moves to its parent, Home and End, the view following.
	// roots: an array, or a signal or function of one; expanded: the open
	// items (none by default); height: the whole tree's.
	public static function Tree<T>(props:{roots:Dynamic, children:T->Null<Array<T>>, render:T->Any, ?expanded:Signal<Array<T>>,
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
		function key(e:Event) {
			var rs = rows.peek(), i = indexOf(selected.peek()), j = i;
			switch e.key {
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
				case _: return;
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
				onPointerMove={e -> if (active.peek() && self != null) set((row ? self.localX(e.x, e.y) : self.localY(e.x, e.y)) - grab)}
				onKeyDown={e -> {
					var v = switch e.key {
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
			switch e.key {
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

	// a progress bar: value from 0 to 1 (a signal, a function or a number)
	public static function Progress(props:{value:Dynamic, ?width:Float, ?label:String, ?tag:String}):View {
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

	// the items' shortcuts (local: while the focus is in the parent)
	static function hotkeys(list:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, local:Bool):Array<Any>
		return [for (it in list) if (it.shortcut != null) UiFlow.Hotkey({keys: it.shortcut, action: it.onSelect, local: local})];

	// focuses nodes[i] if it is shown
	static function focusIn(nodes:Array<Node>, i:Int)
		if (i >= 0 && i < nodes.length && nodes[i].ui != null) nodes[i].ui.setFocus(nodes[i]);

	// a menu's panel of items (their nodes into nodes): Up and Down move
	// through them, a click, Enter or Space chooses one (and sets open to
	// false), Tab closes
	static function menuItems(tag:String, label:Null<String>, list:Array<{label:String, onSelect:Void->Void, ?shortcut:String}>, open:Signal<Bool>, nodes:Array<Node>):View
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
		return <Popover open={() -> Toasts.shown.value.length > 0} placement={props.placement ?? "bottom-right"} gap={16} tag={tag}>
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
		</Popover>;
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
	// key) opens its edit menu
	public static function Field(props:{value:Signal<String>, ?placeholder:String, ?label:String, ?onSubmit:String->Void, ?tag:String}):View {
		var f = new TextField(props.value.peek());
		if (props.tag != null) f.tag = props.tag;
		f.placeholder = props.placeholder ?? "";
		f.semantics.label = props.label ?? props.placeholder;
		f.style.set({padding: [6, 8], borderWidth: 1, radius: 6});
		themed(f);
		f.onChange = s -> props.value.value = s;
		f.onSubmit = props.onSubmit;
		effect(() -> f.setText(props.value.value));
		return editMenu(f, props.tag ?? "field");
	}
}

// a disclosure's arrow: closed (▸), it points to the line's end, right to
// left the other way (as Chromium's disclosure-closed marker)
private class Arrow extends TextNode {
	override function shownText():String
		return text == "▸" && rtl() ? "◂" : text;
}
