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
