package helder.ui.view;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.Mountable;
import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Owner;
import helder.view.graph.Signal;

// helder.ui's own control flow components for markup (import
// helder.ui.view.UiFlow.*), beside helder.view.Flow's:
//
//   <Popover open={open} placement="below">{...}</Popover>
//   <VirtualList each={rows} by={r -> r.id} estimate={44} selected={sel}>{(row, i) -> ...}</VirtualList>
class UiFlow {
	// the children in a popup (helder.ui.Popup: a layer over the tree), open
	// while open is true: anchored to anchor (else the node the markup puts
	// it in), placed by placement ("below", "above", "right", "left",
	// "center"; gap pixels away), modal or not; onDismiss when a click
	// outside (unless dismissOnOutside is false) or Escape asks it to close; onOpen once it is open (to move
	// the focus into it); a modal one's backdrop its colour; the popup's
	// slot for a theme (Node.slot). Its content is rendered once, kept while closed.
	public static function Popover(props:{open:Read<Bool>, ?anchor:Node, ?placement:String, ?gap:Float, ?modal:Bool, ?backdrop:Color, ?slot:String,
			?onDismiss:Void->Void, ?dismissOnOutside:Bool, ?onOpen:helder.ui.Popup->Void, ?at:Void->{x:Float, y:Float}, ?tag:String, ?children:Any}):Any
		return new PopoverMount(props);

	// the window's menu bar (helder.ui.menu.MenuBar): the platform's, or
	// drawn here (put it first in the window's content); ref: the bar
	public static function MenuBarView(props:{menus:Array<helder.ui.menu.Menu>, ?ref:helder.ui.menu.Menus.MenuBar->Void}):Any
		return new helder.ui.menu.Menus.MenuBarMount(props);

	// a long list in a scroller (helder.ui.VirtualScroll): only the rows in
	// view are made, and overscan more on each side (3); rows that leave are
	// hidden and kept (keep of them, 64, the farthest let go first), by key
	// as For keeps them: by the item itself, by what by gives for it (a
	// row's Read then its key's latest item: a change to one item changes
	// its row alone), or keyed={false} by index. Its rows' heights are their
	// own, estimated (estimate, 44 pixels) until each is measured, the scroll
	// anchored to the row in view (an estimate made real, rows put in or
	// taken out above it: nothing moves); itemHeight: every row that high.
	// height pixels high, else it grows in its parent (min-height 0). A
	// listbox of options to assistive technology (label: its name), each
	// with its place among all of them; Up, Down, Page Up and Down, Home
	// and End move the focus to a row (made if need be), selected (the key
	// of the row selected: written as the focus moves, a row pressed) and
	// onActivate (Enter, Space) given its item. Its child function gets a
	// row's item (a Read) and its index when made; ref the VirtualScroll
	// (scrollToIndex, focusIndex, the window).
	public static function VirtualList<T>(props:{each:Read<Array<T>>, children:(Read<T>, Int)->Any, ?by:T->Dynamic, ?keyed:Bool, ?estimate:Float,
			?itemHeight:Float, ?height:Float, ?overscan:Int, ?keep:Int, ?selected:Signal<Dynamic>, ?onActivate:T->Void, ?label:String,
			?ref:VirtualScroll->Void, ?tag:String}):Any
		return new VirtualRows<T>(props);
}

// Popover: a hidden marker where the markup puts it; the popup opened in
// the marker's Ui while open is true
@:renderer(helder.ui.view.NodeRenderer)
class PopoverMount implements Mountable<Node> {
	final props:{open:Read<Bool>, ?anchor:Node, ?placement:String, ?gap:Float, ?modal:Bool, ?backdrop:Color, ?slot:String, ?onDismiss:Void->Void,
		?dismissOnOutside:Bool, ?onOpen:helder.ui.Popup->Void, ?at:Void->{x:Float, y:Float}, ?tag:String, ?children:Any};

	public function new(props)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var marker = new Node("popover");
		marker.style.display = None;
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(marker, i < 0 ? parent.children.length : i);
		var p = new helder.ui.Popup(props.tag);
		if (props.placement != null) p.placement = props.placement;
		if (props.gap != null) p.gap = props.gap;
		p.modal = props.modal == true;
		if (props.backdrop != null) p.style.background = props.backdrop;
		if (props.slot != null) p.slot = props.slot;
		p.onDismiss = props.onDismiss;
		p.dismissOnOutside = props.dismissOnOutside != false;
		p.anchor = props.anchor != null ? props.anchor : parent;
		Render.insert(props.children, p, null);
		var open:Read<Bool> = Read.of(props.open);
		function sync(on:Bool) {
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
		}
		// (opened once the marker is in its Ui: after the insertion)
		var home = Graph.getOwner();
		Graph.onSettled(() -> Graph.runWithOwner(home, () -> Graph.renderEffect(() -> {
			var w:Dynamic = open();
			w != null && w != false;
		}, sync)));
		Graph.onCleanup(() -> if (p.ui != null) p.ui.close(p));
		return [marker];
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


// VirtualList: a VirtualScroll whose rows are the list's, each made in an
// owner of its own (under the list's) holding a signal of its item; the
// list's changes diffed as For's (a common start and end, the middle by key)
// into the scroller's splices, its rows' items written
@:renderer(helder.ui.view.NodeRenderer)
class VirtualRows<T> implements Mountable<Node> {
	final props:{each:Read<Array<T>>, children:(Read<T>, Int)->Any, ?by:T->Dynamic, ?keyed:Bool, ?estimate:Float, ?itemHeight:Float, ?height:Float,
		?overscan:Int, ?keep:Int, ?selected:Signal<Dynamic>, ?onActivate:T->Void, ?label:String, ?ref:VirtualScroll->Void, ?tag:String};

	public function new(props)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var p = props;
		var v = new VirtualScroll(p.tag, p.estimate != null ? p.estimate : p.itemHeight != null ? p.itemHeight : 44);
		if (p.itemHeight != null) v.fixedHeight = p.itemHeight;
		if (p.height != null) v.style.height = p.height else {
			v.style.grow = 1;
			v.style.minHeight = 0;
		}
		if (p.overscan != null) v.overscan = p.overscan;
		if (p.keep != null) v.keep = p.keep;
		if (p.label != null) v.semantics.label = p.label;
		var each:Read<Array<T>> = Read.of(p.each), key = p.by, keyed = p.keyed != false || p.by != null;
		var selected = p.selected, render = p.children;
		var items:Array<T> = [], started = false;
		var home = Graph.getOwner();
		function keyOf(i:Int):Dynamic
			return !keyed ? i : key != null ? key(items[i]) : items[i];
		v.onMakeRow = (i, row) -> {
			var o = new Owner(home), k:Dynamic = keyOf(i);
			var cell = helder.view.graph.Node.signal(items[i], {ownedWrite: true});
			Graph.runWithOwner(o, () -> {
				Render.insert(render(cell, i), row, null);
				// (selected: its row's key's)
				if (selected != null) Graph.renderEffect(() -> selected() == k, (on:Bool) -> row.semantics.selected = on);
			});
			return new RowCell<T>(o, cell);
		};
		v.onDropRow = (row, d) -> (d : RowCell<T>).owner.dispose();
		v.onRowActive = i -> if (selected != null) selected(keyOf(i));
		v.onRowActivate = i -> if (p.onActivate != null) p.onActivate(items[i]);
		function same(a:T, b:T):Bool
			return a == b || key != null && key(a) == key(b);
		Graph.renderEffect(() -> {
			var a:Array<T> = each();
			a == null ? [] : a;
		}, (next:Array<T>) -> {
			var old = items;
			items = next;
			if (!started) {
				started = true;
				v.reset(next.length);
				return;
			}
			if (next == old) return;
			var n = old.length, m = next.length;
			if (!keyed) {
				// (by index: the rows past the shorter's end)
				var c = n < m ? n : m;
				v.splice(c, n - c, m - c);
			} else {
				// (a common start and end; the middle's rows matched by key)
				var lo = 0;
				while (lo < n && lo < m && same(old[lo], next[lo]))
					lo++;
				var s = 0;
				while (s < n - lo && s < m - lo && same(old[n - 1 - s], next[m - 1 - s]))
					s++;
				var removed = n - s - lo, inserted = m - s - lo;
				var moved:Null<Array<Int>> = null;
				if (removed > 0 && inserted > 0) {
					var at = new KeyIndex();
					for (k in 0...inserted)
						at.set(key != null ? key(next[lo + k]) : next[lo + k], k);
					moved = [for (k in 0...removed) at.get(key != null ? key(old[lo + k]) : old[lo + k])];
				}
				v.splice(lo, removed, inserted, moved);
			}
			// (the rows made: their key's item now)
			for (r in v.rows()) {
				var c:Null<RowCell<T>> = r.data;
				if (c != null && r.index < items.length) c.cell.write(items[r.index]);
			}
		});
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(v, i < 0 ? parent.children.length : i);
		if (p.ref != null) p.ref(v);
		Graph.onCleanup(() -> {
			v.reset(0);
			if (v.parent == parent) parent.remove(v);
		});
		return [v];
	}
}

// (a VirtualList's row: its owner, its item)
private class RowCell<T> {
	public final owner:Owner;
	public final cell:helder.view.graph.Node<T>;

	public function new(owner, cell) {
		this.owner = owner;
		this.cell = cell;
	}
}

// (keys to places: numbers, strings, other values by identity)
private class KeyIndex {
	final ints = new haxe.ds.IntMap<Int>();
	final strings = new haxe.ds.StringMap<Int>();
	final others = new haxe.ds.ObjectMap<{}, Int>();

	public function new() {}

	public function set(k:Dynamic, v:Int)
		if (Std.isOfType(k, Int)) ints.set(k, v) else if (Std.isOfType(k, String)) strings.set(k, v) else if (Std.isOfType(k, Float)
			|| Std.isOfType(k, Bool)) strings.set("#" + Std.string(k), v) else others.set(k, v);

	public function get(k:Dynamic):Int {
		var r:Null<Int> = if (Std.isOfType(k, Int)) ints.get(k) else if (Std.isOfType(k, String)) strings.get(k) else if (Std.isOfType(k, Float)
			|| Std.isOfType(k, Bool)) strings.get("#" + Std.string(k)) else others.get(k);
		return r == null ? -1 : r;
	}
}
