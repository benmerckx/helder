# helder.scoped

Scoped memory for Haxe (Haxe package `helder.scoped`): data that lives in a
scope and is freed when the scope ends, all at once, with no garbage
collector involved. It runs on any target, with the reference compiler as
well as with hxmc: Eval, JavaScript, HashLink, the JVM and hxmc (native and
wasm32) are tested. The model is [Goose](https://github.com/aardappel/goose)'s
as hxmc's compiler had it (hxmc's docs/plans/lowlevel.md, "Scoped memory"),
moved out of the compiler into a library: hxmc's docs/plans/lean.md says why.

```haxe
import helder.scoped.*;

@:build(helder.scoped.Struct.build())
abstract Particle(Addr) {
  var x:Float;
  var y:Float;
  var life:Int;
}

@:build(helder.scoped.Scoped.build())
class Physics {
  @:scoped static function step(ps:Slice<Particle>, dt:Float):Int {
    var alive = Scope.grow(Int);            // freed when step returns
    for (i in 0...ps.length) {
      var p = ps[i];                        // the element, in place
      p.x += dt;
      if (--p.life > 0) alive.push(i);
    }
    return alive.length;
  }
}

@:build(helder.scoped.Scoped.build())
class Main {
  @:scoped static function main() {
    var ps = Scope.slice(Particle, 1000);   // zeroed, in main's scope
    Physics.step(ps, 1 / 60);
  }
}
```

## The types

| | |
| --- | --- |
| `Slice<T>` | a view of n elements: `s[i]`, `length`, `sub`, `ref(i)`, `blit`, iteration |
| `Grow<T>` | a grow-only array: `push`, `next()` (a new zeroed struct, in place), `s[i]`, `ref(i)`, `slice()`, `writer()`; references to its elements survive its growth |
| `GrowWriter<T>` | `g.writer()`: appends to g with its length, capacity and buffer in locals (`push`, `next()`, `length`, `grow`); push through it alone while it is in use. A byte writer also has `addString` (a literal: a few stores), `addStr`, `addSlice`, `addBytes`, `pushI32`, `pushI16` |
| `Span` | a run of bytes as a value (address and length, no header), storable in a struct: `Span.of(str)`, `get(i)`, `sub`, `equals`, `hash`, `toString` |
| `Ref<T>` | one element: `get()`, `set(v)` |
| `Str` | UTF-8 bytes: `Str.of(s)`, `toString()`, `==`, `+`, `compare`, `indexOf`, `sub`, `hash` |
| `StrBuf` | builds a `Str`: `add`, `addString`, `addInt`, `toStr()` |
| structs | `@:build(helder.scoped.Struct.build()) abstract X(Addr) { var f:T; ... }`: fields of Int, Float, Bool, `U8`, a value or another struct (inline); `new X()`, `X.SIZE`, `copyFrom` |
| values | `@:build(helder.scoped.Value.build()) class V { var f:T; ... }`: final fields of Int, Float, Bool, `U8` or another value, `new V(f, ...)`; computed with in locals, stored in place in a struct's field |

Element types are Int, Float, `F32` (4 bytes, read as a Float), Bool, `U8` (arithmetic and comparisons work as on an Int) and structs. A byte array (`Slice<U8>`, `Grow<U8>`) also reads little-endian Ints at any offset: `getI32At`, `getU16At`, `getI16At`, `setI32At`, `setI16At`. A struct element is
stored in place: `s[i].x = 1` writes into the slice, and `s[i] = p` copies
`p` into it. Indexes are checked (a `ScopedError`).

## Writing fast code

The rules that keep code built on the package close to what Goose or C
would make of it, on every target:

- **Compute with values, store in structs.** A struct is memory: `p.x` is
  a load or a store. A value (`Value.build`) is a set of locals: Haxe's
  inline constructors turn `p.pos.add(p.vel).scale(dt)` into arithmetic on
  locals, with nothing allocated, as long as the value does not escape (a
  field, an Array, a closure, `Dynamic`). Reading a struct's value field
  loads it, assigning one stores it.
- **Index slices in `@:scoped` functions.** A slice parameter or local that
  is never assigned or captured is read through a view from its
  declaration on: its data, length and stride in locals, so `s[i]` reads
  no header and checks i against the cached length. In
  `for (i in 0...s.length)` and `for (p in s)` nothing is checked.
- **Append through a writer** in a loop: `var w = g.writer()`, then
  `w.push(x)` is a compare and two stores; text goes in whole
  (`w.addString("...")`, `w.addStr(s)`), not a byte at a time.
- **A struct Grow's `next()` and `push(v)`** know the struct's size: a new
  element is zeroed and a copy made with a few stores.
- **Use `F32` for data a loop streams through** when f32 precision is
  enough: half the memory of a Float.
- **Keep allocation out of inner loops.** An iteration that cannot
  allocate has no scope check at all (the macro types the body and looks
  for an allocation, a call to a function without a scope of its own, or a
  closure). One that may pays a compare per iteration.
- **Work on whole slices.** `step(ps:Slice<Particle>, dt)` rather than a
  call per element; split hot data into one slice per field when a loop
  reads few of them.

## Scopes

- `Scope.slice(T, n)`, `Scope.grow(T)`, `Str.of(s)` and `new` of a struct
  allocate in the current scope.
- **`@:scoped` functions** (the `Scoped` build macro on their class; `@:scoped`
  on the class: all of them) mark a scope on entry and free it at every
  return. A function whose result is a scoped value keeps its memory for
  the caller's scope instead. Each loop iteration is a scope of its own:
  what it allocated is freed when the next starts (a compare when it
  allocated nothing, nothing when it cannot allocate).
- **Loops over a slice**, `for (i in 0...s.length)` in a `@:scoped` function,
  read `s[i]` through a view with the data and stride in locals and no
  checks: i is in range by construction, as long as neither s nor i is
  assigned, declared again or captured in the body, which the macro checks.
  Iterating, `for (p in s)`, is as fast.
- **Entry points** (`main`, a callback) are `@:scoped` functions too:
  allocating outside any scope is an error.
- An exception leaves the memory to the enclosing scope, so nothing is ever
  freed early: the return of the function that catches it frees it, or the
  next iteration of its loop. One that leaves every `@:scoped` function
  keeps that memory: an entry point catches its exceptions itself.

## Safety

- **The checker** (`--macro helder.scoped.Check.enable()`; `extraParams.hxml`
  adds it when the package is a `-lib`) rejects a scoped value reaching the
  GC heap, where it could outlive its scope:
  - a field or a static;
  - an Array, Map, `Null<T>`, or a type parameter of a class;
  - an anonymous structure;
  - a closure's capture;
  - `Dynamic` or `Any`;
  - in a loop of a `@:scoped` function, a value made in an iteration kept
    in a variable from outside the loop (the next iteration frees it).
- **Across functions**, it does not track lifetimes beyond these rules.
  Build with `-D scoped_debug` to catch the rest at run time: freed memory
  is overwritten, and Slices, Grows and Strs check a mark in their header
  on every use.
- **Memory is the library's own buffers**, never the host's pointers. An
  access outside them cannot happen (hxmc natively: every address lies in
  its reservation; JavaScript: in its ArrayBuffer) or fails (wasm32,
  HashLink). On JavaScript, the JVM and Eval it is memory-safe regardless.

## Where the memory is

32 buffers of up to 64 MB, shared by the program's threads
(`-D scoped_buffer_bits=27`, `28` or `29`: 16 of 128 MB, 8 of 256 MB or 4
of 512 MB). Buffer 0 is
never used, so no address is 0. A thread claims a buffer for its stack,
which everything that does not grow is bumped on, when it enters its first
scope, and gives it back when it leaves it. Each live `Grow` claims a
buffer too. So stacks and Grows together are at most 31 at once.

Per target (`Store.hx`):
- **hxmc native:** one reservation for all 32 (2 GB of address space,
  `hxmc.rt.Os.reserve`: `mmap` with `MAP_NORESERVE`, or `VirtualAlloc`
  with pages committed as touched), so it does not count against the commit
  limit. An access is base plus address, with no table and no check. A
  buffer has its whole region from the start: nothing is zeroed or copied
  as it grows (memory is zeroed where it is allocated), and a page costs
  only once it is written.
- **hxmc wasm32:** `malloc`ed buffers in a table, each access checked
  (a reservation would grow the linear memory). A buffer grows by
  reallocation: addresses are offsets, so nothing breaks.
- **JavaScript:** one ArrayBuffer holding every buffer at its address, with
  typed-array views over it: an access is `f64[a >> 3]`, with no table and
  no check. Its pages are not committed until touched; a host that will not
  make 2 GB gets half, and fewer buffers.
- **HashLink:** the same in one `hl.Bytes` (31 buffers), each access
  checking its buffer: a shift and a compare.
- **The JVM:** a little-endian `java.nio.ByteBuffer` view per buffer.
- **The other targets:** `haxe.io.Bytes`.

**Threads.** On hxmc, each thread has its own stack and Grows: the thread's
top and the Grows it holds are thread-local statics, which cost a load like
any other. On HashLink, the JVM and Eval, `-D scoped_threads` keeps them in
a `sys.thread.Tls`. That costs 1.4-2.5× on the benchmarks, so without it
scoped memory is for one thread at a time. Claiming and releasing a buffer
takes a lock. A scoped value cannot reach another thread: a closure cannot
capture one.

## Measured

`make scoped-bench` (test/ScopedBench.hx). Particles: 100,000 updated in
place over 200 frames, the dead ones respawned, a temporary list of the
visible ones each frame. "Flat" is the same work in one `Vector` per field,
the best plain Haxe does on that target: the goal for the scoped version.
Trees: 40 binary trees of depth 16, built and walked. Milliseconds on a
shared 4-core Xeon, 2026-10-26, best of three runs (runs varied by up to
2×: other builds were running):

| | particles: scoped | values | GC | flat | trees: scoped | GC |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| hxmc native | 105 | 80 | 196 | 45 | 41 | 86 |
| JavaScript (node 22) | 222 | 191 | 645 | 104 | 54 | 122 |
| HashLink (JIT) | 453 | 477 | 352 | 220 | 66 | 606 |
| HashLink (HL/C, gcc -O2) | 119 | | 321 | 93 | 50 | 643 |
| JVM | 594 | 363 | 500 | 75 | 56 | 54 |

"Values" is the particles written the recommended way (Writing fast code):
`Vec2` values for position and velocity, `p.pos = p.pos.add(p.vel)`, and
the visible list pushed through a writer.

For comparison, natively: the same particles in C (gcc -O2) take 46 ms and
in [Goose](https://github.com/aardappel/goose) 41 ms; Goose's trees take
13 ms.

- **Natively**, particles written with values take 80 ms: 2.4× faster
  than GC objects, 1.7× from flat and from C. One reserved range, loop
  views, loop scopes that cost nothing, values and writers took them from
  351 ms. The rest is hxmc's code generation: the base pointer is
  reloaded before every access (a raw-memory store could change a static,
  as far as it knows), and there are 32-bit sign extensions and spills.
  Those are compiler work (hxmc's docs/plans/lean.md).
- **Trees** are 2× faster than GC objects natively and on JavaScript, and
  9-13× on HashLink, whose collector is a non-generational mark-sweep.
- **On JavaScript and HashLink**, one block for all buffers took particles
  from 661 ms to 222 (JavaScript) and from 826 to 502 (the JIT). With HL/C
  they are about as fast as flat arrays. On the JVM, `ByteBuffer` views
  (the package's own externs: Haxe 5 has none for `java.nio`) took them
  from 785 ms to about 600; they are 8× from flat there, the widest gap
  left.

hxcpp is not in the table: on this machine's toolchain (Haxe 5 preview, the
hxcpp checkout here), generic closures return 0 even without this package.
Neko needs `-D no-inline`: with inlining, the test's functions exceed its
limits.

## Tests

`npm test -- scoped` runs:
- `test/ScopedTest.hx` on Eval, natively and as JavaScript (it also passes
  as wasm32-wasi, as HL/C and with `-D scoped_debug`);
- the programs the checker must reject, `test/reject` (RejectTest.hx).

`make scoped-targets` runs both with the reference compiler on Eval,
JavaScript, HashLink and the JVM, and the test again with
`-D scoped_threads` on Eval, HashLink and the JVM. Natively and with
`-D scoped_threads`, the test runs 40 threads, more than there are
buffers, so a stack not given back would run out.
