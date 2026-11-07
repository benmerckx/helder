# helder studio

A project's screens on a canvas, its code, an inspector and an agent's
tools, all editing the source files: the first vertical slice of the
studio (helder.build's PLAN.md, step 5). It is a helder app, drawn by
helder.ui, and it opens itself.

```sh
bun run helder studio examples/ts-todo     # this checkout; npx helder studio in a project
bun run helder studio                      # the project in this directory
```

- **All screens.** The canvas shows every screen of the project at once,
  a row per flow. Pan with a drag or the wheel, zoom with secondary
  (Ctrl, Cmd) and the wheel, a trackpad's pinch or two fingers. Click a
  screen to spring into it; Escape or "All screens" goes back.
- **A screen, live.** Each screen is a story of the project's program, a
  dev build, running in one process for the whole project (each story a
  root of its own), offscreen at the screen's size; the canvas shows its
  frames as it draws them.
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
- A project without stories has one screen, its own program's window
  (flow "App").

```tsx
// examples/ts-todo/app.story.tsx
export const empty = story({ name: "Todo/Empty", width: 480, height: 560, render: () => <App/> });
export const phone = story({ name: "Phone/Three items", render: () => { todos(three); return <App/>; } });
```

The stories are read from their text (helder.syntax) when the project
opens, not built, so the canvas is laid out before anything compiled.

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
  reloads (`Runtime.reload`: the host's state in Hot's snapshot, the new
  build started from it), `Host.snap` (a frame's pixels read back for
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
  `projects/<name>/`. The welcome (no `?project=`) opens a folder (the File
  System Access API: its sources copied into OPFS, and written back to the
  folder while the page may), an example bundled with the page, or a
  project already in OPFS. The page reads the project into memory before
  the studio's module starts and writes each save back (`studio.mjs`,
  `Files`).
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
| `run.snap {screen?, path?}` | a screen's last frame as a PNG (the one zoomed into, else the first) |
| `run.tree {screen?}` | a screen's node tree: tags, boxes, texts, colours and each node's `file:line` |

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

## Look

Every value of the look is in `src/studio/Theme.hx`: the colours as
tokens (the code view's too), the type, the radius, the layout's sizes
and the canvas' spring, and a helder.ui StyleSheet of the studio's parts
by slot. For now it is a wireframe until the visual design is settled:
one grey ramp and no hues, text in three greys, hairlines only between
regions, no gradients or shadows, selection and focus outlined in
near-white; one body and one small size, regular and medium. Refine it
there. The fonts are Hanken Grotesk for the interface and Geist Mono for
values (`fonts/`, SIL Open Font License).

## Checks and numbers

The studio lane (`bun run test studio`, tests/studio) runs the studio
headless on copies of examples/todo and examples/ts-todo: all screens,
a screen zoomed into, its title selected, its colour changed in the
inspector, a padding added and undone, an attribute typed in the code
view, the prompt bar's `/tree`; the files and every edit's span checked,
the overview, zoomed and selected frames against goldens.

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

- A zoomed screen is drawn at the canvas' scale in halves up to 3, not
  tiled: deeper zooms scale its frame.
- A reload restores the screens in view; the others start afresh when
  shown (Hot's snapshot settles at the host's first frame).
- A story's shortcuts bound at a module's start (Keymap.global there) are
  the program's main context's, not the screens'.
- Selection is click only: no move, resize, snapping, layers or multiple
  selection; the handles are drawn, not dragged.
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
  MCP has no server there (WebMCP is the plan's).
- Opening apps/studio in itself works crudely: its stories show the shell
  without a project and with examples/todo not started, at the window's
  size, without the camera fitted.
