// A uniform's value is read in a stage, passed on to what it calls (in TypeScript: uniform-helper.ts).
// expect: shader: time.value: a uniform is read in a stage (its value passed on to the functions it calls)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

final time = uniform(0.0);

function later(o:O):Vec4
	return o.pos * time.value;

final S = shader({vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))}, fragment: function(o:O):Vec4 return later(o)});

class RejectUniformHelper {
	static function main()
		trace(S.vertexCode);
}
