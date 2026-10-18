package hxmc.physics;

import hxmc.gfx.shader.Vec3;

// Two bodies touching: the normal from a to b, how deep they overlap
class Contact {
	public final a:Body;
	public final b:Body;
	public final normal:Vec3;
	public final depth:Float;

	public function new(a:Body, b:Body, normal:Vec3, depth:Float) {
		this.a = a;
		this.b = b;
		this.normal = normal;
		this.depth = depth;
	}
}
