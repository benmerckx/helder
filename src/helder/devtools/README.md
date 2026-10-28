# helder.devtools

The devtools protocol, and the agent that speaks it in the program: one
message format on the dev connection, for reloads, logs and the tools.
JSON-RPC 2.0 as the Chrome DevTools Protocol and Dart's VM service have
it: methods in domains (`Runtime`, `Log`, `Frame`, `Ui`; libraries add
their own) that cost nothing until a tool enables them. A first slice:
`helder dev` (src/helder/cli) is the relay, `helder inspect` the client
that proves it; the VS Code extension (README, phase 3) comes later.

```
program (agent) ──JSON lines──▶ helder dev ◀──WebSocket── tools (helder inspect, ...)
      HXMC_DEV's TCP connection        /__helder/devtools on its HTTP port
```

The agent is compiled in dev builds only (`-D hxmc.dev`, which `helder
dev` adds, as `helder.dev.Hot`): a release build has none of it, byte for
byte.

```sh
bun run helder dev tests/devtools/Pulse.hx       # writes bin/dev/devtools.json
bun run helder inspect --frames                  # in another terminal
bun run helder inspect --tree --port 4321
```

## Framing

- **Messages** are JSON-RPC 2.0 objects, each with `"jsonrpc": "2.0"`: a
  request `{id, method, params}`, its response `{id, result}` or `{id,
  error: {code, message}}`, a notification `{method, params}` (no id).
  Either side may send requests. Ids are the sender's (integers here);
  `params` and `result` are objects.
- **Program and CLI**: the TCP connection the program opens to `HXMC_DEV`
  (`host:port`), one message per line (UTF-8, `\n`; JSON escapes its
  newlines). A program speaks the protocol only when `helder dev` starts it
  with `HXMC_DEV_PROTOCOL=1`; otherwise (@hxmc/cli's `dev.mjs`) it speaks the
  older `{"type"}` lines: `reload` to it, `saved` and `frame` from it. On
  one connection a line with `jsonrpc` is the protocol's, one with `type`
  the older one's.
- **Tools and CLI**: a WebSocket at `ws://<host>:<port>/__helder/devtools`,
  the dev server's HTTP port (natively too), one message per text message.
  Several tools at once. `helder dev` writes `bin/dev/devtools.json`
  (`{port, host, path, protocol, entry, target}`) under the project for
  tools to find it.
- **The relay**: a tool's request goes to the program under the CLI's own
  id, its response back to that tool under the tool's id. The program's
  notifications go to each tool that enabled their domain; `Runtime`'s go
  to every tool. Methods marked *CLI* below are answered by `helder dev`
  itself.

## Versioning

`protocol` is one integer, now `1`, exchanged by `Runtime.hello`. Adding a
method, a notification, an optional param or a result field does not change
it; a peer ignores fields and notifications it does not know, and answers
a method it does not know with -32601. Removing or renaming anything, or
changing what a field means, makes the next integer. A hello with another
integer is refused (-32010): the tool closes, the program stays on the
older lines.

## Errors

| code | |
| --- | --- |
| -32601 | no such method (a domain the program does not have: `Ui.getTree` without helder.ui) |
| -32603 | the method threw (its message) |
| -32001 | no program connected (a build that failed first, a reload in progress, the web for now) |
| -32002 | the program's connection closed before it answered (a reload, or it ended) |
| -32010 | another protocol version |

## Domains

A domain's notifications flow only while it is enabled: `<Domain>.enable`
(params per domain) and `<Domain>.disable`, both answered `{}` or the
domain's result. The CLI counts the tools: it enables a domain in the
program when the first tool enables it, disables it when the last one
disables it or disconnects, and enables it again in each new build. A
domain's requests (`Ui.getTree`) need no enable.

### Runtime

| method | from | params | result |
| --- | --- | --- | --- |
| `Runtime.hello` | program to CLI, on connecting | `{protocol, program: {name, target, hosted, reloaded}, domains: [names]}` | `{protocol, server}` |
| `Runtime.hello` | tool to CLI (*CLI*) | `{protocol, client?}` | `{protocol, server, program (the last hello's, null if none), entry, target, build}` |
| `Runtime.reload` | CLI to program | `{snapshot, library?}`: the snapshot's file; a dev host's next library | `{saved: true}` once the snapshot is written, then the build exits or hands over |
| `Runtime.state` | tool to program | `{}` | `{kept: [{key, type, bytes}], notKept: [keys], dropped: [keys], reloading}`: the keys `Hot` keeps (each onSnapshot function run, as before a reload), those it cannot (not data), those the last reload restored and nothing asked for |

`name` is the build's (`-D helder.name`), `target` hxmc's, `hosted`
whether a dev host runs it, `reloaded` whether it started from a snapshot,
`domains` those it has when it connects (a library may add one later).
`build` is the last build's `{ok, ms, size}` or `{ok: false, ms, message}`.
A tool's `Runtime.reload` is refused (-32601): a reload is a change to a
source.

| notification | from | params |
| --- | --- | --- |
| `Runtime.ready` | program | `{}`: its first frame (the reload's time) |
| `Runtime.connected` | CLI | `{program, protocol}`: a build said hello |
| `Runtime.built` | CLI | `{ok: true, ms, size}` |
| `Runtime.buildError` | CLI | `{ms, message}`: the errors; the last good build keeps running |
| `Runtime.reloaded` | CLI | `{ms, build}`: from the change seen to the new build's first frame, and the build's part |
| `Runtime.exited` | CLI | `{code}`: the program ended by itself |

### Log

| method | params | result |
| --- | --- | --- |
| `Log.enable` | `{}` | *CLI*: `{entries: [entry]}`, the last 500 kept |
| `Log.disable` | `{}` | `{}` |

| notification | params |
| --- | --- |
| `Log.entry` | `{level, source, message, position?, time}` |

`level` is `info` or `error`; `source` is `trace` (the program's
`trace`, with `position: {file, line, className, method}`), `stdout` and
`stderr` (its output, line by line), `build` (a build's errors) or
`helder` (the program ended). `time` is when the CLI got it (seconds,
wall clock). The CLI enables `Log` in every build, whether a tool has it or
not, and keeps the last 500 entries, so a tool that connects late, or after
a crash, still reads them. With `Log` on, the agent replaces
`haxe.Log.trace`: a trace is sent, not printed, and the CLI prints it as
Haxe does (`file:line: message`); a trace before the hook is printed and
comes as `stdout`. Output and traces come on two streams, so their order
across the two may differ.

### Frame

| method | params | result |
| --- | --- | --- |
| `Frame.enable` | `{interval?}`: ms between batches, 100 by default (the first tool's) | `{interval, timed}` (`timed`: pauses have their time) |
| `Frame.disable` | `{}` | `{}` (the last batch sent first) |

| notification | params |
| --- | --- |
| `Frame.stats` | `{first, dt, work, gcBytes, gcCollections, gcPauseMs, agentBytes}` |

A batch is columns, one value per frame from frame number `first`: `dt`
the frame's time (ms, from the last frame's end), `work` from the turn's
start to its end (ms: `App`'s loop, `Hot.poll` to `Hot.framed`; the rest of
`dt` is waiting for vsync or the next event), `gcBytes` the bytes allocated
on the GC heap (large objects included), `gcCollections` and `gcPauseMs` the
collections and their pauses (stopping the world included). `agentBytes` is
the agent's own garbage since the last batch (the batch itself, the messages
read), taken out of `gcBytes`. A batch is sent per interval, or per 256
frames. The counters are hxmc.GcStats', natively and on wasm32 alike, kept
by the runtime without its stats on (nothing printed to stderr).

### Assets

| notification | from | params |
| --- | --- | --- |
| `Assets.changed` | CLI to program | `{key}`: an asset's file changed (helder.asset: the program loads it again behind the same handle; no build) |

The method exists in a program that loads assets (helder.asset's
`Assets`, in dev builds); without it the notification is ignored. On
the web the page gets `{"type":"asset","key"}` on its WebSocket instead
and hands the key to the module.

### Ui

| method | params | result |
| --- | --- | --- |
| `Ui.getTree` | `{}` | `{uis: [{width, height, root: node, overlay: node}]}` |

A node is `{id, tag, x, y, width, height, style: {display, direction,
grow, opacity, background, color, fontSize}, text, children}`: `x`, `y` in
window pixels and the size after the last layout, colours `#aarrggbb`,
`text` a text node's. An id stays the node's while it is in a tree (not
across a reload). The method exists only in a program with helder.ui:
`helder.ui.DevTree`, which each `Ui` registers with (in dev builds), the
last 8 kept; helder.devtools does not depend on ui.

## The agent

`Agent` (the dispatch, Runtime and Log), `Frames` (the Frame domain) and
`GcCounters` (the collector's counters, the one place they are read:
`hxmc.GcStats`). `helder.dev.Hot` holds the
connection: it hands the agent each message but `Runtime.reload`, calls
`Agent.turn` and `Agent.frame` at each turn's start and end, and
`Agent.dispose` before a reload. A library adds a method with
`Agent.method("Domain.name", params -> result)` (throw an `RpcError` for a
code of its own), under `#if hxmc.dev`.

## Cost

- **Code**: 27 KB in a console program's dev build (Tally: 258 to 285 KB),
  27 KB in the counter example's (1885 to 1912 KB), 35 KB with ui's tree in
  Boxes (841 to 876 KB). Release builds unchanged, byte for byte (Tally,
  counter, todo).
- **A frame** (`bun run test devtools`, FrameCost): disabled 0.4 ns (two
  checks of a flag), enabled 60 ns and no garbage (two reads of the
  clock, `haxe.Timer.stamp`; the GC counters, five columns), a batch of 6
  frames 1.3 µs and 1.5 KB of the agent's garbage: 17 µs a second at 60
  fps. The
  console fixture's frames read 0 GC bytes while it allocates nothing, and
  4800 in every frame once it allocates 100 small arrays.

## Not yet

The agent on the web (the page relaying between the module and the
WebSocket; the log comes from the page's output today), node ids kept
across reloads, get, query and set on properties (as Bevy's BRP),
profiler samples as a binary stream, the other domains (`Scene`,
`Signals`, `Profiler`, `Stories`; `Assets` has its notification only), spans and counters, levels
of the program's own (`Log` takes traces), `Runtime.evaluate`, pick and
highlight, and the VS Code extension.
