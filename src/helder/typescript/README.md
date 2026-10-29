# helder.typescript

TypeScript for helder apps: the program is checked by TypeScript 7.1's
compiler (tsgo, the native one, from the app's own `typescript` package: a
peer dependency, 7.1 or later) and lowered straight to hxmc's IR, then
compiled by hxmc as any helder program, native or wasm, with no JavaScript
in the output and no Haxe source in between.

```
.ts ──► tsgo ──binary AST──► helder.typescript.lower ──► hxmc IR ──► native / wasm
```

## In helder's compiler

This frontend is a plugin of helder's compiler (helder.compiler,
src/helder/compiler: hxmc's compiler with helder's hooks, markup's among
them; see its README). The plugin is `Frontend.hx` here (the compiler's
`Plugin`: the short form, the start of a build, its generation); the
lowering it runs is `lower/Frontend.hx`. A build given
`-D helder.typescript=<entry.ts>` also checks that program (before Haxe
types the build, which types the declaration classes of the modules it
imports with it: their manifest, below) and lowers it into the program's
IR after the Haxe side (`helder.typescript.js`, the JavaScript runtime,
helder's API and whatever they use) is lowered and before code generation
(hxmc's seam for frontends: `hxmc.Main.generate`'s beforeCodegen). So it runs where hxmc's
compiler runs: one-shot builds, and a compilation server, where its tsgo
stays up between builds. `<compiler> <entry.ts> [-o out] [--target t]` is
the short form.

```sh
node src/helder/compiler/build.mjs          # builds helder's compiler, prints its path
$(node src/helder/compiler/build.mjs --quiet) app.ts -o bin/app && bin/app
```

`HELDER_TS_TIMES=1` prints a build's phases, `HELDER_TS_DEBUG=1` the stack of
a compiler error.

## In the CLI

`helder build`, `run` and `dev` take a TypeScript entry (src/helder/cli:
a `.ts`/`.tsx` file, a project's `src/main.ts(x)`, a directory's
`main.ts(x)`) and build it with helder's compiler, built first if needed:

```sh
bun run helder run examples/ts-hello
bun run helder dev examples/ts-ticker   # edit label.ts: rebuilt, swapped in
bun run helder run examples/ts-todo     # helder.ui in TSX: a todo list
```

Under `helder dev` the build lists the program's files for the watcher
(`-D helder.typescript.deps`, also when the check failed), tsgo's errors
come back as the compiler's, at their file, line and columns, and the
JavaScript event loop answers the dev server between its timers
(`helder.dev.Hot.poll`, as helder.os.App's loop does), so a reload swaps the
new build in. A reload starts the program over: its state is not kept yet.

## Checking (`check/`)

`Config.hx`: the project's `tsconfig.json` (the nearest from the entry up to
its package.json's directory, parsed by tsgo, `extends` too), else helder's
defaults. Options that only add checks or name emit settings pass through;
those that change what the program means or what it can use must be
helder's or absent, else the build stops at their line: strict, ES modules
(esnext, es2022, preserve) resolved as a bundler does, a target of ES2022 or
later, defined class fields, no DOM library, no ambient `types`, `jsx`
preserve, no legacy decorators.

`Tsgo.hx` starts the `typescript` package's tsgo (`tsc --api`, found from the
entry's directory up) and speaks its protocol over the pipes: msgpack
`[type, method, payload]` tuples, JSON requests. `Project.hx` creates a
snapshot of the entry, with `globals.d.ts` (what the runtime provides beyond
ECMAScript: console, timers), reports tsgo's diagnostics, then fetches each
source file in tsgo's binary AST encoding, the symbols of its identifiers (one
request a file), the types of its expressions and declared names (one request
a file, then the members of the unions and the elements of the arrays among
them, and its functions' results: `Types.hx`) and the files its module
specifiers resolve to. `Ast.hx`
reads that encoding in place: a pre-order table of fixed-size node records
(kind, pos, end, next sibling, parent, data, flags), node objects made on
first use and unique per index. Positions are UTF-16 offsets; the text is
UTF-8, mapped when it is not ASCII.

`Kind.hx` and `Syntax.hx` are generated (`generate.mjs`) from the
`typescript` this was written against: the SyntaxKind names the frontend
uses, the binary layout's constants, an accessor per child property name.
What a version numbers differently (its SyntaxKind values, each kind's child
properties) `Tables.hx` reads from the installed package by name, so a newer
TypeScript works unchanged; a different binary layout is refused with its
version. Regenerating is only needed to use new syntax.

## Lowering (`lower/`, `ir/`)

`lower/Frontend.hx` lowers the checked AST to hxmc IR in evaluation order. Values
are JavaScript values (`js/`): objects with prototypes, sparse arrays,
closures, classes, iterators, generators, promises with an event loop,
RegExp, Date, Map/Set, iterator helpers, ArrayBuffer/DataView, JSON and
node's `console.log` formatting. `ir/` has the IR builder, a verifier for the frontend's
functions and a text form (`--dump-ir`, the tests' round trip).

### Strict: types are what values look like

The checker's types decide how values are represented (`Reps.hx`): a
`number` is an F64, a `boolean` a Bool, a `string` a String; an instance of a class with a layout (`Classes.hx`: a
top-level class whose fields have plain names, extending nothing or another
such class) is an object of its own hxmc class under the runtime's
JsObject, its fields in typed slots; an array is the runtime's JsArray,
its length and dense elements read in place. Everything else is a dynamic
JavaScript value. Bindings, parameters, direct functions' results and
fields of those types are typed slots, and code on them is plain native
code: arithmetic on F64s, fields at fixed offsets, for-of over an array by
index, `Math`'s functions called directly (Math is frozen). Such a class's
constructor and methods are direct functions on a typed `this`: `new C(...)`
makes and initializes the instance in place, and `o.m(...)` calls the
method o's class runs (found by o's prototype among C and its subclasses
with layouts), the prototype keeping thin wrappers for dynamic calls. Its
prototype is locked: replacing a method, or hiding one with an instance's
own property, diverges (TSHX100). A binding no
closure captures is a plain local (`Captures.hx`); a captured one is a
shared box. A string local a loop only appends to (`s += x`, no other use
of it in the loop) is built in a buffer while the loop runs, so the loop is
linear; `s.charCodeAt(i)` on a string is String.prototype's own (made
read-only, as Math is frozen).

TypeScript's types can be wrong about values (`any`, `as`, a missing
argument, `JSON.parse`). A value enters a typed slot only through a check:
where it is not what the type says, the program stops with a TypeError
(TSHX100) at the line where it entered, rather than computing something
JavaScript would not. A typed class's field cannot be deleted, made
read-only or turned into an accessor (TSHX100 as well).

### helder's API and TSX (`api/`, `lower/Api.hx`, `lower/Haxe.hx`, `lower/Tsx.hx`)

A program calls helder's Haxe API through declarations: `helder/view`,
`helder/ui` and `helder/web` (`index.d.ts` beside the packages, exported
by package.json), generated from the Haxe types (below). Each declares its
classes, each the Haxe class `__haxe` names, its functions and components
as `const f: typeof Class.f`, that class's static, and names the module's
declaration class (`__module`). TSX is helder.view's markup.

```tsx
import { signal } from "helder/view";
import { UiWindow, Surface } from "helder/ui";

const count = signal(0);
UiWindow.run(<Surface title="Counter">
	<view:button onPress={() => count(c => c + 1)}>{count() * 2}</view:button>
</Surface>);
```

**Modules.** A TypeScript module is a Haxe class, its package's
`TypeScript` (src/helder/view/TypeScript.hx...), whose metadata names what
it exports (`api/Modules.hx`): `@:typescript("helder/view")`, its classes
(`@:typescript.classes`: their public members, or those marked
`@:typescript`), its functions (`@:typescript.functions(signal =
helder.view.graph.Graph.signalValue, ...)`), its types
(`@:typescript.types`: Signal, Memo and Read, View, an enum abstract's
values), the renderers its markup reaches that its types do not name
(`@:typescript.renderers`), its part of JSX (`@:typescript.jsx`). A
program's own Haxe classes are declared the same way (tests/view's
TestTypeScript).

**The manifest** (`api/Manifest.hx`, the format there; DESIGN.md 7.3): the
declaration class's build macro writes its module's manifest, from the
Haxe types, as the class's metadata (`@:helder.manifest`, JSON): each
class's members (methods, fields, properties' accessors, inline constants'
values) and their Haxe types, and each renderer the module reaches (its
`@:rendered` nodes, ViewOf<R> in its types, those it names): its id, node
class, runtime (`ViewRuntime_<name>`, made by HostMacro) and that
runtime's functions, its elements (`@:elements`), its events (`@:events`:
each attribute's event type), whether it realises the neutral elements,
its functions and, where its setter is a macro (ui's), the function for
each attribute name (Renders' `setterTable`). Keeps name every function
the manifest lists, each a class's `__init__` under a condition never true
(`Interop.keeping()`): the module's own (its renderers' contracts and
runtimes, what the lowering itself calls) and one per class of the module
(`<declaration class>_<its type path>`). hxmc lowers what code names, so
each is in the program's IR; the frontend leaves the keeps of the classes
the program does not name out of what hxmc lowers (`@:helder.keep`: a
program of helder/ui's `Key` alone lowers no window), drops the others'
`__init__`s after the lowering, and hxmc's reach leaves out what the
program does not call. Nothing in it depends on the program: a build adds
the declaration classes the program's declaration files name (`__module`)
to what it types, as any class of helder's (no macro on the command line:
one would defeat hxmc's module cache for the whole build). Its macro runs
in each build (helder/ui's 0.15 s warm: it names the renderers' runtimes,
which HostMacro makes in each).

**Calls** (`lower/Haxe.hx`): a call of helder's (a static, `new`, an
instance's method), a member read or written, compile to the function
Haxe's typing lowered (its IR name, the class's ident and the field's), the
program's values converted by the manifest's types: a number into an Int
or a Float, a string, a Bool, a Read (`Interop.reader`), an instance
checked (TSHX100 where it is not one), an array's elements, a function as
a closure of the parameter's signature (its arguments made the program's,
its result Haxe's), a structure field by field, the rest untyped
(`Interop.toHaxe`); the result back (`Interop.toJs`, numbers as they are).
helder's objects pass as they are, opaque to the program. A signal's call
is chosen by its static type: `count()` its node read, `count(v)` written,
`count(c => c + 1)` (an argument of a function type) updated;
`Render.render(content, parent)` mounts with the runtime of the renderer
whose node parent is (its class's `@:rendered`). The `Interop` functions are
where values cross.

**TSX** (`lower/Tsx.hx`) goes through helder.markup's planner
(`helder.markup.Plan`, DESIGN.md 7.2), its TypeScript target, so a literal
means what the same Haxe markup means: renderer boundaries, components,
neutral elements, keys, refs and handlers, and holes that read bound
(3.3): a hole or an attribute whose expression may read, a call or a read
through a get accessor (the program's or a Haxe property's), is given as a
function of it, which the runtime binds, so `{count() * 2}` follows count
with no `() =>`; a literal, a name or an expression of them is set once,
and one of a type never reactive (a string, a number, a boolean) straight
to the renderer. A component's prop of a type that reads (`Read<T>`,
helder's components' and the program's) whose value may read is given as
a function of it too. The planner's facts come from the manifest (a
renderer's elements, a component's props that read, whether its children
are a function, the renderer they are for, the renderer it is pinned to)
and from TypeScript's types. A literal's holes are evaluated where it is
(the program's values made Haxe's; a component's factory and a bound hole
the program's functions, its bindings captured as an arrow's); its mount
is IR on Haxe values, calling its renderer and its runtime directly
(createElement, put, prop, the setter for a literal attribute name...), as
the markup macro's code does. A literal's renderer is the one where it is:
a call's parameter of type `ViewOf<R>` (`UiWindow.run`'s, a root's),
`Render.render`'s parent, the literal around it (its holes), a component's
children's; else it is agnostic and its mount is made for each renderer
the manifest has, installed at the start (ViewRuntime's late, as HostMacro's
late code is). Handlers are checked by tsgo against the declarations' JSX
types (an event attribute of a neutral element typed by ui's events: its
untyped parameter is an `Event`).

**The declarations** (`api/Declarations.hx`, `api/dts/`): written from the
Haxe types by `node src/helder/typescript/api/declarations.mjs` (`--check`
fails when one differs: the tests run it), with the `//` comment above
each declaration in its Haxe source. The printer and the type mapping are
benmerckx/genes' declaration typing (its TypeEmitter and
DefinitionEmitter, MIT: `api/dts/LICENSE.genes`), reworked: Haxe's typed
classes from the module, a type named only where a module declares it (an
import of another module's), else written out (a typedef's structure, an
abstract's @:from types or the type under it, an enum abstract's values, a
class no module declares `unknown`), `@:typescript.type("...")` on a type,
a field or an argument its text (genes' `@:genes.type`), the type's
parameters substituted (`@:typescript.input`/`output` for one side: a
`ViewOf<R>` taken is `unknown`, any content), an abstract called as a
function (`@:op(a())`) an interface of its call signatures (Signal, Memo),
one made from other values (Read) branded, its `ReadFrom<T>` what TSX's
component props take (`JSX.LibraryManagedAttributes`), and helder/view's
and helder/ui's part of JSX (the neutral elements' attributes, their
handlers typed by ui's events).

### Built-ins

The runtime's optional built-ins (RegExp, normalize's Unicode tables,
Date, ArrayBuffer/DataView, JSON, iterator helpers, Promise and the timers
with the event loop, `Array.fromAsync`, Set's algebra, the URI functions,
`structuredClone`) are installed by a program that uses them (`Features.hx`:
the globals it names, the method names it calls, its syntax); hxmc leaves
the rest out. A hello world is 538 KB instead of 904 KB. A program that
names `globalThis` or calls a method by a computed name installs them all.

A `.json` file the program imports (`import data from "./data.json"`,
resolveJsonModule's) is a module whose default export is its value.

Excluded, with a diagnostic: `eval`, `Function`, `Proxy`, `with`,
`__proto__`/`setPrototypeOf`, dynamic `import()`. Not yet: BigInt, typed
arrays, `process` and node's other globals.

## What is built

helder.view's DESIGN.md §7, as built:

- **TSX through the shared markup planner**: helder.markup's `Plan<E>`
  compiles Haxe's markup (`MarkupMacro.HaxeTarget`) and TSX (`lower/Tsx.hx`'s
  `TsTarget`) with the same decisions, so the two read the same, the
  lambdas aside. A hole that reads is bound (`{count() * 2}`), a
  component's Read prop is given as a function of its value, a renderer's
  boundary, a neutral element and a handler mean what they mean in Haxe.
- **The manifest** of the API, made from the Haxe types while the build is
  typed (each module's declaration class's), read by the lowering instead
  of generated call sites: no glue module, no Haxe written per program.
- **Generated declarations**: the `.d.ts` files come from the same Haxe
  types, with benmerckx/genes' declaration typing as the base.
- **Signals by static type**: a call of a value of type `Signal` reads,
  writes or updates by its argument's type; the function a signal comes to
  the program as, called dynamically, reads or writes (a function written
  into it a TSHX100 divergence, never an update).

```tsx
function Checkbox(props: {checked: Signal<boolean>, label: string}) {
	return <view:button role="checkbox" checked={props.checked} onPress={() => props.checked(c => !c)}>
		<Show when={props.checked()}><icon name="check"/></Show>
	</view:button>;
}
```

Not yet: the async of 7.4 (a TypeScript `async` function given to `memo`
is not a coroutine of helder.async's), the helder.dev reload keeping a
program's state, a module's typedefs named in the declarations (written
out), ui's `env()` values in a literal attribute (SafeArea: set as a
string).

## Tests

`bun run test typescript` (tests/typescript): the IR checks, then every
program of `cases/` and `modules/` compiled by tsc and run on node (24), and
by helder's compiler natively and as wasm32-wasi, the outputs compared; `standards/`
check themselves where node still differs from the specification;
`reject/` must fail with a diagnostic at the line it names; `diverge/` must
compile and stop with TSHX100 at the line it names. The declaration
files must be as the Haxe types make them (`declarations.mjs --check`,
helder's and tests/view's TestTypeScript's `helder/test-renderer.d.ts`).
`helder/` programs call helder's API and render TSX headless (tests/view's
TestRenderer), their output checked against `<name>.out`: `view.tsx`
(signals, a component, control flow, events), `holes.tsx` (holes and
attributes that read bound, a Read prop, a getter), `static.tsx` (helder.web's
static renderer, an island).

The lane needs node 24 or later.

`node tests/typescript/bench.mjs [names]` times the programs of `bench/`
compiled by helder's compiler against node (median of 5 runs each).
