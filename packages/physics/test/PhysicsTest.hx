import hxmc.gfx.shader.Vec3;
import hxmc.physics.*;
import hxmc.scene.*;

// @hxmc/physics (make 3d-check: on Eval, natively and as wasm32-wasi): a
// ball comes to rest on a plane and on a box, bounces by its restitution,
// two balls trade momentum, raycasts, sleeping and waking, a body moving
// its node; the same steps give the same numbers everywhere (a checksum
// of a pile of balls after 300 steps).
class PhysicsTest {
	// the pile's checksum after 300 steps (Eval, native and wasm32-wasi alike)
	static inline var CHECKSUM = 44358533;
	static var checks = 0;
	static var failed = 0;

	static function check(what:String, ok:Bool) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('PhysicsTest: FAIL: $what');
		}
	}

	static function near(a:Float, b:Float, eps:Float):Bool
		return Math.abs(a - b) <= eps;

	static function main() {
		var dt = 1 / 60;
		// resting on a plane
		var w = new PhysicsWorld();
		w.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		var ball = w.add(new Body(Sphere(0.5), new Vec3(0, 3, 0)));
		for (_ in 0...300)
			w.step(dt);
		check("rests on the plane", near(ball.position.y, 0.5, 0.01) && ball.sleeping);
		// bouncing: restitution 0.8 from 2 m, the first bounce back up to about 0.8^2 of it
		var w2 = new PhysicsWorld();
		var floor = w2.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		floor.restitution = 1;
		var b2 = w2.add(new Body(Sphere(0.1), new Vec3(0, 2.1, 0)));
		b2.restitution = 0.8;
		var falling = true, peak = 0.0;
		for (_ in 0...200) {
			w2.step(dt);
			if (falling && b2.velocity.y > 0) falling = false;
			if (!falling && b2.velocity.y >= 0) peak = Math.max(peak, b2.position.y - 0.1);
		}
		check('bounces to about 0.64 of its height (${Math.round(peak * 100) / 100} m)', peak > 2 * 0.64 * 0.85 && peak < 2 * 0.64 * 1.15);
		// two balls: momentum kept
		var w3 = new PhysicsWorld();
		w3.gravity = new Vec3(0, 0, 0);
		var a = w3.add(new Body(Sphere(0.5), new Vec3(-2, 0, 0), 1)), b = w3.add(new Body(Sphere(0.5), new Vec3(2, 0, 0), 3));
		a.velocity = new Vec3(4, 0, 0);
		a.restitution = b.restitution = 1;
		a.friction = b.friction = 0;
		for (_ in 0...120)
			w3.step(dt);
		var p = a.velocity.x * 1 + b.velocity.x * 3;
		check('momentum kept ($p)', near(p, 4, 1e-9) && a.velocity.x < 0 && b.velocity.x > 0);
		var energy = 0.5 * a.velocity.x * a.velocity.x + 1.5 * b.velocity.x * b.velocity.x;
		check('an elastic collision keeps energy ($energy)', near(energy, 8, 1e-6));
		// a box as a step
		var w4 = new PhysicsWorld();
		w4.add(new Body(Box(new Vec3(1, 0.5, 1)), new Vec3(0, 0.5, 0), 0));
		var onBox = w4.add(new Body(Sphere(0.25), new Vec3(0.2, 2, 0)));
		for (_ in 0...240)
			w4.step(dt);
		check("rests on the box", near(onBox.position.y, 1.25, 0.01));
		// raycasts
		var hit = w4.raycast(new Vec3(0.2, 5, 0), new Vec3(0, -1, 0));
		check("raycast hits the ball first", hit != null && hit.body == onBox && near(hit.distance, 5 - 1.5, 0.02));
		var boxHit = w4.raycast(new Vec3(-5, 0.5, 0), new Vec3(1, 0, 0));
		check("raycast hits the box", boxHit != null && near(boxHit.distance, 4, 1e-9));
		check("raycast misses", w4.raycast(new Vec3(-5, 5, 0), new Vec3(-1, 0, 0)) == null);
		// sleeping, then woken by an impulse
		check("asleep", onBox.sleeping);
		onBox.applyImpulse(new Vec3(0, 3, 0));
		w4.step(dt);
		check("woken by an impulse", !onBox.sleeping && onBox.position.y > 1.25);
		// a node moved by its body
		var world = new World();
		var node = world.node("ball");
		var w5 = new PhysicsWorld();
		w5.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		var nb = w5.add(new Body(Sphere(0.5), new Vec3(1, 4, 2)), node);
		w5.step(dt);
		check("the node follows its body", node.position.y == nb.position.y && node.position.x == 1);
		// boxes: tilted, one falls flat on the plane; a second stacks on it
		var w6 = new PhysicsWorld();
		w6.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		var box = w6.add(new Body(Box(new Vec3(0.5, 0.25, 0.5)), new Vec3(0, 1.5, 0)));
		box.orientation = hxmc.scene.math.Quat.axisAngle(new Vec3(1, 0, 1), 0.5);
		var turned = false;
		var top:Null<Body> = null;
		for (k in 0...600) {
			// (the second box dropped once the first lies still)
			if (k == 300) top = w6.add(new Body(Box(new Vec3(0.3, 0.3, 0.3)), box.position + new Vec3(0.05, 1.5, 0)));
			w6.step(dt);
			var a = box.angular;
			if (a.x * a.x + a.y * a.y + a.z * a.z > 0.01) turned = true;
		}
		var up = box.orientation.rotate(new Vec3(0, 1, 0));
		check('a tilted box tumbles flat (up ${Math.round(up.y * 1000) / 1000}, y ${Math.round(box.position.y * 1000) / 1000})',
			turned && Math.abs(up.y) > 0.99 && near(box.position.y, 0.25, 0.03));
		check('a box stacks on it (y ${Math.round(top.position.y * 1000) / 1000})', near(top.position.y, 0.5 + 0.3, 0.05));
		// a turned box's raycast: from above at a corner's reach
		var rb = new PhysicsWorld();
		var turnedBox = rb.add(new Body(Box(new Vec3(1, 1, 1)), new Vec3(0, 0, 0), 0));
		turnedBox.orientation = hxmc.scene.math.Quat.axisAngle(new Vec3(0, 0, 1), Math.PI / 4);
		var rh = rb.raycast(new Vec3(0, 5, 0), new Vec3(0, -1, 0));
		check("raycast on a turned box", rh != null && near(rh.distance, 5 - Math.sqrt(2), 1e-9));
		// determinism: a pile of balls in a box of planes
		var pile = new PhysicsWorld();
		pile.add(new Body(Plane(new Vec3(0, 1, 0), 0), new Vec3(0, 0, 0), 0));
		for (n in [new Vec3(1, 0, 0), new Vec3(-1, 0, 0), new Vec3(0, 0, 1), new Vec3(0, 0, -1)])
			pile.add(new Body(Plane(n, -2), new Vec3(0, 0, 0), 0));
		for (k in 0...12)
			pile.add(new Body(Sphere(0.3), new Vec3((k % 3) * 0.7 - 0.7 + k * 0.01, 1 + k * 0.5, (k % 2) * 0.4 - 0.2)));
		// (and boxes, landing on the balls and tumbling: rotation in the checksum)
		for (k in 0...3)
			pile.add(new Body(Box(new Vec3(0.25, 0.2, 0.3)), new Vec3(k * 0.6 - 0.6, 8 + k, 0.1 * k)));
		for (_ in 0...300)
			pile.step(dt);
		var sum = 0.0;
		for (bd in pile.bodies)
			sum += bd.position.x * 3 + bd.position.y * 5 + bd.position.z * 7 + bd.orientation.x * 11 + bd.orientation.y * 13;
		var inside = true;
		for (bd in pile.bodies)
			if (!bd.isStatic() && (Math.abs(bd.position.x) > 1.75 || Math.abs(bd.position.z) > 1.75 || bd.position.y < 0.19)) inside = false;
		check("the pile stays in its box", inside);
		Sys.println('PhysicsTest: pile checksum ${Math.round(sum * 1e6)}');
		// (the value on Eval, natively and as wasm32-wasi alike)
		check("the pile's checksum, the same on every target", Math.round(sum * 1e6) == CHECKSUM);
		Sys.println('PhysicsTest: $checks checks, ' + (failed == 0 ? "ok" : '$failed FAILED'));
		if (failed > 0) Sys.exit(1);
	}
}
