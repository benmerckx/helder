# helder studio

A project's screens on a canvas, its code, an inspector and an agent's
tools, all editing the source files: the first vertical slice of the
studio (helder.build's PLAN.md, step 5). It is a helder app, drawn by
helder.ui, and it opens itself.

```sh
bun run helder studio examples/ts-todo     # this checkout; npx helder studio in a project
bun run helder studio examples/design      # design files alone: nothing built
bun run helder studio                      # the project in this directory
```

- **The project's files** in the sidebar (below, "The sidebar"), each
  opening in its view.
- **All screens.** The canvas shows every screen of the project at once,
  a row per flow. Pan with a drag or the wheel, zoom with secondary
  (Ctrl, Cmd) and the wheel, a trackpad's pinch or two fingers. Click a
  screen to spring into it; Escape or "All screens" goes back.
- **A screen, live.** Each story's screen is a story of the project's
  program, a dev build, running in one process for the whole project
  (each story a root of its own), offscreen at the screen's size; the
  canvas shows its frames as it draws them.
- **A design's frame, at once.** A design file's frames (`*.helder`,
  below) are drawn by the studio itself, interpreted from their markup:
  nothing built or run, an edit drawn again in the next frame.
- **Select.** Click inside the screen you zoomed into: the node there is
  selected (the program's tree: its box, and where its markup is), drawn
  as an outlined box. The inspector shows its layout (width, height,
  padding, gap), style (fill, colour, radius), text and source line.
- **Edit.** A field changes the element's attribute in the source,
  formatting kept (helder.syntax), only its span. A live literal's value
  (a colour, a number, a text written in the markup) is patched in the
  running screens at once, no build, then saved; anything else is saved
  and built, and the screens reloaded with their state. A number's label
  scrubs it: drag left or right.
- **Code.** "Code" shows the selected node's file beside the screen
  (helder.ui.code's CodeEditor), its element revealed and marked. Typing
  is saved after a pause: patched when only live literals changed, else
  built, the build's diagnostics in the editor.
- **Undo and redo** (secondary-Z, secondary-shift-Z, the header's
  buttons) go through every edit in order, whoever made it: the canvas,
  the inspector, the code, an agent. Each edit is a helder.syntax
  transaction on one file; a gesture (a field typed into, a number
  scrubbed, a word typed) is one entry.
- **The prompt bar** asks about what is in focus ("Ask about the whole
  app…", "Ask about Three items…"). No model is connected yet: `/tree`,
  `/snap`, `/check` and `/read <file>` call the studio's tools, and any
  other prompt says how to drive the studio over MCP.

## Screens

A screen's content has a source (Project.Source): a story of the
program, the program's own window (the App), or a design file's frame.

A project's screens are its **stories**: `story({...})` in its
`*.story.hx` (Haxe) and `*.story.tsx` / `*.story.ts` (TypeScript) files,
anywhere under the project's directory but `bin/` and `node_modules/`
(helder.story).

- A story's **name** is `Flow/Screen`: its flow the part before the last
  `/` (no `/`: the flow "Screens"), its label the rest. The canvas has a
  row per flow, in the order the files (by path) and their stories (as
  written) give.
- Its **size** is the story's `width` and `height` (points); without them
  a phone's, 390 by 844.
- TypeScript's stories are **exported** (`export const items = story({...})`):
  the studio imports them by name.
- A project with an entry and no stories has one screen of its program,
  its own window (the page "App"), design files or not. (With stories
  the program is theirs: the App is not drawn beside them.)

```tsx
// examples/ts-todo/app.story.tsx
export const empty = story({ name: "Todo/Empty", width: 480, height: 560, render: () => <App/> });
export const phone = story({ name: "Phone/Three items", render: () => { todos(three); return <App/>; } });
```

The stories are read from their text (helder.syntax) when the project
opens, not built, so the canvas is laid out before anything compiled.

## Design files

A design file (`*.helder`, DESIGN.md) is helder's markup alone: a root
(`<Design>`, or a fragment) of frames, each a place on the canvas with a
size. Every one under the project's directory (but `bin/`,
`node_modules/` and dot directories) is a page of the canvas, named by its
path, its frames its screens, before the stories' flows. A frame's id is
its file's path and its name (`app.helder#Home`), so that no story's
`Flow/Screen` is one.

```
<Design>
	<Frame name="Home" width={390} height={844} canvas:at="0 0" background="#f8fafc" padding={24}>
		<note>For the editor only.</note>
		<text font-size={28} font-weight={700} color="#3b82f6">todos</text>
	</Frame>
</Design>
```

- **A frame** is drawn as a view of its size (a phone's, 390 by 844,
  without), its attributes its style but its name and the editor's; at
  `canvas:at` in its flow's row (else after the one before). `canvas:*`
  attributes and `<note>` are the editor's: dropped before it is drawn.
- **Interpreted, in the studio's process** (helder.ui.view.Interpreter: a
  Target of helder.markup.Plan, the compiler's planner, its steps run at
  once against NodeRenderer's run-time functions), into nodes in the
  canvas' world beside the stories' images, under ui's defaults rather
  than the studio's theme. The same literal compiled makes the same tree
  (the test lane's Interpreter.test.hx).
- **What it cannot run is marked in place**, the rest drawn: a hole that
  is not a literal number or string (`{items.length}`), an unknown
  element, a component (code: not drawn in a design yet), a value its
  attribute rejects, each outlined in red; a file that does not read
  shows why in its frames.
- **Select and edit as a story's screens**: a click selects the node
  there directly (the interpreted nodes' boxes and their markup's
  offsets, no program to ask); the inspector's fields, the code view and
  undo go through the same helder.syntax transactions (`.helder` is
  helder.syntax's Markup language), the file saved and its frames drawn
  again at once.
- **Followed as it changes**: the file's frames are read again after
  every edit of it (the inspector, the code view, an agent, undo), and the
  design files on disk are watched (a second apart, natively): a file
  changed there comes in as an edit (its one differing range, in the
  history), a file added or deleted shows or drops its page. A frame
  added, removed or renamed shows at once; a renamed frame keeps its focus
  and selection.
- **Pages**: the sidebar lists each design file, each story flow and the
  App, a page's title showing its screens (fitted, none zoomed into); the
  canvas keeps every page's screens, a row each.
- **Images by path** (`<image src="logo.png"/>`, an SVG too): read from
  the design file's folder, decoded by helder.image (again when the file
  changes); natively (in the browser: marked, not yet).
- **A project of design files alone** has no program: it opens with no
  build and no App screen (examples/design). A project with stories and
  design files builds its stories' program as before, its frames drawn
  from the start; one with an entry and no stories, its App.
- Opening a `.helder` file opens its folder as the project.
- **MCP's `run.tree` and `run.snap`** on a design frame: its nodes
  interpreted offscreen at its size (the tree: tags, boxes, texts,
  colours, each node's `file:line`, and what could not be interpreted),
  drawn by a headless device of the studio's own as store screenshots
  are (a PNG at 2x).

### Editing on the canvas

On a design's frame the canvas edits the markup directly
(helder.build's PLAN step 6, design frames first; Drag, Snap, Layers):

- **Move a frame** by its caption (or by itself, selected: a click on
  its background): `canvas:at` written.
- **Resize** by the selection's handles: a frame's `width` and `height`
  (and `canvas:at` from its left or top); a node's `width` and `height`,
  a node placed absolutely (`position="absolute"`) its `left` and `top`
  too from its left or top.
- **Move nodes** placed absolutely by dragging them (`left`, `top`); a
  node in auto layout is resized only (its place is its parent's: reorder
  it in the layers).
- **Snapping**: the moving edges (and centre, for a move) to the frame's
  and the siblings' edges and centres (a frame's to the other frames'),
  within 6 points of the stage, the guides drawn; values rounded to a
  point.
- **Layers**: the zoomed frame's elements as written (`<note>`s left
  out), a row each beside the frame; a click selects (shift: adds), a row
  dragged up or down moves its element among its siblings
  (helder.syntax's Edits.move), the markup's order the drawing's.
- **Multiple selection**: shift-click adds a node or takes it out; the
  selected nodes placed absolutely move together; the inspector shows
  the one clicked last.
- Each gesture is one entry of the history (its moves one transaction
  each, merged), the file's formatting kept, the frame interpreted again
  at once; undo and redo as for any edit.

## The sidebar: the project's files

The sidebar's tree is the project's folder (`FileTree`: bin/,
node_modules/ and dot directories left out; read again every second
natively, after the studio's own writes in the browser). Folders holding
design or story files start open, the others closed; a row's chevron
opens and closes it.

- **A design file** (`.helder`) goes on to its frames, **a story file** to
  its stories: a click on the file shows its page on the canvas, on a frame
  focuses it.
- **Code** (`.hx`, `.ts`, `.tsx`, `.json`, `.md`...) opens in the code view.
- **An image** (PNG, JPEG, GIF, WebP, SVG) opens in its viewer
  (`FileView`): fitted (never past 1:1) or at 1:1, its size, format and
  bytes, and where it is used: each line of the project's code and design
  files naming it, a click opening that file. Natively (images by path are
  not read in the browser yet).
- **A font** (TTF, OTF) opens in a specimen: its family, the alphabet, a
  line at 12, 16, 24 and 36 points.
- **glTF models and sounds** show their kind and size: their viewport and
  waveform are not made yet.
- **Layers** of the frame in focus are a section below the tree, its
  header closing it.
- **Drag an image from the tree onto a design's frame**: an `<image src>`
  of its path from the design file, its size the image's (fitted into the
  frame's width), the frame's last child, one history entry.
- **Drop files from the system** on a folder's row (a file's: its folder;
  elsewhere, the project's): copied there, natively.

## How it runs

- **The project never runs in the studio's process, and runs once.** The
  studio builds one program of the project's stories (a dev build, `-D
  hxmc.dev`, `-D helder.headless`; its main `helder.story.Screens` over
  them, generated in `<root>/bin/studio/<name>`) and starts it once: the
  preview host (helder.story.NativeHost), every story mounted as a root of
  its own with a context of its own (helder.story.Host,
  helder.ui.ScreenContext: its clock and timers, keymap, settings, safe
  area, dark or light). A crash or an endless loop takes the host down,
  not the studio: the canvas keeps the last frames and the host is started
  again.
- **Frames are GPU textures the studio composites.** The host draws each
  screen into a texture of its own the studio's process opens without a
  copy (helder.gfx's shared textures: an IOSurface through Metal on macOS,
  a DXGI texture with a keyed mutex through Direct3D 11 on Windows, a
  dma-buf through EGL on Linux), and the studio draws it as an image with
  its own renderer (Image.ofShared: the zoom, the selection's outline and
  the transitions stay the studio's). A frame's texture goes back to the
  host once the canvas drew a newer one (up to three a screen). Where the
  GPU shares none (Mesa's llvmpipe: CI, this lane) the frames come through
  shared memory instead (a file in /dev/shm both map: helder.story.FrameFile),
  copied into the studio's texture. Only the screens in the canvas' view
  draw: the one zoomed into every frame it changes, at the canvas' scale
  (its pixels a point in halves, up to 3), the others at 1x when something
  in them changes; a screen out of view is suspended and its last frame
  kept.
- **The devtools protocol on the dev connection** (src/helder/devtools,
  helder.story.HostAgent): `Host.show` (the screens in view, the one
  zoomed into, its scale), `Host.frame` and `Host.release` (the frames'
  textures), `Ui.getTree` and `Ui.nodesAt` naming a screen, live literals
  (`Hot.literals`: one program, every screen's next frame shows a patch),
  reloads (`Runtime.reload`: the host's state in Hot's snapshot, each
  screen's keys in a scope of its name, the new build started from it with
  the screens the last one had built), `Host.snap` (a frame's pixels read back for
  `run.snap`). The host ends with the studio (`HXMC_DEV_EXIT_WITH_SERVER`).
- The compiler stays warm (helder.compiler.service). One build runs at a
  time; files edited during a build are written after it.
- A project's stories share its modules' state, one program: a story keeps
  what it changes to itself (examples/ts-todo's stories each make a store
  of their own, `store(three, "done")`, rather than setting the module's
  signals).

## In the browser

The same studio built for the web (helder's web target, WebGPU or WebGL2:
`?gfx=webgl2`), its page `apps/studio/web`:

```sh
node apps/studio/web/build.mjs bin/studio-web/site examples/todo=Todo   # then serve the directory
```

- **Projects live in OPFS** (the origin's private file system), each under
  `projects/<name>/`. The welcome (no `?project=`) makes a new project
  (`web/new/app.helder`, one design file: nothing built, named `project`,
  `project-2`...), opens a folder (the File System Access API: its sources
  copied into OPFS, and written back to the folder while the page may), an
  example bundled with the page, or a project already in OPFS; `?new` and
  `?example=<name>` do the first and the third from a link (helder.build's
  pages). The page reads the project into memory before the studio's
  module starts and writes each save back (`studio.mjs`, `Files`). The
  page's URLs are relative: it is served under any path (helder.build's
  `/studio/`).
- **One preview host per project.** The project's program runs once, in a
  Web Worker, every story mounted in it as a root of its own with a
  context of its own (helder.story.Host, helder.ui.ScreenContext: its
  clock and timers, keymap, settings, safe area, dark or light; its Ui's
  focus and theme). Only the screens in the canvas' view draw: the one
  zoomed into every frame, the others when something in them changes; a
  screen out of view is suspended and its last frame kept. Each frame is
  drawn on the worker's OffscreenCanvas and posted as an ImageBitmap; the
  studio's renderer uploads it (copyExternalImageToTexture) and composites
  it like any image, so the studio owns its pixels
  (helder.story.web.Preview, `studio.web.WebPreviews`). The screen zoomed
  into draws at the canvas' scale (its pixels a point in halves, up to 3),
  the others at 1x.
- **The devtools protocol as the worker's messages**: Ui.getTree and
  Ui.nodesAt name the screen, Hot.literals patches the one program (every
  screen's next frame shows it). An inspector's colour reaches the
  preview's frame in 10 to 25 ms, one or two studio frames.
- **The preview's module** of an example is built where the page is built
  (`helder studio <project> -- --export-web <dir>`: the screens' program
  for the web, a dev build, with its live literals' tables and the links
  from its build's paths to the project's). A structural edit goes to the
  compiler's worker (helder.compiler.web, its protocol's `build`, when the
  site is built with it: `build.mjs --compiler bin/compiler-web`): the
  project written to the compiler under `/work/<name>`, the screens'
  program beside it (`.studio/gen`), built, and the preview host started
  again from the running one's state (Hot's snapshot); the build's live
  literals' tables come back with it, so the next colour is a patch again.
- **Touch.** Narrower than 900 points (a phone, a tablet upright) the
  studio is compact: the screens' list a drawer from the header's
  "Screens", the inspector a bottom sheet sliding up when a screen is
  zoomed into (its handle opens and closes it; motion's springs), the
  canvas panned with a finger and zoomed with a pinch. A phone's studio
  is this page in the system's web view.

The studio-web lane (`bun run test studio-web`, tests/studio-web) drives
it in headless Chromium: the welcome's Todo opened, all screens shown,
one zoomed into, its title selected, its colour changed (patched, the
next frames showing it, the file in OPFS), at a desktop's width and a
phone's (taps, a pinch, the drawer), the overview and zoomed states
against goldens; and 50 screens opened and measured. The story-host lane
measures the host natively and the desktop studio with it (50 screens of
examples/todo, Linux, llvmpipe, 4 cores):

| | open to every first frame | resident | Pss |
|---|---|---|---|
| one host, headless (helder.story.Host, frames read back) | 280–310 ms | 202 MB | 168–201 MB |
| the desktop studio's preview process (NativeHost; llvmpipe: frames through shared memory) | 304 ms from its start (2.8 s from the project's open, its cold build included) | 209 MB | 150 MB |
| the desktop studio itself, the 50 frames its images | | 312 MB | 252 MB |
| a process a screen (the desktop studio before) | 0.8–3.3 s | 6.1 GB (sum) | 2.8 GB (sum) |

An inspector's colour change on a zoomed screen reaches the host's new
frame on the canvas in 17 ms, one studio frame. Each screen's first frame
in the host was its own process's byte for byte (the studio lane's
goldens, unchanged). In
Chromium (SwiftShader's WebGPU, the same machine), 50 screens: every
screen shown 0.7 to 2.4 s after the project opened, the preview's module
78 MB, the studio's 27 MB, the page's JavaScript 12 MB. With the
compiler's worker: started in 0.5 to 0.8 s, a padding added built (its
first build) and swapped in in 8.8 s, undone (warm) in 0.8 s; when a warm
build's program ends right after it starts (hxmc's server, as above), the
page builds it again from cold with a new compiler.

## Agents over MCP

The studio serves its tools over MCP (Streamable HTTP, JSON responses)
on 127.0.0.1: the port `--mcp-port`, else `HELDER_STUDIO_MCP_PORT`, else
a free one. It prints the URL at start and writes it to
`<root>/bin/studio/<name>/mcp.json`.

| Tool | Does |
|---|---|
| `project.read {path?}` | a file's text as the studio has it (its unsaved state too); without a path, the files and the screens by flow |
| `project.patch {path, edits: [{old, new}]}` or `{path, text}` | an edit through the studio's history (undoable like any other): live literals patched in the screens, anything else built; answers what happened and the diagnostics |
| `build.check {}` | the program typed (tsgo's check too), nothing written: diagnostics at file and line |
| `run.snap {screen?, path?}` | a screen's last frame as a PNG (the one zoomed into, else the first); a design's frame drawn offscreen |
| `run.tree {screen?}` | a screen's node tree: tags, boxes, texts, colours and each node's `file:line` (a design's frame: its interpreted nodes) |

Claude Code, with the studio open on a project:

```sh
bun run helder studio examples/ts-todo --mcp-port 7340
claude mcp add --transport http helder-studio http://127.0.0.1:7340/mcp
```

Then ask Claude Code to change the app: it reads the files and the
screens' trees (`project.read`, `run.tree`), edits with `project.patch`
(you see each edit on the canvas, and can undo it), checks with
`build.check` and looks at the result with `run.snap` before it reports.
The prompt bar's agent (`Agent`, `LocalAgent` for now) is the interface
the hosted prompt box plugs into later, through the same tools.

**In the browser** the same tools are the page's (`studio.web.WebTools`:
the page calls them through the module, `studio.mjs`, and makes each
`run.snap`'s PNG from the GPU's pixels: a design's frame drawn into a
render target, read back asynchronously; a story's frame from its
bitmap). Where the browser has WebMCP (`document.modelContext`, earlier
`navigator.modelContext`: Chrome's `chrome://flags/#enable-webmcp-testing`)
they are registered with it, beside `project.create {name?, files?}`,
`project.list` and `project.open {name}` (the page's projects in OPFS);
without it nothing changes. Two links open files an agent made:

- `#import=<data>`: `{name?, files: {path: text}}` as JSON (as is,
  percent-encoded), base64url, or `z.` and base64url of its deflate-raw
  bytes; opened as a new project of OPFS (at most 1 MB and 200 files).
- `#draft=<id>`: a draft of helder.build's MCP relay
  (`https://helder.build/mcp`), opened into OPFS and kept linked
  (`.studio/draft.json`): the agent's patches come over a WebSocket and go
  through the studio's history (shown at once, undoable), the files the
  studio writes go back, and after each change the tab reports its check,
  each screen's tree and a small PNG (at most 12 screens), which the
  agent reads with `project.status`.

## Look

Every value of the look is in `src/studio/Theme.hx`: the colours as
tokens (the code view's too), the type, the radii, the layout's sizes and
the canvas' spring, and a helder.ui StyleSheet of the studio's parts by
slot. Its direction is Spacedrive's interface, made the studio's own:

- **Cool, blue-tinted darks** instead of neutral greys: the canvas
  darkest (`canvas`), the cards a step up (`bg`), fields and hovers above
  (`well`, `hover`, `active`); text in three cool greys (`fg`, `fg2`,
  `fg3`); hairlines faint (`line`, `edge`: a blue-grey at 7% and 14%).
- **Cards over the canvas**: the sidebar and the inspector (or the code)
  are cards inset 8 points from the window, radius 12, a faint edge; the
  canvas runs under them (the camera fits what is in focus between them:
  `Studio.insets`). The toolbar sits between them on the canvas: a
  breadcrumb (project, page, frame), the command field (secondary-K:
  `Command`, a frame, a file or a tool by name; arrows and Enter), undo,
  redo, Design and Code. Its empty parts and the sidebar's top drag the
  window: the title bar is inset into the app (helder.os's `TitleBar`), the
  window's buttons in the sidebar's card (`<WindowControls/>`).
- **One accent**, a blue (`accent`), for whatever is active: the
  selection's outline and handles (white squares edged in it), the snaps'
  guides, the frame in focus (its outline, its name a blue pill), the
  current page, frame and layer (a soft fill, `accent-soft`), focus.
- **Icons throughout**: Lucide's (ISC, `icons/`, only those used,
  embedded by `Icons.hx`, strokes 1.75): a page's kind, a frame, a layer's
  element, each section, the toolbar's buttons.
- **Sections** with an icon and a header in small capitals; a row's label
  left, its value right (the inspector's fields, in Geist Mono). Radii 6
  (controls, rows), 8 (the command field, menus), 12 (cards); titles
  medium (500).
- **The code's hues** (violet keywords, blue tags, rose attributes, green
  strings, orange numbers) retuned to the darks; its cursor and selection
  the accent's.
- **Motion**: hovers and the current row's fill ease on helder.ui's
  springs (`motion-color="snappy"` on the window), the selection's box
  springs to a new node, cards and lists enter with `fade`.

Dark first: every colour is a token, so a light theme is a sheet of the
same names. The fonts are Hanken Grotesk for the interface and Geist Mono
for values (`fonts/`, SIL Open Font License).

## Checks and numbers

The studio lane (`bun run test studio`, tests/studio) runs the studio
headless on copies of examples/todo and examples/ts-todo: all screens,
a screen zoomed into, its title selected, its colour changed in the
inspector, a padding added and undone, an attribute typed in the code
view, the prompt bar's `/tree`; the files and every edit's span checked,
the overview, zoomed and selected frames against goldens. Then on
examples/design (design files alone): both frames drawn with nothing
built, the first moved by its caption (snapped to the other's top), the
title selected, its colour changed (drawn again within 3 frames: in 1 on
a Mac), undone and redone, resized by its handle (snapped to the frame's
centre), a second node shift-clicked into the selection and out, the
title's layer dragged below the input row, both undone (the resize one
entry), every edit's span and the file checked. Then the file browser
(tests/studio/files.json: examples/design with an image, a font and code
in folders): the folders opened, the image, the font and the code each in
its view, the image dragged onto the Home frame (the file's `<image>`), a
file dropped from the system on a folder (headless scripts' `drop`). The
test lane runs the studio's own tests (Snap.test.hx, FileTree.test.hx).

On a 4-core Linux container (Mesa's llvmpipe, headless, otherwise idle):

| | todo (Haxe) | ts-todo (TypeScript) |
|---|---|---|
| Cold start to the first frame | 116 ms | 134 ms |
| Project open to all 4 screens shown (a cold build, one host process) | 2.6 s | 3.1 s |
| An inspector's colour change to the program's frame (a live literal) | 17 ms, 1 studio frame | 20 ms, 1 studio frame |
| A structural edit (an attribute added): built, the screens reloaded | 0.6–0.8 s (built in 0.57 s) | 0.6–1.2 s (built in 0.47–0.54 s) |

The gfx-shared lane proves each platform's way of sharing a frame between
two processes (tests/gfx/SharedTexture.hx: a frame drawn in one, opened,
drawn and read back in the other, then a second frame through the same
texture): IOSurface on CI's macOS runner (opened and drawn in 95 ms, the
next frame 1.7 ms), DXGI on its Windows runner (7.7 ms, 0.7 ms), dma-bufs
where the GPU exports them (none on CI: llvmpipe, which the studio lane
runs through shared memory).

## Not yet

- Design files (DESIGN.md), beyond frames of static markup: components
  in a design's frame (islands drawn by the preview host), parts used
  from code, tokens and themes, `<For>` over sample data, interactions.
- Canvas editing, beyond the above: a node is not dragged into another
  parent (the layers reorder among siblings), a multiple selection is
  not resized, no arrow keys' nudges, no new frame or node drawn on the
  canvas; a story's screen (code) is not edited on the canvas yet.
- The App beside stories: one program a project, so a project with
  stories shows them and not its App.
- Designs in the browser's studio are drawn and edited as on the
  desktop (examples/design bundled, a new project's); images by path
  and `run.snap` of a design are native only, and its files are not
  watched (the page's own copy).
- In the browser a project's screens are its stories and design frames:
  an App screen (a project without stories) does not run in the preview
  host's worker, so the examples bundled are those with stories
  (examples/todo, signup, mail) and examples/design.

- A zoomed screen is drawn at the canvas' scale in halves up to 3, not
  tiled: deeper zooms scale its frame.
- A story's shortcuts bound at a module's start (Keymap.global there) are
  the program's main context's, not the screens'.
- On a story's screen selection is click only: no move, resize,
  snapping, layers or multiple selection (a design's frame has them).
- The inspector writes attributes as text; its fields do not come from
  the generated declarations yet (types, units, enums).
- The warm compiler sometimes builds a wrong program after an attribute
  is added to an element of a module a story file uses (hxmc's server:
  the story's view gets its attributes crossed; fixed by hxmc#161, not yet
  in the nightly package.json pins); the studio sees the host end at its
  start and builds again from cold (2 s more).
- No model calls: the prompt bar's agent only calls the tools.
- In the browser: a TypeScript project's structural edits are not built
  there yet (its screens' program for the web is Haxe's alone); its screens share its modules'
  state in one program (a story that sets a module's signal sets it for
  every screen: ts-todo's stories), so only Haxe examples are bundled; the
  screens' input (a click on a screen selects, it is not the app's yet);
  no MCP server of its own (WebMCP, a draft's link); `run.snap` of a
  design's frame needs WebGPU and a tab in the foreground (its frames).
- Opening apps/studio in itself works crudely: its stories show the shell
  without a project and with examples/todo not started, at the window's
  size, without the camera fitted.
