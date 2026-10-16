package hxmc.ui.draw;

import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The renderer's one shader. Every quad is a rounded rectangle given by its
// half size and corner radius, each fragment's position relative to its
// centre (local), so that its edge is anti-aliased by the signed distance
// to it and a border of borderWidth is drawn inside it (mode 0); or a
// glyph, the atlas's coverage of the colour (mode 1); or an image, its
// texels tinted by the colour's alpha (mode 2). Colours are premultiplied
// (Blend.Premultiplied).
@:structInit @:publicFields class UiVertex {
	var pos:Vec2; // clip space
	var local:Vec2; // pixels from the rectangle's centre
	var half:Vec2; // the rectangle's half size in pixels
	var uv:Vec2; // the texture's coordinates (modes 1 and 2)
	var color:Vec4; // the fill (premultiplied)
	var border:Vec4; // the border's colour (premultiplied)
	var params:Vec4; // x: radius, y: border width, z: mode
}

@:structInit @:publicFields class UiVaryings {
	@:position var pos:Vec4;
	var local:Vec2;
	var half:Vec2;
	var uv:Vec2;
	var color:Vec4;
	var border:Vec4;
	var params:Vec4;
}

class UiShader implements Shaders {
	@:vertex static function vs(v:UiVertex):UiVaryings
		return {
			pos: vec4(v.pos, 0, 1),
			local: v.local,
			half: v.half,
			uv: v.uv,
			color: v.color,
			border: v.border,
			params: v.params
		};

	@:fragment static function fs(i:UiVaryings, atlas:Texture2D, image:Texture2D):Vec4 {
		var coverage = texture(atlas, i.uv).x;
		var texel = texture(image, i.uv);
		var mode = i.params.z;
		if (mode > 1.5) return texel * i.color.w;
		if (mode > 0.5) return i.color * coverage;
		var r = min(i.params.x, min(i.half.x, i.half.y));
		var q = abs(i.local) - i.half + vec2(r, r);
		var d = length(max(q, vec2(0, 0))) + min(max(q.x, q.y), 0) - r;
		var edge = clamp(0.5 - d, 0, 1);
		var bw = i.params.y;
		var inBorder = bw > 0 ? clamp(0.5 + d + bw, 0, 1) : 0.0;
		return mix(i.color, i.border, inBorder) * edge;
	}
}
