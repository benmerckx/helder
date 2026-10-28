# helder.typescript

TypeScript for helder apps: the program is checked by TypeScript 7.1's
compiler (tsgo, the native one, from the app's own `typescript` package: a
peer dependency, 7.1 or later) and lowered straight to hxmc's IR, then
compiled by hxmc as any helder program, native or wasm, with no JavaScript
in the output and no Haxe source in between.

```
.ts ──► tsgo ──binary AST──► helder.typescript.lower ──► hxmc IR ──► native / wasm
```

## The compiler

`helder-ts` is hxmc's compiler (@hxmc/cli's `haxe`, with the same command
line) with this frontend linked in (`Compiler.hx`): a build given
`-D helder.typescript=<entry.ts>` also checks that program and lowers it into
the program's IR after the Haxe side (`helder.typescript.js`, the JavaScript
runtime, and whatever it uses) is lowered and before code generation. So it
runs where hxmc's compiler runs: one-shot builds, and a compilation server,
where its tsgo stays up between builds. `helder-ts <entry.ts> [-o out]
[--target t]` is the short form.

```sh
node src/helder/typescript/build.mjs          # builds helder-ts, prints its path
$(node src/helder/typescript/build.mjs --quiet) app.ts -o bin/app && bin/app
```

`build.mjs` builds it once per hxmc version and per hash of these sources,
into the user's cache (`~/.cache/helder/typescript/`). It links hxmc's
compiler sources, which the npm packages do not ship yet: `HXMC_SRC` names a
checkout, else the commit the installed nightly's version names is fetched
with git (sparse: `haxe/src`, `hxmc/src`) into `~/.cache/helder/hxmc-src/`.
`HELDER_TS_TIMES=1` prints a build's phases, `HELDER_TS_DEBUG=1` the stack of
a compiler error.

## In the CLI

`helder build`, `run` and `dev` take a TypeScript entry (src/helder/cli:
a `.ts`/`.tsx` file, a project's `src/main.ts(x)`, a directory's
`main.ts(x)`) and build it with helder-ts, built first if needed:

```sh
bun run helder run examples/ts-hello
bun run helder dev examples/ts-ticker   # edit label.ts: rebuilt, swapped in
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
request a file) and the files its module specifiers resolve to. `Ast.hx`
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

`Frontend.hx` lowers the checked AST to hxmc IR in evaluation order. Values
are JavaScript values (`js/`): objects with prototypes, sparse arrays,
closures, classes, iterators, generators, promises with an event loop,
RegExp, Date, Map/Set, iterator helpers, ArrayBuffer/DataView, JSON and
node's `console.log` formatting. `NumberProof.hx` proves which bindings and
function results always hold numbers; those are F64 and compile to plain
arithmetic. `ir/` has the IR builder, a verifier for the frontend's
functions and a text form (`--dump-ir`, the tests' round trip).

The runtime's optional built-ins (RegExp, normalize's Unicode tables,
Date, ArrayBuffer/DataView, JSON, iterator helpers, Promise and the timers
with the event loop, `Array.fromAsync`, Set's algebra, the URI functions,
`structuredClone`) are installed by a program that uses them (`Features.hx`:
the globals it names, the method names it calls, its syntax); hxmc leaves
the rest out. A hello world is 538 KB instead of 904 KB. A program that
names `globalThis` or calls a method by a computed name installs them all.

Excluded, with a diagnostic: `eval`, `Function`, `Proxy`, `with`,
`__proto__`/`setPrototypeOf`, dynamic `import()`. Not yet: BigInt, typed
arrays, `process` and node's other globals, calling helder's Haxe API.

## Tests

`bun run test typescript` (tests/typescript): the IR checks, then every
program of `cases/` and `modules/` compiled by tsc and run on node (24), and
by helder-ts natively and as wasm32-wasi, the outputs compared; `standards/`
check themselves where node still differs from the specification;
`reject/` must fail with a diagnostic at the line it names.

These sources are formatted by haxe-formatter (its master, for Haxe 4.3's
operators) with the repository's `hxformat.json`, which keeps helder's
single-line bodies and unwrapped lines; `generate.mjs` writes its files
already formatted.
