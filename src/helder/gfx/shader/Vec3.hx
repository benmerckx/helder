package helder.gfx.shader;

// 3 floats: vec3 in a shader, an immutable value in CPU code (a
// @:hxmc.struct value on hxmc's targets: copied, never allocated; an object
// elsewhere, such as the macro context). The components and swizzles read
// only; the operators are VecBuild's.
@:build(helder.gfx.shader.VecBuild.vector(3))
@:forward(x, y, z)
abstract Vec3(Vec3Data) {
	public inline function new(x:Float, y:Float, z:Float)
		this = new Vec3Data(x, y, z);
}

@:hxmc.struct @:noCompletion final class Vec3Data {
	public final x:Float;
	public final y:Float;
	public final z:Float;

	public inline function new(x:Float, y:Float, z:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
	}
}
