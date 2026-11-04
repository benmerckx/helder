package helder.physics;

import helder.gfx.shader.Vec3;
import helder.scene.math.Quat;
import helder.physics.Shape;
import helder.test.Test;

// Kinematic bodies (Body.kinematic): moved by the velocities set on them,
// pushing dynamic bodies and waking sleeping ones, never pushed; a body
// removed wakes what rested on it; raycast's result kept by the world, so
// a step's raycasts allocate nothing (natively and as wasm32-wasi). The
// physics-stress example's paddle and its stacks: examples/physics-stress.
function tests() {
	describe("kinematic bodies and waking", () -> {
		final dt = 1 / 60;
		function world():PhysicsWorld {
			var w = new PhysicsWorld();
			w.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
			return w;
		}
		test("moves by its velocity, ignores gravity and contacts", () -> {
			var w = world();
			var k = w.add(Body.kinematic(Box(new Vec3(0.5, 0.5, 0.5)), new Vec3(0, 2, 0)));
			k.velocity = new Vec3(1, 0, 0);
			k.angular = new Vec3(0, 1, 0);
			for (_ in 0...60)
				w.step(dt);
			approx(k.position.x, 1, 1e-6);
			approx(k.position.y, 2, 1e-9);
			assert(Math.abs(k.orientation.y) > 0.4, 'turned: ${k.orientation.y}');
			assert(k.isStatic() && k.isKinematic, "no mass, kinematic");
			throws(() -> Body.kinematic(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0)));
		});
		test("pushes a box and wakes it from sleep", () -> {
			var w = world();
			var box = w.add(new Body(Box(new Vec3(0.25, 0.25, 0.25)), new Vec3(0, 0.25, 0)));
			for (_ in 0...200)
				w.step(dt);
			assert(box.sleeping, "the box asleep on the floor");
			var paddle = w.add(Body.kinematic(Box(new Vec3(0.1, 0.4, 0.6)), new Vec3(-1.5, 0.4, 0)));
			paddle.velocity = new Vec3(2, 0, 0);
			for (_ in 0...60)
				w.step(dt);
			approx(paddle.position.x, 0.5, 1e-6);
			assert(box.position.x > 0.5, 'pushed ahead of it: ${box.position.x}');
			// (stopped, it stops pushing: the box sleeps again, the paddle never moved by it)
			paddle.velocity = new Vec3(0, 0, 0);
			for (_ in 0...300)
				w.step(dt);
			approx(paddle.position.x, 0.5, 1e-6);
			assert(box.sleeping, "asleep again");
		});
		test("a body removed wakes what rested on it", () -> {
			var w = world();
			var under = w.add(new Body(Box(new Vec3(0.5, 0.25, 0.5)), new Vec3(0, 0.25, 0)));
			var top = w.add(new Body(Box(new Vec3(0.25, 0.25, 0.25)), new Vec3(0, 0.75, 0)));
			var far = w.add(new Body(Sphere(0.3), new Vec3(4, 0.3, 0)));
			for (_ in 0...300)
				w.step(dt);
			assert(under.sleeping && top.sleeping && far.sleeping, "all asleep");
			w.remove(under);
			assert(!top.sleeping && far.sleeping, "the one on it woken, the far one not");
			for (_ in 0...120)
				w.step(dt);
			approx(top.position.y, 0.25, 0.02);
		});
		test("raycasts allocate nothing", () -> {
			var w = world();
			for (k in 0...20)
				w.add(new Body(Sphere(0.3), new Vec3(k, 0.3, 0)));
			function shoot(k:Int):Float {
				var hit = w.raycast(new Vec3(k % 20, 5, 0), new Vec3(0, -1, 0));
				return hit == null ? -1 : hit.distance + hit.point.y;
			}
			var s = shoot(0);
			approx(s, 4.4 + 0.6, 1e-9);
			var before = hxmc.GcStats.bytesAllocated();
			for (k in 0...1000)
				s += shoot(k);
			equals(hxmc.GcStats.bytesAllocated() - before, 0.0);
			equals(w.raycast(new Vec3(0, 5, 0), new Vec3(0, 1, 0)), null);
		});
	});
}
