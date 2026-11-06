// Shader functions cannot recurse (GLSL, WGSL, MSL and HLSL have no recursion), not even through another function.
// expect: ShaderRecursion.hx:28: characters 27-38
// expect: recursion: ShaderRecursion.even -> ShaderRecursion.odd -> ShaderRecursion.even (shader functions cannot recurse)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V):O return {pos: position(vec4(v.pos, ShaderRecursion.even(3) ? 1 : 0, 1))},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderRecursion {
	static function main()
		trace(S.vertexCode);

	public static function even(n:Int):Bool
		return n == 0 ? true : odd(n - 1);

	static function odd(n:Int):Bool
		return n == 0 ? false : even(n - 1);
}
