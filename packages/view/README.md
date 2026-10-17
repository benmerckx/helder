# @hxmc/view

Signals and JSX-like markup for Haxe, on every target: fine-grained
reactivity as Solid has it, and markup literals compiled to direct calls
on a renderer, with no virtual DOM. `@hxmc/ui` renders it into its nodes,
drawn or native. Why it is built this way: [docs/plans/view.md](../../docs/plans/view.md).

```haxe
import hxmc.view.*;
import hxmc.view.Flow.*;
import hxmc.view.Reactive.*;

class App implements Markup {
	static function Counter(props:{label:String}):View {
		var count = signal(0);
		return <view direction="row" column-gap={8}>
			<text>{props.label}: {count}</text>
			<view onClick={_ -> count.value++}>+1</view>
		</view>;
	}

	static function main() {
		var items = signal(["a", "b"]);
		Render.render(<view>
			<Counter label="Clicks"/>
			<For each={items} render={(i:String) -> <text>{i}</text>}/>
		</view>, root);
	}
}
```

## Signals

`hxmc.view.Reactive`: `signal(v)` (`.value` reads and tracks, writes and
notifies; `peek`, `update`, `changed`), `memo(fn)` (derived, lazy, its
observers notified only when its value differs), `effect(fn)` (runs now
and again after a change to what it read), `batch`, `untrack`, `root`,
`onCleanup`, `onMount`, `getOwner` and `runWithOwner`, contexts
(`context`, `provide`, `use`, `setContext`). Computations form an
ownership tree: what a computation creates is disposed before it runs
again. No glitches: a diamond runs once per write, with consistent values.

## Markup

A class that `implements Markup` has its literals compiled (one alone:
`View.view(<...>)`). A literal's value is a `View`: its holes (`{expr}`
children and attribute values) are evaluated where the literal is; mounting
it makes its nodes, each time it is mounted.

- Lowercase names are the renderer's elements; capitalized or dotted names
  are components, `Name(props)`, called once when mounted, untracked, in an
  owner of their own. Haxe checks the props: a wrong type or an unknown
  prop is an error at the attribute. Content is the `children` prop, a
  `View`.
- Attributes: `name="text"`, `name={expr}`, `name` (true), `{...object}`;
  `on...` are listeners, `ref={n -> ...}` gets the node, `key` is ignored,
  `style` is the renderer's style.
- A hole or attribute whose value is a `Signal`, a `Memo` or a function is
  bound: the text, attribute or region follows it. Text follows JSX's
  whitespace rule; a run of text and text holes is one text node.
- Control flow (`hxmc.view.Flow`): `For` (keyed: rows kept and moved),
  `Index` (a row per index, its item a signal), `Show`, `Switch` and
  `Match`, `Provider`, `ErrorBoundary`.

Each literal compiles to straight-line code: the elements made by tag,
put in their parents, their static attributes set as they are, holes
through `Render` (which binds the reactive ones), static text joined at
compile time. Nothing walks a template at run time.

## The renderer contract

A renderer is a class of static functions over its node type that
implements `Renders<N>` (the list is in `Renders.hx`, checked at compile
time): `createElement`, `createText`, `createMarker`, `setText`,
`holdsText`, `setProperty`, `setStyle`, `listen`, `insert`, `remove`,
`parentOf`, `arrange`, `isNode`. A program names its renderer with
`-D hxmc.view.renderer=<class>`; markup and the runtime call it as `Host`
(its node type `HostNode`), so every operation is a direct call. `@hxmc/ui`'s
is `hxmc.ui.view.NodeRenderer`, which `-lib hxmc.ui` sets.

## Tests

`make view-check`: `test/ViewTest.hx` on a test renderer, on Eval and
natively, and the programs the macro rejects (`test/reject`).
