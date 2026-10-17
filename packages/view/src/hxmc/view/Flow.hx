package hxmc.view;

import hxmc.view.Reactive;
import hxmc.view.Signal;
import hxmc.view.Memo;

// Control flow components for markup (import hxmc.view.Flow.*):
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
		return new ForList(props.each, cast props.render);

	public static function Index<T>(props:{each:Dynamic, render:(Signal<T>, Int)->Any}):Any
		return new IndexList(props.each, cast props.render);

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
		} else if (Std.isOfType(v, View)) {
			var parts = (v : View).parts;
			if (parts == null) throw "hxmc.view: a Switch holds Match cases only";
			for (x in parts())
				collect(x, out);
		}
	}

	public static function Provider<T>(props:{context:Context<T>, value:T, ?children:Any}):Any {
		Reactive.setContext(props.context, props.value);
		return props.children;
	}

	public static function ErrorBoundary(props:{fallback:(Dynamic, Void->Void)->Any, ?children:Any}):Any
		return new Boundary(props.fallback, props.children);
}

// content a renderer's own components mount (ui's Popover, VirtualList):
// it inserts its nodes before before and returns the ones it keeps there
// (a marker: what it shows goes before it); content of a renderer whose
// nodes are not N is not one
interface Mountable<N> {
	function mount(parent:N, before:Null<N>):Array<N>;
}

class MatchCase {
	public final when:Dynamic;
	public final children:Any;

	public function new(when:Dynamic, children:Any) {
		this.when = when;
		this.children = children;
	}
}

// For's, Index's and ErrorBoundary's content, which each renderer's
// Runtime mounts
class ForList {
	public final each:Dynamic;
	public final render:Dynamic->Any;

	public function new(each:Dynamic, render:Dynamic->Any) {
		this.each = each;
		this.render = render;
	}
}

class IndexList {
	public final each:Dynamic;
	public final render:(Signal<Dynamic>, Int)->Any;

	public function new(each:Dynamic, render:(Signal<Dynamic>, Int)->Any) {
		this.each = each;
		this.render = render;
	}
}

class Boundary {
	public final fallback:(Dynamic, Void->Void)->Any;
	public final children:Any;

	public function new(fallback:(Dynamic, Void->Void)->Any, children:Any) {
		this.fallback = fallback;
		this.children = children;
	}
}
