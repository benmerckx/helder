// position(...) marks a varying where the vertex stage builds its varyings, nowhere else.
// expect: ShaderPositionElsewhere.hx:17: characters 38-53
// expect: position(...) marks a field of the varyings where the vertex stage builds them
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))},
	fragment: function(o:O):Vec4 return position(o.pos)
});

class ShaderPositionElsewhere {
	static function main()
		trace(S.vertexCode);
}
