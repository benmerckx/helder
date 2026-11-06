// A closure is not shader code.
// expect: ShaderClosure.hx:17: characters 11-29
// expect: a closure is not supported in a shader
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V):O {
		var f = (x:Float) -> x * 2;
		return {pos: position(vec4(v.pos, f(0.5), 1))};
	},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderClosure {
	static function main()
		trace(S.vertexCode);
}
