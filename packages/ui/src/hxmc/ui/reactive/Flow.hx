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
		var i = before == null ? parent.children.length : parent.children.indexOf(before);
		parent.insert(anchor, i < 0 ? parent.children.length : i);
		var entries:Array<{item:T, nodes:Array<Node>, owner:Owner}> = [];
		Reactive.effect(() -> {
			var items:Array<T> = Render.read(each);
			if (items == null) items = [];
			Reactive.untrack(() -> {
				var next = [];
				var old = entries.copy();
				for (item in items) {
					var k = -1;
					for (j in 0...old.length)
						if (old[j].item == item) {
							k = j;
							break;
						}
					if (k >= 0) {
						next.push(old[k]);
						old.splice(k, 1);
					} else {
						var o = new Owner(Reactive.owner);
						var saved = Reactive.owner;
						Reactive.owner = o;
						var nodes = Render.insert(render(item), parent, anchor);
						Reactive.owner = saved;
						next.push({item: item, nodes: nodes, owner: o});
					}
				}
				for (e in old) {
					e.owner.dispose();
					for (n in e.nodes)
						if (n.parent == parent) parent.remove(n);
				}
				// in order, before the anchor
				for (e in next)
					for (n in e.nodes)
						parent.insert(n, parent.children.indexOf(anchor));
				entries = next;
			});
		});
		Reactive.onCleanup(() -> for (e in entries)
			for (n in e.nodes)
				if (n.parent == parent) parent.remove(n));
		return [anchor];
	}
}
