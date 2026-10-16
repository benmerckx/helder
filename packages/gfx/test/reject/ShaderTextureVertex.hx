// Textures belong to the fragment stage.
// expect: shader: vs: textures are parameters of the @:fragment function only
import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

@:structInit @:publicFields class V {
	var pos:Vec2;
}

@:structInit @:publicFields class O {
	@:position var pos:Vec4;
}

class ShaderTextureVertex implements Shaders {
	@:vertex static function vs(v:V, t:Texture2D):O
		return {pos: texture(t, v.pos)};

	@:fragment static function fs(o:O):Vec4
		return o.pos;

	static function main()
		trace(vertexCode);
}
