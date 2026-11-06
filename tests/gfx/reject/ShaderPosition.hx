// The vertex stage's varyings have one position(...) (the clip-space position).
// expect: ShaderPosition.hx:20: characters 10-68
// expect: the vertex function: exactly one field of NoPosition is the clip-space position, marked by position(...) where it is built (it has 0)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

@:structInit @:publicFields class NoPosition {
	var color:Vec4;
}

final S = shader({
	vertex: function(v:V):NoPosition return {color: vec4(v.pos, 0, 1)},
	fragment: function(o:NoPosition):Vec4 return o.color
});

class ShaderPosition {
	static function main()
		trace(S.vertexCode);
}
