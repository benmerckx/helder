// A function shader code calls is compiled from its source (Sources): what it may not do is an error at its own line.
// expect: ShaderHelper.hx:27: characters 14-18
// expect: a String is not a shader value
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	var pos:Vec4;
}

final S = shader({
	vertex: function(v:V):O return {pos: position(vec4(v.pos, Helpers.twice(0.25), 1))},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderHelper {
	static function main()
		trace(S.vertexCode);
}

class Helpers {
	public static function twice(x:Float):Float
		return x * "ab".length;
}
