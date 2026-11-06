// A stage's parameters are one object after its input, not parameters of their own.
// expect: ShaderParams.hx:17: characters 12-117
// expect: a stage takes its input and one object of parameters ({frame: Frame, image: Texture2D}), not 2
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
	fragment: function(o:O, tex:Texture2D, other:Texture2D):Vec4 return sample(tex, o.pos.xy) * sample(other, o.pos.xy)
});

class ShaderParams {
	static function main()
		trace(S.vertexCode);
}
