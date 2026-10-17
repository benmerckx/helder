# View, web and the site

One reactive view layer with several renderers, a web package built on
it, and the project's site rebuilt with both. Step 1, `@hxmc/view`, is
built; its design (what was looked at, chosen and rejected) is
[view.md](view.md). Step 2, `@hxmc/web`, is built
([packages/web](../../packages/web/README.md)), and step 3, the site
(`site/`), built with it, has replaced `hxmc/web`.

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

## `@hxmc/web` (built)

`hxmc.web` ([packages/web](../../packages/web/README.md), 0.1.0); `-lib
hxmc.web` names its renderer, the DOM's in JavaScript and static HTML's
elsewhere. `@hxmc/view` needed no change.

- **The DOM renderer** (`DomRenderer`, JavaScript): the sketch above,
  but for two choices. Listeners are the elements' own, not delegated: a
  fine-grained renderer adds each once, so delegation would save little
  and cost `stopPropagation` and handler order their DOM meaning. SVG's
  namespace comes from the tag (SVG's own elements; `svg:a` for the
  names both have), since an element is made before it is inserted.
- **The static renderer** (`StaticRenderer`, `Static`): a tree of
  elements, texts and comments, serialized once; natively, on Eval or in
  node. The markers as sketched (a pair of comments, `<!---->` between
  adjacent texts) and `<!--#-->` for an empty text, which the parser
  would lose; no separators inside `script`, `style`, `textarea` and
  `title`, whose content is one text.
- **Hydration**, a mode of the DOM renderer (`DomRenderer.hydrate`). A
  node is claimed when it is made, not when it is inserted: the runtime
  keeps the node a create call returned, so that node must be the page's.
  Markup makes each element and inserts it before its attributes and
  children, so creation follows document order but for markers, which a
  region makes before its content: a marker claims the end of the pair
  at the cursor and removes its start, and its content is claimed next.
  A mismatch (another element, nodes missing or left over, or an error)
  renders the island again from scratch, with a warning in debug builds;
  the end is found by an `onMount` of a `Mountable` placed first in the
  content.
- **Islands** (`Island.define`, `Island.Wasm`, `Islands.start`,
  `loader.js`): an `<hxmc-island>` element with the island's name, its
  props as JSON in an attribute and its bundle; the loader (1.2 KB
  gzipped) loads a bundle once and hydrates on load, on idle or once
  visible. One shared bundle per page is the smaller choice: a small
  island alone is 42 KB (9 KB gzipped), nearly all `@hxmc/view`'s
  runtime, which a shared bundle holds once. A WebAssembly island is a
  canvas the loader hands to `@hxmc/os`'s `browser.mjs`: gfx's cube in
  the demo page.
- **JavaScript calling WebAssembly** (`Exports`, `WasmModule`): a class
  declares the functions, compiled into both programs; in the module each
  gets a `@:hxmc.callback` wrapper named to `imports.mjs` at start (the
  way in for JavaScript the WebAssembly target has: its module exports
  only `memory`, `_start` and the table, and `@:hxmc.export` is the
  runtime's, for symbols its C code calls), in JavaScript a typed call of
  it. Bytes and strings cross in bulk through the C heap, which the
  collector does not move.

Not built: DOM bindings for wasm32-wasi programs through `imports.mjs`
(a WebAssembly DOM renderer, `N` a handle), until a program needs DOM
nodes from WebAssembly (the text input overlay over a canvas, case (b)
above).

What the site takes from it: pages rendered from components at build time
(`Static.document`, `Static.write`, `Static.copy` for an example's wasm
build), islands of either kind, and an example's source read when the
page is rendered (the demo's `Source` component).

## The site: `site/` (built)

`site/` replaced `hxmc/web`, built with `@hxmc/web`: static pages
rendered at build time by a generator in Haxe (`site/src`, on the tool's
Eval or natively), with islands; how to build it:
[development.md](../development.md#the-site).

- Pages: home (three tiles, each with a proof: conformance, the
  self-compile's time and memory, the cube running), compiler (conformance,
  downloads, the benchmarks and target tables, lix), hxmc (targets, sizes
  and cold build times measured by the build, how it works, low-level
  Haxe), packages (each with its README's sample), examples, playground,
  docs and story. One layout; light and dark (the system's, or a switch
  kept in `localStorage`, applied before the first paint); a menu button on
  a phone.
- Islands: JavaScript for the menu, the theme and the examples' source tabs
  (`site.js`: 49 KB, 10 KB gzipped, loaded when idle), and the examples'
  Counter and Lab; WebAssembly for the examples, each loaded once visible;
  the playground's and the benchmark tables' scripts as islands of their
  own (an `<hxmc-island>` whose hydration is a hand-written function). The
  home page loads 81 KB (20 KB gzipped) before its cube.
- Examples: each package's `examples/` files with a header (title,
  summary, tags, demo) built for wasm32-wasi by the site's build and shown
  next to their source; `@hxmc/web` gained what they needed (`Island.url`
  for pages in folders and cache-busting, a click load for sound, fonts and
  no canvas for wasm islands, `hxmcWasmOptions` for tests).
- Docs generated from the sources: the narrative docs, the roadmap and the
  plans, each package's README and ui's guide (a small Markdown renderer at
  build time, code highlighted), and an API reference read with the
  compiler: the packages' modules typed together (`--json`: signatures as
  typed) and the `//` comment above each declaration read from its source
  (the packages do not write `/** */`, which the compiler would keep).
- Tests (`make site-check`, CI's `playground` job): links, every page at
  two widths in Chromium (the key pages in Firefox and WebKit), islands
  hydrated, the examples drawing (the triangle and cube against their
  golden images), the playground's compiler.

Left: graphics programs in the playground ([graphics.md](graphics.md));
the history charts (hidden, as before); NativeForm (native controls as DOM
elements) in the gallery, which needs the loader to give a container.
