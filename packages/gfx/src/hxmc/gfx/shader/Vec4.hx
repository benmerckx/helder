package hxmc.gfx.shader;

// 4 floats: vec4 in a shader, an immutable value in CPU code (an object,
// which Haxe's inline constructors remove where it does not escape). The
// components and swizzles read only; the operators are VecBuild's.
@:build(hxmc.gfx.shader.VecBuild.vector(4))
@:forward(x, y, z, w)
abstract Vec4(Vec4Data) {
	public inline function new(x:Float, y:Float, z:Float, w:Float)
		this = new Vec4Data(x, y, z, w);
}

@:noCompletion final class Vec4Data {
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
