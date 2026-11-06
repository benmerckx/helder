// Position(...) marks a varying where the vertex stage builds them (in TypeScript: position-elsewhere.ts).
// expect: shader: position(...) marks a field of the varyings where the vertex stage builds them
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

final S = shader({vertex: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))}, fragment: function(o:O):Vec4 return position(o.pos)});

class RejectPositionElsewhere {
	static function main()
		trace(S.vertexCode);
}
