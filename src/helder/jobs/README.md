# helder.jobs

Background work awaited from a coroutine (Haxe package `helder.jobs`): a
job runs on another thread, natively a pool's, in a browser a Web Worker's
instance of the program's own module, and its result resumes the awaiting
coroutine on its own `helder.async` loop. A coroutine never changes thread;
only data crosses. A package of its own, apart from `helder.async`: it
needs hxmc's `hxmc.unsafe` (no Eval), has its own browser modules
(`imports.mjs`, `worker.mjs`), and nothing of it is linked into a program
that does not use it.

```haxe
import helder.jobs.*;
import hxmc.unsafe.*;

// GC-free, the engine's: an @:hxmc.unsafe callback over off-heap memory
@:hxmc.unsafe @:hxmc.callback static function invert(job:Job):Int {
  var n = job.input.length, src = job.input.ptr, out = job.output(n);
  if (out.isNull()) return -1;                     // < 0: a JobError's code
  for (i in 0...n) {
    if (i & 0xFFFF == 0 && job.cancelled) return -2;
    Mem.setI8(out, i, 255 - Mem.getU8(src, i));
  }
  return 0;
}

// a GC job, user code: sendable values in and out
static function words(s:String):Int return s.split(" ").length;

Async.run(task -> {
  var out:IoBuffer = Jobs.run(invert, IoBuffer.ofBytes(bytes));  // the input moved in
  out.free();                                                     // the output is ours
  var n = Jobs.run(words, "one two three");                       // 3
  var t = task.async(_ -> Jobs.run(words, text));                 // a Task
  var ch = new Channel<{done:Int, of:Int}>();                     // progress from a job
  task.async(_ -> Jobs.run(Work.all, {items: items, progress: ch}));
  var p; while ((p = ch.receive()) != null) trace('${p.done}/${p.of}');
});
```

## Jobs

`Jobs.run(f, ?input)` (a macro) awaits `f`'s run with its input; `f` is a
static function, named (`Class.field`, private too):

- **GC-free** (`@:hxmc.unsafe @:hxmc.callback function (job:Job):Int`):
  its input an `IoBuffer` moved into the run (freed after it), its
  output one it allocates with `job.output(n)` (not zeroed; `truncate(n)`
  shortens it), which `run` returns; a result < 0 is a `JobError` with that
  code. Natively the pool calls it in a safe region (`hxmc.unsafe.Blocking`),
  so other threads' collections never wait for it: the compiler checks
  that it touches no GC object. The default for the engine (decoding:
  `helder.image.ImageJobs`).
- **GC** (any static function of one sendable argument, or none, to a
  sendable result, or Void): its argument and result copied across
  (`Sendable`, below); its exception a `JobError` (code -1, the message;
  the exception stays where it was thrown). Natively it shares the heap's
  collections, which wait for its longest loop without an allocation (a
  4K PNG's decode: 35-55 ms, 200 ms since PngDecoder allocates nothing in
  its decode): short work only. In a browser it is an isolate.
- **Cancellation**: cancelling the awaiting task resumes it at once (a
  `CancellationException`). Natively the job sees `job.cancelled` and may
  return early; in a browser a queued job is dropped, a running one's
  worker ended and another made for the next job.
- **The pool**: `Jobs.workers` threads or workers, read at the first job
  (-1: the cores but one, at least one); `Jobs.workers = 0`, a WASI host
  without `helder_jobs` or a browser without `Worker`: jobs run on the
  loop at its next turn, with the same results. `Jobs.onWorker()`: whether
  this code runs on one.

Natively (`Pool`) the threads wait on one queue; a run's end is posted to
its loop, whose wake pipe ends its wait (`helder.async.Loop`; App.run's
wait polls it too). A run's record (`Job`) is malloc'ed: the job reads it
in its region, the cancel flag included.

## Sendable

What crosses (`Sendable`, a macro: checked where a job is run or a
`Channel<T>` named, the culprit and where it is in the type in the error,
its codec generated, `Wire`):

| | |
| --- | --- |
| `Int`, `Float`, `Bool`, `haxe.Int64` | copied |
| `String`, `haxe.io.Bytes` | copied (null too) |
| `hxmc.unsafe.IoBuffer` | moved: natively its address, in a browser its bytes (the sender's freed) |
| `@:hxmc.struct` classes | copied (their bytes) |
| `Null<T>`, abstracts over a `T` | as `T` (enum abstracts too) |
| `{a:T, ...}`, `Array<T>` | copied, field by field |
| `Channel<T>` | the channel |

Not: classes and interfaces (shared mutable state), enums (not yet),
functions, `Dynamic`, `Ptr`, type parameters, recursive types.
tests/jobs/reject's programs are rejected so:

```
helder.jobs: count's input cannot be sent: .items[]: Item is a class (shared mutable state) (sendable: ...)
```

## Channels

`Channel<T>` (T sendable: a class made per T): `send(v)` from any thread
or job (a copy; a `JobError` once closed), `receive()` on the loop of the
thread that made it, in order (null once closed and drained), `close()`
from either side. Natively a queue under a lock, its sends posted to that
loop; from a browser's worker the page delivers them. One way, many
senders: jobs report progress or stream results to their awaiter.

## In the browser

`imports.mjs` (module `helder_jobs`, for browser.mjs's option `imports`;
`helder build --target web` copies it and `worker.mjs`) starts workers as jobs
come, each instantiating the page's compiled module (`host.module`,
posted: compiled once) with `worker.mjs`'s small WASI (no files, the
console). A worker's instance runs the static initializers up to
`WebJobs`' `__init__`, which serves jobs instead of running main. A job is
its callback's index in the function table, the same in every instance;
its input and output are copied out of one instance's memory into an
ArrayBuffer, transferred, and copied into the other's. No
SharedArrayBuffer, no cross-origin isolation. Under node (helder test's
`wasi.mjs`) the workers are worker_threads.

## Measured

tests/bench/results/jobs.md, "Through helder.jobs" (linux-x86_64, a
shared 4-core VM; wasm32 under node 22): the 4K PNG decoded while 60 fps
frames run.

| | frame max (ms) | longest pause (ms) | decode (ms) |
| --- | ---: | ---: | ---: |
| frames alone, natively | 1.4-4.9 | 0.4-0.7 | |
| on the loop (`workers = 0`) | 168 | 0.6 | 177 |
| GC-free job (`ImageJobs`) | 5.8-6.4 | 0.5-0.6 | 177-204 |
| GC job (PngDecoder) | 219 | **217** | 252 |
| frames alone, wasm32 | 9.9 | 8.1 | |
| on the loop, wasm32 | 285 | 4.6 | 290 |
| GC-free job, wasm32 (a worker) | 9.6 | 4.4 | 377 |

A job's round trip (an empty one, awaited one after the other): 28 µs
natively (GC-free or GC), 45-53 µs on wasm32's workers, 0.3-1 µs on the
loop. Linked only when used: a program awaiting one GC-free job is 40 KB
larger natively than one awaiting a timer, 15 KB on wasm32; a GC job's
codec 4 KB more.

## Not yet

Channels toward a worker (a job receives none), enums as sendable
values, a job reading files in a browser's worker (no file system there),
GC jobs safe natively (hxmc's loop safepoints), SharedArrayBuffer as a
fast path, text's glyphs as jobs (README, phase 3).

Tests: `tests/jobs/Jobs.test.hx` (the pool, both tiers, cancellation,
errors, channels, the loop without workers: `bun run helder test
tests/jobs --target host,wasm`), `bun run test jobs` (the sendable
check's rejections), `jobs-web` (Chromium: workers, a cancelled one
ended, the loop without frames), `app` (App.run's loop: tests/os/AppLoopTest.hx),
`jobs-bench`.
