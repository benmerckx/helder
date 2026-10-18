package hxmc.physics;

import hxmc.gfx.shader.Vec3;
import hxmc.scene.Node;
import hxmc.scene.math.Quat;

// A rigid body: its shape, position and orientation, linear and angular
// velocity (world space, radians a second), mass (0: static, never moved)
// and its inertia from its shape, how much it bounces (restitution, 0 to
// 1) and grips (friction). A body added with a node writes its position
// and orientation to the node after each step.
class Body {
	public final shape:Shape;
	public var position:Vec3;
	public var orientation:Quat = Quat.identity();
	public var velocity:Vec3 = new Vec3(0, 0, 0);
	public var angular:Vec3 = new Vec3(0, 0, 0);
	public final mass:Float;
	public final invMass:Float;
	// the inverse inertia's diagonal in the body's frame
	public final invInertia:Vec3;
	public var restitution = 0.3;
	public var friction = 0.4;
	public var node:Node = Node.NONE;
	// resting: not moved until something touches it
	public var sleeping(default, null) = false;
	@:allow(hxmc.physics) var still = 0;

	public function new(shape:Shape, position:Vec3, mass = 1.0) {
		this.shape = shape;
		this.position = position;
		switch shape {
			case Plane(_, _):
				if (mass > 0) throw "hxmc.physics: planes are static (mass 0)";
			case _:
		}
		this.mass = mass;
		invMass = mass > 0 ? 1 / mass : 0;
		invInertia = if (mass <= 0) new Vec3(0, 0, 0) else switch shape {
			case Sphere(r):
				var i = 2 / 5 * mass * r * r;
				new Vec3(1 / i, 1 / i, 1 / i);
			case Box(h):
				var x = 2 * h.x, y = 2 * h.y, z = 2 * h.z;
				new Vec3(12 / (mass * (y * y + z * z)), 12 / (mass * (x * x + z * z)), 12 / (mass * (x * x + y * y)));
			case _: new Vec3(0, 0, 0);
		}
	}

	public inline function isStatic():Bool
		return invMass == 0;

	public function wake() {
		sleeping = false;
		still = 0;
	}

	@:allow(hxmc.physics) function sleep() {
		sleeping = true;
		velocity = new Vec3(0, 0, 0);
		angular = new Vec3(0, 0, 0);
	}

	// the inverse inertia (world space) times v
	public function applyInvInertia(v:Vec3):Vec3 {
		if (isStatic()) return new Vec3(0, 0, 0);
		var local = orientation.conjugate().rotate(v);
		return orientation.rotate(new Vec3(local.x * invInertia.x, local.y * invInertia.y, local.z * invInertia.z));
	}

	// an impulse j at the world point p (null: the centre)
	public function applyImpulse(j:Vec3, ?p:Vec3) {
		if (isStatic()) return;
		velocity = velocity + j * invMass;
		if (p != null) angular = angular + applyInvInertia(cross(p - position, j));
		wake();
	}

	// the velocity of the body's point p
	public inline function velocityAt(p:Vec3):Vec3
		return velocity + cross(angular, p - position);

	static inline function cross(a:Vec3, b:Vec3):Vec3
		return new Vec3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}
