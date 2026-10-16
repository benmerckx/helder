// A closure is not shader code.
// expect: ShaderClosure.hx:17: characters 11-29
// expect: shader: a closure is not supported in a shader
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderClosure implements Shaders {
	@:vertex static function vs(v:V):O {
		var f = (x:Float) -> x * 2;
		return {pos: vec4(v.pos, f(0.5), 1)};
	}

	@:fragment static function fs(o:O):Vec4
		return o.pos;

	static function main()
		trace(vertexCode);
}
