package hxmc.physics;

import hxmc.gfx.shader.Vec3;
import hxmc.scene.Node;

// A rigid body: its shape, its position and velocity (no rotation yet: the
// shapes that move are spheres), its mass (0: static, never moved), how
// much it bounces (restitution, 0 to 1) and grips (friction). A body
// attached to a node (PhysicsWorld.add with a node) writes its position to
// the node after each step.
class Body {
	public final shape:Shape;
	public var position:Vec3;
	public var velocity:Vec3 = new Vec3(0, 0, 0);
	public final mass:Float;
	public final invMass:Float;
	public var restitution = 0.3;
	public var friction = 0.4;
	public var node:Node = Node.NONE;
	// resting: not moved until something touches it
	public var sleeping(default, null) = false;
	@:allow(hxmc.physics) var still = 0;

	public function new(shape:Shape, position:Vec3, mass = 1.0) {
		this.shape = shape;
		this.position = position;
		this.mass = mass;
		invMass = mass > 0 ? 1 / mass : 0;
		switch shape {
			case Sphere(_):
			case _:
				if (mass > 0) throw "hxmc.physics: only spheres move for now (boxes and planes are static: mass 0)";
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
	}

	public function applyImpulse(j:Vec3) {
		if (isStatic()) return;
		velocity = velocity + j * invMass;
		wake();
	}
}
