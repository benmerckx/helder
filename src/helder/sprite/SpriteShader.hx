package helder.sprite;

import helder.gfx.*;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// SpriteBatch's shader: a quad's corner in drawing units, moved into clip
// space by the view (x' = x * view.x + view.z, y' = y * view.y + view.w),
// the image's texel (premultiplied) times the quad's colour (premultiplied:
// its alpha 0 for an additive sprite, which Blend.Premultiplied then adds).
@:structInit @:publicFields class SpriteVertex {
	var pos:Vec2;
	var uv:Vec2;
	var color:Vec4; // four bytes (buffers: UByte4Norm)
}

@:structInit @:publicFields class SpriteVaryings {
	var pos:Vec4;
	var uv:Vec2;
	var color:Vec4;
}

@:structInit @:publicFields class SpriteView {
	var view:Vec4;
}

// the vertex buffer: SpriteQuads' 20 bytes a vertex, the colour four bytes
final buffers:Array<VertexBufferLayout> = [
	{
		stride: SpriteQuads.STRIDE,
		attributes: [
			{location: 0, format: Float2, offset: 0},
			{location: 1, format: Float2, offset: 8},
			{location: 2, format: UByte4Norm, offset: 16}
		]
	}
];

final SpriteShader = shader({
	vertex: function(v:SpriteVertex, p:{s:SpriteView}):SpriteVaryings
		return {pos: position(vec4(v.pos.x * p.s.view.x + p.s.view.z, v.pos.y * p.s.view.y + p.s.view.w, 0, 1)), uv: v.uv, color: v.color},
	fragment: function(i:SpriteVaryings, p:{image:Texture2D}):Vec4
		return sample(p.image, i.uv) * i.color
});
