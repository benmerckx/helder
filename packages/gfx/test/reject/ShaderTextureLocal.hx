// A texture is a parameter, not a local value.
// expect: ShaderTextureLocal.hx:20: characters 3-13
// expect: shader: u: a texture is not a local value
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderTextureLocal implements Shaders {
	@:vertex static function vs(v:V):O
		return {pos: vec4(v.pos, 0, 1)};

	@:fragment static function fs(o:O, t:Texture2D):Vec4 {
		var u = t;
		return texture(u, o.pos.xy);
	}

	static function main()
		trace(fragmentCode);
}
