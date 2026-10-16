package hxmc.gfx.shader;

// 3 floats: vec3 in a shader, an immutable value in CPU code (an object,
// which Haxe's inline constructors remove where it does not escape). The
// components and swizzles read only; the operators are VecBuild's.
@:build(hxmc.gfx.shader.VecBuild.vector(3))
@:forward(x, y, z)
abstract Vec3(Vec3Data) {
	public inline function new(x:Float, y:Float, z:Float)
		this = new Vec3Data(x, y, z);
}

@:noCompletion final class Vec3Data {
	public final x:Float;
	public final y:Float;
	public final z:Float;

	public inline function new(x:Float, y:Float, z:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
}
