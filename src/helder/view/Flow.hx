package helder.view;

import helder.view.graph.Graph;
import helder.view.graph.Read;
import helder.view.graph.Context;

// Control flow components for markup (import helder.view.Flow.*), Solid 2's:
//
//   <For each={todos}>{t -> <Item todo={t}/>}</For>
//   <For each={names} keyed={false}>{name -> <text>{name()}</text>}</For>
//   <Repeat count={3}>{i -> <dot/>}</Repeat>
//   <Show when={count() > 0} fallback="none">{...}</Show>
//   <Switch fallback="other"><Match when={a()}>A</Match><Match when={b()}>B</Match></Switch>
//   <Provider context={theme} value={dark}>{...}</Provider>
//   <Errored fallback={(e, reset) -> ...}>{...}</Errored>
//   <Loading fallback={<text>loading</text>}>{...}</Loading>
//
// For's row is its child function, given the item as a Read: keyed by the
// item itself (the default), a row is kept and moved while its item is in
// the list, its Read the item; keyed={false}, a row per index, its Read
// what is at that index (Solid 1's Index). Repeat makes a row per number
// below count. Show and Switch render a branch again only when the branch
// chosen changes (not on every change of what chooses it): `when` is
// truthy when not null and not false. Provider sets a context for its
// children (Graph.use). Errored shows fallback instead of its children
// when making them throws, or a computation inside them does later; reset
// tries again. Loading shows fallback instead of its children while what
// they read on their first load is pending (an async memo, helder.asset's
// Asset); once it has shown them it keeps them shown, a later change held
// until it lands (Graph.isPending says one is on its way). Its children
// are made once: what reads a value not ready waits inside the graph.
class Flow {
	public static function For<T>(props:{each:Read<Array<T>>, ?keyed:Bool, children:Read<T>->Any}):Any
		return new ForList(cast Read.of(props.each), props.keyed != false, cast props.children);

	public static function Repeat(props:{count:Read<Int>, children:Int->Any}):Any {
		var count:Read<Int> = Read.of(props.count), render = props.children;
		var numbers = Graph.memo(() -> [for (i in 0...count()) i]);
		return new ForList(cast(numbers : Read<Array<Int>>), true, (i:Read<Dynamic>) -> render(i()));
	}

	public static function Show<T>(props:{when:Read<T>, ?fallback:Any, ?children:Any}):Any {
		var when:Read<T> = Read.of(props.when);
		var on = Graph.memo(() -> truthy(when()));
		return () -> on() ? props.children : props.fallback;
	}

	public static function Match<T>(props:{when:Read<T>, ?children:Any}):Any
		return new MatchCase(cast Read.of(props.when), props.children);

	public static function Switch(props:{?fallback:Any, ?children:Any}):Any {
		var cases:Array<MatchCase> = [];
		Graph.untrack(() -> collect(props.children, cases));
		var chosen = Graph.memo(() -> {
			var k = -1;
			for (i in 0...cases.length)
				if (truthy(cases[i].when.read())) {
					k = i;
					break;
				}
			k;
		});
		return () -> {
			var k = chosen();
			k < 0 ? props.fallback : cases[k].children;
		};
	}

	// (truthy: not null, not false)
	static inline function truthy(v:Dynamic):Bool
		return v != null && v != false;

	// the Match cases among a Switch's children (its components called)
	static function collect(v:Dynamic, out:Array<MatchCase>) {
		if (v == null) return;
		if (Std.isOfType(v, MatchCase)) out.push(v) else if (Std.isOfType(v, Array)) {
			for (x in (v : Array<Dynamic>))
				collect(x, out);
		} else if (Std.isOfType(v, View)) {
			var parts = (v : View).parts;
			if (parts == null) throw "helder.view: a Switch holds Match cases only";
			for (x in parts())
				collect(x, out);
		}
	}

	public static function Provider<T>(props:{context:Context<T>, value:T, ?children:Any}):Any {
		Graph.setContext(props.context, props.value);
		return props.children;
	}

	public static function Errored(props:{fallback:(error:Dynamic, reset:Void->Void)->Any, ?children:Any}):Any
		return new Boundary(props.fallback, props.children);

	public static function Loading(props:{?fallback:Any, ?children:Any}):Any
		return new Waiting(props.fallback, props.children);
}

// content a renderer's own components mount (ui's Popover, VirtualList):
// it inserts its nodes before before and returns the ones it keeps there
// (a marker: what it shows goes before it); content of a renderer whose
// nodes are not N is not one
interface Mountable<N> {
	function mount(parent:N, before:Null<N>):Array<N>;
}

class MatchCase {
	public final when:Reader<Dynamic>;
	public final children:Any;

	public function new(when:Reader<Dynamic>, children:Any) {
		this.when = when;
		this.children = children;
	}
}

// For's, Loading's and Errored's content, which each renderer's
// ViewRuntime mounts
class ForList {
	public final each:Reader<Array<Dynamic>>;
	public final keyed:Bool;
	public final render:Read<Dynamic>->Any;

	public function new(each:Reader<Array<Dynamic>>, keyed:Bool, render:Read<Dynamic>->Any) {
		this.each = each;
		this.keyed = keyed;
		this.render = render;
	}
}

class Waiting {
	public final fallback:Any;
	public final children:Any;

	public function new(fallback:Any, children:Any) {
		this.fallback = fallback;
		this.children = children;
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

// (a component whose making read a value not ready: made once it is)
class Deferred {
	public final factory:Void->Any;

	public function new(factory:Void->Any)
		this.factory = factory;
}
