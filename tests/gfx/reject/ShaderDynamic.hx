// Dynamic has no shader type.
// expect: ShaderDynamic.hx:20: characters 3-23
// expect: shader: Dynamic is not a shader type
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderDynamic implements Shaders {
	@:vertex static function vs(v:V):O
		return {pos: vec4(v.pos, 0, 1)};

	@:fragment static function fs(o:O):Vec4 {
		var d:Dynamic = 0.5;
		return o.pos * (d : Float);
	}

	static function main()
		trace(fragmentCode);
}
