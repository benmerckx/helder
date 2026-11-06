// A definition's argument is static (in TypeScript: not-static.ts).
// expect: shader: stages is not static
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

typedef V = {pos:Vec2};
typedef O = {pos:Vec4};

class RejectNotStatic {
	static function main() {
		var stages = {vertex: (v:V) -> ({pos: position(vec4(v.pos, 0, 1))} : O), fragment: (o:O) -> o.pos};
		trace(shader(stages).vertexCode);
	}
}
