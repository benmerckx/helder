// Strings are not shader values.
// expect: ShaderString.hx:17: characters 11-16
// expect: shader: a String is not a shader value
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderString implements Shaders {
	@:vertex static function vs(v:V):O {
		var s = "pos";
		return {pos: vec4(v.pos, s.length, 1)};
	}

	@:fragment static function fs(o:O):Vec4
		return o.pos;

	static function main()
		trace(vertexCode);
}
