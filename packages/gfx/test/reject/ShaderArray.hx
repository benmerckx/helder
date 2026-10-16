// Arrays allocate: not in a shader (the error at the array).
// expect: ShaderArray.hx:17: characters 11-21
// expect: shader: arrays are not supported in a shader
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderArray implements Shaders {
	@:vertex static function vs(v:V):O {
		var a = [1.0, 2.0];
		return {pos: vec4(v.pos, a[0], a[1])};
	}

	@:fragment static function fs(o:O):Vec4
		return o.pos;

	static function main()
		trace(vertexCode);
}
