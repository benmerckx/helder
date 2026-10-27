# helder.view

Signals and JSX-like markup for Haxe, on every target: fine-grained
reactivity as Solid has it, and markup literals compiled to direct calls
on a renderer, with no virtual DOM. `helder.ui` renders it into its nodes,
drawn or native.

```haxe
import helder.view.*;
import helder.view.Flow.*;
import helder.view.Reactive.*;

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

`helder.view.Reactive`: `signal(v)` (`.value` reads and tracks, writes and
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
- Control flow (`helder.view.Flow`): `For` (keyed: rows kept and moved),
  `Index` (a row per index, its item a signal), `Show`, `Switch` and
  `Match`, `Provider`, `ErrorBoundary`.

Each literal compiles to straight-line code: the elements made by tag,
put in their parents, their static attributes set as they are, holes
through the runtime (which binds the reactive ones), static text joined at
compile time. Nothing walks a template at run time.

## Renderers in markup (design)

No defines: a literal's renderer comes from where it is, react-three-fiber's
`<Canvas>` model. helder.view knows no renderer by name; a renderer package
declares its own with types and metadata the macro reads:

- **Nodes**: a node class names its renderer, `@:rendered(helder.ui.view.NodeRenderer)`
  on `helder.ui.Node` (subclasses inherit it). `Render.render(content,
  parent)` and `insert` pick the renderer from the parent's type as now;
  a type with no `@:rendered` is matched against the renderers reached so
  far (`Renders<N>`), else an error naming it. A renderer may also give an
  entry of its own (`DomRenderer.render`) for node types it cannot mark.
- **Pinned views**: `helder.view.ViewOf<R>` (an abstract over `View`, `R` the
  renderer's class) is a View of R's markup; packages name theirs
  (`helder.ui.view.UiView`, `helder.scene.view.SceneView`).
- **Boundary tags** are ordinary components: their `children` prop typed
  `ViewOf<S>` makes their content S's markup, their return type (`ViewOf<R>`,
  or R's node type) the renderer whose markup they go in. `<Scene>` is
  `(props:{?camera:..., ?children:SceneView}):helder.ui.Node`: a ui node
  whose children are scene nodes. `<Surface>` returns no node: the root of a
  program (`App.run(<Surface>...</Surface>)`, which calls its components in a
  root of their own, `Render.open`).
- **Elements**: a renderer with a closed set lists it, `@:elements("node",
  "mesh", ...)` on its class; another name in its markup is an error.

The macro compiles each literal when it is typed (an expression macro; the
`Markup` build macro only wraps the literals) and tracks the renderer down
the tree: a literal's renderer is, in order, the one given by the literal
around it (nested markup in its holes, a component's children unless the
component's `children` prop names another), by `Render.render`'s parent,
by the expected type (`ViewOf<R>`), by the enclosing function's return type
(`ViewOf<R>` or R's node: a component pinned to R), by its class's
`@:renderer` when it names one. A literal so placed is compiled once, for
that renderer; a component's call in it is checked against the component's
pin. A literal with none of these (a component returning plain `View`, a
literal held in a variable) is compiled for each renderer the program
reaches: its code for each is generated after typing (`Context.onAfterTyping`),
from a template kept in its class's metadata (so a cached module keeps it),
into one class per renderer whose `__init__` hands it to that renderer's
runtime; its holes, component factories included, are evaluated where the
literal is, as before. A renderer is reached when markup is compiled for it
or content is mounted into its nodes; only those get a runtime
(`ViewRuntime_<renderer>`). Renderer identity at run time is a hash of the
class path (`Render.idOf`), stable across builds.

Errors, at the tag or the literal:

- `helder.view: <Scene> is helder.ui.view.NodeRenderer's (it returns
  helder.ui.Node), not helder.web.DomRenderer's markup`;
- `markup: <view> is no element of helder.scene.view.SceneRenderer
  (node, mesh, light, camera; <Ui> goes back to ui)`;
- `helder.view: String is no renderer's node (... @:rendered)`;
- at run time, a View pinned to one renderer mounted into another's node:
  `helder.view: View(File.hx:12) is SceneRenderer's markup, mounted into a
  NodeRenderer node`.

## Renderers

A renderer is a class of static functions over its node type that
implements `Renders<N>` (the list is in `Renders.hx`, checked at compile
time): `createElement`, `createText`, `createMarker`, `setText`,
`holdsText`, `setProperty`, `setStyle`, `listen`, `insert`, `remove`,
`parentOf`, `arrange`, `isNode`. A program names its renderers with
`-D helder.view.renderer.<name>=<class>` (`-lib helder` sets ui's,
`helder.ui.view.NodeRenderer`); there may be several.

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
widgets only make sense there: `@:renderer(helder.ui.view.NodeRenderer)`
(renderers by their classes) compiles its markup for those only (another
renderer's code a throw), and `Render.render` and `insert` into nodes of a
renderer the program lacks a throw too. Its components, in another
renderer's markup, are the functions of the same name of the class it
names for that renderer: with `@:renderer(helder.ui.view.NodeRenderer,
helder.web.DomRenderer => DomControls)` on a class of drawn controls,
`<Button/>` with them imported is `DomControls.Button` in a page's markup (`helder.view.Pick`, when the literal is typed); a component
with none for a renderer is an error naming it and the renderer.

A function of such a class marked `@:neutral` is for every renderer, one
definition for all (a single-source component): its elements are the neutral
ones (`view`, `text`, `scroll`, `icon`, `field`, and `view:button`,
`text:p`... naming a page's element), which a renderer with
`neutralElement`, `neutralProperty`, `neutralSetter`, `neutralListen`
and `part` (macros: helder.web's DomRenderer) realises its own way at
compile time, and any other as its own elements (ui's, whose vocabulary
they are). A neutral element's `ref` gets a part (`helder.ui.Part`: the
Node, or the page's element wrapped when a ref is given), its `tag` and
`id` are compiled into the passes that use them only.

## Tests

`bun run test view`: `tests/view/ViewTest.hx` on two test renderers (boundaries
between them included), on Eval, natively and in JavaScript, and the
programs the macro rejects (`tests/view/reject`). The core uses no hxmc-only
feature, so components compile to JavaScript unchanged.
