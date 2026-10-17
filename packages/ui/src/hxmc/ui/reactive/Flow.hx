package hxmc.ui.reactive;

import hxmc.ui.*;
import hxmc.ui.reactive.Reactive;
import hxmc.ui.reactive.Signal;
import hxmc.ui.reactive.Memo;

// Control flow components for markup (import hxmc.ui.reactive.Flow.*):
//
//   <For each={todos} render={t -> <Item todo={t}/>}/>
//   <Index each={names} render={(name, i) -> <text>{name}</text>}/>
//   <Show when={() -> count.value > 0} fallback="none">{...}</Show>
//   <Switch fallback="other"><Match when={a}>A</Match><Match when={b}>B</Match></Switch>
//   <Provider context={theme} value={dark}>{...}</Provider>
//   <ErrorBoundary fallback={(e, reset) -> ...}>{...}</ErrorBoundary>
//   <Hotkey keys="Mod+S" action={save}/>
//
// For keeps each item's nodes (keyed by the item itself): when the list
// changes, items still there are moved, not made again; the others are
// made, or removed with their computations. Index keeps a row per index,
// its item a signal set to the new item. Show and Switch render a branch
// again only when the branch chosen changes (not on every change of what
// chooses it). Provider sets a context for its children (Reactive.use).
// ErrorBoundary shows fallback instead of its children when rendering them
// throws, or a computation inside them does later; reset tries again.
class Flow {
	public static function For<T>(props:{each:Dynamic, render:T->Any}):Any
		return new ForList(props.each, props.render);

	public static function Index<T>(props:{each:Dynamic, render:(Signal<T>, Int)->Any}):Any
		return new IndexList(props.each, props.render);

	public static function Show(props:{when:Dynamic, ?fallback:Any, ?children:Any}):Any {
		var on = Reactive.memo(() -> {
			var w:Dynamic = Render.read(props.when);
			w != null && w != false;
		});
		return () -> on.value ? props.children : props.fallback;
	}

	// the children in a popup (hxmc.ui.Popup: a layer over the tree), open
	// while open is true: anchored to anchor (else the node the markup puts
	// it in), placed by placement ("below", "above", "right", "left",
	// "center"; gap pixels away), modal or not; onDismiss when a click
	// outside or Escape asks it to close; onOpen once it is open (to move
	// the focus into it); a modal one's backdrop its colour. Its content is
	// rendered once, kept while closed.
	// a keyboard shortcut while it is mounted (Ui.shortcut): keys
	// (hxmc.ui.Shortcut: "Mod+S", "Shift+F10") run action anywhere in the
	// window, or, local, while the focus is inside the node the markup puts it in
	public static function Hotkey(props:{keys:String, action:Void->Void, ?local:Bool}):Any
		return new HotkeyMount(props);

	public static function Popover(props:{open:Dynamic, ?anchor:Node, ?placement:String, ?gap:Float, ?modal:Bool, ?backdrop:Color,
			?onDismiss:Void->Void, ?onOpen:hxmc.ui.Popup->Void, ?at:Void->{x:Float, y:Float}, ?tag:String, ?children:Any}):Any
		return new PopoverMount(props);

	// a long list in a scrolling view height pixels high: only the rows in
	// view are made (and overscan more on each side, 3), each itemHeight
	// high, again as it scrolls; render gets a row's item (a signal: what is
	// at its index when the list changes) and its index
	public static function VirtualList<T>(props:{each:Dynamic, itemHeight:Float, height:Float, render:(Signal<T>, Int)->Any, ?overscan:Int,
			?tag:String}):Any
		return new VirtualRows(props.each, props.itemHeight, props.height, props.render, props.overscan ?? 3, props.tag);

	public static function Match(props:{when:Dynamic, ?children:Any}):Any
		return new MatchCase(props.when, props.children);

	public static function Switch(props:{?fallback:Any, ?children:Any}):Any {
		var cases:Array<MatchCase> = [];
		Reactive.untrack(() -> collect(props.children, cases));
		var chosen = Reactive.memo(() -> {
			var k = -1;
			for (i in 0...cases.length) {
				var w:Dynamic = Render.read(cases[i].when);
				if (w != null && w != false) {
					k = i;
					break;
				}
			}
			k;
		});
		return () -> {
			var k = chosen.value;
			k < 0 ? props.fallback : cases[k].children;
		};
	}

	// the Match cases among a Switch's children (its components called)
	static function collect(v:Dynamic, out:Array<MatchCase>) {
		if (v == null) return;
		if (Std.isOfType(v, MatchCase)) out.push(v) else if (Std.isOfType(v, Array)) {
			for (x in (v : Array<Dynamic>))
				collect(x, out);
		} else if (Std.isOfType(v, hxmc.esx.Esx)) {
			var e:hxmc.esx.Esx = v;
			collectNode(e.template.root, e.values, out);
		}
	}

	static function collectNode(n:hxmc.esx.Template.TNode, values:Array<Any>, out:Array<MatchCase>) {
		switch n.kind {
			case Fragment:
				for (c in n.children)
					collectNode(c, values, out);
			case Component:
				collect((values[n.hole] : Void->Any)(), out);
			case Hole:
				collect(values[n.hole], out);
			case Text:
				if (StringTools.trim(n.text) != "") throw "hxmc.ui: a Switch holds Match cases only";
			case Element:
				throw "hxmc.ui: a Switch holds Match cases only, not <" + n.name + ">";
		}
	}

	public static function Provider<T>(props:{context:Context<T>, value:T, ?children:Any}):Any {
		Reactive.setContext(props.context, props.value);
		return props.children;
	}

	public static function ErrorBoundary(props:{fallback:(Dynamic, Void->Void)->Any, ?children:Any}):Any
		return new Boundary(props.fallback, props.children);
}

// content Render mounts itself: it inserts its nodes before before and
// returns the ones it keeps there (an anchor: what it shows goes before it)
interface Mountable {
	function mount(parent:Node, before:Null<Node>):Array<Node>;
}

// Popover: a hidden marker where the markup puts it; the popup opened in
// the marker's Ui while open is true
class PopoverMount implements Mountable {
	final props:{open:Dynamic, ?anchor:Node, ?placement:String, ?gap:Float, ?modal:Bool, ?backdrop:Color, ?onDismiss:Void->Void,
		?onOpen:hxmc.ui.Popup->Void, ?at:Void->{x:Float, y:Float}, ?tag:String, ?children:Any};

	public function new(props)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var marker = new Node("popover");
		marker.style.display = None;
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(marker, i < 0 ? parent.children.length : i);
		var p = new hxmc.ui.Popup(props.tag);
		if (props.placement != null) p.placement = props.placement;
		if (props.gap != null) p.gap = props.gap;
		p.modal = props.modal == true;
		if (props.backdrop != null) p.style.background = props.backdrop;
		p.onDismiss = props.onDismiss;
		p.anchor = props.anchor != null ? props.anchor : parent;
		Render.insert(props.children, p, null);
		function sync() {
			var w:Dynamic = Render.read(props.open);
			var on = w != null && w != false;
			Reactive.untrack(() -> {
				if (on && marker.ui != null && p.ui == null) {
					// (placement "point": where at says, when it opens)
					if (props.at != null) {
						var a = props.at();
						p.placement = Point;
						p.atX = a.x;
						p.atY = a.y;
					}
					marker.ui.open(p);
					if (props.onOpen != null) props.onOpen(p);
				} else if (!on && p.ui != null) p.ui.close(p);
			});
		}
		// (opened once the marker is in its Ui: after the insertion)
		Reactive.onMount(() -> {
			Reactive.effect(sync);
		});
		Reactive.onCleanup(() -> if (p.ui != null) p.ui.close(p));
		return [marker];
	}
}

// Hotkey: a hidden marker; the shortcut added to its Ui once mounted
class HotkeyMount implements Mountable {
	final props:{keys:String, action:Void->Void, ?local:Bool};

	public function new(props)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var marker = anchorAt(parent, before, "hotkey");
		// (a mistake in keys thrown at once)
		Shortcut.parse(props.keys);
		var remove:Null<Void->Void> = null;
		Reactive.onMount(() -> {
			if (marker.ui != null) remove = marker.ui.shortcut(props.keys, () -> props.action(), props.local == true ? parent : null);
		});
		Reactive.onCleanup(() -> if (remove != null) remove());
		return [marker];
	}
}

class MatchCase {
	public final when:Dynamic;
	public final children:Any;

	public function new(when:Dynamic, children:Any) {
		this.when = when;
		this.children = children;
	}
}

// a hidden node marking where content goes (before it)
function anchorAt(parent:Node, before:Null<Node>, tag:String):Node {
	var anchor = new Node(tag);
	anchor.style.display = None;
	var i = before == null ? parent.children.length : parent.indexOf(before);
	parent.insert(anchor, i < 0 ? parent.children.length : i);
	return anchor;
}

// For's content: Render mounts it through mount()
@:allow(hxmc.ui.reactive.Render)
class ForList<T> implements Mountable {
	final each:Dynamic;
	final render:T->Any;

	public function new(each:Dynamic, render:T->Any) {
		this.each = each;
		this.render = render;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var anchor = anchorAt(parent, before, "for");
		// (the rows belong to the owner the list is mounted in, not to the
		// effect below: its next run would dispose the rows it keeps)
		var home = Reactive.owner;
		var entries:Array<{item:T, nodes:Array<Node>, owner:Owner}> = [];
		Reactive.effect(() -> {
			var items:Array<T> = Render.read(each);
			if (items == null) items = [];
			Reactive.untrack(() -> {
				var next = [];
				// (the old entries matched: an item is looked for from the first
				// one not taken, so that a list kept in order matches in one pass)
				var old = entries, taken = [for (_ in old) false], first = 0;
				for (item in items) {
					var k = -1;
					for (j in first...old.length)
						if (!taken[j] && old[j].item == item) {
							k = j;
							break;
						}
					if (k >= 0) {
						next.push(old[k]);
						taken[k] = true;
						while (first < old.length && taken[first])
							first++;
					} else {
						var o = new Owner(home);
						var saved = Reactive.owner;
						Reactive.owner = o;
						var nodes = Render.insert(render(item), parent, anchor);
						Reactive.owner = saved;
						next.push({item: item, nodes: nodes, owner: o});
					}
				}
				for (j in 0...old.length)
					if (!taken[j]) {
						old[j].owner.dispose();
						for (n in old[j].nodes)
							if (n.parent == parent) parent.remove(n);
					}
				// in order, before the anchor (where the rows are: the new ones
				// were put there; a row's node moved out by hand is put back)
				var seq = [for (e in next) for (n in e.nodes) n];
				var at = parent.indexOf(anchor);
				var inPlace = at >= seq.length;
				if (inPlace)
					for (k in 0...seq.length)
						if (seq[k].parent != parent) {
							inPlace = false;
							break;
						}
				if (inPlace) {
					var set = new haxe.ds.ObjectMap<Node, Bool>();
					for (n in seq)
						set.set(n, true);
					for (k in at - seq.length...at)
						if (!set.exists(parent.children[k])) {
							inPlace = false;
							break;
						}
				}
				if (inPlace) parent.reorder(at - seq.length, seq) else
					for (n in seq)
						parent.insert(n, parent.indexOf(anchor));
				entries = next;
			});
		});
		Reactive.onCleanup(() -> for (e in entries)
			for (n in e.nodes)
				if (n.parent == parent) parent.remove(n));
		return [anchor];
	}
}

// Index's content: a row per index, its item in a signal
class IndexList<T> implements Mountable {
	final each:Dynamic;
	final render:(Signal<T>, Int)->Any;

	public function new(each:Dynamic, render:(Signal<T>, Int)->Any) {
		this.each = each;
		this.render = render;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var anchor = anchorAt(parent, before, "index");
		var home = Reactive.owner;
		var rows:Array<{item:Signal<T>, nodes:Array<Node>, owner:Owner}> = [];
		Reactive.effect(() -> {
			var items:Array<T> = Render.read(each);
			if (items == null) items = [];
			Reactive.untrack(() -> {
				var keep = items.length < rows.length ? items.length : rows.length;
				Reactive.batch(() -> for (i in 0...keep)
					rows[i].item.value = items[i]);
				while (rows.length > items.length) {
					var r = rows.pop();
					r.owner.dispose();
					for (n in r.nodes)
						if (n.parent == parent) parent.remove(n);
				}
				for (i in rows.length...items.length) {
					var o = new Owner(home);
					var saved = Reactive.owner;
					Reactive.owner = o;
					var item = new Signal(items[i]);
					var nodes = try Render.insert(render(item, i), parent, anchor) catch (e:Dynamic) {
						Reactive.owner = saved;
						throw e;
					}
					Reactive.owner = saved;
					rows.push({item: item, nodes: nodes, owner: o});
				}
			});
		});
		Reactive.onCleanup(() -> for (r in rows)
			for (n in r.nodes)
				if (n.parent == parent) parent.remove(n));
		return [anchor];
	}
}

// VirtualList: a scrolling view, a spacer as tall as every row, the rows in
// view placed absolutely at their index's height (each with its owner,
// under the list's)
class VirtualRows<T> implements Mountable {
	final each:Dynamic;
	final itemHeight:Float;
	final height:Float;
	final render:(Signal<T>, Int)->Any;
	final overscan:Int;
	final tag:Null<String>;

	public function new(each, itemHeight, height, render, overscan, tag) {
		this.each = each;
		this.itemHeight = itemHeight;
		this.height = height;
		this.render = render;
		this.overscan = overscan;
		this.tag = tag;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var view = new Node(tag ?? "virtual-list");
		view.style.overflow = Scroll;
		view.style.height = height;
		var spacer = new Node("spacer");
		view.append(spacer);
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(view, i < 0 ? parent.children.length : i);
		var home = Reactive.owner;
		var first = new Signal(0);
		view.onScroll = () -> first.value = Math.floor(view.scrollY / itemHeight);
		var rows = new Map<Int, {item:Signal<T>, node:Node, owner:Owner}>();
		function drop(k:Int) {
			var r = rows.get(k);
			r.owner.dispose();
			view.remove(r.node);
			rows.remove(k);
		}
		Reactive.effect(() -> {
			var items:Array<T> = Render.read(each);
			if (items == null) items = [];
			var f = first.value;
			Reactive.untrack(() -> {
				spacer.style.height = items.length * itemHeight;
				var lo = f - overscan, hi = f + Math.ceil(height / itemHeight) + 1 + overscan;
				if (lo < 0) lo = 0;
				if (hi > items.length) hi = items.length;
				for (k in [for (k in rows.keys()) k])
					if (k < lo || k >= hi) drop(k);
				Reactive.batch(() -> for (k in lo...hi) {
					var r = rows.get(k);
					if (r != null) r.item.value = items[k];
				});
				for (k in lo...hi) {
					if (rows.exists(k)) continue;
					var row = new Node("row");
					row.style.position = Absolute;
					row.style.left = 0;
					row.style.right = 0;
					row.style.top = k * itemHeight;
					row.style.height = itemHeight;
					var o = new Owner(home);
					var saved = Reactive.owner;
					Reactive.owner = o;
					var item = new Signal(items[k]);
					try Render.insert(render(item, k), row, null) catch (e:Dynamic) {
						Reactive.owner = saved;
						throw e;
					}
					Reactive.owner = saved;
					view.append(row);
					rows.set(k, {item: item, node: row, owner: o});
				}
			});
		});
		Reactive.onCleanup(() -> {
			for (k in [for (k in rows.keys()) k])
				drop(k);
			if (view.parent == parent) parent.remove(view);
		});
		return [view];
	}
}

// ErrorBoundary's content: its children, or the fallback for an error
class Boundary implements Mountable {
	final fallback:(Dynamic, Void->Void)->Any;
	final children:Any;

	public function new(fallback:(Dynamic, Void->Void)->Any, children:Any) {
		this.fallback = fallback;
		this.children = children;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var anchor = anchorAt(parent, before, "boundary");
		// (the error, boxed: null is none)
		var error = new Signal<Null<{e:Dynamic}>>(null);
		var current:Array<Node> = [];
		function clear() {
			for (n in current)
				if (n.parent == parent) parent.remove(n);
			current = [];
		}
		function show(err:Null<{e:Dynamic}>):Void {
			clear();
			if (err != null) {
				current = Render.insert(fallback(err.e, () -> error.value = null), parent, anchor);
				return;
			}
			// the children in an owner of their own, which catches their errors
			var o = new Owner(Reactive.owner);
			o.onError = e -> error.value = {e: e};
			var saved = Reactive.owner;
			Reactive.owner = o;
			var start = parent.indexOf(anchor);
			try {
				current = Render.insert(children, parent, anchor);
				Reactive.owner = saved;
			} catch (e:Dynamic) {
				Reactive.owner = saved;
				// (what was put before the error, removed)
				while (parent.indexOf(anchor) > start)
					parent.remove(parent.children[parent.indexOf(anchor) - 1]);
				o.dispose();
				current = Render.insert(fallback(e, () -> error.value = null), parent, anchor);
			}
		}
		Reactive.effect(() -> {
			var err = error.value;
			Reactive.untrack(() -> show(err));
		});
		Reactive.onCleanup(clear);
		return [anchor];
	}
}
