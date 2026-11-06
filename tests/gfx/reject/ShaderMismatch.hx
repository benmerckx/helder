// The fragment stage takes what the vertex stage returns.
// expect: ShaderMismatch.hx:22: characters 12-58
// expect: stage interface mismatch: the fragment function takes Other, but the vertex function returns O
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

@:structInit @:publicFields class Other {
	var pos:Vec4;
	var color:Vec3;
}

final S = shader({
	vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))},
	fragment: function(o:Other):Vec4 return vec4(o.color, 1)
});

class ShaderMismatch {
	static function main()
		trace(S.vertexCode);
}
