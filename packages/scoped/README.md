# @hxmc/scoped

Scoped memory for Haxe (Haxe package `hxmc.scoped`): data that lives in a
scope and is freed when the scope ends, all at once, with no garbage
collector involved. It runs on any target, with the reference compiler as
well as with hxmc: Eval, JavaScript, HashLink, the JVM and hxmc (native and
wasm32) are tested. The model is [Goose](https://github.com/aardappel/goose)'s
as hxmc's compiler had it (hxmc's docs/plans/lowlevel.md, "Scoped memory"),
moved out of the compiler into a library: hxmc's docs/plans/lean.md says why.

```haxe
import hxmc.scoped.*;

@:build(hxmc.scoped.Struct.build())
abstract Particle(Addr) {
  var x:Float;
  var y:Float;
  var life:Int;
}

@:build(hxmc.scoped.Scoped.build())
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

var ps = Scope.slice(Particle, 1000);       // zeroed, in the current scope
Physics.step(ps, 1 / 60);
```

## The types

| | |
| --- | --- |
| `Slice<T>` | a view of n elements: `s[i]`, `length`, `sub`, `ref(i)`, `blit`, iteration |
| `Grow<T>` | a grow-only array: `push`, `next()` (a new zeroed struct, in place), `s[i]`, `ref(i)`, `slice()`; references to its elements survive its growth |
| `Ref<T>` | one element: `get()`, `set(v)` |
| `Str` | UTF-8 bytes: `Str.of(s)`, `toString()`, `==`, `+`, `compare`, `indexOf`, `sub`, `hash` |
| `StrBuf` | builds a `Str`: `add`, `addString`, `addInt`, `toStr()` |
| structs | `@:build(hxmc.scoped.Struct.build()) abstract X(Addr) { var f:T; ... }`: fields of Int, Float, Bool, `U8` or another struct (inline); `new X()`, `X.SIZE`, `copyFrom` |

Element types are Int, Float, Bool, `U8` and structs. A struct element is
stored in place: `s[i].x = 1` writes into the slice, and `s[i] = p` copies
`p` into it. Indexes are checked (a `ScopedError`).

## Scopes

- `Scope.slice(T, n)`, `Scope.grow(T)`, `Str.of(s)` and `new` of a struct
  allocate in the current scope.
- **`@:scoped` functions** (the `Scoped` build macro on their class; `@:scoped`
  on the class: all of them) mark a scope on entry and free it at every
  return. A function whose result is a scoped value keeps its memory for
  the caller's scope instead. Each loop iteration is a scope of its own:
  what it allocated is freed when the next starts (a compare when it
  allocated nothing).
- **Loops over a slice**, `for (i in 0...s.length)` in a `@:scoped` function,
  read `s[i]` through a view with the data and stride in locals and no
  checks: i is in range by construction, as long as neither s nor i is
  assigned, declared again or captured in the body, which the macro checks.
  Iterating, `for (p in s)`, is as fast.
- **`Scope.run(f)`** runs f in a scope of its own, freed when f returns or
  throws: the entry point from ordinary code.
- An exception leaves the memory to the enclosing scope, so nothing is ever
  freed early.

## Safety

- **The checker** (`--macro hxmc.scoped.Check.enable()`; `extraParams.hxml`
  adds it when the package is a `-lib`) rejects a scoped value reaching the
  GC heap, where it could outlive its scope:
  - a field or a static;
  - an Array, Map, `Null<T>`, or a type parameter of a class;
  - an anonymous structure;
  - a closure's capture;
  - `Dynamic` or `Any`.
- **Within a function**, it does not yet track a value assigned to a
  variable of an enclosing loop and used in a later iteration. Build with
  `-D scoped_debug` to catch those at run time: freed memory is
  overwritten, and Slices, Grows and Strs check a mark in their header on
  every use.
- **Memory is the library's own buffers**, never the host's pointers. An
  access outside them fails (hxmc, HashLink) or cannot happen (JavaScript's
  typed arrays). On JavaScript, the JVM and Eval it is memory-safe
  regardless.

## Where the memory is

Sixteen buffers per program. Buffer 0 is bumped by everything that does
not grow; each live `Grow` claims one of the others, so at most 15 Grows
are live at once. Each buffer holds up to 128 MB.

Per target (`Store.hx`):
- **hxmc native:** one reservation for all 16, 2 GB of address space
  committed as it is touched. An access is base plus address, with no table
  and no check: every address lies inside the reservation. The reservation
  is a `malloc`; an `mmap`/`VirtualAlloc` one would not count against the
  commit limit, but `hxmc.unsafe` does not declare those yet.
- **hxmc wasm32:** `malloc`ed buffers in a table, each access checked
  (a reservation would grow the linear memory). A buffer grows by
  reallocation: addresses are offsets, so nothing breaks.
- **JavaScript:** typed-array views over an ArrayBuffer per buffer.
- **HashLink:** the bytes' `hl.Bytes`, each access checked.
- **The other targets:** `haxe.io.Bytes`.

It is single-threaded for now: one set of buffers per program.

## Measured

`make scoped-bench` (test/ScopedBench.hx). Particles: 100,000 updated in
place over 200 frames, the dead ones respawned, a temporary list of the
visible ones each frame. "Flat" is the same work in one `Vector` per field,
the best plain Haxe does on that target: the goal for the scoped version.
Trees: 40 binary trees of depth 16, built and walked. Milliseconds on a
shared 4-core Xeon, 2026-10-26, best of three runs (runs varied by up to
40%):

| | particles: scoped | GC | flat | trees: scoped | GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| hxmc native | 115 | 163 | 52 | 39 | 87 |
| JavaScript (node 22) | 661 | 622 | 102 | 113 | 124 |
| HashLink (JIT) | 826 | 503 | 198 | 89 | 366 |
| JVM | 785 | 689 | 65 | 73 | 45 |

For comparison, natively: the same particles in C (gcc -O2) take 46 ms and
in [Goose](https://github.com/aardappel/goose) 41 ms; Goose's trees take
13 ms.

- **Natively**, scoped particles are faster than GC objects and 2.2× from
  flat. One reserved range, the loop views and cheap loop scopes took them
  from 351 ms. The rest is hxmc's code generation: the base pointer is
  reloaded before every access (a raw-memory store could change a static,
  as far as it knows), and there are 32-bit sign extensions and spills.
  Those are compiler work (hxmc's docs/plans/lean.md).
- **Trees** are 2.2× faster than GC objects natively and 4× on HashLink,
  whose collector is a non-generational mark-sweep.
- **On JavaScript, HashLink and the JVM**, particles are 4-12× from flat:
  the next steps there are a cached typed-array view per loop (JavaScript),
  `ByteBuffer` views on the JVM (Haxe 5 has no `java.nio` externs yet), and
  HL/C rather than the JIT.

hxcpp is not in the table: on this machine's toolchain (Haxe 5 preview, the
hxcpp checkout here), generic closures return 0 even without this package.
Neko needs `-D no-inline`: with inlining, the test's functions exceed its
limits.

## Tests

`make scoped-check` runs:
- `test/ScopedTest.hx` on Eval, natively and as JavaScript;
- the programs the checker must reject, `test/reject` (RejectTest.hx).

`make scoped-targets` runs both with the reference compiler on Eval,
JavaScript, HashLink and the JVM.
