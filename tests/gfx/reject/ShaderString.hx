// Strings are not shader values.
// expect: ShaderString.hx:17: characters 11-16
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
	vertex: function(v:V):O {
		var s = "pos";
		return {pos: position(vec4(v.pos, s.length, 1))};
	},
	fragment: function(o:O):Vec4 return o.pos
});

class ShaderString {
	static function main()
		trace(S.vertexCode);
}
