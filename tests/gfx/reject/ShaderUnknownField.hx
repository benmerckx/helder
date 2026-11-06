// A shader takes the fields it knows.
// expect: ShaderUnknownField.hx:16: characters 9-66
// expect: shader: the argument has no field vertx (it has vertex, fragment)
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertx: function(v:V):O return {pos: position(vec4(v.pos, 0, 1))},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderUnknownField {
	static function main()
		trace(S.vertexCode);
}
