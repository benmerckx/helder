// A texture is a parameter, passed on: not a local.
// expect: ShaderTextureLocal.hx:20: characters 3-15
// expect: shader: t: a texture is a parameter, not a local
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

	@:fragment static function fs(o:O, tex:Texture2D):Vec4 {
		var t = tex;
		return sample(t, o.pos.xy);
	}

	static function main()
		trace(vertexCode);
}
