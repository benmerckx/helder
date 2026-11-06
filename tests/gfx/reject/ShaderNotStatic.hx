// A definition's argument is static: literals, objects, functions, constants.
// expect: ShaderNotStatic.hx:18: characters 16-22
// expect: shader: stages is not static
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

class ShaderNotStatic {
	static function main() {
		var stages = {vertex: (v:V) -> ({pos: position(vec4(v.pos, 0, 1))} : O), fragment: (o:O) -> o.pos};
		trace(shader(stages).vertexCode);
	}
}
