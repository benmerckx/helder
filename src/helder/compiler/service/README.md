# helder.compiler.service

The compiler as a library: one in-process API for the studio, the CLI and,
later, the web's worker, over helder's compiler kept warm as a compilation
server. `helder build`, `run` and `dev` build through it
(`helder.cli.Compiler.CompileServer` is a thin wrapper that prints what a
build printed), so the studio's path and the CLI's are the same.

```haxe
import helder.compiler.service.Service;

var s = Service.start(task, {tool: helder.cli.Compiler.tool(), std: helder.cli.Compiler.hxmcStd()});
var e = helder.cli.Entry.resolve("examples/todo");          // the project: its compiler words
var words = e.args().concat(["-D", "hxmc.dev", "--custom-target", "hxmc=bin/dev/Todo"]);

s.check(e.args(), cwd, changed);    // {ok, diagnostics, ms}: typed (and tsgo's check), nothing written
s.literals("bin/dev/Todo.literals"); // dev builds write their sources' live literals' tables there
s.build(words, cwd, changed);        // {ok, diagnostics, messages, printed, ms}
s.edit(running, saved);              // Patched(literals) | Unchanged | Build(why)
s.reload(running, {snapshot: file, library: lib}); // the running program swapped to the build, its state kept
s.stop();
```

| | |
| --- | --- |
| `Service.start(task, {tool, env?, std?})` | helder's compiler as a resident server (`--server-connect`), warm across requests: Haxe's typed modules, hxmc's lowered bodies (LowerCache) and per-module objects |
| `check(words, cwd, ?changed)` | the program typed with `--no-output` (a frontend's own check too: tsgo's), its diagnostics as data (`Diagnostic`: file, line, column, endColumn, severity, message) |
| `build(words, cwd, ?changed)` | a build; its output is the words' (`--custom-target hxmc=<out>`); a dev build (`-D hxmc.dev`) with `literals(dir)` on writes the live literals' tables |
| `invalidate(files, cwd)` | files changed (the server compares times, which two saves in one second share); `check` and `build` take them as `changed` |
| `edit(running, saved)` | the saved files compared with the sources the running build was made from (`LiteralEdit`): only live literals' values changed, they are patched in the program (`Hot.literals`), nothing built; else `Build(why)` |
| `reload(running, params)` | `Runtime.reload` to the running program (its snapshot's file, a dev host's next library), true once it saved and handed over |

`running` is a function sending a devtools request to the program and
handing its response over (`helder dev`: its relay, `Devtools.request`;
the studio: its connection to the preview's process), false when none is
connected. The protocol is `src/helder/devtools/README.md`'s.

## Live literals

In a dev build (`-D hxmc.dev`; never `helder.release`) the markup planner
(`helder.markup.Plan`, Haxe's markup and TSX alike) writes the literals of
markup as reads of a slot table (`helder.dev.Literals`):

- elements' and neutral elements' attribute values: numbers, strings
  (colours `#3b82f6`, `rgb(...)`; lengths `4 6`, `50%`), flags; style props
  are attributes (`background="#fff"`, `padding={24}`);
- texts (`<text>todos</text>`);
- the values of a ternary's branches and `??`'s fallback in an attribute
  (`color={done() ? "#a1a1aa" : "#18181b"}`), and a `Color.rgb`/`rgba`/`hex`
  channel (Haxe);
- components' literal props (bound when the prop reads, `Read<T>`; else
  read once: a patch of it is a build).

Not live: identities and references (`key`, `ref`, `tag`, `id`, `slot`,
`variant`, `states`, `role`, `style`, `name`, `type`), handlers, and literals
elsewhere in code (a `case`, an argument): their edits build.

A slot is a signal: a literal in a reactive position (an attribute, a text,
a prop that reads) is bound as any read is, so a patch re-runs only what
reads it, and the next frame shows it. The id is
`<file>:<line>:<column>:<kind>` (byte column from 1), derived from the
source the build was made from; `helder dev` keeps that source and maps a
save to those ids (a value of another length moves nothing for the
program). A patch survives a reload in the snapshot and finds its slot
again by id, else by file, kind and anchor (its line, values left out),
while the compiled value is still the one it replaced.

`helder dev` patches a save that changed only literals' values (no build):
`patched 1 literal, nothing built`, then `shown in N ms` (the frame).
`--literals-only-check` says each change's path and why (`build Todo.hx,
line 57: not a live literal's value`); `--no-literals` builds every change.
A literal read once, not bound (a plain prop), makes the save a build.
The web target builds every change (its page has no devtools agent yet).

The tables: `-D helder.literals=<dir>` (the service's `literals(dir)`) has
each source's live literals written as `<dir>/<md5 of the source>.json`
(`{file, entries: [{id, start, end, form}]}`), by Haxe's markup macro
(`helder.view.LiveMacro`) and TypeScript's lowering (`Tsx.live`), content
addressed, so a module the server did not type again keeps its table.

Release builds contain none of it: `helder build examples/todo` and
`examples/ts-todo` are byte for byte what they were before live literals
(the markup macro's code positions unmoved, no node numbered for a text).

## The web (wasm) build: what blocks it

The API holds no native assumption beyond its backend: `Resident` is a
process and a socket. In the browser the compiler is hxmc's compiler built
as wasm32-wasi, called in a worker on the same requests
(`helder.compiler.Compiler.run(args)`: the words, `--cwd`). What blocks
that today:

- **Processes**: the compiler spawns none for Haxe, but helder.typescript's
  check runs tsgo, a native executable (`helder.typescript.check.Tsgo`):
  TypeScript 7's API as wasm (tsgo builds for `GOOS=wasip1`) or a JS
  TypeScript in the worker.
- **Threads**: hxmc's code generation is parallel (`Driver.parallel`,
  `domains()`); the compiler for helder is built `-D disable-parallelism`
  already, and wasm32-wasi has no threads: one domain.
- **Files**: sources, std, the module cache and the object store are
  files: WASI preopens over an in-memory or OPFS file system the studio
  fills (the project, helder's src, hxmc's std).
- **Resident state**: the server keeps its state in its process; in a
  worker the module (and its heap) stays alive between requests, so the
  same warm path works without the socket.
- **Native targets**: a native preview links against the runtime objects
  (`rt.o`, the platform packages); in the browser the preview is the app's
  own wasm32 build, which needs none.
- **`chmod`** after a link (`Driver.markExecutable`): `HXMC_EXE_LIST`
  covers WASI already.

## Structural edits: where the time goes

`bun run test edit-loop` (bin/edit-loop/results.md) times helder dev on
examples/todo and examples/ts-todo, warm, in a window (Linux, Xvfb,
llvmpipe; 4 cores), from the save to the new frame. Medians, ms:

| app | edit | total | watcher | tsgo | typing | filters | lowering | codegen | link | server | cli | reload | frame | other |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| todo | literal (patched) | 18 | 12 | | | | | | | | | | 4 | 2 |
| todo | a component's body | 707 | 33 | | 153 | 72 | 114 | 120 | 39 | 90 | 15 | 10 | 32 | 27 |
| todo | a component added | 727 | 34 | | 168 | 67 | 113 | 151 | 34 | 87 | 15 | 6 | 31 | 27 |
| ts-todo | literal (patched) | 18 | 13 | | | | | | | | | | 4 | 1 |
| ts-todo | a component's body | 632 | 34 | 45 | 54 | 84 | 164 | 131 | 43 | 3 | 19 | 10 | 31 | 25 |
| ts-todo | a component added | 688 | 12 | 47 | 53 | 88 | 166 | 184 | 42 | 3 | 19 | 6 | 31 | 25 |

(Before this work every edit, literals too, took 650 to 860 ms.) The
studio's budget for a structural edit is 300 ms warm: about 520 to 590 ms
of each is inside the compilation server, hxmc's and Haxe's. The build's
sequence for a one-function edit of Todo.hx, with what the server's stats
say (HELDER_DEV_SERVER_LOG=1 with HELDER_DEV_PHASES=1):

1. the request, before `beforeTypingHook` (`server`): about 90 ms for the
   Haxe program, 3 ms for the TypeScript one: the target's init macro
   (`hxmc.Init.init()`), `Setup.initializeTarget`, `ServerCache`'s checks of
   what it keeps (the macro context's modules among them: the markup
   macros' world, which the TypeScript build barely has);
2. init macros and typing (`typing`): 150 to 170 ms for Todo.hx alone typed
   again (its markup expanded by MarkupMacro on the macro interpreter);
3. Haxe's filters (`filters`): 70 ms, whole program, every build;
4. hxmc's lowering: 110 to 165 ms although `bodies 3746 reused (147 by
   key), 101 lowered`: the reuse's own cost over every body;
5. prepare, codegen, data (`codegen`): prepare 50 to 140 ms (whole
   program: reach, 3587 functions), codegen of the modules whose
   fingerprint changed (10 of 277 for a lambda's body changed in Todo.hx:
   inlining spreads a change), data regenerated whole (26 to 29 ms);
6. link: 35 to 45 ms, the whole executable (a shared library for the dev
   host) linked again.

What the dev loop adds is about 110 ms: the watcher (its 25 ms tick),
helder dev's own step (the assets' check, the live literals' tables read),
the dev host's swap (the snapshot, the library loaded: 6 to 10 ms) and the
new build's first frame (31 ms).

Suggestions for hxmc (not patched here):

- **The request's start**: cache `ServerCache.afterTargetInit`'s verdicts
  for modules whose files' stamps did not change, and the macro context's
  validity when no macro module changed (90 ms of Todo's).
- **Filters and lowering per module**: run Haxe's filters (DCE aside) and
  hxmc's lowering only for the modules typed again; today both walk the
  whole program (150 to 230 ms together), even with LowerCache's reuse.
- **Prepare incrementally**: keep `Prep`/`Reach` results across builds of
  the server and update them from the changed modules' functions.
- **Fingerprints that do not spread**: a lambda's body changed in Todo
  recompiled 10 modules; inlining (Fingerprint.Inlined) could key on the
  inlined function's own digest only where it is inlined.
- **Data and link incrementally**: for a dev build the data object and the
  link could be patched, or the changed modules' objects linked into a
  small shared library the dev host loads over the last (per-module
  reload), which hxmc's dev-host support (`-D hxmc.shared`) is close to.
- **Typing the markup**: MarkupMacro on the macro interpreter costs most of
  Todo.hx's 150 ms typing; the interpreter's tiers (HXMC_MIR_TIER) or a
  compiled macro host would help every markup-heavy module.
