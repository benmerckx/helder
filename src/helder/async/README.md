# helder.async

Async on Haxe 5's coroutines (`haxe.coro`), with helder's own mechanism
underneath (Haxe package `helder.async`): a loop per thread, tasks with
structured concurrency, timers, and I/O natively on the same loop (TCP,
child processes, file watching), an HTTP and WebSocket server on it
(`helder.async.http`), and in the browser the same loop turned by the
page's. What the native CLI juggles at once: the compilation server's
socket, watching, the dev server, the running program's socket, child
processes, debounce timers.

```haxe
import helder.async.*;

Async.main(task -> {
  var server = Server.listen("127.0.0.1", 0);          // server.port
  task.async(_ -> while (true) {
    var s = server.accept();
    task.async(_ -> {
      var line = new Reader(s).readLine();
      s.writeString(line.toUpperCase() + "\n");
      s.close();
    });
  });
  var p = new Process("haxe", ["build.hxml"]);
  var out = new Reader(p.stdout);
  var line; while ((line = out.readLine()) != null) Sys.println(line);
  trace(p.wait());                                     // its exit code
  var w = new PollWatcher(["src"]);
  var changed = Async.timeout(30, _ -> w.next());      // a TimeoutException after 30 s
  task.cancel();                                       // the server's tasks with it
});
```

## Tasks

`Async.run(body)` runs `body` as the root task of this thread's loop until
it is done (its result, or its error thrown); `Async.main` is a program's
(in the browser it returns at once, see below); `Async.launch` starts a
root task without waiting. A body is a coroutine given its task (a
`Node`), which starts children:

- `task.async(body)`: a child `Task<T>`, started when the current task
  suspends; `t.await()` its result, `Async.all(tasks)` theirs in order;
  `task.awaitChildren()`.
- A task is done once its body and all its children are: `Async.run`
  waits for children nobody awaited.
- `t.cancel()` cancels it and its children: their suspensions end with a
  `CancellationException`, and a child started in a cancelled task never
  runs. A child's cancellation leaves its parent alone.
- A child's error cancels its parent (and so its siblings) and becomes the
  parent's, also when the parent awaited it and caught it.
  `Async.scope(body)` runs body in a task of its own whose error is the
  caller's to catch instead.
- Timers: `Async.delay(seconds)`, `Async.yield()` (after what is ready and
  the next poll), `Async.timeout(seconds, body)` (a scope cancelled with a
  `TimeoutException`).
- `Lock`: one coroutine at a time, in order (whole messages on a socket
  several tasks write to).

Suspension is the building block: `Async.suspend(cont -> ...)` resumes
when `cont` is resumed (at once if `f` does it), `Async.suspendCancellable`
also on the task's cancellation, after the function `f` returned undoes
what it started. Everything resumes through the loop, never on another
thread: a coroutine never changes threads.

The names are hxcoro's (`async`, `await`, `awaitChildren`, `scope`,
`timeout`, `suspend`, `suspendCancellable`, `TimeoutException`), its times
in seconds; the loop is haxe.coro's `Dispatcher` and `IScheduler` and a
task is the context's `CancellationToken`, so hxcoro's own `Coro.delay`,
`suspendCancellable` and tasks (`ContextRun.launchTask(Async.context(),
...)`) run on it and are cancelled by it. helder does not use hxcoro.

## The loop

`Loop.current()` is this thread's: what is dispatched to it runs in order
(a ring, drained each turn), then due timers (a binary heap), then a wait
on I/O of at most the next timer's time. `run()` until nothing is left or
`stop()`; `turn(seconds)` one turn, waiting at most that long (0: not at
all), for a loop driven by another (App.run's frames: a turn of 0 each
frame, and `App.wait` bounded by the next timer, are what it takes; the
X11, Cocoa and Win32 waits do not see the sockets yet). `post(f)` from
another thread (polled every 10 ms between `hold` and `release`).

The I/O backend (`Io.Backend`) is completion-based, as io_uring and IOCP
are: an `Op` (accept, connect, read into a buffer, write, a process's
exit) is submitted, owns its buffer, and comes back completed through the
loop. `PollIo` emulates that natively with poll(2) (`hxmc.net.Poll.wait`:
no allocation, any descriptor): it waits for readiness, then makes the
call; a connect's outcome is `SocketTools.connectError`'s. On POSIX a
child's pipes are non-blocking descriptors it polls, and its exit Linux's
pidfd (`processExitFd`), elsewhere (macOS) a waitpid at each poll (at most
10 ms apart). On Windows (WSAPoll takes sockets only) and Eval (`SelectIo`,
select(2)) a thread reads each pipe and another waits for the exit,
posting to the loop. io_uring, kqueue and IOCP are backends to come behind
the same interface.

| | |
| --- | --- |
| `Socket` | `Socket.connect(host, port)`, `read(b, pos, len)` (0 at the end), `write`, `writeString`, `shutdown`, `close` |
| `Server` | `Server.listen(host, port)` (port 0: any free one, `port`), `accept()`, `close` |
| `Process` | `new Process(cmd, args, ?{cwd, env})` (`env` the whole environment, `Process.environment()` a copy): `stdout` and `stderr` (`Source`s), `stdin` (a `Sink`), `wait()`, `signal(SIGINT/SIGTERM/SIGKILL)`, `kill`, `stop(grace)` (SIGTERM, SIGKILL after `grace` s), `close` |
| `Signals` | `Signals.next([SIGINT, SIGTERM])`: the next signal this process receives, which then no longer ends it (POSIX natively: a handler writing to a polled pipe) |
| `Reader` | a `Source` through a buffer: `readLine` (null at the end), `readBytes(n)`, `readAll` |
| `PollWatcher` | a `Watcher` by scanning (mtime to the nanosecond natively and size, recursive, debounced): `next()` the paths of a batch; inotify, FSEvents and `ReadDirectoryChangesW` to come |
| `SampledWatcher` | a `Watcher` of given files and directories (`watch(files, dirs)`, replaced after each build), polled as esbuild polls: the 16 recent paths and a shuffled slice of the rest each tick; stamps (natively `statTimes`: mtime and ctime to the nanosecond, the size), contents while an mtime is too recent (10 ms natively, 2 s on Eval), directories' listings (`helder dev`'s) |
| `Fetch` | `Fetch.bytes(path)`: in the browser a fetch (aborted when cancelled), natively the file |

## HTTP and WebSocket

`helder.async.http`, a dev server's needs on the TCP above (a package of
its own so that only programs that serve type it):

```haxe
var server = Server.listen("127.0.0.1", 8080);
Http.serve(server, req -> {
  if (req.path == "/ws" && WebSocket.wants(req)) {
    var ws = WebSocket.upgrade(req);
    var m; while ((m = ws.receive()) != null) ws.send("echo " + m);
    return null;                                       // the connection is the socket's
  }
  return Http.file("public", req.path) ?? Response.text("not found", 404);
});
```

HTTP/1.1 kept alive, bodies by `content-length`, each connection a child
task (an error in the handler is a 500, and the server goes on), `HEAD`.
WebSocket: text messages, fragments joined, pings answered, close; a
client too (`WebSocket.connect(host, port, path)`).

## In the browser

On wasm32-wasi the loop is turned by the page's event loop
(`src/helder/async/imports.mjs`, module `helder_async`, in browser.mjs's
option `imports`): `run` and `Async.main` return at once, a turn comes when
something is dispatched (as a task of its own, not a microtask: the page
renders between turns), when a timer is due (one `setTimeout`, the
earliest) or when a fetch ends. No sockets or processes there.

## Not yet

Workers and channels between threads, job tiers (GC-free jobs on
off-heap memory in a safe region), supervisors, `chunked`
bodies, TLS. A caught error is thrown again by the next coroutine call
that returns without suspending (the coroutine transform's,
tests/async/rep/CatchThenCall.hx); helder.async's own calls clear it.

Tests: `tests/async/Watcher.test.hx` (SampledWatcher; `WatchBench.hx` its
cost a tick against PollWatcher's), `tests/async/Tasks.test.hx` (tasks, cancellation, errors, timers:
helder.test's, `bun run helder test tests/async --target all`),
`AsyncTest.hx` (the loop, TCP, processes, the watcher, HTTP and
WebSocket: `bun run test async`, on Eval and natively), `WebTest.hx` (the
browser's loop: under node, and in Chromium with `bun run test
async-web`), `examples/async-dev` end to end (`tests/async/dev.mjs`),
`AsyncBench.hx`.
