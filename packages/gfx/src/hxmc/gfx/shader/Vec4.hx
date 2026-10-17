package hxmc.gfx.shader;

// 4 floats: vec4 in a shader, an immutable value in CPU code (a
// @:hxmc.struct value on hxmc's targets: copied, never allocated; an object
// elsewhere, such as the macro context). The components and swizzles read
// only; the operators are VecBuild's.
@:build(hxmc.gfx.shader.VecBuild.vector(4))
@:forward(x, y, z, w)
abstract Vec4(Vec4Data) {
	public inline function new(x:Float, y:Float, z:Float, w:Float)
		this = new Vec4Data(x, y, z, w);
}

@:hxmc.struct @:noCompletion final class Vec4Data {
	public final x:Float;
	public final y:Float;
	public final z:Float;
	public final w:Float;

	public inline function new(x:Float, y:Float, z:Float, w:Float) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}
}
