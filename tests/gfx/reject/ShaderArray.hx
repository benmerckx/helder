// Arrays allocate: not in a shader (the error at the array).
// expect: ShaderArray.hx:17: characters 11-21
// expect: arrays are not supported in a shader
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
		var a = [1.0, 2.0];
		return {pos: position(vec4(v.pos, a[0], a[1]))};
	},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderArray {
	static function main()
		trace(S.vertexCode);
}
