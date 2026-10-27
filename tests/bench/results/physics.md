# Physics without garbage: before and after

The README's "An allocation-free core", for helder.physics: a step
allocated 45-570 KB on the GC heap (baseline.md: 330 KB for 200 crates);
it now allocates nothing once its buffers have grown to the world's size
(6be57d0). The same numbers bit for bit: PhysicsTest unchanged (its
pile's checksum on Eval, natively and as wasm32-wasi), every body's
position, orientation and velocities hashed after 150-200 steps of each
workload alike before and after, natively and as wasm32, and the 3d lane's
physics.png, chains.png and walker.png exact.

## Where the allocations came from

Bytes a step natively, steps 2 to 31 of each workload, by phase (GcStats
read around each one; the phases not listed allocated nothing: gravity,
the solver's iterations, integration, pushing apart, sleep, nodes):

| KB a step | stacks | chains | pile | joints | walkers |
| --- | ---: | ---: | ---: | ---: | ---: |
| contacts (Collide) | 308.0 | 0 | 456.6 | 230.5 | 261.6 |
| the broad phase's index (a `Map<Body, Int>` a step) | 18.1 | 40.1 | 32.1 | 16.7 | 8.1 |
| the pairs' sort (`Array.sort` with a closure) | 9.1 | 4.8 | 82.3 | 8.4 | 7.0 |
| hinges (`for (t in [t1, t2])`) | | | | 17.5 | |
| `Character.update` (its rays) | | | | | 162.0 |
| total | 335.3 | 44.9 | 571.1 | 273.1 | 438.7 |

- **Contacts**: a `Contact` object each (112 B), and another for each one
  flipped (a and b swapped): 17-23% of Collide's bytes. The rest is the
  box tests: a box's 8 corners in an `Array<Vec3>`, both boxes' axes in
  two more and their extents in `Array<Float>`s, made per pair (box
  against box, box against a plane).
- **Vec3** is hxmc's struct value (`@:hxmc.struct`): in locals, fields,
  arguments and results it is never allocated, and the vector maths
  (`a + b * s`, `cross`, `Quat.rotate`, `toMat4`) allocates nothing.
  It is boxed (32 B) where the representation is generic: an element of an
  `Array<Vec3>` that escapes (stored, returned, passed to a function), an
  optional `?p:Vec3` argument that is given. That is where physics' boxed
  vectors were: the corners and axes Arrays, and a hinge's two tangents,
  `for (t in [t1, t2])` (120 B a hinge an iteration: a literal hxmc does not
  allocate unless the loop's body has a `continue`, as that one had).
- **Character's rays**: `raycast` returns an object, and a box's ray test
  made an `Aabb` (a class: its `ray` is not inlined, so it escapes), for
  each body each ray (85 bodies, 1-4 rays a character).

## What changed

- **Contacts** (new, internal): the step's contacts struct-of-arrays, the
  bodies in two `Array<Body>` and 11 floats each in one `Array<Float>`
  (normal, point, depth, the accumulated impulses, the bounce), cleared
  each step, not reallocated. Collide adds to it; flipping swaps in place.
  `Collide.test(a, b, Array<Contact>)` stays, through a scratch Contacts.
- **The box tests** compute a corner (`corner(b, h, k)`) and an axis
  (`axis(m, i)`, a column of the rotation) where they are needed: the same
  expressions in the same order, so the same bits.
- **The broad phase**: a body's index on the body (set each step) instead
  of the Map; the pairs sorted by two counting passes (second body, then
  first) into kept arrays instead of `Array.sort`; any correct sort of the
  same unique keys gives the same order.
- **Rays**: `PhysicsWorld.ray` (internal) returns the distance and leaves
  the body in `hit`; `raycast` keeps its API on top of it, Character uses
  `ray`. The box's slab test is Collide's own, without an Aabb.
- **Hinges**: their two tangents in a loop over an index.

The public API and its behaviour are unchanged. `Contact` lost its
solver fields (internal ones), which the world now keeps in Contacts.

## Before and after

Medians of five alternating runs of the two builds (each run: the
workload's median and p99 over its runs; each workload in a process of its
own), 2026-10-27, Intel Xeon, 4 cores, a shared VM (medians move by about
10% from run to run, p99s more). 30 steps a run, each from a new world
(pile and walkers after 45 and 10 untimed steps). KB/run: GC heap bytes in
a run (/30 for a step); GCs over all runs (60, pile 40); the longest time
collecting in one run (natively; wasm32's collector does not time itself).

| workload | target | median ms | p99 ms | KB/run | GCs (majors) | longest GC ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| physics.stacks | native | 39.81 → 39.31 (-1%) | 44.56 → 50.83 | 9831.4 → 172.7 | 72 (0) → 0 (0) | 0.29 → 0 |
| physics.chains | native | 11.09 → 10.29 (-7%) | 12.41 → 11.59 | 1337.3 → 17.9 | 10 (0) → 0 (0) | 0.14 → 0 |
| physics.pile | native | 94.95 → 88.65 (-7%) | 108.16 → 111.13 | 17031.7 → 160.0 | 84 (0) → 0 (0) | 0.41 → 0 |
| physics.joints | native | 35.60 → 34.38 (-3%) | 41.36 → 41.30 | 8559.6 → 596.1 | 103 (0) → 3 (0) | 0.19 → 0.48 |
| physics.walkers | native | 42.79 → 42.42 (-1%) | 62.24 → 47.30 | 13193.5 → 0 | 163 (0) → 0 (0) | 0.22 → 0 |
| physics.stacks | wasm32 | 45.80 → 43.52 (-5%) | 55.16 → 57.57 | 9831.4 → 172.7 | 72 (0) → 0 (0) | - |
| physics.chains | wasm32 | 12.66 → 11.92 (-6%) | 15.69 → 15.93 | 1337.3 → 17.9 | 10 (0) → 0 (0) | - |
| physics.pile | wasm32 | 113.59 → 101.04 (-11%) | 145.85 → 120.68 | 17032.7 → 160.0 | 84 (0) → 0 (0) | - |
| physics.joints | wasm32 | 44.01 → 42.38 (-4%) | 57.00 → 46.62 | 8491.4 → 802.7 | 103 (0) → 3 (0) | - |
| physics.walkers | wasm32 | 52.73 → 50.25 (-5%) | 67.06 → 63.60 | 13125.3 → 0 | 164 (0) → 0 (0) | - |

What is left after is a new world's buffers growing (contacts, pairs, the
broad phase's order): joints' 192 links reach 1536 contacts in their first
steps. In steady state (`Bench <font> steady`: each world after 300 steps,
the next 300), natively and as wasm32 alike:

| B a step | stacks | chains | pile | joints | walkers |
| --- | ---: | ---: | ---: | ---: | ---: |
| before | 580,516 | 37,787 | 716,718 | 227,505 | 236,700 |
| after | 0 | 0 | 0 | 0 | 0 |
| GCs in 300 steps, before → after | 41 → 0 | 3 → 0 | 52 → 0 | 16 → 0 | 17 → 0 |

The time hardly moves: physics' step is arithmetic, and hxmc's nursery
made the garbage cheap (a collection of it took 0.1-0.4 ms natively). What
is gone is the collections themselves: none in steady state, so no pause
from physics however long it runs.

Builds: examples/walker (KB; seconds from nothing, `-D hxmc.no-module-cache`,
without and with scoped's checker, best of three alternating builds):

| | target | size before | after | compile before | after | with checker before | after |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Walker | native | 705 | 700 (-0.7%) | 1.01 | 1.00 | 1.74 | 1.75 |
| Walker | wasm32 | 524 | 521 (-0.7%) | 1.16 | 1.16 | 1.78 | 1.78 |

## GC buffers against helder.scoped

The same design with its hot storage in scoped memory (not committed): a
`@:scoped` step, the contacts a `Grow` of a struct (`ContactData`: the
bodies as their indexes in the world, the same 11 floats), the pairs a
`Grow<Int>`, the sort's buffers slices, all in the step's scope. The same
numbers bit for bit. Medians of the same five alternating runs:

| workload | target | GC buffers ms | scoped ms | scoped / GC | p99 GC / scoped |
| --- | --- | ---: | ---: | ---: | ---: |
| physics.stacks | native | 39.31 | 37.75 | 0.96 | 50.83 / 41.95 |
| physics.chains | native | 10.29 | 10.75 | 1.04 | 11.59 / 12.34 |
| physics.pile | native | 88.65 | 87.81 | 0.99 | 111.13 / 109.88 |
| physics.joints | native | 34.38 | 33.71 | 0.98 | 41.30 / 34.62 |
| physics.walkers | native | 42.42 | 41.56 | 0.98 | 47.30 / 56.08 |
| physics.stacks | wasm32 | 43.52 | 44.56 | 1.02 | 57.57 / 62.02 |
| physics.chains | wasm32 | 11.92 | 12.15 | 1.02 | 15.93 / 14.52 |
| physics.pile | wasm32 | 101.04 | 105.71 | 1.05 | 120.68 / 147.61 |
| physics.joints | wasm32 | 42.38 | 42.74 | 1.01 | 46.62 / 44.09 |
| physics.walkers | wasm32 | 50.25 | 51.66 | 1.03 | 63.60 / 58.88 |

Both allocate nothing in steady state; scoped also nothing in a new
world's first steps (its memory is the step's scope: 4-8 KB a run left,
the broad phase's GC `order` array growing), where GC buffers grow once.

| Walker | size GC buffers | scoped | compile GC | scoped | with checker GC | scoped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| native | 700 KB | 712 KB (+1.7%) | 1.00 s | 1.13 s (+13%) | 1.75 s | 1.88 s |
| wasm32 | 521 KB | 549 KB (+5.4%) | 1.16 s | 1.42 s (+22%) | 1.78 s | 2.00 s |

**Verdict: GC buffers.** The times are within 5% either way and within the
VM's noise: natively scoped was 1-4% faster on four workloads and 4%
slower on chains, on wasm32 1-5% slower on all five (each access through
scoped's table, as the text pilot found). Storage is a small part of a
step: the time is the contact tests' and the solver's arithmetic. So the
simpler code wins: plain Arrays, bodies by reference rather than by index
into the world, no build macro on Collide and PhysicsWorld, and a
smaller, faster build (scoped's macros: +13-22% compile time, +1.7-5.4%
size). Scoped memory would also claim a buffer per Grow per step (two of
its 31), which worlds stepped on several threads would compete for.

## hxmc

- **`Array.resize` grows to the exact length** (hxmc.rt.Arr.grow: "the
  storage allocated at the new length"), so an array grown by resize each
  time it needs one more slot is copied each time: quadratic, 2 KB an
  element growing an `Array<Int>` to 1000 one at a time, where `push`
  takes 8 B amortized. The sort's buffer grows by half itself here.
- **Struct values are boxed in generic storage**: an `Array<V>` element
  stored, an optional `?v:V` argument given: 32 B for 3 floats.
  Non-escaping array literals of them are not allocated.
- **A `for` over an array literal of struct values allocates when its
  body has a `continue`**: `for (v in [new V3(k, 0, 0), new V3(0, k, 0)])
  { if (v.y > 500) continue; sink += v.y; }` takes 112 B an iteration (the
  Array and both values boxed); without the `continue`, or indexing the
  literal, nothing.
- **`Array.sort` allocates** about 17 B an element (100 Ints: 1.7 KB a
  call), with its closure.

Reproduction (natively; prints the bytes each):

```haxe
@:hxmc.struct final class V3 {
	public final x:Float;
	public final y:Float;
	public final z:Float;
	public inline function new(x:Float, y:Float, z:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
}

@:access(hxmc.rt.Gc)
class Repro {
	static inline function bytes():Float {
		var p = hxmc.rt.Gc.yptr;
		var young:Float = cast hxmc.rt.Gc.youngBytes;
		return young + (p.isNull() ? 0.0 : cast p.diff(hxmc.rt.Gc.youngStart));
	}

	static var sink = 0.0;

	static function opt(a:V3, ?b:V3)
		sink += a.x + (b == null ? 0 : b.x);

	static function main() {
		hxmc.rt.Gc.stats = true;
		var arr = [for (k in 0...8) new V3(k, 0, 0)], b0 = bytes();
		for (k in 0...1000) arr[k & 7] = new V3(k, 0, 0);
		Sys.println('Array<V3> store: ${(bytes() - b0) / 1000}');        // 32
		b0 = bytes();
		for (k in 0...1000) opt(new V3(k, 0, 0), new V3(1, 0, 0));
		Sys.println('optional V3 given: ${(bytes() - b0) / 1000}');      // 32
		var a:Array<Int> = [];
		b0 = bytes();
		for (k in 1...1001) a.resize(k);
		Sys.println('resize(length + 1): ${(bytes() - b0) / 1000}');     // 2012
		var c:Array<Int> = [];
		b0 = bytes();
		for (k in 0...1000) c.push(k);
		Sys.println('push: ${(bytes() - b0) / 1000}');                    // 8.3
		b0 = bytes();
		for (k in 0...1000)
			for (v in [new V3(k, 0, 0), new V3(0, k, 0)]) {
				if (v.y > 500) continue;
				sink += v.y;
			}
		Sys.println('for with continue: ${(bytes() - b0) / 1000}');       // 112
	}
}
```

`haxe -main Repro -D hxmc.target=linux-x86_64 --custom-target hxmc=Repro`

## After hxmc 8841f02

`Array.resize` grows geometrically and a `for` over a literal with a
`continue` allocates nothing: the sort's buffer is grown by `resize(n)`
and the hinge's tangents are `for (t in [t1, t2])` again. Steady state still
0 B a step in every world, the times within the noise (physics.joints 34.4
ms natively, 588 KB a run). `Array.sort` allocates nothing up to 128
elements only (2000 Ints: 8 KB a call), so the pairs keep their counting
passes.
