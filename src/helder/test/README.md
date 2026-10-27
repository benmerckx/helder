# helder.test

Tests as bun and jest write them, without macros: tests registered by
calls, assertions as plain functions located by their caller's position
(`haxe.PosInfos`), async tests as coroutines on `helder.async`'s loop.
Files are `*.test.hx`, built and run by `helder test` (src/helder/cli).

```haxe
// src/geom/Vec.test.hx
package geom;

import helder.async.Async;
import helder.test.Test;

function tests() {
  describe("Vec", () -> {
    var v = new Vec(0, 0);
    beforeEach(() -> v = new Vec(3, 4));
    test("length", () -> approx(v.length(), 5));
    test("fields", () -> equals({x: v.x, y: v.y}, {x: 3.0, y: 4.0}));
    test("parse", () -> {
      var p = require(Vec.parse("1,2"));     // stops the test on null
      equals(p.x, 1.0);
    });
    test("later", () -> fail("todo")).skip();
  });
  test("loads", async(() -> {
    Async.delay(0.01);
    assert(true);
  })).timeout(1);
}
```

```sh
bun run helder test                       # every test file, natively
bun run helder test geom -t length        # the files under geom, tests named so
bun run helder test --target all --watch
```

## Files

A test file is a module with a module-level `tests()` function, named
`*.test.hx`, under `src/`, `tests/` or one of the project's class paths
(package.json's `"haxe": {"classPath"}`), never under `bin/` or
`node_modules/`. Its `package` line is its directory's under that root.
It can use what its package can (`@:allow` included); private helpers are
`private function`s.

Haxe takes no dot in a module's name ("Module "Vec.test" does not have a
valid name"), so `helder test` links each one into bin/test/src under its
package's directories as `Vec_test.hx` (a symbolic link, else a hard link,
else a copy, each kept the file's content), generates
bin/test/src/HelderTestMain.hx, whose main calls each `tests()` and then
the runner, builds that once with the project's class paths plus
bin/test/src, and runs it. Positions are the same in the link, so the
compiler's output and the program's are written with the real paths
again (the CLI rewrites them, and the runner maps the paths PosInfos
records itself, for a program run directly).

Editors: the Haxe display server takes `Vec.test.hx` for the module
`geom.Vec` (the name up to the first dot): with a `Vec.hx` beside it,
requests answer for that file (no diagnostics, no hover, no completion in
the test), without one they fail ("Type not found : geom.Vec"). The link
does not help (it is resolved to the real path); a copy would. Until the
editor extension (phase 6), a test file is written without the language
server. Windows makes symbolic links only in developer mode, and hard
links on the same volume: else the copy, rewritten when the test file
changes.

## Registering

`import helder.test.Test;` gives the functions:

- `test(name, body)`, `describe(name, body)` (its body registers its tests,
  hooks and groups at once); both return the entry, for `.skip()`,
  `.only()` (only those marked, across files, run; a group's mark covers
  its tests) and `.timeout(seconds)` (a group's: its tests').
- `beforeEach`, `afterEach` (inner first, also after a failure),
  `beforeAll`, `afterAll`, in a file or a group. A failed beforeAll is
  reported and leaves its group's tests out.
- A body is a plain function, or `async(coroutine)`: a test or hook that
  suspends, run on `helder.async`'s loop with a timeout (5 s, else
  `.timeout()` or `--timeout`). helder.async is linked only into programs
  with an `async`. In the browser's loop (wasm32-wasi) the run goes on as
  each async step ends: nothing blocks.

(`async(...)` and not an overload of `test`: overload resolution types
the argument once without the coroutine's expected type, and a coroutine
lambda nested in the body (`Async.scope(task -> ...)`) fails to type.)

## Assertions

| | |
| --- | --- |
| `assert(cond, ?msg)` | a failure if false |
| `equals(actual, expected, ?msg)` | deep (`Equal.diff`): numbers by value, arrays, lists, maps, anonymous structures and instances by field, enums, Bytes, Dates; both values shown, and where they differ (`.list[0].a`) |
| `notEquals(actual, expected)` | |
| `approx(actual, expected, epsilon = 1e-6)` | |
| `throws(fn):Dynamic` | the error as thrown (an exception, or a value); a failure if none. `throwsAsync(coroutine)` in a coroutine |
| `require(v, ?msg):T` | v, not null; null stops the test |
| `fail(msg)` | a failure, the test stopped |
| `snapshot(name, value)` | value (a String, or shown as a literal) against Vec.test.snap beside the file: written when missing, `-u` rewrites a changed one |

A failure is the file and line of the call, then its message; the test
goes on, except after `require`, `fail` or an error thrown (its message
and the frames above the runner's).

## Running

The runner (`Runner`) prints each file, then `(pass)`, `(fail)` with its
failures, or `(skip)` per test with its time, and a summary (pass, skip,
fail, checks, the time); exit code 1 on a failure. `helder test`:

| | |
| --- | --- |
| `[filter...]` | a filter that is part of a test file's path picks those files; any other one the tests whose full name ("describe > test") contains it |
| `-t <text>` | the tests whose full name contains it; `/text/` a regex (the generated main gives the runner EReg only then) |
| `--target <t>` | `host` (natively, the default), `interp` (Eval), `wasm` (wasm32-wasi under node: src/helder/test/wasi.mjs, node's WASI with the working directory and helder.async's imports), `all`, or several (`host,wasm`); a line per target at the end |
| `--watch`, `-w` | built and run again after each change under the roots (mtimes to the nanosecond: a save within the same second is seen); builds go to a compilation server (`haxe --wait`), stopped with the CLI on ctrl-c or SIGTERM |
| `-u` | snapshots rewritten |
| `--timeout <s>` | an async step's limit |

Sizes and times (this repository's 42 tests, 3 files, Linux x86-64):
a file with one plain test builds to 327 KB natively and 165 KB for
wasm32-wasi (a hello world is 129 KB), 0.58 s from nothing and 0.21 s
from the module cache, and runs in 2 ms. The repository's build: 0.55 s
cold, 0.21 s cached (0.26 s for wasm), 0.25 to 0.45 s through the
compilation server; Eval compiles and runs it in 0.42 s (0.06 s with
no test run).

## Not yet

A macro (`assert(a == b)` showing both sides, tests collected without
`tests()`), golden images beside snapshots, the runner's sub-runs in
process (helder.test's own tests run the program again for what fails),
`test.each`, coverage, the browser as a target, the CLI as a binary on
npm. Tests: `*.test.hx` here (`bun run helder test src/helder/test`), and
the `test` lane (`bun run test test`).
