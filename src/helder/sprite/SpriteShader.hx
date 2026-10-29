package helder.sprite;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// SpriteBatch's shader: a quad's corner in drawing units, moved into clip
// space by the view (x' = x * view.x + view.z, y' = y * view.y + view.w),
// the image's texel (premultiplied) times the quad's colour (premultiplied:
// its alpha 0 for an additive sprite, which Blend.Premultiplied then adds).
@:structInit @:publicFields class SpriteVertex {
	var pos:Vec2;
	var uv:Vec2;
	var color:Vec4;
}

@:structInit @:publicFields class SpriteVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
	var color:Vec4;
}

@:structInit @:publicFields class SpriteView {
	var view:Vec4;
}

class SpriteShader implements Shaders {
	@:vertex static function vs(v:SpriteVertex, s:SpriteView):SpriteVaryings
		return {pos: vec4(v.pos.x * s.view.x + s.view.z, v.pos.y * s.view.y + s.view.w, 0, 1), uv: v.uv, color: v.color};

	@:fragment static function fs(i:SpriteVaryings, image:Texture2D):Vec4
		return sample(image, i.uv) * i.color;
}
