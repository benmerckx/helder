// Strings are not shader values (in TypeScript: string.ts).
// expect: shader: a String is not a shader value
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

final S = shader({vertex: function(v:V):O {
	var s = "pos";
	return {pos: position(vec4(v.pos, s.length, 1))};
}, fragment: function(o:O):Vec4 return o.pos});

class RejectString {
	static function main()
		trace(S.vertexCode);
}
