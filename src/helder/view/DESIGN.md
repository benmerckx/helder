# helder.view: the reactive core, redesigned

Status: a proposal, for review. Nothing here is built yet.

helder.view's core is Solid 1's model with async added on: signals,
memos and effects in an ownership tree, Reactively's clean/check/dirty
colouring, and a value not ready as an exception (`Pending`) that a
computation catches and a `<Loading>` boundary hears about. It works,
but the graph does not know about async: pending is a throw on each
read, not a state of a node; nothing holds a half-updated screen back;
nothing cancels a stale load; errors and pending take two different
paths. This proposes Solid 2.0's semantics on a runtime close to
today's, with four small syntax changes and no compiler magic beyond
the markup macro that exists.

Sources: Solid 2.0's RFCs (solidjs/solid, branch `next`,
`documentation/solid-2.0/`: 01 reactivity, batching and effects; 02
signals, derived values and ownership; 03 control flow; 05 async data;
06 actions and optimistic updates) and its docs (docs.solidjs.com/v2).

## 1. What is there today

- **Signal**: a value and its observers. A write that changes it (`==`)
  marks its observers and runs effects at once (`batch` per write, or
  at the end of an outer `batch`).
- **Memo**: computed eagerly when made, again when read after a source
  changed (check/dirty). Its readers are told only when the result
  differs.
- **Effect**: a `Computation` that runs at once and whenever a source
  changes; side effects and tracking in one function.
- **Owner**: children, cleanups, contexts, `onError` (ErrorBoundary),
  `onPending` (Loading).
- **Pending**: thrown by `Asset.value` while loading. A memo stores it
  and rethrows it to its readers; an effect passes it to the nearest
  Loading boundary; it re-runs when the source resolves.
  `Reactive.isPending` re-runs a function with a probe to find
  refreshing sources.
- **Markup**: `{expr}` is evaluated once, so it is reactive only when
  it is a function or a signal itself (`{() -> a.value}`, `{icon}`).
- **Loading** drops its children and makes them again when a first
  load resolves (components run twice).

Problems this design fixes:

1. **Async is outside the graph.** A pending value is an exception,
   not a state: a memo that read a pending value has a stale `v` and a
   stored `notReady`. Errors take yet another path. Neither propagates
   as a state that boundaries read.
2. **Torn frames.** A write is visible and its effects run at once. If
   part of what depends on it is pending, the screen shows new values
   next to old ones.
3. **No cancellation.** A stale async run is not stopped or dropped;
   the last one to finish wins.
4. **Effects mix tracking and side effects.** An effect can run its
   side effects while other parts of the graph have not caught up.
5. **Allocations per write.** `observers.copy()` on each notify,
   `sources.copy()` on each check, resubscribing every source on each
   run. The frame loop is meant to allocate nothing.
6. **Markup holes are not reactive** unless written as a function, and
   components run twice under Loading.
7. **Dynamic everywhere** (`when:Dynamic`, `Render.read`), so a
   mistake in markup is a runtime error.

## 2. The graph

### Nodes

One node type underneath, three roles:

| role | made by | holds | runs |
|---|---|---|---|
| signal | `signal(v)` | a value | never |
| memo | `memo(fn)` | a value derived by `fn` | lazily, when read and stale |
| effect | `effect(compute, apply)` | a value from `compute` | `compute` in the graph, `apply` after the commit |

Every node with a value carries a **status** beside it:

- `Ready(value)`
- `Pending(previous)` (a new value is on its way; the previous one, if
  any, is still there)
- `Errored(error)`

Status propagates like a value: a memo that reads a pending node is
pending; one that reads an errored node is errored (unless it catches
it). There is no exception in the normal path. Reading `value` of a
pending node inside a tracked computation stops that computation
there, as Solid 2 does with its internal `NotReadyError`; this is the
one place an exception is used, internal to the runtime, and the
computation's status becomes Pending. Outside a tracked computation,
`peek()` returns the last ready value or null, and never throws.

### Async memos are coroutines

```haxe
var user = memo(@:coroutine () -> api.user(id()));
```

A memo whose function is a coroutine (helder.async) runs as a task
owned by its node:

- while it runs, the node is `Pending(previous)`;
- when it returns, `Ready(value)`; when it throws, `Errored(e)`;
- when a source changes before it returns, the task is **cancelled**
  (helder.async's cancellation: the task tree under it too) and a new
  run starts. A superseded result is never committed. Solid 2 only
  drops the result; with structured tasks we can stop the work.
- `onCleanup` inside it runs when the run is superseded or the node is
  disposed (Solid 2: cleanup before the first await runs when the run
  is replaced).

An asset is a node of this kind: `Asset.image(path)` is a memo whose
run loads and decodes the file. `load()` stays: a coroutine that waits
for the node to be Ready.

### Writes and commits (no torn frames)

Writes are **deferred and committed together**, as Solid 2:

- `count.set(v)` queues the write; reading `count()` right after still
  returns the committed value.
- The queue is applied at a **commit**: at the end of the current
  event handler or frame (helder's loop knows both, so no microtask
  is needed), or at once with `flush()`. `flush(fn)` runs `fn` and
  commits what it wrote before returning.
- A commit recomputes what is stale (memos lazily, effects' `compute`
  eagerly), then runs every effect's `apply` in order.
- **Transitions.** When a commit makes a node that is *rendered* (read
  by an effect's compute that is not under a boundary showing its
  fallback) pending, the commit is held: the screen keeps the old
  values for everything the transition touches, and the commit lands
  in one piece when the pending nodes resolve. Several transitions can
  be in flight; ones that touch disjoint nodes commit independently.
- `latest(fn)` reads in-flight values during a transition (falling
  back to the committed one); `isPending(fn)` is true when something
  `fn` reads has a new value on its way (not on a first load, which
  `Loading` shows).

This replaces `batch` (removed, as in Solid 2) and the probe hack in
`isPending`.

### Effects in two halves

```haxe
effect(() -> count(), (value, prev) -> {
	trace(value);
	return () -> {}; // cleanup, optional
});
```

All `compute` halves of a commit run before any `apply` half, so side
effects only see a complete graph. `apply` runs every time `compute`
re-runs (no comparison; put a memo in front to skip unchanged values).
An optional third argument handles an errored status instead of the
nearest `<Errored>` boundary.

Renderers' bindings (a text node's text, an attribute, a style) are
effects of this kind with a renderer-supplied `apply`: the graph never
touches nodes outside `apply`.

### Memos

- **Lazy**: computed when first read, not when made.
- **equals**: `==` by default, an `equals` function optional. Readers
  are marked only when the value differs.
- **Writable derived values** (Solid 2's `createSignal(fn)`): a memo
  you can also `set`; the write lands at once, and the next run of
  `fn` gets it as `prev`. Useful for a selection that resets when its
  list changes but can be changed by the user in between.
- **unobserved**: an optional callback when the last reader goes, for
  releasing a socket or a timer. A lazy memo with no readers is torn
  down and recomputed on the next read.

### Ownership

Unchanged in spirit:

- computations made while another runs belong to it and are disposed
  before it re-runs;
- `root(fn)` made inside an owner is owned by it (Solid 2), and
  `runWithOwner(null, fn)` detaches;
- disposal unwinds children first, later cleanups before earlier ones.

Added:

- an async run's task is a child of its node;
- `onSettled(fn)` replaces `onMount`: runs once the current commit and
  its transitions have landed; it may read reactively and return a
  cleanup.

### Boundaries

- `<Loading fallback>` shows its fallback while a node read under it
  is pending **on its first load**. After it has shown content, a
  later pending value (a refetch, a dev reload) keeps the content on
  screen and holds the transition instead. Its children are made once:
  the parts reading a pending value wait inside the graph, nothing is
  dropped and made again. `on={...}` re-arms it when what it reads
  changes (Solid 2).
- `<Errored fallback={(e, reset) -> ...}>` (renamed from
  ErrorBoundary) shows its fallback when a node read under it is
  errored; `reset` re-runs the errored nodes.
- No boundary above a pending read: that part renders nothing, logged
  in dev builds. No boundary above an error: it reaches the root, which
  logs it and keeps the last frame.

### Actions and optimistic values (later)

Solid 2's `action` (a generator that writes, awaits and refreshes, as
one transition) and `optimistic` signals (writes that show at once and
revert when the transition lands) fit helder.async's coroutines
directly: an action is a coroutine run as a transition. Not in the
first version; the graph is built so they can be added without
changing it.

### Allocation

Steady-state writes and commits allocate nothing:

- nodes keep sources and observers in arrays reused across runs, with
  index bookkeeping instead of `copy()` and `remove()` (alien-signals'
  linked edges are the other option; measure both);
- the commit queue and the effect queue are reused arrays;
- a status is a field and a value, not an object;
- an async run allocates its task (GC user code, as any coroutine).

A test in the GcStats style measures a write and a commit through a
memo to an effect at 0 bytes.

## 3. Syntax

Four changes, all at runtime level except the markup rule, which is the
macro that exists.

### 3.1 Calls to read, `set` to write

```haxe
var count = signal(0);
var double = memo(() -> count() * 2);
count.set(count() + 1);
count.update(c -> c + 1);
```

`Signal<T>`, `Memo<T>` and the others are abstracts over the node with
`@:op(a())` (checked: works on hxmc native and Eval with Haxe
5.0.0-preview.1), inlined, so a read is one call. `.value` and
`.peek()` stay: `value` for code that prefers it, `peek()` untracked.

### 3.2 `Read<T>` for props

```haxe
function Counter(step:Read<Int>) ...

<Counter step={1}/>       // a constant
<Counter step={size}/>    // a signal or a memo
<Counter step={() -> a() + b()}/>
```

An abstract that accepts a value (`@:from T`), a node (`@:from
Signal<T>`, `Memo<T>`) or a function (`@:from Void->T`), read with
`step()`. Props stay reactive without proxies, and destructuring
cannot break them because there is nothing to destructure. A constant
should not allocate a closure: the abstract is over a small class (a
node or a constant cell), not a function.

### 3.3 Markup holes are reactive when they read

The markup macro wraps a hole or an attribute in a computation when
its expression may read: any call or field access that is not a
constant. Literals and constant identifiers stay plain.

```haxe
<text>{double()} {user().name}</text>   // reactive, no () -> needed
<text>{"literal"}</text>               // plain
```

This is what Solid's JSX compiler does. `{icon}` (a node) keeps
working.

### 3.4 Coroutine components

```haxe
@:coroutine function Inventory() {
	var icon = Asset.image("ui/sword.png").load();
	return <image src={icon}/>;
}
```

A component that is a coroutine is a node's async run: under a
`<Loading>` it is pending until it returns, it is cancelled when its
owner goes, and it is made once. Plain components stay plain
functions.

## 4. What changes for existing code

- `Reactive.signal(v).value` keeps working; `get()` becomes a call.
- `Reactive.batch` is removed (`flush(fn)` where code needed it).
- `Reactive.effect(fn)` becomes `effect(compute, apply)`; a
  one-argument form stays for renderers' internal use only.
- `onMount` becomes `onSettled`.
- `ErrorBoundary` becomes `Errored`.
- `Pending` and `Loadable` leave the public API; `Asset` becomes a node.
- `Flow`'s props become typed (`when:Read<Bool>`, `each:Read<Array<T>>`)
  instead of `Dynamic`.
- Dev reload's state keys (`Refresh`) attach to nodes as today.

## 5. Plan

1. Port Solid 2's reactive tests (signals, memos, effects, ownership,
   async, transitions, Loading, Errored) to helder.test.
2. The new core beside the old one (`helder.view.graph`), passing them,
   with the allocation test.
3. Syntax 3.1 and 3.2, then the markup rule 3.3.
4. Move helder.view's renderers (DOM, ui, native), helder.asset and
   scene onto it; remove the old core.
5. Coroutine components (3.4).
6. Later: actions, optimistic values, stores.

Each step keeps every lane green and measures compile time (the markup
rule is the only macro change) and the frame loop's allocations.

## 6. Open questions

1. **When does a commit happen without an event?** A write from a
   coroutine after an await, or from a timer: commit at the next frame
   (the loop is running) or at the end of the loop turn. Proposed: the
   end of the loop turn, so it works without a frame loop too.
2. **Transitions' scope.** Solid 2 holds per transition, which needs
   bookkeeping of which nodes each touches. A first version could hold
   the whole commit while anything rendered is pending, and refine
   later. Proposed: start with the simple whole-commit hold, measure.
3. **Writes inside computations.** Solid 2 forbids writing a signal
   from a component body or effect compute (dev error) unless the
   signal opts in. Proposed: the same, as a dev-build check.
4. **Markup's "may read" rule.** A call to a plain function that reads
   nothing gets wrapped needlessly; cheap, but not free. Proposed:
   wrap, and let `untrack(...)` or a constant mark opt out.
5. **Stores.** Solid 2's stores are proxies; Haxe has none. A typed
   store would be a build macro per class; out of scope here.
