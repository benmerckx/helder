# helder.compiler.web

helder's compiler toolchain in the browser: hxmc's compiler with helder's
hooks (markup, definitions, helder.typescript's frontend) built as
wasm32-wasi, and TypeScript's API as WebAssembly, in a worker. The web and
mobile studio check, build and preview on the device with it; the preview
is the app's own wasm32 build, run by the page.

The worker answers helder.compiler.service's requests (check, build,
invalidate, edit, reload) as messages. Its compilation server stays warm
between builds (the module and its heap stay alive in the worker), and an
edit of live literals' values patches the running preview without a build.

## The protocol

`protocol.d.ts` has the messages; `client.mjs` wraps them as promises:

```js
import { CompilerClient } from 'helder/src/helder/compiler/web/client.mjs';
const c = new CompilerClient(new Worker(new URL('worker.mjs', base), { type: 'module' }));
await c.init();                                    // {protocol, versions, threads, persistent, ms, bytes}
await c.write({ '/work/app/main.tsx': text, '/work/app/package.json': '{}' });
const d = await c.check('/work/app');               // {ok, diagnostics, ms}
const b = await c.build('/work/app');               // {ok, diagnostics, messages, printed, ms, out, wasm}
c.running = (request) => preview.devtools(request); // the preview's devtools (preview.mjs)
const e = await c.edit({ '/work/app/main.tsx': saved }); // {kind: 'patched' | 'unchanged' | 'build', ...}
if (e.kind === 'build') await c.build('/work/app');
```

| Request | Does | Reply |
| --- | --- | --- |
| `init {assets?, persist?}` | downloads and compiles the compiler and TypeScript's modules, unpacks the sources, warms the server | `InitResult` |
| `write {files}` | files into the file system (`null`: removed), marked changed | `{}` |
| `read {path}`, `list {dir}` | a file's bytes; a directory's files | `Uint8Array`, `string[]` |
| `check {entry, changed?, args?}` | the program typed, TypeScript's check, nothing written | `{ok, diagnostics, ms}` |
| `build {entry, dev?, out?, changed?, args?}` | a wasm32 build (dev by default: live literals' tables kept) | `BuildResult` (the module transferred) |
| `invalidate {files}` | files changed outside `write` | `{}` |
| `edit {files?, changed?}` | saved files against the last dev build's sources: only live literals' values changed, patched in the preview (`Hot.literals` through `running`) | `{kind: 'patched', literals}`, `{kind: 'unchanged'}`, `{kind: 'build', why}` |
| `reload {params?}` | `Runtime.reload` to the preview through `running` | `boolean` |
| `stats` | memory, files, builds | `StatsResult` |

An entry is what `helder build` takes (helder.cli.Entry): a project's
directory (its package.json, `src/main.ts(x)` or a main class), a `.hx` or
a `.ts`/`.tsx` file. Diagnostics are helder.compiler.service's
(`Diagnostic`: Haxe's columns).

`running` is how the worker reaches the preview: an event
`{type: 'running', rid, request}` that the page answers with
`{type: 'running', rid, response}` (the program's JSON-RPC response, or
null when none runs). `client.mjs` calls its `running` function for it.

## The file system

| Path | |
| --- | --- |
| `/helder/src` | helder's sources (the bundle) |
| `/hxmc/std`, `/haxe/std` | hxmc's std, Haxe's std (the bundle) |
| `/typescript` | the `typescript` package's declarations TypeScript's API reads (the bundle) |
| `/work` | the page's projects (`write`) |
| `/out` | builds' modules |
| `/cache` | hxmc's module cache and helder's: kept in OPFS where the browser has it |

In memory, with `/cache` mirrored to OPFS (written after each build, read
at `init`).

## The preview

A build's module is a wasm32-wasi program like any `helder build --target
web` makes: `src/helder/os/browser.mjs` runs it with the imports of the
packages it uses. `preview.mjs` runs one in a page or a worker with
helder dev's imports (`hxmc_dev`), so the worker's `edit` and `reload`
reach it: `preview.devtools(request)` hands a devtools request to the
program and resolves with its response.
