package helder.ui.view;

import helder.ui.*;
import helder.view.*;
import helder.view.Flow.Mountable;
import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Owner;

// helder.ui's own control flow components for markup (import
// helder.ui.view.UiFlow.*), beside helder.view.Flow's:
//
//   <Popover open={open} placement="below">{...}</Popover>
//   <Hotkey keys="Mod+S" action={save}/>
//   <VirtualList each={rows} itemHeight={20} height={300}>{(row, i) -> ...}</VirtualList>
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

	// a keyboard shortcut while it is mounted (Ui.shortcut): keys
	// (helder.ui.Shortcut: "Mod+S", "Shift+F10") run action anywhere in the
	// window, or, local, while the focus is inside the node the markup puts it in
	public static function Hotkey(props:{keys:String, action:Void->Void, ?local:Bool}):Any
		return new HotkeyMount(props);

	// a long list in a scrolling view height pixels high: only the rows in
	// view are made (and overscan more on each side, 3), each itemHeight
	// high, again as it scrolls; its child function gets a row's item (a
	// Read: what is at its index when the list changes) and its index
	public static function VirtualList<T>(props:{each:Read<Array<T>>, itemHeight:Float, height:Float, children:(Read<T>, Int)->Any, ?overscan:Int,
			?tag:String}):Any
		return new VirtualRows(cast Read.of(props.each), props.itemHeight, props.height, cast props.children, props.overscan ?? 3, props.tag);
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

// Hotkey: a hidden marker; the shortcut added to its Ui once mounted
class HotkeyMount implements Mountable<Node> {
	final props:{keys:String, action:Void->Void, ?local:Bool};

	public function new(props)
		this.props = props;

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var marker = anchorAt(parent, before, "hotkey");
		// (a mistake in keys thrown at once)
		Shortcut.parse(props.keys);
		var remove:Null<Void->Void> = null;
		Graph.onSettled(() -> {
			if (marker.ui != null) remove = marker.ui.shortcut(props.keys, () -> props.action(), props.local == true ? parent : null);
		});
		Graph.onCleanup(() -> if (remove != null) remove());
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


// VirtualList: a scrolling view, a spacer as tall as every row, the rows in
// view placed absolutely at their index's height (each with its owner,
// under the list's)
@:renderer(helder.ui.view.NodeRenderer)
class VirtualRows<T> implements Mountable<Node> {
	final each:Reader<Array<T>>;
	final itemHeight:Float;
	final height:Float;
	final render:(Read<T>, Int)->Any;
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
		// (its height the rows' extent: kept, not shrunk to the view)
		spacer.style.shrink = 0;
		view.append(spacer);
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(view, i < 0 ? parent.children.length : i);
		var home = Graph.getOwner();
		var first = Graph.signalOf(0, {ownedWrite: true});
		view.onScroll = () -> first(Math.floor(view.scrollY / itemHeight));
		var rows = new Map<Int, {item:helder.view.graph.Node<T>, node:Node, owner:Owner}>();
		function drop(k:Int) {
			var r = rows.get(k);
			r.owner.dispose();
			view.remove(r.node);
			rows.remove(k);
		}
		Graph.renderEffect(() -> {
			var items:Array<T> = each.read();
			{items: items == null ? [] : items, first: first()};
		}, (at:{items:Array<T>, first:Int}) -> {
			var items = at.items, f = at.first;
			spacer.style.height = items.length * itemHeight;
			var lo = f - overscan, hi = f + Math.ceil(height / itemHeight) + 1 + overscan;
			if (lo < 0) lo = 0;
			if (hi > items.length) hi = items.length;
			for (k in [for (k in rows.keys()) k])
				if (k < lo || k >= hi) drop(k);
			for (k in lo...hi) {
				var r = rows.get(k);
				if (r != null) r.item.write(items[k]);
			}
			for (k in lo...hi) {
				if (rows.exists(k)) continue;
				var row = new Node("row");
				row.style.position = Absolute;
				row.style.left = 0;
				row.style.right = 0;
				row.style.top = k * itemHeight;
				row.style.height = itemHeight;
				var o = new Owner(home);
				var item = helder.view.graph.Node.signal(items[k], {ownedWrite: true});
				Graph.runWithOwner(o, () -> Render.insert(render(item, k), row, null));
				view.append(row);
				rows.set(k, {item: item, node: row, owner: o});
			}
		});
		Graph.onCleanup(() -> {
			for (k in [for (k in rows.keys()) k])
				drop(k);
			if (view.parent == parent) parent.remove(view);
		});
		return [view];
	}
}
