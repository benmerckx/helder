// A stage's object of parameters is read by its fields (in TypeScript: params-whole.ts).
// expect: shader: p, the stage's parameters, is read by its fields (p.name): it is no shader value
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};
typedef Tint = {color:Vec4};

final S = shader({vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))}, fragment: function(o:O, p:{tint:Tint}):Vec4 {
	var q = p;
	return q.tint.color;
}});

class RejectParamsWhole {
	static function main()
		trace(S.vertexCode);
}
