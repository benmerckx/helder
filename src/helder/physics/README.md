# helder.physics

A small rigid-body core for `helder.scene` (Haxe package `helder.physics`). A separate package: the 3D
core never depends on it.

```haxe
var physics = new PhysicsWorld();
physics.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));    // static floor
physics.add(new Body(Box(new Vec3(1, 0.5, 1)), new Vec3(3, 0.5, 0), 0));      // static box
var ball = physics.add(new Body(Sphere(0.3), new Vec3(0, 4, 0)), ballNode);  // moves ballNode
// each fixed step (helder.scene.FixedStep):
physics.step(dt);
var hit = physics.raycast(origin, direction);
```

A sweep-and-prune broad phase picks the pairs. Spheres, boxes and capsules (`Capsule(radius, half)`,
along the body's y) move and turn (inertia from the shape; `body.rotates = false` keeps a character's capsule
upright); planes are static. Contacts (sphere against sphere, box and plane; box against plane
and box, by separating axes among their faces and the corners where the faces overlap: crates of one size stack; edges crossing get one contact midway; capsules as spheres at their segments' nearest points) are resolved by
sequential impulses at the contact points, accumulated and clamped, with
restitution and friction; resting bodies sleep and wake on contact or
impulse; the same steps give the same numbers on every target (Eval,
native, wasm32-wasi: tested). Joints: `physics.join(Joint.ball(a, anchorA, b, anchorB))` (a ball and socket; `b` null: a point of the world) `Joint.distanceOf(...)` (a rigid rod) and `Joint.hinge(a, anchorA, axisA, b, anchorB, axisB)` (doors, wheels). `Character` walks an upright capsule: steered towards a wanted velocity, grounded by a ray, jumping, climbing steps. Next: convex hulls (GJK and EPA), box edge-against-edge axes, slopes for characters; a binding to an
established engine behind the same API later.

A step allocates nothing on the GC heap once its buffers have grown to the world's size: the contacts
struct-of-arrays in `Contacts`, cleared each step, the vectors hxmc's struct values (never in an Array, which
boxes them). Measured by `bun run test bench` (physics.stacks, chains, pile, joints, walkers):
[tests/bench/results/physics.md](../../../tests/bench/results/physics.md).

Examples: `Falling` (balls and boxes) and `Walker` (a `Character` among crates; `Shapes.capsule` draws it).

Tests: `tests/physics/PhysicsTest.hx` and the Falling and Walker examples' frames
(tests/3d, `bun run test 3d`, `bun run test 3d-web`).
