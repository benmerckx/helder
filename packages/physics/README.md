# @hxmc/physics

A small rigid-body core for `@hxmc/3d` (Haxe package `hxmc.physics`; its
place in the plan: docs/plans/3d.md, step 6). A separate package: the 3D
core never depends on it.

```haxe
var physics = new PhysicsWorld();
physics.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));    // static floor
physics.add(new Body(Box(new Vec3(1, 0.5, 1)), new Vec3(3, 0.5, 0), 0));      // static box
var ball = physics.add(new Body(Sphere(0.3), new Vec3(0, 4, 0)), ballNode);  // moves ballNode
// each fixed step (hxmc.scene.FixedStep):
physics.step(dt);
var hit = physics.raycast(origin, direction);
```

Moving bodies are spheres for now; boxes and planes are static. Contacts
(sphere against sphere, box and plane) are resolved by sequential impulses
with restitution and friction; resting bodies sleep and wake on contact or
impulse; the same steps give the same numbers on every target (Eval,
native, wasm32-wasi: tested). Next: dynamic boxes and capsules (GJK and
EPA), rotation, a broad phase, a character controller; a binding to an
established engine behind the same API later.

Tests: `test/PhysicsTest.hx` and the Falling example's frame
(packages/3d/test, `make 3d-check`, `make 3d-web-check`).
