# helder.view: the reactive core, redesigned

Status: steps 1 to 4 of the plan (5) built: the graph (helder.view.graph),
the markup planner, and helder's renderers, helder.asset, helder.scene
and every program on them, the old core removed. Section 5 says what
step 4 decided where this text did not.

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

### Holds: Solid 2's fundamentals, helder's mechanism

The rules are Solid 2's async fundamentals (its
`packages/signals/docs/RULES-FUNDAMENTALS.md`, F-1 to F-12), which
its maintainer keeps as the immutable base: the screen is whole (F-1);
a change that needs async to be shown is held, the screen keeping what
it showed (F-2); only render effects are readers, and one holds only
while it is the display (F-3); an armed `<Loading>` (one that has not
shown content, or re-armed by `on`) catches what is pending under it
(F-4), a disarmed one forwards (F-5); `latest` and `isPending` read
ahead of a hold and never hold it (F-6), nothing else reveals ahead
(F-7); `isPending` is about a new question, a first load is loading,
not pending (F-9); a write is visible at its flush, to every channel
(F-10); an error sends a boundary to its fallback, pending is not an
error (F-12). F-11 (optimistic values) comes with actions, later.

The mechanism is helder's: a flush is a **transaction** over the
nodes its writes reach. Each node keeps its committed value (the
screen's, and what untracked reads see) and, while a transaction holds
it, a staged one beside it; computations run for a transaction read
its staged values. A render effect whose compute reads a value not
ready, with no armed boundary above it, parks the transaction: its
stagings stay staged, no apply runs. A computation that reads a node
another parked transaction holds joins it (the two land as one, F-2);
transactions that touch disjoint nodes stay independent. When the
async a transaction waits on answers (a value or an error), its
readers run again in its world, and once nothing it renders waits it
commits: every staging becomes the committed value and the applies run
in one frame (render effects first). An async computation returns an
`Awaitable<T>` (helder.async's tasks, helder.asset's loads,
TypeScript's promises): its reads are tracked until it returns, its
answer lands into the transaction that asked, a superseded one is
cancelled and its answer dropped.

`Awaitable<T>` is the core's whole contract with async work (an answer
later, a cancel), so the core needs no loop and runs wherever
helder.view does. Each language writes it its own way:

```haxe
interface Awaitable<T> {
	function onAnswer(value:T->Void, error:Dynamic->Void):Void; // once
	function cancel():Void; // superseded, or its owner disposed
}

var icon = memo(() -> Asset.image('icons/${name()}.png')); // an Awaitable
var user = memo(task(() -> {
	var u = api.fetchUser(id()); // read before the first suspension: tracked
	Async.delay(0.2);            // after one: not tracked (as Solid)
	u;
}));
```

```ts
const user = memo(async () => (await fetch(`/users/${id()}`)).json());
```

A coroutine is the Haxe form, through `task(coroutine)` (a function
taking the `Coroutine<Void->T>`, so that its lambda is typed as one: an
`@:from` on `Compute` types it without that expected type, as
helder.test's `async` notes), which the graph starts as a helder.async task **now**, inside the
computation (not at the loop's next turn, as `Async.launch` does), so
its reads up to the first suspension are tracked; its completion
answers the memo, and `cancel` cancels the task and the tasks under it
(checked on hxmc: the body runs to its first suspension inside the
call, a cancelled task never resumes). So a superseded run stops its
work, not only its result (Solid drops the result). A TypeScript
Promise is an Awaitable made by the frontend's own async functions.

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

As built (step 4, Handlers): `signal(fnValue)` is the derived form, so
`var s:Signal<Int->Int> = signal(f)` is a type error; but Haxe has no
negative constraint, so without a macro `Signal<F>` itself cannot be
refused, and `signal(() -> f)` (a derived signal whose value is a
function) types as one. The rest is at run time, never a dispatch: the
derived signal of a function throws when it is made (as `signal(v)` of a
function value does), and a write whose argument is a function at run
time (a `Dynamic`, which the static type sends to the write) throws
(`Node.set`) instead of storing it. A Haxe signal is then never seen
holding one, and no `Dynamic` decides between a write and an update.

`.peek()` stays, an untracked read. `.value` goes (6, 9): one way to
read and write.

### 3.2 `Read<T>` for props

```haxe
function Counter(props:{step:Read<Int>}) ...

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

Done in the planner (Target.mayRead, thunk): for Haxe a call, or a
field or index read through a function (typed where the literal is: a
property's getter, an abstract's), not inside a function or a literal
of its own; a component's props stay as they are until props are an
object (step 4). A bound region that is its parent's last child needs
no marker (the runtime draws it at the end), as in Solid, unless its
renderer marks every region (`markEnds`: helder.web's DOM and static
renderers, whose hydration reads the markers).

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
function Slot(props:{item:Read<Item>}) return <box padding={4}>{props.item().name}</box>;
function Inventory(props:{items:Read<Array<Item>>}) return <For each={props.items}>{i -> <Slot item={i}/>}</For>;
```

Done, with no change to hxmc: helder's compiler (hxmc's, with helder's
frontends linked: one binary, 7) wraps hxmc's parse
(`TypeloadParse.parseHook`, helder.compiler.MarkupHook). Haxe parses
`<view/>` as `@:markup "<...>"`, which hxmc's typer refuses ("Markup
literals must be processed by a macro"); each file parsed has its
literals wrapped as `implements Markup` wraps them,
`helder.view.View.literal(@:markup "<...>")`, natively, on the parsed
file, so only the literals reach the macro (MarkupMacro.literal, the
planner, 7.2), as they did. The CLI builds every program with helder's
compiler (hxmc's as a fallback, with a warning, when it cannot build
it); plain `haxe` still needs `implements Markup`, and type-checking in
an editor goes through helder's compiler (its `--wait` and
`--server-connect`; a compilation server's own parse is wrapped again
before each build). Measured: examples/todo warm 0.90 s with hxmc's
compiler, 0.96 s with helder's, the same executable; every test program
and example natively byte for byte the same. hxmc's PR #123 (a typer
hook) is on hold for a `markup($e)` call resolved through imports
(Juraj's proposal); if it lands, the parse hook goes and the literal's
entry stays.

Measured and rejected: the markup build macro added to the project's
packages from the CLI's `--macro` (`Compiler.addGlobalMetadata`). It
works (checked: module-level functions too) but no warm build reuses
the module cache any more: examples/todo 0.85 s to 3.5 s,
examples/showroom 0.46 s to 1.7 s. `implements Markup` (the build
macro on that class only) stays for builds by plain `haxe`.

## 4. What changes for existing code

- `.value` and `get()` become a call, `count()`; `.value = v` and
  `set(v)` `count(v)`; `update(f)` `count(f)`.
- A `Signal` of a function type is an error (3.1): such code keeps the
  function in a structure.
- `Reactive.batch` is removed (`flush(fn)` where code needed it).
- `Reactive.effect(fn)` becomes `effect(compute, apply)`; a
  one-argument form stays for renderers' internal use only.
- `onMount` becomes `onSettled`.
- `ErrorBoundary` becomes `Errored`.
- `Pending` and `Loadable` leave the public API; `Asset` becomes a node.
- Props are one object (6, 6); `For` takes its row as a child
  function, `Index` becomes `For`'s keying by index (6, 7).
- `Flow`'s props become typed (`when:Read<Bool>`, `each:Read<Array<T>>`)
  instead of `Dynamic`.
- Dev reload's state keys (`Refresh`) attach to nodes as today.

## 5. Plan

1. Port Solid 2's reactive tests (signals, memos, effects, ownership,
   async, transitions, Loading, Errored) to helder.test: the ones that
   state behaviour (its createSignal, createMemo, createEffect,
   createRoot, context, boundaries and async-semantics specs), not those
   that pin its scheduler's internals (lanes, verdicts, attribution).
2. The new core beside the old one (`helder.view.graph`), passing them,
   with the allocation test.
3. Syntax 3.1 and 3.2. Then the markup macro split (7.2): its
   decisions into helder.markup, the Haxe output unchanged (the view
   tests pin it), so that the markup rule 3.3 and plain-function
   components (3.5) are written once, in the planner, for both
   languages.
4. Move helder.view's renderers (DOM, ui, native), helder.asset and
   scene onto it; remove the old core. Done; what it decided:
   - **Props bound as Solid binds them**: the planner gives a prop whose
     type is `Read<T>` (Component.reads, typed where the literal is) the
     function of its value when that value may read (3.3); a prop of
     another type is evaluated once. `Read<T>` is an abstract over a
     `Reader<T>` (a node, a `Const`, a `Thunk`): a constant is a cell, a
     signal or a memo its node.
   - **For's row** is its child function, given the item as a `Read`
     (Solid 2's accessor): keyed by the item, its Read a constant;
     `keyed={false}` (Index's successor), a signal of what is at its
     index. Haxe has no optional arity, so the row takes the item only
     (no index accessor); `Repeat` makes rows by count. A child that is
     a function alone is the children prop itself only for a component
     whose `children` is a function (Component.childFunction); T is not
     always inferred from `each` before the row's lambda is typed: a row
     that reads the item's fields names its type, `(t:Read<Todo>) -> ...`.
   - **The runtime**: a binding is a render effect whose compute reads
     and whose apply touches the node; a region's content is mounted in
     its apply, in an owner of its own under the region's (so an armed
     boundary above still catches what waits in it). `<Loading>` and
     `<Errored>` make their children in the boundary's compute
     (Graph.loadingBoundary, errorBoundary: what reads a pending value
     inside is caught there); the nodes those children put in the parent
     are kept by a capture, taken out while the fallback shows and put
     back after, and a node put into a hidden capture is only recorded.
     A component is untracked: one whose body reads a value not ready is
     made later, by a region that waits on that node (the boundary above
     shows its fallback meanwhile), not made twice as before.
   - **Flushes**: helder's loop flushes at the end of each event and
     frame: `Ui`'s pointer, key, text and access entry points, `Ui.update`,
     `Clock.tick`, `App.run`'s callbacks, a page's listeners (DomRenderer,
     helder.web's neutral elements), a native control's callbacks,
     NativeHost.step; helder.async's loop at the end of its turn (one
     dispatch object, queued once). `Render.render`, `Render.open` and
     `DomRenderer.hydrate` at the top flush before returning (what they
     scheduled, `onSettled`'s, has run), as onMount ran at the end of the
     insertion.
   - **Handlers**: one that takes no event is given one it ignores
     (Target.handler: typed where the literal is). A `Signal`'s update
     overload is declared before its write: an argument of no static type
     (Dynamic) is then a write, a function literal an update (3.1 said
     Dynamic picks the update); a Dynamic that is a function at run time
     is an error, not written (3.1, as built).
   - **Typed handlers**: each renderer declares its events, `@:events(T)` on
     its class (the contract's metadata, beside `@:elements`), T a
     structure of each event attribute's event type: ui's
     `helder.ui.view.NodeEvents` (`onPress` an `Event`, `onTap` a `Tap`,
     `onPan` a `Pan`, `onPinch` and `onScale` a `Scale`), which are the
     neutral elements' in every renderer; `helder.web.DomEvents` (lib.dom's
     types, `on` typing `on:name`; Dynamic outside JavaScript, where the
     static renderer drops them); `helder.scene.view.SceneEvents` (a
     `SceneEvent`). helder.ui.native's controls are components, their
     handlers props (`onClick:Void->Void`, `onSubmit:String->Void`), which
     Haxe checks as any prop. The planner hands each listener to the
     target with its name and renderer (Target.handler); the macro checks
     it: an untyped parameter typed as the event (`e -> name(e.text)` a
     String written), a function of the event (or of a supertype: `(g:Gesture) -> ...`)
     or of none taken, `null` too; a name not declared, a value of no static
     type, a function of another type or of two arguments an error from the
     attribute's name to its value's end: `markup: onKeyDown's handler
     takes a js.html.MouseEvent, but helder.web.DomRenderer gives onKeyDown
     a js.html.KeyboardEvent: a function of a js.html.KeyboardEvent or of
     none (js.html.KeyboardEvent -> Void, or Void -> Void)`. A renderer
     declaring none (a test's) takes any function of one argument or none;
     so does an agnostic literal's own element (`<div>` in a plain View: no
     renderer to check against until it is made for each, after typing,
     where its holes are values of no type). The structures are data the
     manifest (7.3) reads: the `.d.ts`'s `JSX.IntrinsicElements` per
     renderer, `onKeyDown?: (e: KeyboardEvent) => void`, without a list
     written twice. tests/view/reject's Handler*.hx pin the errors.
   - **3.3's rule**: `new X(...)` reads what its arguments read, not more
     (a struct made once: hxmc passes no function returning a struct as
     one of another type). TSX's (7.2): a call, a read through a get
     accessor (the program's, a Haxe property's), not inside a function or
     a literal of its own.
   - **Asset** is a class implementing `Reader<T>` over an async memo
     (an answer per run, a reload a new question): `read()` reads it, the
     handle is bound as a hole, an attribute or a Read prop; a class is not
     callable, so `asset()` is not its form. `AssetPending`, `Pending`,
     `Loadable` and `refreshing` are gone (`isPending`).
   - **Dev reload's keys** (Refresh): `Graph.signal` is a macro under
     `-D hxmc.dev` only, keying the signal where it is made as before; a
     computation's compute and apply run in its own Hot scope.
   - **TypeScript**: a node, a Read and an asset come to the program as a
     JavaScript function (Interop: called to read, with a value to write;
     cached per node; the same value back), a JavaScript function given for
     a `Read` prop a Thunk. A call of a value whose static type is `Signal`
     reads, writes or updates by its argument's type (7.1); TSX's holes that
     read are bound, as Haxe's (7.2).
   - **Allocation**: a steady write, flush and render effect allocate
     nothing for object values (tests/view/graph/Alloc.test.hx); hxmc boxes
     an Int or a Float stored in a type parameter, 16 bytes a value.
   - `use` outside an owner is an error (Solid 2's); a test reads a
     context in a `root`.
5. Coroutine components (3.4).
6. Later: actions, optimistic values, stores.

TypeScript (7) after step 3: the TSX front end and IR emitter, the
manifest and the generated declarations, the glue removed (done: 7.2,
7.3); its async onto coroutines beside step 5. TypeScript is part of helder, not a tool
beside it: the compiler helder ships includes the frontend, one package
and one binary.

Each step keeps every lane green and measures compile time (the markup
rule is the only macro change) and the frame loop's allocations.

## 6. Decisions

Where Solid 2 has an answer, helder takes its decision rather than
inventing one: its semantics, not its implementation. helder's target
is native nodes, not the DOM, and a compiler that knows the types, so
the runtime underneath is its own (2, Allocation).

1. **A commit without an event** (a write from a coroutine after an
   await, a timer): Solid 2's microtask, which is helder's loop's: the
   writes of one task of the loop are committed when it yields back to
   the loop, before the next task runs. No frame loop needed.
2. **Transitions** are Solid 2's: held per transition, each knowing the
   nodes it touches, independent transitions committing independently.
   No whole-commit hold as a first step.
3. **Writes inside computations** (a component body, an effect's
   compute, a memo) are an error in dev builds, as Solid 2's
   `REACTIVE_WRITE_IN_OWNED_SCOPE`, `untrack` not excepting them; a
   signal made with `ownedWrite` opts out.
4. **Markup's "may read" rule** is Solid's compiler's: a call or a
   field access is wrapped, a literal or a plain identifier is not.
5. **Stores** are Solid 2's model (a draft mutated by the setter,
   `createStore(fn)` derived, projections) when they come, typed by a
   build macro per class; not in the first version.
6. **Props are one object** in both languages, `Counter(props:{step:Read<Int>})`,
   as TSX passes them; 3.5's argument form is not taken.
7. **`For` is Solid 2's**: its row a child function,
   `<For each={items}>{i -> ...}</For>`, keyed by identity or by index
   (replacing `Index`), and `<Repeat>` by count.
8. **Handlers** may omit the event: listener props accept `Void->Void`
   too (`@:from`), so `onPress={() -> ...}` in both languages. An
   element's are typed by its renderer's events (`@:events`, step 4).
9. **`.value` goes**, now: the call form is the only one (3.1);
   helder's own code and the examples are ported with the core.

## 7. TypeScript

helder.typescript (src/helder/typescript) compiles TypeScript straight
to hxmc IR, a frontend of helder's compiler (helder.compiler). TypeScript programs use this core and this markup, not a
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

As built: `Signal<T>` and `Memo<T>` are interfaces of their abstracts'
`@:op(a())` functions (the update's overload before the write's), `Read<T>`
an interface of its call, branded (`readonly [readBrand]: T`: no other
function is one), and `ReadFrom<T>` its `@:from` types (`Read<T> |
Signal<T> | Memo<T> | (() => T) | T`), which `JSX.LibraryManagedAttributes`
gives each Read prop of a component, helder's or the program's (`<For
each={items}>` infers T from a signal, a function or an array). The
function a signal is to the program, called dynamically, reads or writes;
a function written is a TSHX100 divergence. A call the program writes of a
value whose static type is `Signal` compiles to its node's read, write or
update (`Interop.signalRead`, `signalWrite`, `signalUpdate`), the update
when the argument is a function (a function expression, or of a type with
call signatures, which tsgo answers while the program is checked); `T
extends Function ? never : T` on `signal`'s argument (Graph.signalValue's
`@:typescript.type`).

### 7.2 One markup compiler

MarkupMacro's decisions move into a library of plain Haxe (no macro
API), helder.markup, used by the Haxe macro on Eval and compiled into
helder's compiler for TypeScript:

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

Done for the macro: helder.markup.Syntax (the parser) and
helder.markup.Plan (the planner), a `Target<E>` writing its code;
MarkupMacro's HaxeTarget writes Haxe expressions, its output byte for
byte the macro's before the split (every test program and example,
natively and as JavaScript, the rejected programs' errors).

Done for TypeScript: helder.typescript.lower.Tsx's TsTarget. The TSX
tree is made Syntax's nodes (text by JSX's whitespace rule and entities,
as the parser does; a hole the TypeScript expression), and the planner
decides as it does for Haxe: the literal's renderer (a call's parameter of
type `ViewOf<R>`, `Render.render`'s parent, the literal around it, a
component's children's; else agnostic, made for each renderer the
manifest has, installed as ViewRuntime's late at the start), components
(Pick's choice for the renderer, the pin checks, their props that read
bound, a function alone their children when theirs are one), neutral
elements, keys, refs, holes that read bound (3.3: TsTarget.mayRead, a call
or a read through a get accessor; the type never reactive by TypeScript's
types). Its facts are the manifest's (7.3). Its code: the holes evaluated
where the literal is (the program's values made Haxe's; a bound hole and a
component's factory the program's functions, their bindings captured as
an arrow's, adapted to Haxe's signature), the mount IR on Haxe values
calling the renderer and its runtime directly (the setter of a literal
attribute name included, as the macro's forRenderer does). Handlers are
checked by tsgo against the declarations' JSX types. TSX and Haxe now read
the same, the lambdas aside: `{props.tags.map(t => <li>{t}</li>)}` is a
call, bound as Haxe's is, so a static page has a region's markers around
it (tests/typescript/helder/static.out).

### 7.3 The manifest and the declarations

Built with helder: each renderer's contract (the IR names of its
functions, its elements (`@:elements`), its events (`@:events`: a
structure of each event attribute's event type, step 4), its setters and
their types) and the public
API's signatures. The TypeScript frontend reads it instead of typing helder in Haxe
per program, and the `.d.ts` files (with typed `JSX.IntrinsicElements`
per renderer) are generated from it: nothing written by hand to drift.
helder itself no longer depends on the program, so its typed and
lowered code can be cached per version: a TypeScript build is tsgo,
the lowering and the code generation.

As built (helder.typescript.api): a TypeScript module is a Haxe class
declaring it, its package's `TypeScript` (`@:typescript("helder/view")`,
its classes, functions, types, renderers and part of JSX in metadata:
Modules). Its build macro (Manifest.build) makes its manifest while the
build is typed, from the Haxe types, as the class's metadata
(`@:helder.manifest`, JSON, version 1; the format is Manifest.hx's): its
classes (hxmc's ident, the Haxe type path, `@:rendered`, `@:renderer`'s
limits) with each public member's kind (method, var, a property's
accessors, an inline constant's value), its type in a small JSON language
(`"Int"`, `{fn: [...], ret}`, `{anon: [...]}`, `{class: path}`, `{read: T}`,
`{view: R}`, `{abstract: path, under, values}`, `{null: T}`...), and each
renderer it reaches (its `@:rendered` nodes and ViewOf<R> in its types,
those it names): its id, node class, `ViewRuntime_` class and functions,
`@:elements`, `@:events`' types, whether it realises the neutral elements,
its statics (function, macro or constant) and, for a setter that is a
macro, each attribute name's function (Renders' `setterTable`). Keeps
name every function listed, each an `__init__` under a condition never
true, so hxmc lowers them (its lowering is reached from code): the
module's own (its renderers' contracts and runtimes, what the lowering
itself calls) and one class per class of the module (`<declaration
class>_<its type path>`). The frontend leaves the keeps of the classes the
program does not name out of what hxmc lowers (a program of helder/ui's
`Key` alone lowers no window), drops the others' `__init__`s once the
program is lowered, and what the program does not call is not in the
executable. The frontend adds the declaration
classes the program's declaration files name (`__module`) to the build
and reads their metadata after typing (helder.typescript.lower.Api's
Manifest); the lowering calls the listed functions directly, converting
values by the types (lower.Haxe). Nothing depends on the program: no
Haxe module is written per program, and no macro is on the command line
(an init macro defeats hxmc's module cache for the whole build, 3.5:
measured, examples/ts-todo's warm build 1.1 s to 2.4 s). The declaration
classes' macro runs in each build (helder/ui's 0.15 s warm: they name the
renderers' runtimes, which HostMacro makes in each). Measured,
examples/ts-todo's warm `helder build`: 1.1 s with the glue, 0.9 s with
the manifest; its executable 2.41 MB and 2.44 MB (its agnostic literals'
code for each renderer the manifest has).

The declarations come from the same types (Declarations: `node
src/helder/typescript/api/declarations.mjs`, `--check` in the tests), the
printer and the type mapping benmerckx/genes' (api/dts, MIT), reworked:
the module's classes and their marked members, each with the `//` comment
above it in its Haxe source, a type named where a module declares it (an
import of another's), else written out, `@:typescript.type` (genes'
`@:genes.type`) on a type, a field or an argument; `JSX.IntrinsicElements`
any tag (helder/view's), the neutral elements' attributes with ui's events
(helder/ui's), so an untyped handler's parameter is an `Event`.

### 7.4 Async

Not built yet. A TypeScript `async` function given to `memo` must be a coroutine of
helder.async's for cancellation and the commit's timing to hold. To
check first: the TypeScript frontend's state machines implementing `haxe.coro`'s
continuation interface, a Promise being how JavaScript sees a Task.
Else a Promise is a pending node at the boundary: no cancellation,
only the superseded result dropped (Solid's behaviour). Either way
`Seed`'s jobs run on helder's loop, so writes after an await commit at
the end of the loop turn (6, question 1) in both languages.
