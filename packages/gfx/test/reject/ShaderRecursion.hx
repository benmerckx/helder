// Shader functions cannot recurse (GLSL, WGSL, MSL and HLSL have no recursion), not even through another function.
// expect: ShaderRecursion.hx:26: characters 27-38
// expect: shader: recursion: ShaderRecursion.even -> ShaderRecursion.odd -> ShaderRecursion.even (shader functions cannot recurse)
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderRecursion implements Shaders {
	@:vertex static function vs(v:V):O
		return {pos: vec4(v.pos, even(3) ? 1 : 0, 1)};

	@:fragment static function fs(o:O):Vec4
		return o.pos;

	static function even(n:Int):Bool
		return n == 0 ? true : odd(n - 1);

	static function odd(n:Int):Bool
		return n == 0 ? false : even(n - 1);

	static function main()
		trace(vertexCode);
}
