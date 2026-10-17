# View, web and the site

The direction after the UI branch lands: one reactive view layer with
several renderers, a web package built on it, and the project's site
rebuilt with both. Nothing here is built yet; the pieces it starts from
are the UI branch's `@hxmc/esx` (JSX-like markup after the ESX proposal)
and `hxmc.ui.reactive` (signals and a Solid-like renderer for ESX markup),
and the current site, `hxmc/web`.

## `@hxmc/view`

Signals, esx markup and a renderer contract, in one package: `@hxmc/esx`
and `hxmc.ui.reactive` merged and made independent of `@hxmc/ui`.

- Signals: fine-grained reactivity (signals, derived values, effects),
  with no virtual DOM: markup compiles to code that creates nodes once
  and updates exactly what a signal reaches, as Solid does.
- esx: the markup, checked at compile time against the renderer's
  elements and properties.
- The renderer contract: the few operations markup compiles to (create an
  element or text, set a property, insert, remove, listen), implemented
  per renderer. Renderers: `@hxmc/ui` (drawn), `hxmc.ui.native` (native
  controls), the browser DOM and static HTML (both in `@hxmc/web`).
- One implementation of signals and markup for every renderer; a
  component written against the contract runs on any of them.

## `@hxmc/web`

The browser, for programs compiled to wasm32-wasi:

- DOM bindings through `imports.mjs`, the convention `@hxmc/os` and
  `@hxmc/gfx` use (docs/hxmc.md, "WebAssembly"): elements, properties,
  events and the few browser APIs a site needs, JavaScript objects as
  handles.
- A DOM renderer for `@hxmc/view`.
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
