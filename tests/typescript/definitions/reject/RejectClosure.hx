// A closure is not shader code (in TypeScript: closure.ts).
// expect: shader: a closure is not supported in a shader
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

final S = shader({vertex: function(v:V):O {
	var f = (x:Float) -> x * 2;
	return {pos: position(vec4(v.pos, f(0.5), 1))};
}, fragment: function(o:O):Vec4 return o.pos});

class RejectClosure {
	static function main()
		trace(S.vertexCode);
}
