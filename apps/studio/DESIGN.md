# helder studio: design files

Status: a plan, its first steps built (README.md, "Design files"): a
screen's source (a story, the app, a design's frame), the interpreter
(helder.ui.view.Interpreter), `.helder` files' frames on the canvas,
selected and edited in place. The studio otherwise draws every screen by
running the project's program: a dev build of its stories in one preview
host. That stays, but as one source of a frame among others.
The canvas's own work, Figma's kind (layout, type, colour, a screen
drawn before any code), is markup the studio renders at once, in its own
process, with no build: a design file.

## 1. The model

- **A design file** (`*.helder`, the extension still open) is helder's
  markup and nothing else: the syntax of a literal in `.hx` and `.tsx`,
  parsed by helder.markup.Syntax, so that taking a part of it into code
  is a move, not a translation. One language for both: neither Haxe's
  nor TypeScript's.
- **Interpreted in the studio, compiled everywhere else.** The studio
  renders a design file by running helder.markup.Plan's mount steps
  directly (view's DESIGN.md 7.2's third emitter) against helder.ui's
  renderer, in the studio's process: an edit shows the same frame. A
  build compiles it through the markup macro like any literal: no
  interpreter in an app, DCE as usual. Interpreting at an app's run time
  (server-driven ui, mods) is not planned.
- **Design owns the look, code the behaviour.** A logo, an illustration,
  an empty state, a card's layout can stay design forever; only what
  needs logic moves to code.

### What you open

- **A project folder**, as VS Code opens one: the studio opens a
  directory, never a file alone. Opening a single `.helder` file opens
  its folder as the project, that file's page shown.
- **Each `.helder` file is a page**, as Figma's pages: its frames on the
  canvas together, a page per file.
- **The canvas' sidebar lists pages**: the design files, then a page per
  story file (its flows), and the app. The file tree belongs to the code
  view, not the canvas.
- **A new project starts with one `app.helder`**: a page to draw on before
  any code; the program comes when something needs to run.

## 2. Frames

A `<Frame>` is a place on the canvas with a size; its content has one of
four sources, each labelled on the canvas (Design, Component, Story,
App), so that what is instant and what runs is always visible:

```
<Frame name="Home">...markup...</Frame>                   design: interpreted, instant
<Frame name="Card"><ShipCard title="Hornet"/></Frame>     design around a component
<Frame name="Card/plain" story="cards.story.tsx#plain"/>  a story, live
<Frame name="Checkout" app route="/checkout"/>            the app itself, live
```

- A design frame may hold compiled components: the markup around them
  is interpreted, each component an island drawn by the preview host
  (its frames as today's screens'). A frame is not all one or the other.
- References are a path and an export's name (`cards.story.tsx#plain`),
  the same from both languages, read from the text without a build as
  the studio reads stories now.
- A live frame shows its last image (or a skeleton at its size) until
  its build is there, so the canvas never jumps; as the host keeps the
  last frames through a crash.
- `app route=...` needs routing (the roadmap's phase 7); until then the
  app's frame is the app as it starts. Flows on the canvas and the router
  are the same feature.

## 3. What else is markup

Everything on the canvas is markup; what only the editor needs is
namespaced and dropped by the planner, as a release build drops stories.

| | in an app | in a build |
|---|---|---|
| flows (an arrow: a screen to another on a trigger, a transition) | navigation | kept: routes and transitions |
| timelines (property tracks) | animation, cutscenes, video | kept: motion tracks |
| frames (sizes, variants) | screens, routes | kept; their sizes and variants stories' and screenshots' |
| notes (`<note>`) | none; devtools' annotations in dev builds | dropped |
| canvas positions (`canvas:at="0 0"`) | none | dropped |

A frame's position is one attribute, so a move is a one-line diff; a
sidecar beside the file if that proves noisy.

## 4. Parts: design used from code

A design file is a library of named parts, imported as assets are:

```tsx
import {Logo, EmptyState} from './brand.helder'

function Header() {
  return <row><Logo size={32}/><Nav items={items()}/></row>
}
```

```haxe
final logo = Design.part('brand.helder', 'Logo')
```

- **Exported explicitly**: `<Part name="Logo">` or `export` on any node,
  not only frames, so a rename or a delete is deliberate; the studio shows
  a part's uses ("used in 3 components") and warns before breaking them,
  and renames the references.
- **Checked when compiling**: a missing part or a wrong prop is an error
  at the reference, as `Asset.image`'s path.
- **Typed**: a `.d.ts` for each design file, generated from its exports,
  a prop's type from its default (`size={24}`: `size?: number`); Haxe's
  macro reads the file itself.
- **Props and a slot**: defaults for the props, children for the slot,
  so a `<Card>` of a design file wraps content from code.
- **Live both ways**: an imported part's values are literals, so an edit
  in the studio patches the design frames at once and the running stories
  and apps that use it as live literals, no build.
- A part may hold a component that imports another part; a real cycle is
  the compiler's error.

On a design node the studio offers "use from code" first, "upgrade to
code" second.

## 5. Upgrading

"Upgrade to code" on a frame or a node: a name, a file and a language
(`.hx` or `.tsx`); the markup moves there as a component, as it is, its
props its parameters; the frame keeps the instance (`<ShipCard
title="Hornet"/>`), so nothing changes on the canvas but its label.
Optionally a story with it, from the frame's values and variants (a test
and a store screenshot for free). One way: code is not made design again,
but the canvas keeps editing it through the preview host, as today.

## 6. The format's other needs

Shaping the format, so first:

- **Tokens and themes**: colours, spacing and type as named variables with
  modes (light and dark, brands), in markup (`<Tokens>`, helder.ui's
  StyleSheet) and referenced by name (`color="accent"`); code uses the
  same ones.
- **Components, variants, slots, overrides**: a part's sizes and states
  as one part with variants (stories' match), children in a slot, a nested
  child changed in one instance.
- **Sample data and repetition**: `<For each={...}>` over inline data or a
  JSON fixture beside the file, interpreted; empty, loading and error as
  frames.
- **Interactions, a fixed set**: navigate, a variant switched, a toggle,
  an overlay opened, compiled to handlers; anything more is code. Without
  that line the format becomes a scripting language.

Then:

- **Elements and attributes as data**: the interpreter needs helder.ui's
  elements and how each attribute's value parses (colours, lengths,
  enums) at run time; the inspector's fields need the same table (the
  README's "Not yet").
- **One renderer by construction**: the interpreter a `Target` of the same
  Plan; a lane interpreting every example's markup and compiling it,
  `Ui.getTree` equal.
- **Errors in place**: an unknown element or a wrong value marked where it
  is, the rest still drawn.
- **Assets on the canvas**: a dropped image, SVG or font written into the
  project and referenced by path (helder.asset).
- **Sizes**: auto layout first, absolute placement allowed (`position:
  absolute`); a frame at several sizes side by side from one definition.
- **Migrations**: a design file is markup against helder.ui's elements;
  a rename needs a codemod, or a version on the file.
- **Tests**: every frame a tree snapshot in `helder test`, as stories are.
- **Scenes**: `<Scene>` markup interpreted once scene's elements are in
  the table; physics and the like stay live.

Later, beside it:

- **The agent**: design markup renders without a build, so an agent's
  loop (write, look, adjust) is fast; `run.snap` and `run.tree` on
  interpreted frames too.
- **Together**: multiplayer edits and comments (a CRDT over the syntax
  tree, written back as files: the hosted helder.build's); notes as
  comments.
- **In and out**: SVG pasted, Figma's files through its REST API, a
  screenshot through the agent; frames exported as PNG, SVG or PDF
  (helder.canvas, helder.pdf).

## 7. Open

- The extension (`.helder`) against a restricted `*.design.tsx` /
  `*.design.hx`: the second has editors' support for free but ties a
  design to one language and has no place for the canvas. Leaning to the
  extension.
