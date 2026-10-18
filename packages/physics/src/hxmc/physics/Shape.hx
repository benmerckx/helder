package hxmc.physics;

import hxmc.gfx.shader.Vec3;

// A body's shape, in the body's frame (centred on its position): a sphere
// of a radius, an axis-aligned box of half extents (static bodies only for
// now: dynamic boxes, capsules and convex hulls need a general contact
// test, GJK, next), or a plane through the origin facing normal (static).
enum Shape {
	Sphere(radius:Float);
	Box(half:Vec3);
	Plane(normal:Vec3, offset:Float);
}
