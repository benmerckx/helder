// A shader takes the fields it knows (in TypeScript: unknown-field.ts).
// expect: shader: the argument has no field vertx (it has vertex, fragment)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

final S = shader({vertx: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))}, fragment: function(o:O):Vec4 return o.pos});

class RejectUnknownField {
	static function main()
		trace(S.vertexCode);
}
