// The fragment stage takes what the vertex stage returns (in TypeScript: mismatch.ts).
// expect: shader: stage interface mismatch: the fragment function takes Other, but the vertex function returns O
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

typedef Other = {pos:Vec4, color:Vec3};
final S = shader({vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))}, fragment: function(o:Other):Vec4 return vec4(o.color, 1)});

class RejectMismatch {
	static function main()
		trace(S.vertexCode);
}
