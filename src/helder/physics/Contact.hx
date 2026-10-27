package helder.physics;

import helder.gfx.shader.Vec3;

// Two bodies touching at a point: the normal from a to b, how deep they
// overlap (Collide.test's; the world keeps its own in Contacts)
class Contact {
	public final a:Body;
	public final b:Body;
	public final normal:Vec3;
	public final point:Vec3;
	public final depth:Float;

	public function new(a:Body, b:Body, normal:Vec3, point:Vec3, depth:Float) {
		this.a = a;
		this.b = b;
		this.normal = normal;
		this.point = point;
		this.depth = depth;
	}
}
