// A texture is sampled where it is a parameter, not passed on.
// expect: shader: tint: a texture is not passed to other functions
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderTexturePass implements Shaders {
	@:vertex static function vs(v:V):O
		return {pos: vec4(v.pos, 0, 1)};

	@:fragment static function fs(o:O, t:Texture2D):Vec4
		return tint(t, o.pos.xy);

	static function tint(t:Texture2D, uv:Vec2):Vec4
		return texture(t, uv) * 0.5;

	static function main()
		trace(fragmentCode);
}
