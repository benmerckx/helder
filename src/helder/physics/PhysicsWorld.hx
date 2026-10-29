package helder.physics;

import helder.gfx.shader.Vec3;
import helder.scene.Node;
import helder.scene.math.Quat;

// A small rigid-body world: bodies under
// gravity, stepped at a fixed rate (helder.scene.FixedStep's dt): velocities
// integrated (semi-implicit Euler, orientations too), contacts found
// (a sweep-and-prune broad phase, then Collide: spheres, boxes, capsules, planes), resolved by sequential impulses at the contact points (linear
// and angular: boxes tumble) with restitution and friction, the impulses
// accumulated and clamped over the iterations, overlap pushed apart,
// resting bodies put to sleep. A body added with a node moves and turns
// that node. Deterministic: the same steps give the same result on every
// target. A step allocates nothing once its buffers (contacts, pairs) have
// grown to the world's size.
class PhysicsWorld {
	public var gravity = new Vec3(0, -9.81, 0);
	public var iterations = 10;
	public final bodies:Array<Body> = [];
	// the last step's contacts (statistics)
	public var contacts(default, null) = 0;
	// speeds under which a body counts as still, and the steps it must stay
	// still to sleep
	public var sleepSpeed = 0.05;
	public var sleepSteps = 30;

	final pending = new Contacts();
	public final joints:Array<Joint> = [];

	public function new() {}

	public function add(body:Body, ?node:Node):Body {
		bodies.push(body);
		if (node != null) {
			body.node = node;
			node.position = body.position;
			node.rotation = body.orientation;
		}
		return body;
	}

	public function remove(body:Body)
		bodies.remove(body);

	// a joint between bodies (Joint.ball, Joint.distanceOf), solved with the contacts
	public function join(joint:Joint):Joint {
		joints.push(joint);
		return joint;
	}

	public function unjoin(joint:Joint)
		joints.remove(joint);

	public function step(dt:Float) {
		for (b in bodies)
			if (!b.isStatic() && !b.sleeping) b.velocity = b.velocity + gravity * dt;
		pending.clear();
		broadPhase();
		var cs = pending;
		contacts = cs.length;
		for (i in 0...cs.length) {
			var a = cs.a[i], b = cs.b[i];
			// (a moving body touching a sleeping one wakes it)
			if (a.sleeping && !b.isStatic() && !b.sleeping) a.wake();
			if (b.sleeping && !a.isStatic() && !a.sleeping) b.wake();
			// (the bounce: from the approach speed, none at resting speeds)
			var p = cs.point(i);
			var vn = dot(b.velocityAt(p) - a.velocityAt(p), cs.normal(i));
			cs.set(i, Contacts.BOUNCE, vn < -0.5 ? -Math.min(a.restitution, b.restitution) * vn : 0);
		}
		for (j in joints)
			j.wake();
		for (_ in 0...iterations) {
			for (i in 0...cs.length)
				resolve(cs, i);
			for (j in joints)
				j.solve(dt);
		}
		for (b in bodies)
			if (!b.isStatic() && !b.sleeping) {
				b.position = b.position + b.velocity * dt;
				var w = b.angular, q = b.orientation;
				// (dq = w q / 2: w as a quaternion of no scalar part)
				var spin = new Quat(w.x, w.y, w.z, 0) * q;
				b.orientation = new Quat(q.x + spin.x * dt / 2, q.y + spin.y * dt / 2, q.z + spin.z * dt / 2, q.w + spin.w * dt / 2).normalized();
			}
		// (what is still overlapping, pushed apart: 20% of it a step, past a slop)
		for (i in 0...cs.length) {
			var a = cs.a[i], b = cs.b[i];
			var total = a.invMass + b.invMass;
			if (total == 0) continue;
			var push = Math.max(cs.get(i, Contacts.DEPTH) - 0.005, 0) * 0.2 / total;
			if (!a.sleeping) a.position = a.position - cs.normal(i) * (push * a.invMass);
			if (!b.sleeping) b.position = b.position + cs.normal(i) * (push * b.invMass);
		}
		for (b in bodies) {
			if (b.isStatic() || b.sleeping) continue;
			var v = b.velocity, w = b.angular;
			if (dot(v, v) < sleepSpeed * sleepSpeed && dot(w, w) < sleepSpeed * sleepSpeed) {
				if (++b.still >= sleepSteps) b.sleep();
			} else
				b.still = 0;
		}
		for (b in bodies)
			if (!b.node.isNone && b.node.valid && !b.isStatic()) {
				b.node.position = b.position;
				b.node.rotation = b.orientation;
			}
	}

	// the pairs whose bounds overlap, by sweep and prune along x: the
	// bodies sorted by their bounds' start (insertion sort: the order
	// changes little between steps), each tested against those starting
	// before its end; planes, unbounded, against every body. Pairs in the
	// order of the bodies list, so the result does not depend on the sort
	// (a pair is its bodies' indexes, the lower one's in the high 16 bits,
	// sorted by two counting passes). The arrays are kept between steps.
	final order:Array<Body> = [];
	final pairs:Array<Int> = [];
	final sorted:Array<Int> = [];
	final counts:Array<Int> = [];

	function broadPhase() {
		order.resize(0);
		for (b in bodies)
			if (!b.shape.match(Plane(_, _))) order.push(b);
		for (b in order)
			b.bounds();
		for (i in 1...order.length) {
			var b = order[i], j = i - 1;
			while (j >= 0 && order[j].minX > b.minX) {
				order[j + 1] = order[j];
				j--;
			}
			order[j + 1] = b;
		}
		pairs.resize(0);
		for (k in 0...bodies.length)
			bodies[k].index = k;
		for (i in 0...order.length) {
			var a = order[i];
			for (j in i + 1...order.length) {
				var b = order[j];
				if (b.minX > a.maxX) break;
				if (a.maxY < b.minY || b.maxY < a.minY || a.maxZ < b.minZ || b.maxZ < a.minZ) continue;
				var ia = a.index, ib = b.index;
				pairs.push(ia < ib ? ia * 65536 + ib : ib * 65536 + ia);
			}
		}
		for (k in 0...bodies.length)
			if (bodies[k].shape.match(Plane(_, _)))
				for (j in 0...bodies.length)
					if (j != k && !bodies[j].shape.match(Plane(_, _))) pairs.push(k < j ? k * 65536 + j : j * 65536 + k);
		// (by the second body, then the first: each pass keeps the order of
		// the last; Array.sort would allocate above 128 elements)
		var n = pairs.length;
		if (sorted.length < n) sorted.resize(n);
		countingSort(pairs, sorted, n, 0);
		countingSort(sorted, pairs, n, 16);
		for (p in pairs) {
			var a = bodies[p >>> 16], b = bodies[p & 0xFFFF];
			if ((a.isStatic() || a.sleeping) && (b.isStatic() || b.sleeping)) continue;
			Collide.collide(a, b, pending);
		}
	}

	// from's first n pairs into to, by their body index at shift (stable)
	function countingSort(from:Array<Int>, to:Array<Int>, n:Int, shift:Int) {
		var m = bodies.length;
		counts.resize(0);
		for (_ in 0...m + 1)
			counts.push(0);
		for (i in 0...n)
			counts[((from[i] >>> shift) & 0xFFFF) + 1]++;
		for (k in 0...m)
			counts[k + 1] += counts[k];
		for (i in 0...n) {
			var p = from[i], k = (p >>> shift) & 0xFFFF;
			to[counts[k]++] = p;
		}
	}

	// one contact's impulses at its point: along the normal up to the
	// bounce (accumulated, never pulling), then along two tangents
	// (friction, within the Coulomb cone of the normal impulse)
	function resolve(cs:Contacts, i:Int) {
		var a = cs.a[i], b = cs.b[i];
		if (a.invMass + b.invMass == 0) return;
		var n = cs.normal(i), p = cs.point(i);
		var vn = dot(b.velocityAt(p) - a.velocityAt(p), n);
		var k = mass(a, b, p, n);
		var normalImpulse = cs.get(i, Contacts.NORMAL_IMPULSE);
		var jn = Math.max(normalImpulse + (cs.get(i, Contacts.BOUNCE) - vn) / k, 0);
		var dj = jn - normalImpulse;
		cs.set(i, Contacts.NORMAL_IMPULSE, jn);
		apply(a, b, p, n * dj);
		// friction: two tangents of the normal
		var t1 = Math.abs(n.x) > 0.7 ? normalize(cross(n, new Vec3(0, 1, 0))) : normalize(cross(n, new Vec3(1, 0, 0)));
		var t2 = cross(n, t1);
		var mu = Math.sqrt(a.friction * b.friction), limit = mu * jn;
		for (axis in 0...2) {
			var t = axis == 0 ? t1 : t2, field = axis == 0 ? Contacts.TANGENT_IMPULSE1 : Contacts.TANGENT_IMPULSE2;
			var vt = dot(b.velocityAt(p) - a.velocityAt(p), t);
			var acc = cs.get(i, field);
			var jt = Math.max(-limit, Math.min(limit, acc - vt / mass(a, b, p, t)));
			var d = jt - acc;
			cs.set(i, field, jt);
			apply(a, b, p, t * d);
		}
	}

	// the effective mass's inverse along dir at the point p of a and b
	static function mass(a:Body, b:Body, p:Vec3, dir:Vec3):Float {
		var ra = p - a.position, rb = p - b.position;
		var ka = cross(a.applyInvInertia(cross(ra, dir)), ra), kb = cross(b.applyInvInertia(cross(rb, dir)), rb);
		return a.invMass + b.invMass + dot(dir, ka) + dot(dir, kb);
	}

	// an impulse j at the point p: -j on a, j on b
	static function apply(a:Body, b:Body, p:Vec3, j:Vec3) {
		if (!a.isStatic() && !a.sleeping) {
			a.velocity = a.velocity - j * a.invMass;
			a.angular = a.angular - a.applyInvInertia(cross(p - a.position, j));
		}
		if (!b.isStatic() && !b.sleeping) {
			b.velocity = b.velocity + j * b.invMass;
			b.angular = b.angular + b.applyInvInertia(cross(p - b.position, j));
		}
	}

	// the first body a ray hits (dir of any length but zero), within
	// maxDistance (ignore: a body left out, as a character's own)
	public function raycast(origin:Vec3, dir:Vec3, maxDistance = 1e9, ?ignore:Body):Null<{body:Body, distance:Float, point:Vec3}> {
		var t = ray(origin, dir, maxDistance, ignore);
		return hit == null ? null : {body: hit, distance: t, point: origin + dir / Math.sqrt(dot(dir, dir)) * t};
	}

	// raycast without its result object, allocating nothing (a game's
	// step, Character's): the distance (maxDistance: nothing hit), the body
	// hit in hit (null: none)
	public var hit(default, null):Null<Body> = null;

	public function ray(origin:Vec3, dir:Vec3, maxDistance:Float, ignore:Null<Body>):Float {
		var l = Math.sqrt(dot(dir, dir));
		var d = dir / l;
		var best:Null<Body> = null, bestT = maxDistance;
		for (b in bodies) {
			if (b == ignore) continue;
			var t = Collide.ray(b, origin, d);
			if (t >= 0 && t < bestT) {
				bestT = t;
				best = b;
			}
		}
		hit = best;
		return bestT;
	}

	static inline function dot(a:Vec3, b:Vec3):Float
		return a.x * b.x + a.y * b.y + a.z * b.z;

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);

	static inline function normalize(a:Vec3):Vec3
		return a / Math.sqrt(dot(a, a));
}
