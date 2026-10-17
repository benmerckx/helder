# `@hxmc/view`: the design

`@hxmc/esx` (markup literals compiled to a static template and an array of
values) and `hxmc.ui.reactive` (signals, and `Render`, which walked those
templates into `hxmc.ui` nodes) merged into one package, independent of
`@hxmc/ui`: signals, markup, and a renderer contract that ui implements.
What the web needs is in [web.md](web.md).

## What was looked at

- **Signals.** Preact signals (`signal`, `computed`, `effect`, `batch`,
  `untracked`, `.value`, `.peek()`), the TC39 Signals proposal
  (`State`, `Computed`, watchers: a substrate for libraries, no effects
  of its own), Solid 1 and 2 (`createSignal`/`createMemo`/`createEffect`,
  ownership and cleanup; 2.0 batches writes until a flush and splits
  effects into a tracked compute and an untracked apply), Svelte 5's runes
  (`$state`, `$derived`, `$effect`: the same graph behind compiler
  syntax), Vue's refs, Leptos and Sycamore (Solid's model in Rust).
- **Markup.** Solid and Vue Vapor compile templates to direct DOM
  operations; Leptos (`tachys`) and Sycamore compile `view!` to calls on a
  renderer trait, generic over the DOM, a server string or a mock; Lit
  and Dioxus keep a static template per literal and update its dynamic
  parts (what `@hxmc/esx` did); SwiftUI and Compose re-run view functions
  and diff or memoize positionally.
- **Renderers.** Solid's universal renderer (`createElement`,
  `createTextNode`, `replaceText`, `setProperty`, `insertNode`,
  `removeNode`, sibling queries), Leptos's `Renderer` trait, React
  Native's mutation list over its own layout.

## What was chosen

- **Signals: kept.** The API (`signal`, `memo`, `effect`, `batch`,
  `untrack`, `root`, `onCleanup`, `onMount`, contexts) is already
  Preact's and Solid's, and the algorithm (Reactively's clean, check,
  dirty colouring, lazy memos, an ownership tree) is what Solid 2 and the
  TC39 polyfill do. Moved to `hxmc.view`; `getOwner` and `runWithOwner`
  added (Solid's) so that renderers' own components can place work in an
  owner. An owner's children and cleanups, a computation's sources and a
  signal's observers are made when first needed (a list of 1000 rows had
  27000 empty arrays from them), and a memo is its own computation (no
  closure of its own). Solid 2's deferred flush was not taken: ui's
  tests and widgets rely on writes taking effect at once outside `batch`,
  and a frame-based UI gains little from it.
- **Markup: compiled to direct calls.** Each literal becomes code that
  makes its elements, sets their attributes and inserts them, run when it
  is mounted (Solid, Vue Vapor, Leptos); no template is walked at run
  time. The literal's holes are evaluated where the literal is, as
  before, so a hole read inside a reactive region is tracked there. Its
  value is a `View` (a mount function), which content, props and control
  flow pass around as `Esx` values were.
- **Renderers: per mount point, dispatched statically.** A renderer is a
  class of static functions over its node type (`Renders<N>`); a
  program may have several (`-D hxmc.view.renderer.<name>=<class>`, one
  per package: `-lib hxmc.ui` sets ui's). Components stay
  renderer-agnostic: each literal is compiled once per renderer (a
  `View` holds one mount function, which runs the code of the renderer
  it is given), and the runtime (`Runtime`, written against the
  placeholders `Host` and `HostNode`) is copied for each renderer by a
  build macro. `Render.render(content, parent)` picks the renderer by the
  parent's type when compiling. Inside a subtree every node operation is
  a direct call to its renderer, which hxmc can inline; the only choice
  made at run time is which code a `View` runs, once per literal mounted
  (Leptos and Sycamore get the same by monomorphizing over a renderer
  trait). With one renderer, nothing is copied and nothing chosen.
- **Boundaries are components.** A component that makes a node of one
  renderer and renders its children into it with another switches
  renderers there; content passes through unchanged and stays reactive
  across it. ViewTest renders through two test renderers, either way.
  The cases: a ui canvas inside a page's DOM (an island), a page's
  element over a canvas, laid out by ui (text input, video, an iframe),
  and on the desktop a GPU view inside native controls, native controls
  over a GPU view as overlays ([web.md](web.md)). In ui itself the drawn
  and native backends share one renderer, so no boundary is needed there:
  a native window's `Control`s are nodes of the same tree.
- **JavaScript too.** The core uses nothing hxmc-only (no struct values,
  no unsafe memory), so components compile to JavaScript unchanged;
  ViewTest runs on Eval, natively and in JavaScript.
- **The contract: ui's needs first.** Create an element, a text and a
  marker; set text, a property, the style; listen; insert before,
  remove, parent; arrange a keyed list's rows at once (ui reorders them
  in one pass); and `holdsText`, for ui's text nodes, which take their
  text children as their own text and their elements as spans.
  `@hxmc/ui` implements it once (`hxmc.ui.view.NodeRenderer`) over
  `hxmc.ui` nodes, which both its drawn backend and its native backend
  (`hxmc.ui.native`: platform controls as nodes) display.

## What was rejected

- **Keeping templates** (Lit, Dioxus, `@hxmc/esx`): one interpreter per
  renderer walking every literal at run time, every value boxed and
  tested by type; it did let one compiled literal serve any renderer.
- **A renderer interface called through an object**: an indirect call
  per node operation, and no inlining.
- **One renderer per build** (a define naming it, as a Solid build targets
  one of `dom`, `ssr` or `universal`): simpler, but a page could not
  hold a ui canvas, nor ui a page's element; the first version did this.
- **Re-running views** (SwiftUI, Compose, React): needs a diff or
  positional memoization; fine-grained signals already know what changed.
- **Hydration in the contract.** Claiming nodes of a statically rendered
  page (Solid's `getNextElement`, hydration keys and comment markers)
  bends every create call and needs markers ui has no use for; it
  belongs to the web layer, not to the contract ui implements
  ([web.md](web.md#hxmcweb)).
