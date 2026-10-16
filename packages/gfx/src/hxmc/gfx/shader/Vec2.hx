package hxmc.gfx.shader;

// 2 floats: vec2 in a shader, an immutable value in CPU code (an object,
// which Haxe's inline constructors remove where it does not escape). The
// components and swizzles read only; the operators are VecBuild's.
@:build(hxmc.gfx.shader.VecBuild.vector(2))
@:forward(x, y)
abstract Vec2(Vec2Data) {
	public inline function new(x:Float, y:Float)
		this = new Vec2Data(x, y);
}

@:noCompletion final class Vec2Data {
	public final x:Float;
	public final y:Float;

	public inline function new(x:Float, y:Float) {
		this.x = x;
		this.y = y;
	}
}
