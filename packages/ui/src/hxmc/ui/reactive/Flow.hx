package hxmc.ui.reactive;

import hxmc.ui.*;
import hxmc.ui.reactive.Reactive;
import hxmc.ui.reactive.Signal;
import hxmc.ui.reactive.Memo;

// Control flow components for markup (import hxmc.ui.reactive.Flow.*):
//
//   <For each={todos} render={t -> <Item todo={t}/>}/>
//   <Show when={() -> count.value > 0} fallback="none">{...}</Show>
//
// For keeps each item's nodes (keyed by the item itself): when the list
// changes, items still there are moved, not made again; the others are
// made, or removed with their computations.
class Flow {
	public static function For<T>(props:{each:Dynamic, render:T->Any}):Any
		return new ForList(props.each, props.render);

	public static function Show(props:{when:Dynamic, ?fallback:Any, ?children:Any}):Any
		return () -> {
			var w:Dynamic = Render.read(props.when);
			w != null && w != false ? props.children : props.fallback;
		};
}

// For's content: Render mounts it through mount()
@:allow(hxmc.ui.reactive.Render)
class ForList<T> {
	final each:Dynamic;
	final render:T->Any;

	public function new(each:Dynamic, render:T->Any) {
		this.each = each;
		this.render = render;
	}

	public function mount(parent:Node, before:Null<Node>):Array<Node> {
		var anchor = new Node("for");
		anchor.style.display = None;
		var i = before == null ? parent.children.length : parent.indexOf(before);
		parent.insert(anchor, i < 0 ? parent.children.length : i);
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
						var o = new Owner(Reactive.owner);
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
