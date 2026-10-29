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

- `count(v)` queues the write; reading `count()` right after still
  returns the committed value. `count(c -> c + 1)` is given the latest
  queued value (Solid 2's function setter), so two of them in one
  handler add two; `count(count() + 1)` twice adds one. Read-modify-write
  is written with the function form.
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
  you can also write, `signal(() -> ...)` (a signal never holds a
  function, 3.1, so a function given to `signal` is unambiguous); the
  write lands at once, and the next run of `fn` gets it as `prev`. Useful for a selection that resets when its
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

### 3.1 Calls to read, write and update

```haxe
var count = signal(0);
var double = memo(() -> count() * 2);
count(5);             // write
count(c -> c + 1);    // update: given the latest queued value
```

The same in TypeScript (7), character for character but for `var`
and `->`. `Signal<T>`, `Memo<T>` and the others are abstracts over the
node with `@:op(a())` overloaded by its argument: none reads, a `T`
writes, a `T->T` updates. Inlined, so a read is one call. Checked with
Haxe 5.0.0-preview.1 on Eval: the three overloads resolve for any
concrete type, and a write of the wrong type is an error ("Could not
find a suitable overload"). A memo has the read only.

**A signal never holds a function.** With a function type for `T` the
write and the update are ambiguous (Haxe picks the first overload,
silently; with `Dynamic` it picks the update), so `signal` rejects a
`T` that is a function type at compile time, in both languages, and
the overload is always chosen from the static type, never by testing
the value at run time as Solid does. A callback, a component or a
render function is kept in a structure (`signal({view: Red})`) or,
better, named by an enum and chosen with `<Switch>`. What it buys:
Solid's shape with no separate `set` and `update`, and `signal(fn)`
free for writable derived values (2, Memos).

`.value` (read and write) and `.peek()` stay: `value` for code that
prefers it, `peek()` untracked.

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
node or a constant cell), not a function. A signal, a memo and a
getter are all readers already (each is read by calling it), so only
a constant is converted.

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

### 3.5 Components as plain functions, no `implements Markup`

```haxe
// app/Inventory.hx: module-level functions, no class
function Slot(item:Read<Item>) return <box padding={4}>{item().name}</box>;
function Inventory(items:Read<Array<Item>>) return <For each={items} render={i -> <Slot item={i}/>}/>;
```

The CLI adds the markup build macro to the project's own packages with
`Compiler.addGlobalMetadata(pack, "@:build(helder.view.MarkupMacro.build())")`
from its `--macro` (it passes one already). Checked with Haxe
5.0.0-preview.1: a global `@:build` reaches module-level functions as
well as classes, so a component is a plain function in a module.
`implements Markup` keeps working for code built without the CLI.

Limits and costs to measure:

- only the project's class paths, never the std or libraries;
- the macro returns at once for a class without markup literals (a
  scan of its expressions), so its cost is a walk of the project's code
  per build;
- whether a global `@:build` keeps the compile server's module cache
  reusing modules (the asset work found some `--macro` callbacks that
  broke it): a warm build of examples/showroom must stay at its
  current time.

## 4. What changes for existing code

- `Reactive.signal(v).value` keeps working; `get()` becomes a call,
  `set(v)` `count(v)`, `update(f)` `count(f)`.
- A `Signal` of a function type is an error (3.1): such code keeps the
  function in a structure.
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
3. Syntax 3.1 and 3.2. Then the markup macro split (7.2): its
   decisions into helder.markup, the Haxe output unchanged (the view
   tests pin it), so that the markup rule 3.3 and plain-function
   components (3.5) are written once, in the planner, for both
   languages.
4. Move helder.view's renderers (DOM, ui, native), helder.asset and
   scene onto it; remove the old core.
5. Coroutine components (3.4).
6. Later: actions, optimistic values, stores.

TypeScript (7) after step 3: the TSX front end and IR emitter, the
manifest and the generated declarations, the glue removed; its async
onto coroutines beside step 5.

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
6. **Props: an object or arguments.** TSX passes one props object,
   so a component shared with TypeScript is `Counter(props:{step:Read<Int>})`.
   3.5's `Counter(step:Read<Int>)` reads better in Haxe. Proposed: the
   object form everywhere (it is also what an IDE completes), the
   argument form accepted by the macro for Haxe-only code, or not at all.
7. **`For`'s row.** helder's `render={i -> ...}` prop or Solid's child
   function `<For each={items}>{i -> ...}</For>`, and Solid 2's keying
   modes (`<For>` keyed by identity or by index, `<Repeat>` by count)
   replacing `Index`. Proposed: Solid's, so that ports read the same.
8. **Handlers' arity.** A Haxe handler takes the event (`_ -> ...`), a
   TypeScript one may omit it. Proposed: listener props accept
   `Void->Void` too (`@:from`), so `onPress={() -> ...}` in both.
9. **`.value`.** Kept (3.1) for existing code; with the call form it is
   a second way to say the same. Proposed: keep it, deprecated in the
   docs, removed once the examples and helder's own code are ported.

## 7. TypeScript

helder.typescript (src/helder/typescript) compiles TypeScript straight
to hxmc IR. TypeScript programs use this core and this markup, not a
copy: one graph, one commit queue, one planner.

### 7.1 The same code

```tsx
export function Counter(props: { step: Read<number>; label?: string }) {
	const count = signal(0);
	const double = memo(() => count() * 2);
	effect(() => count(), v => console.log(v));
	return <view direction="row" column-gap={8}>
		<text>{props.label ?? "Count"}: {count()} (doubled: {double()})</text>
		<view:button onPress={() => count(c => c + props.step())}>+</view:button>
	</view>;
}
```

The declarations helder ships (generated, 7.3) type it:

- `Signal<T>` is a callable interface, `(): T`, `(value: T): void`,
  `(update: (prev: T) => T): void`; `signal<T>(v: T extends Function ?
  never : T)` rejects a function, as Haxe does. With `any` or
  `unknown` the frontend picks the overload by the argument's checked
  type; in strict mode a function written into one at run time is a
  TSHX100 divergence, never an update.
- `Read<T>` is `() => T` inside a component. At a JSX site,
  `JSX.LibraryManagedAttributes` widens a `Read<T>` prop to `T |
  (() => T)`, so `step={1}` checks; the frontend makes the constant a
  cell, as Haxe's `@:from` does. Calls of a signal compile to the
  node's functions directly, as any call does: no rewriting.

### 7.2 One markup compiler

MarkupMacro's decisions move into a library of plain Haxe (no macro
API), helder.markup, used by the Haxe macro on Eval and compiled into
helder-ts:

```
Haxe <markup/> ─parse─┐                       ┌─ Haxe Expr  (MarkupMacro)
                      ├─ Markup IR ─ planner ─┤
TSX (tsgo's AST) ─────┘                       └─ hxmc IR    (helder.typescript)
```

The IR is elements, attributes (static, holes, spreads, listeners),
text, holes and components; each front end marks a hole as constant or
may-read by 3.3's rule, the planner does the rest (whitespace and
static text, static or bound attributes, neutral elements, the
renderer), its output a short list of mount steps (create, set, bind,
listen, append, insert, mount a component) that each emitter turns
into its code. Both languages compile markup the same way by
construction; a third emitter could run the steps directly (dev
reloads without a build).

### 7.3 The manifest and the declarations

Built with helder: each renderer's contract (the IR names of its
functions, its elements, its setters and their types) and the public
API's signatures. helder-ts reads it instead of typing helder in Haxe
per program, and the `.d.ts` files (with typed `JSX.IntrinsicElements`
per renderer) are generated from it: nothing written by hand to drift.
helder itself no longer depends on the program, so its typed and
lowered code can be cached per version: a TypeScript build is tsgo,
the lowering and the code generation.

### 7.4 Async

A TypeScript `async` function given to `memo` must be a coroutine of
helder.async's for cancellation and the commit's timing to hold. To
check first: helder-ts's state machines implementing `haxe.coro`'s
continuation interface, a Promise being how JavaScript sees a Task.
Else a Promise is a pending node at the boundary: no cancellation,
only the superseded result dropped (Solid's behaviour). Either way
`Seed`'s jobs run on helder's loop, so writes after an await commit at
the end of the loop turn (6, question 1) in both languages.
