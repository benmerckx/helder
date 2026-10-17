# @hxmc/web

`@hxmc/view` on the web: the same components rendered to the DOM in
JavaScript, or to HTML at build time, and static pages whose interactive
parts, islands, hydrate in JavaScript or run as WebAssembly. Why it is
built this way: [docs/plans/web.md](../../docs/plans/web.md).

```hxml
-lib hxmc.web   # hxmc.view's renderer: the DOM's in JavaScript, static HTML's elsewhere
```

## The DOM renderer (JavaScript)

`hxmc.web.DomRenderer`, a node a DOM `Node`, each function the DOM call:

```haxe
class App implements Markup {
	static function main() {
		var count = signal(0);
		Render.render(<button onClick={() -> count.value++}>Clicked {count} times</button>,
			js.Browser.document.getElementById("app"));
	}
}
```

- Elements by tag; SVG's own (`svg`, `path`, `circle`, `g`, ...: `Html.SVG`)
  in its namespace, and a name both have as `svg:a`, `svg:title`.
- Attributes as Solid has them: `class` or `className`, `for` or
  `htmlFor`, boolean attributes present when true and absent when false or
  null, `data-*` and `aria-*` written as they are (true as `"true"`), any
  other an attribute (null or false removes it). DOM properties: `value`,
  `checked`, `selected`, `muted`, `indeterminate`, `innerHTML`,
  `textContent`.
- `style`: a string, or an object (`{color: "red", fontSize: 12}`: camelCase
  or CSS names, numbers in px but for the unitless properties).
- Listeners on the element itself (`onClick`: `click`, `onDoubleClick`:
  `dblclick`, `on:my-event`: `my-event`). Not delegated: a listener per
  element keeps `stopPropagation` and the handlers' order as the DOM has
  them, and fine-grained updates do not re-add them.

## Static pages

`hxmc.web.StaticRenderer` renders the same components to HTML at build
time, natively, on Eval or in node (`Static.render`, `Static.document`):

```haxe
class Site implements Markup {
	static function main() {
		Static.write("out/index.html", Static.document(<html lang="en">
			<head><title>hxmc</title><script src="loader.js" defer></script></head>
			<body><Demo.Counter start={3}/></body>
		</html>));
		Static.copy("bin/cube.wasm", "out/cube.wasm");
	}
}
```

Text and attributes escaped (a `script`'s `</` too), void elements without
an end tag, boolean attributes bare, styles serialized, a `pre`'s or
`textarea`'s first newline kept. Listeners are dropped and effects run
once. What hydration reads back: a region's or a list's marker is a pair of
comments, `<!--[-->` before its content and `<!--]-->` after it; adjacent
texts are separated by `<!---->`; an empty text is `<!--#-->`.

## Hydration

`DomRenderer.hydrate(content, element)` takes over markup the static
renderer wrote for the same content. The client's code runs as it would to
render (listeners added, effects run, values set again), and each node it
makes is claimed from the page in document order instead (an element of the
same tag, a text, the end comment of a pair for a marker); no node is made
again, and only the start comments of pairs are removed. When the page
differs (another element, nodes missing or left over), the content is
rendered again from scratch, with a console warning in debug builds.

## Islands

An island is a component defined once, in code both the page's build and
the island's bundle compile; its props are JSON:

```haxe
class Demo implements Markup {
	static function CounterView(props:{start:Int}):View ...
	public static final Counter = Island.define("counter", CounterView, {script: "islands.js", load: Visible});
}

// the page: <Demo.Counter start={3}/>
// the bundle (JavaScript): static function main() Islands.start([Demo.Counter]);
```

On the page it is an `<hxmc-island>` carrying its name, props
(`data-props`), bundle (`data-src`) and when to load it (`data-load`:
`Visible`, once it scrolls into view; `Idle`; `Eager`, at once; `Click`, on
the first click or key press inside it). The loader, `loader.js` (3.3 KB,
1.5 KB gzipped), loads each bundle once and hydrates the island; an island
that has started gets `data-hydrated` (and an `hxmc:hydrated` event), one
that failed `data-error` with the message (and `hxmc:error`).
`Island.url` gives the address written for each file an island loads, from
its name: a site with pages in folders, or its build in the addresses
(cache-busting), sets it per page. One bundle may hold several islands; a small island alone (a
button and a signal, `examples/Counter.hx`) is 42 KB of JavaScript, 9 KB
gzipped, nearly all of it `@hxmc/view`'s runtime, which a shared bundle
holds once (the demo's three islands: 61 KB, 13 KB gzipped).

A WebAssembly island runs a wasm32-wasi module on a canvas, with
`@hxmc/os`'s `browser.mjs` and the packages' `imports.mjs` (a ui or gfx
canvas inside a page):

```haxe
<Island.Wasm src="cube.wasm" id="cube" imports={["os/imports.mjs", "gfx/imports.mjs"]} width={256} height={192}>
	<p>A caption, shown with the canvas.</p>
</Island.Wasm>
```

`fonts` lists font files for `@hxmc/text` (a browser gives a module none);
`canvas={false}` runs it without a canvas (a sound, with `load={Click}`:
browsers start audio only after one). Once it runs, its element's
`data-gfx` names the graphics API it draws with. `hxmcWasmOptions[id]`, set
by a page or a test before the island loads, adds to the runner's options
(`args`, `gfx`). The project's site (`site/`) is built this way.

## JavaScript calling WebAssembly

A class that implements `hxmc.web.Exports` declares a module's functions
for JavaScript, typed on both sides; the same class is compiled into both:

```haxe
class LabExports implements hxmc.web.Exports {
	public static function invert(data:haxe.io.Bytes):haxe.io.Bytes return Lab.invert(data);
	public static function sum(a:Int, b:Int):Int return a + b;
}
```

In the module, `LabExports.register()` (in main) names a `@:hxmc.callback`
wrapper of each to `imports.mjs`. In JavaScript the class keeps only these
functions, each calling the module it is given:

```haxe
WasmModule.load("lab.wasm", {imports: ["web/imports.mjs"]}).then(m -> {
	LabExports.module = m;
	trace(LabExports.sum(2, 3), LabExports.invert(bytes).length);
});
```

Int, Float, Bool, String (UTF-8) and `haxe.io.Bytes` cross, bytes in bulk
(one copy each way, through the C heap: the GC does not move it).
`WasmModule.island(id)` gives the module of a WebAssembly island of the
page.

## Example and tests

`examples/`: `DemoPage.hx` (the page, static), `DemoIslands.hx` (its
islands), `DemoBundle.hx` and `Counter.hx` (their bundles), `Lab.hx` and
`LabExports.hx` (the wasm module JavaScript calls), gfx's `Cube.hx` as the
WebAssembly island, shown with its source.

`make web-check`: `test/StaticTest.hx` on Eval and natively (escaping,
attributes, styles, markers, islands), then `test/web.mjs` in headless
Chromium: `test/DomTest.hx` (the DOM renderer; hydration of what the static
renderer wrote, compiled with both renderers), and the demo page:
hydrated with every node kept, reactive afterwards, the mismatch rendered
again with its warning, the JavaScript island calling `lab.wasm`, the cube
fetched only once it scrolls into view, then drawing.
