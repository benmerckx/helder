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
- Haxe's lexer ends a literal at its root's `/>` only while it is in the
  root's opening tag, which any `<` in an attribute leaves (`i < n`,
  `render={i -> <Card/>}`): such a root is closed by its closing tag,
  `<Rows render={i -> <Card/>}></Rows>`. Inside the root, markup and
  comparisons nest freely.
- Control flow (`hxmc.view.Flow`): `For` (keyed: rows kept and moved),
  `Index` (a row per index, its item a signal), `Show`, `Switch` and
  `Match`, `Provider`, `ErrorBoundary`.

Each literal compiles to straight-line code: the elements made by tag,
put in their parents, their static attributes set as they are, holes
through the runtime (which binds the reactive ones), static text joined at
compile time. Nothing walks a template at run time.

## Renderers

A renderer is a class of static functions over its node type that
implements `Renders<N>` (the list is in `Renders.hx`, checked at compile
time): `createElement`, `createText`, `createMarker`, `setText`,
`holdsText`, `setProperty`, `setStyle`, `listen`, `insert`, `remove`,
`parentOf`, `arrange`, `isNode`. A program names its renderers with
`-D hxmc.view.renderer.<name>=<class>` (`-lib hxmc.ui` sets ui's,
`hxmc.ui.view.NodeRenderer`); there may be several.

Components are renderer-agnostic: each literal is compiled for each
renderer, and the runtime (`ViewRuntime`, written against placeholders) is
copied for each. `Render.render(content, parent)` picks the renderer by
the parent's type when compiling; everything mounted there is made by
that renderer, every node operation a direct call to it. A component that
makes a node of one renderer and renders its children into it with
another is a boundary:

```haxe
// a ui canvas in a page: the page's element, ui inside it
static function UiCanvas(props:{width:Int, height:Int, ?children:View}):Any {
	var canvas = DomRenderer.createElement("canvas");
	var window = new UiWindow(canvas, props.width, props.height);
	Render.render(props.children, window.root);
	return canvas;
}
```

A class's literals may be limited to some renderers, those whose
widgets only make sense there: `@:renderer(hxmc.ui.view.NodeRenderer)`
(renderers by their classes) compiles its markup for those only (another
renderer's code a throw), and `Render.render` and `insert` into nodes of a
renderer the program lacks a throw too. Its components, in another
renderer's markup, are the functions of the same name of the class it
names for that renderer: `@:renderer(hxmc.ui.view.NodeRenderer,
hxmc.web.DomRenderer => hxmc.web.widgets.Widgets)` is ui's widgets, so
that `<Button/>` with ui's widgets imported is the DOM's Button in a
page's markup (`hxmc.view.Pick`, when the literal is typed); a component
with none for a renderer is an error naming it and the renderer.

## Tests

`make view-check`: `test/ViewTest.hx` on two test renderers (boundaries
between them included), on Eval, natively and in JavaScript, and the
programs the macro rejects (`test/reject`). The core uses no hxmc-only
feature, so components compile to JavaScript unchanged.
