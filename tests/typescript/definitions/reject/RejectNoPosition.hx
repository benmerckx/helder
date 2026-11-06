// The varyings have one position(...) (in TypeScript: no-position.ts).
// expect: shader: the vertex function: exactly one field of NoPosition is the clip-space position, marked by position(...) where it is built (it has 0)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

typedef NoPosition = {color:Vec4};
final S = shader({vertex: function(v:V):NoPosition return {color: vec4(v.pos, 0, 1)}, fragment: function(o:NoPosition):Vec4 return o.color});

class RejectNoPosition {
	static function main()
		trace(S.vertexCode);
}
