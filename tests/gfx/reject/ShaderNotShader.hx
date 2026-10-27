// Shader code calls only the functions of shader classes (Shaders): another class's were typed with inlining, for the CPU only.
// expect: ShaderNotShader.hx:17: characters 28-47
// expect: shader: Helpers.twice is not a shader function
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderNotShader implements Shaders {
	@:vertex static function vs(v:V):O
		return {pos: vec4(v.pos, Helpers.twice(0.25), 1)};

	@:fragment static function fs(o:O):Vec4
		return o.pos;

	static function main()
		trace(vertexCode);
}

class Helpers {
	public static function twice(x:Float):Float
		return x * 2;
}
