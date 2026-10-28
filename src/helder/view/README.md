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

## Renderers in markup

No defines: a literal's renderer comes from where it is, react-three-fiber's
`<Canvas>` model. helder.view knows no renderer by name; a renderer package
declares its own with types and metadata the macro reads:

- **Nodes**: a node class names its renderer, `@:rendered(helder.ui.view.NodeRenderer)`
  on `helder.ui.Node` (subclasses inherit it). `Render.render(content,
  parent)` and `insert` pick the renderer from the parent's type; a type
  with no `@:rendered` is matched against the renderers reached so far,
  else an error naming it. A renderer may give an entry of its own for node
  types it cannot mark (`DomRenderer.render`: `Render.renderAs`).
- **Pinned views**: `helder.view.ViewOf<R>` (an abstract over `View`, `R` the
  renderer's class) is a View of R's markup; packages name theirs
  (`helder.ui.view.UiView`, `helder.scene.view.SceneView`).
- **Boundary tags** are ordinary components: their `children` prop typed
  `ViewOf<S>` makes their content S's markup, their return type (`ViewOf<R>`,
  or R's node type) the renderer whose markup they go in. `<Scene>` is
  `(props:{?camera:..., ?children:SceneView}):helder.ui.Node`: a ui node
  whose children are scene nodes. They mount their children with
  `Render.insert`, in their own owner: contexts reach across them.
- **Roots**: `RootView` (`ViewOf<Root>`, `Root` no renderer) is content
  with no parent, components only; a component returning one is a root
  (`<Surface>`: a window). `Render.open(<>...</>)` calls them in a root of
  their own (a Show among them opens and closes them), its dispose closes
  them; `UiWindow.run(content)` opens it and runs the loop.
- **Elements**: a renderer with a closed set lists it, `@:elements("node",
  "mesh", ...)` on its class; another name in its markup is an error.

The macro compiles each literal when it is typed (an expression macro,
`View.literal`; the `Markup` build macro only wraps the literals) and
tracks the renderer down the tree: a literal's renderer is, in order, the
one given by the literal around it (nested markup in its holes, a
component's children unless the component's `children` prop names
another), by `Render.render`'s parent, by the expected type (`ViewOf<R>`),
by the enclosing function's return type (`ViewOf<R>` or R's node: a
component pinned to R), by its class's `@:renderer` when it names one. A
literal so placed is compiled once, for that renderer; a component's call
in it is checked against the component's pin. A literal with none of these
(a component returning plain `View`, a literal held in a variable) is
agnostic, compiled for each renderer the program reaches: its code for each
is generated after typing (`Context.onAfterTyping`), from a template kept
in its class's metadata (so a cached module keeps it), into a class per
renderer (`Late_<hash>`, named by its code) whose `__init__` hands it to
that renderer's runtime; on JavaScript each literal's code is a function
of its own, kept by DCE only with the field the literal is in
(`@:ifFeature`). Its holes, component factories included, are evaluated
where the literal is, as before. A renderer is reached when markup is
compiled for it or content is mounted into its nodes; only those get a
runtime (`ViewRuntime_<name>`). Renderer identity at run time is a hash of
the class path (`Render.idOf`), stable across builds.

Errors, at the tag or the literal (tests/view/reject):

- `helder.view: <Mark> is OtherRenderer's markup (it returns
  helder.view.ViewOf<OtherRenderer>), not TestRenderer's` (a component
  pinned to another renderer; `<Scene>` in a page's markup: ui's);
- `helder.view: <Window> is a root (it returns helder.view.RootView):
  UiWindow.run's or Render.open's content, not TestRenderer's markup`;
- `markup: <div> needs a renderer's parent: a root (RootView: UiWindow.run's,
  Render.open's) holds components only (<Surface>...)`;
- `helder.view: WebTags.Surface has no version for
  helder.ui.view.NodeRenderer (@:renderer names none)` (a component of a
  class limited to other renderers);
- `markup: <view> is no element of helder.scene.view.SceneRenderer (node,
  mesh, light, camera)`;
- `helder.view: String is no renderer's node (its class names its renderer
  with @:rendered(...); ...)`;
- at run time, a View compiled for one renderer mounted into another's
  node: `helder.view: View(File.hx:12) is markup for another renderer than
  TestRenderer, whose node it is mounted into`.

Measured against the defines (origin/main 4dc6a10), `helder build` (cold:
an empty module cache; warm: built again; seconds, wall clock with bun):

| | before | after |
| --- | --- | --- |
| Todo, native: cold, warm, size | 2.21, 0.44, 1867352 B | 2.20, 0.87, 1887904 B |
| Todo, web: cold, warm, size | 2.05, 0.56, 1525583 B | 2.25, 0.93, 1541137 B |
| Showroom (no markup), native | 1.62, 0.33, 973032 B | 1.62, 0.33, 973096 B |
| Planets (`<Scene>`), native, web | (new) | 2.51, 0.89, 2272880 B; 2.45, 1.15, 1884962 B |
| web demo: counter.js, islands.js | 43066 B, 61935 B | 46863 B, 66970 B |

The compiler's own warm build of Todo is 0.40 s before, 0.64-0.70 s after:
the runtimes (`ViewRuntime_<name>`) and the late code are made by macros
each build, where the module cache served `ViewRuntime` before, so a warm
build loads the macro context. The sizes grow by the late code (kept
whole by DCE natively), the agnostic literals' holes arrays and, on
JavaScript, `Island.render` (the static renderer's, chosen at run time).

On hxmc da5aa2b (#94: what an `onAfterTyping` callback defines is no
longer restored with the module that typed it), Todo's and Planets' warm
native builds by `helder build` went from 0.76 and 0.73 s to 0.55 and
0.55 s. The late classes keep their hash names, no longer needed for
correctness, for stable names; reusing them across builds waits on hxmc's
"one cache".

## Renderers

A renderer is a class of static functions over its node type that
implements `Renders<N>` (the list is in `Renders.hx`, checked at compile
time): `createElement`, `createText`, `createMarker`, `setText`,
`holdsText`, `setProperty`, `setStyle`, `listen`, `insert`, `remove`,
`parentOf`, `arrange`, `isNode`. Its node class names it
(`@:rendered(R)`); a program may reach several.

Components are renderer-agnostic unless pinned: an agnostic literal is
compiled for each renderer reached, and the runtime (`ViewRuntime`, written
against placeholders) is copied for each. `Render.render(content, parent)` picks the renderer by
the parent's type when compiling; everything mounted there is made by
that renderer, every node operation a direct call to it. A component that
makes a node of one renderer and renders its children into it with
another is a boundary:

```haxe
// <Scene>: ui's node, scene nodes inside it (helder.scene.view.SceneTags)
static function Scene(props:{?world:World, ?children:SceneView}):helder.ui.Node {
	var box = new SceneBox(props.world ?? new World("scene"));
	Render.insert(props.children, box.root, null);
	return box;
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

`bun run test view`: `tests/view/ViewTest.hx` on two test renderers
(boundaries between them, a component under both, roots: several windows
by `Render.open`), on Eval, natively and in JavaScript, and the programs the
macro rejects (`tests/view/reject`: a component of another renderer, a
root in markup, an element in a root, helder.web's `<Surface>` in ui's
markup). The test renderers name themselves as a package's do
(`@:rendered`), the one mechanism there is: no define, no exception. The core uses no hxmc-only
feature, so components compile to JavaScript unchanged.
