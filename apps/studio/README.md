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
- **A screen, live.** Each screen is the project's program, a dev build,
  running in a process of its own at the screen's size, offscreen; the
  canvas shows its frames as it draws them.
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

- **The project never runs in the studio's process.** The studio builds
  one program of the project's stories (a dev build, `-D hxmc.dev`,
  headless: `-D helder.headless`; its main `helder.story.Screens` over
  them, generated in `<root>/bin/studio/<name>`) and starts it once per
  screen (`HELDER_STUDIO_SCREEN` names which), so each screen has its
  own state, and a crash or an endless loop takes only that screen down.
- Each screen draws offscreen at its size (helder.headless's serve mode:
  each frame written to a file and told as `Headless.frame`), and talks
  to the studio over the devtools protocol (src/helder/devtools): its
  tree (`Ui.getTree`, `Ui.nodesAt`), live literals (`Hot.literals`),
  reloads (`Runtime.reload`, its state kept). A screen ends with the
  studio (`HXMC_DEV_EXIT_WITH_SERVER`).
- The compiler stays warm (helder.compiler.service). One build runs at a
  time; files edited during a build are written after it.

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
  preview's frame in 12 to 24 ms, one studio frame.
- **The preview's module** of an example is built where the page is built
  (`helder studio <project> -- --export-web <dir>`: the screens' program
  for the web, a dev build, with its live literals' tables and the links
  from its build's paths to the project's). A structural edit goes to the
  compiler's worker (helder.compiler.web, its protocol's `build`: the
  screens' program written beside the project, the host started again
  from its state) when the page has one; until it lands such an edit is
  saved, not built, and the studio says so.
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
measures one host against a process a screen natively (50 screens of
examples/todo, Linux, llvmpipe):

| | open to every first frame | resident (sum) | Pss (sum) |
|---|---|---|---|
| one host (helder.story.Host) | 308 ms | 202 MB | 168 MB |
| a process a screen (today's desktop studio) | 3329 ms | 6147 MB | 2798 MB |

In Chromium (SwiftShader's WebGPU, the same machine), 50 screens: every
screen shown 0.7 s after the project opened, the preview's module 78 MB,
the studio's 27 MB.

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
| Project open to all 4 screens shown (a cold build, 4 processes) | 2.6 s | 2.9 s |
| An inspector's colour change to the program's frame (a live literal) | 27 ms, 1 studio frame | 24 ms, 1 studio frame |
| A structural edit (an attribute added): built, the screens reloaded | 0.6–0.8 s (built in 0.57 s) | 0.6–1.2 s (built in 0.47–0.54 s) |

## Not yet

- The screens' frames go through a file each frame (RGBA, uploaded as an
  image), not a shared GPU texture; they are drawn at 1x and scaled, not
  tiled at the canvas' zoom.
- Selection is click only: no move, resize, snapping, layers or multiple
  selection; the handles are drawn, not dragged.
- The inspector writes attributes as text; its fields do not come from
  the generated declarations yet (types, units, enums).
- The warm compiler sometimes builds a wrong program after an attribute
  is added to an element of a module a story file uses (hxmc's server:
  the story's view gets its attributes crossed); the studio sees the
  screens end at their start and builds again from cold (2 s more).
- No model calls: the prompt bar's agent only calls the tools.
- The desktop studio still runs a process a screen: the one-host model with
  shared GPU textures (HostRuntime's native runtime) is next; the host and
  its contexts are ready for it.
- In the browser: structural edits wait for the compiler's worker
  (helder.compiler.web); a TypeScript project's screens share its modules'
  state in one program (a story that sets a module's signal sets it for
  every screen: ts-todo's stories), so only Haxe examples are bundled; the
  screens' input (a click on a screen selects, it is not the app's yet);
  MCP has no server there (WebMCP is the plan's).
- Opening apps/studio in itself works crudely: its stories show the shell
  without a project and with examples/todo not started, at the window's
  size, without the camera fitted.
