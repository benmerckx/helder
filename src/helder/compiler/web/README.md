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
| `/node_modules/helder` | helder's package.json and sources (`src/`: `HELDER_SRC`) (the bundle) |
| `/node_modules/@hxmc/cli` | hxmc's package.json, Haxe's std (`haxe/upstream/std`: its `haxe`, `sys`, `eval` packages and top-level classes) and hxmc's std (`hxmc/bootstrap/hxmc-std`) (the bundle) |
| `/node_modules/typescript` | the `typescript` package's package.json, its API's protocol (`dist/api/node`) and enums (`enums`): helder.typescript's tables (the bundle) |
| `/node_modules/@typescript/typescript-wasip1-wasm/lib` | TypeScript's ECMAScript libraries (`lib.*.d.ts`, without the DOM's, webworker's and scripthost's) (the bundle) |
| `/work` | the page's projects (`write`) |
| `/out` | builds' modules (`/out/<name>.wasm`; live literals' tables in `/out/.literals`) |
| `/cache` | `HOME`: hxmc's module cache (`/cache/hxmc`) and helder's (`/cache/helder`): kept in OPFS where the browser has it |

In memory, with `/cache` mirrored to OPFS (written after each build, read
at `init`).

## The preview

A build's module is a wasm32-wasi program like any `helder build --target
web` makes: `src/helder/os/browser.mjs` runs it with the imports of the
packages it uses. `preview.mjs` runs one in a page (helder.os's browser
imports draw on the DOM's canvases: a frame of its own keeps it apart)
with helder dev's imports (`hxmc_dev`), so the worker's `edit` reaches it:
`preview.devtools(request)` hands a devtools request to the program and
resolves with its response, and `preview.swap(build)` runs a new build in
the running one's place with its state (Hot's snapshot), as helder dev's
page does.

```js
import { Preview } from 'helder/src/helder/compiler/web/preview.mjs';
const preview = new Preview({ base: '/helder/src/helder/', fonts: [dejavu] });
await preview.run(await c.build('/work/app'));
c.running = (request) => preview.devtools(request);
const e = await c.edit({ '/work/app/main.tsx': saved });
if (e.kind === 'build') await preview.swap(await c.build('/work/app'));
```

## Building and testing

`node src/helder/compiler/web/build.mjs [out]` writes the files the worker
fetches (bin/compiler-web: `helder-compiler.wasm`, `tsc.wasm`,
`sources.bundle`, their `.br`, `typescript/`, `manifest.json`); the
compiler's module is kept in helder's cache (`HELDER_CACHE`) per hash of
its sources. `bun run test compiler-web` builds them, then checks and
builds todo and ts-todo in node (tests/compiler-web/node.mjs) and in
headless Chromium (tests/compiler-web/browser.mjs: the worker, the
preview in a frame, a literal edit patched and a structural one built and
swapped in), and prints the numbers.

## Numbers

Headless Chromium 156 on a Linux x86-64 CI-class machine (the lane's
numbers, 2026-11-07), against the native compiler on the same machine:

| | in the browser | native |
| --- | --- | --- |
| download (brotli; raw) | 13.8 MB: compiler 2.2, tsc.wasm 9.5, sources 2.0 (81 MB: 17.4, 52.8, 10.8) | |
| cold start, served locally | 0.6–0.9 s (download 0.3–0.4, compile 0.1, warm-up 0.2–0.3) | |
| todo, first build | 5.9–7.6 s | 2.8 s (server), 2.7 s (one-shot) |
| ts-todo, first build | 7.1–8.6 s | 3.5 s (server), 3.2 s (one-shot) |
| a structural edit, warm build | todo 0.74–0.81 s, ts-todo 1.4–1.9 s (and 25–35 ms to swap it in) | 0.3–0.4 s |
| a literal edit | 1–8 ms, patched, no build | |
| memory | the compiler's 1.8 GB after both, tsgo's 55 MB | 1.3 GB (the server's peak RSS) |

The compiler's linear memory only grows: two projects built in one worker
reach ~1.8 GB of the 4 GB wasm32 allows (a nursery of 32 MB, `RT_MINOR_KB`).
