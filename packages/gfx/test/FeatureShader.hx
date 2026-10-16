import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// FeatureScene's shader: a solid colour (mode 0), an R8 mask's coverage of
// the colour (mode 1), or an RGBA8 image tinted by it (mode 2); the colour
// is premultiplied, for Blend.Premultiplied
@:structInit @:publicFields class FeatureVertex {
	var pos:Vec2;
	var uv:Vec2;
	var color:Vec4;
	var mode:Float;
}

@:structInit @:publicFields class FeatureVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
	var color:Vec4;
	var mode:Float;
}

class FeatureShader implements Shaders {
	@:vertex static function vs(v:FeatureVertex):FeatureVaryings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv, color: v.color, mode: v.mode};

	@:fragment static function fs(i:FeatureVaryings, mask:Texture2D, image:Texture2D):Vec4 {
		var m = texture(mask, i.uv).x;
		var c = texture(image, i.uv);
		if (i.mode < 0.5) return i.color;
		if (i.mode < 1.5) return i.color * m;
		return c * i.color;
	}
}
