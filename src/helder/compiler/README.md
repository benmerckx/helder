# helder.compiler

helder's compiler: hxmc's compiler (@hxmc/cli's `haxe`, with the same
command line) with helder's hooks linked in. The helder CLI builds every
program with it (src/helder/cli's `Compiler.hx`; hxmc's native compiler,
with a warning, when it cannot build it): one-shot builds and `helder dev`'s
compilation server alike.

- `Compiler.hx`, the main: installs hxmc's hooks (defines, the module
  cache, C interop, target flags, std DCE), `MarkupHook`, and helder's
  frontends' plugins, then runs Haxe's driver. Under a compilation server
  (`--wait`, `--server-listen`, `--server-connect`) the build stays resident
  and a frontend's errors come back as the compiler's messages, at their
  file, line and columns.
- `MarkupHook.hx`: markup in any function (helder.view's DESIGN.md 3.5).
  Around hxmc's parse (`TypeloadParse.parseHook`, again when a compilation
  server has replaced it), each parsed file's markup literals are wrapped as
  `implements Markup` wraps them, `helder.view.View.literal(@:markup
  "<...>")`, so a module-level function or a class of no interface returns
  markup.
- `Plugin.hx`: a frontend's plugin point, one per frontend: the compiler's
  short form (`<compiler> <entry> ...`), the start of a build (before Haxe
  types it) and its generation in hxmc's place. helder.typescript's
  (`helder.typescript.Frontend`) is the one listed.

```sh
node src/helder/compiler/build.mjs          # builds helder's compiler, prints its path
$(node src/helder/compiler/build.mjs --quiet) app.ts -o bin/app && bin/app
```

`build.mjs` builds it once per hxmc version and per hash of helder.compiler's
and helder.typescript's sources, into the user's cache
(`~/.cache/helder/compiler/`, `HELDER_CACHE` names another). It links hxmc's
compiler sources from `@hxmc/source` (a dev dependency at `@hxmc/cli`'s
version), or a checkout `HXMC_SRC` names; `--sources` prints their path
instead (for tests that link them too).

These sources are formatted by haxe-formatter with the repository's
`hxformat.json`.
