# View, web and the site

One reactive view layer with several renderers, a web package built on
it, and the project's site rebuilt with both. Step 1, `@hxmc/view`, is
built; its design (what was looked at, chosen and rejected) is
[view.md](view.md). The current site is `hxmc/web`.

## `@hxmc/view` (built)

Signals, markup and a renderer contract, in one package independent of
`@hxmc/ui`: `@hxmc/esx` and `hxmc.ui.reactive` merged
([packages/view](../../packages/view/README.md)).

- Signals: `signal`, `memo`, `effect`, `batch`, `untrack`, ownership and
  cleanup, contexts, `For`, `Index`, `Show`, `Switch`, `ErrorBoundary`.
- Markup: each literal compiles to direct calls (elements made by tag,
  attributes set, nodes inserted), no template walked at run time and no
  virtual DOM.
- Renderers per mount point: a program may have several, components are
  compiled for each, and inside a subtree every node operation is a
  direct call to the renderer that owns it. `@hxmc/ui` implements one,
  `hxmc.ui.view.NodeRenderer`, for both its drawn and native backends.

The contract as built (`Renders<N>`: static functions of the renderer
class, checked when it is first used):

```haxe
static function createElement(tag:String):N;
static function createText(text:String):N;
static function createMarker(name:String):N;           // where a region or list puts its content
static function setText(node:N, text:String):Void;     // a text node's, or a text holder's own
static function holdsText(el:N):Bool;                  // ui's text nodes; the DOM: false
static function setProperty(el:N, name:String, value:Dynamic):Void;
static function setStyle(el:N, value:Dynamic):Void;
static function listen(el:N, name:String, handler:Dynamic):Void;
static function insert(parent:N, node:N, before:Null<N>):Void;
static function remove(parent:N, node:N):Void;
static function parentOf(node:N):Null<N>;
static function arrange(parent:N, nodes:Array<N>, before:N):Void;  // a keyed list's rows, in order
static function isNode(v:Dynamic):Bool;
```

### JavaScript or WebAssembly, per island

Chosen per island, not per site; the port's JavaScript generator is
there:

- DOM-heavy views compile to JavaScript (Haxe's JS target): direct DOM
  calls, small output, a fast start. `@hxmc/view`'s core compiles to
  JavaScript unchanged (ViewTest runs in node), so it uses no hxmc-only
  feature; struct values and the like only behind abstractions with a
  JavaScript fallback.
- Heavy work compiles to wasm32-wasi: the playground, gfx and ui
  canvases, computation.
- JavaScript hosts the WebAssembly modules: their `@:hxmc.export`s get
  typed JavaScript wrappers generated, WebAssembly calls JavaScript
  through `imports.mjs`, and data crosses in bulk (bytes, views of
  structs), not in chatty calls.

### Renderers for the web (sketches)

- **The DOM, in JavaScript first** (`@hxmc/web`): `N` a DOM `Node`,
  each function the DOM call (`document.createElement`,
  `createTextNode`, `createComment` for markers, `textContent` for
  `setText`, `holdsText` false, `setProperty` choosing a property or an
  attribute as Solid does, `setStyle` a string or an object, `listen`
  through one delegated listener per event type, `insertBefore`,
  `removeChild`, `arrange` as `insertBefore` of the nodes out of
  place). A WebAssembly DOM renderer only where a wasm program needs some
  DOM (the text input overlay below): `N` a handle into a table
  `imports.mjs` keeps, as `@hxmc/gfx` does. Both fit the contract as is.
- **Static HTML**: `N` a small tree (element, text, comment) serialized
  once the page is rendered, at build time. `listen` does nothing,
  effects run once (a root disposed after the render). It fits too.
- **Boundaries** are components (see `packages/view/README.md`):
  - (a) a ui canvas in a page: `<UiCanvas>` makes a DOM canvas element,
    a `UiWindow` on it, and renders its children into the window's
    root with ui's renderer: the island case for the site;
  - (b) a page's element over a canvas: in a drawn ui tree, a node that
    ui lays out like any other, whose DOM element (an input with its IME,
    a video, an iframe) the page positions over the node's rectangle
    after each layout, its children rendered with the DOM renderer;
  - (c) the desktop's analogue: a GPU view inside native controls is a
    native child surface; native controls over a GPU view only as
    overlays, as (b).

  Content passes through a boundary unchanged and stays reactive across
  it (ViewTest checks both directions with two renderers).
- **Hydration** is not in the contract (see [view.md](view.md)). It can
  be a mode of the DOM renderer instead: the static renderer writes a
  marker as a pair of comments (`<!--[-->` before the content a region
  or list puts before it, `<!--]-->` the marker itself) and separates
  adjacent texts with an empty comment, so that the page parses back into
  the same nodes; the hydrating DOM renderer adopts, in `insert`, the
  node already at its parent's cursor for each node the client's code
  makes (an element of the same tag, a text, the end comment of a pair),
  instead of inserting it. The client's code runs as it would to render
  (listeners added, effects run, values set again, to the same values);
  a mismatch renders the island again from scratch. If that proves too
  fragile, an island can simply replace its pre-rendered markup when its
  module loads; either way it stays inside `@hxmc/web`. Static pages
  hydrate into JavaScript islands by default, WebAssembly ones where an
  island chooses it.

## `@hxmc/web`

The browser, for programs compiled to wasm32-wasi:

- DOM bindings through `imports.mjs`, the convention `@hxmc/os` and
  `@hxmc/gfx` use (docs/hxmc.md, "WebAssembly"): elements, properties,
  events and the few browser APIs a site needs, JavaScript objects as
  handles.
- A DOM renderer for `@hxmc/view`, in JavaScript first.
- A static renderer: the same components rendered to HTML at build time
  (natively or on any target), for pages that need no WebAssembly.
- Hydration islands: a static page in which only the interactive parts
  load a module and take over their pre-rendered markup.

## The site: `site/`

`site/` replaces `hxmc/web`, built with `@hxmc/web`: static pages with
islands for the playground, the benchmark charts and the examples.

- Docs generated from the sources: the narrative docs (`docs/`), each
  package's README, and an API reference extracted with the compiler (the
  port's typed modules or HXB, doc comments included), so the site never
  repeats what the repository says.
- An examples gallery from each package's `examples/` (gfx's triangle and
  cube today, then ui's and view's), each built for the browser and shown
  with its source.
- The playground and the benchmark history carried over from `hxmc/web`;
  graphics programs in the playground ([graphics.md](graphics.md)).
- CI keeps today's browser checks (the `site` and `playground` jobs) on
  the new site.
