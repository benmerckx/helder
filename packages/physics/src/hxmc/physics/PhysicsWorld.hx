package hxmc.physics;

import hxmc.gfx.shader.Vec3;
import hxmc.scene.Node;

// A small rigid-body world (docs/plans/3d.md, step 6): bodies under
// gravity, stepped at a fixed rate (hxmc.scene.FixedStep's dt): velocities
// integrated (semi-implicit Euler), contacts found (sphere against sphere,
// box and plane: all pairs, a broad phase when worlds grow), resolved by
// sequential impulses with restitution and friction over a few
// iterations, overlap pushed apart, resting bodies put to sleep. A body
// added with a node moves that node. Deterministic: the same steps give
// the same result on every target.
class PhysicsWorld {
	public var gravity = new Vec3(0, -9.81, 0);
	public var iterations = 8;
	public final bodies:Array<Body> = [];
	// the last step's contacts (statistics)
	public var contacts(default, null) = 0;
	// speed under which a body counts as still, and the steps it must stay
	// still to sleep
	public var sleepSpeed = 0.05;
	public var sleepSteps = 30;

	final pending:Array<Contact> = [];

	public function new() {}

	public function add(body:Body, ?node:Node):Body {
		bodies.push(body);
		if (node != null) {
			body.node = node;
			node.position = body.position;
		}
		return body;
	}

	public function remove(body:Body)
		bodies.remove(body);

	public function step(dt:Float) {
		for (b in bodies)
			if (!b.isStatic() && !b.sleeping) {
				b.velocity = b.velocity + gravity * dt;
			}
		// contacts
		pending.resize(0);
		for (i in 0...bodies.length)
			for (j in i + 1...bodies.length) {
				var a = bodies[i], b = bodies[j];
				if ((a.isStatic() || a.sleeping) && (b.isStatic() || b.sleeping)) continue;
				var c = Collide.test(a, b);
				if (c != null) pending.push(c);
			}
		contacts = pending.length;
		for (c in pending) {
			// (a moving body touching a sleeping one wakes it)
			if (c.a.sleeping && !c.b.isStatic() && !c.b.sleeping) c.a.wake();
			if (c.b.sleeping && !c.a.isStatic() && !c.a.sleeping) c.b.wake();
		}
		for (_ in 0...iterations)
			for (c in pending)
				resolve(c);
		for (b in bodies)
			if (!b.isStatic() && !b.sleeping) b.position = b.position + b.velocity * dt;
		// (what is still overlapping, pushed apart: 80% of it, past a slop)
		for (c in pending) {
			var total = c.a.invMass + c.b.invMass;
			if (total == 0) continue;
			var push = Math.max(c.depth - 0.001, 0) * 0.8 / total;
			if (!c.a.sleeping) c.a.position = c.a.position - c.normal * (push * c.a.invMass);
			if (!c.b.sleeping) c.b.position = c.b.position + c.normal * (push * c.b.invMass);
		}
		for (b in bodies) {
			if (b.isStatic() || b.sleeping) continue;
			var v = b.velocity;
			if (v.x * v.x + v.y * v.y + v.z * v.z < sleepSpeed * sleepSpeed) {
				if (++b.still >= sleepSteps) b.sleep();
			} else
				b.still = 0;
		}
		for (b in bodies)
			if (!b.node.isNone && b.node.valid && !b.isStatic()) b.node.position = b.position;
	}

	// one contact's impulses: along the normal (restitution, never pulling),
	// then along the surface (friction, within the Coulomb cone)
	function resolve(c:Contact) {
		var a = c.a, b = c.b, total = a.invMass + b.invMass;
		if (total == 0) return;
		var rv = b.velocity - a.velocity;
		var vn = dot(rv, c.normal);
		if (vn > 0) return;
		var e = Math.min(a.restitution, b.restitution);
		// (no bounce at resting speeds: no jitter)
		if (-vn < 0.5) e = 0;
		var j = -(1 + e) * vn / total;
		var impulse = c.normal * j;
		if (!a.sleeping) a.velocity = a.velocity - impulse * a.invMass;
		if (!b.sleeping) b.velocity = b.velocity + impulse * b.invMass;
		// friction
		rv = b.velocity - a.velocity;
		var tangent = rv - c.normal * dot(rv, c.normal);
		var tl = Math.sqrt(dot(tangent, tangent));
		if (tl > 1e-9) {
			var t = tangent / tl;
			var jt = -dot(rv, t) / total;
			var mu = Math.sqrt(a.friction * b.friction);
			if (Math.abs(jt) > j * mu) jt = jt > 0 ? j * mu : -j * mu;
			var f = t * jt;
			if (!a.sleeping) a.velocity = a.velocity - f * a.invMass;
			if (!b.sleeping) b.velocity = b.velocity + f * b.invMass;
		}
	}

	// the first body a ray hits (dir of any length but zero), within maxDistance
	public function raycast(origin:Vec3, dir:Vec3, maxDistance = 1e9):Null<{body:Body, distance:Float, point:Vec3}> {
		var l = Math.sqrt(dot(dir, dir));
		var d = dir / l;
		var best:Null<Body> = null, bestT = maxDistance;
		for (b in bodies) {
			var t = Collide.ray(b, origin, d);
			if (t >= 0 && t < bestT) {
				bestT = t;
				best = b;
			}
		}
		return best == null ? null : {body: best, distance: bestT, point: origin + d * bestT};
	}

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;
}
