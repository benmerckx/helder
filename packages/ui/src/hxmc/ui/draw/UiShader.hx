package hxmc.ui.draw;

import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The renderer's one shader. Every quad is a rounded rectangle given by its
// half size and corner radius, each fragment's position relative to its
// centre (local), so that its edge is anti-aliased by the signed distance
// to it and a border of borderWidth is drawn inside it (mode 0); or a
// glyph, the atlas's coverage of the colour (mode 1); or an image, its
// texels (premultiplied) times the colour's alpha, its corners rounded as a
// rectangle's (mode 2); or a shadow, the rectangle
// faded over its blur (mode 3). Every fragment is also clipped by a
// rounded rectangle (clip, in target pixels, and its radius: extra.z), from
// its own position (extra.xy): clips need no scissor and nest on the CPU.
// Colours are premultiplied (Blend.Premultiplied).
@:structInit @:publicFields class UiVertex {
	var pos:Vec2; // clip space
	var local:Vec2; // pixels from the rectangle's centre
	var half:Vec2; // the rectangle's half size in pixels
	var uv:Vec2; // the texture's coordinates (modes 1 and 2)
	var color:Vec4; // the fill (premultiplied)
	var border:Vec4; // the border's colour (premultiplied)
	var params:Vec4; // x: radius, y: border width, z: mode, w: blur
	var extra:Vec3; // xy: the target pixel, z: the clip's radius
	var clip:Vec4; // the clip: x0, y0, x1, y1 in target pixels
}

@:structInit @:publicFields class UiVaryings {
	@:position var pos:Vec4;
	var local:Vec2;
	var half:Vec2;
	var uv:Vec2;
	var color:Vec4;
	var border:Vec4;
	var params:Vec4;
	var extra:Vec3;
	var clip:Vec4;
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
			params: v.params,
			extra: v.extra,
			clip: v.clip
		};

	// the signed distance from p (relative to the centre) to a rounded rectangle
	static function box(p:Vec2, half:Vec2, radius:Float):Float {
		var r = min(radius, min(half.x, half.y));
		var q = abs(p) - half + vec2(r, r);
		return length(max(q, vec2(0, 0))) + min(max(q.x, q.y), 0) - r;
	}

	@:fragment static function fs(i:UiVaryings, atlas:Texture2D, image:Texture2D):Vec4 {
		var coverage = texture(atlas, i.uv).x;
		var texel = texture(image, i.uv);
		var ch = (i.clip.zw - i.clip.xy) * 0.5;
		var clipped = clamp(0.5 - box(i.extra.xy - i.clip.xy - ch, ch, i.extra.z), 0, 1);
		var mode = i.params.z;
		if (mode > 2.5) {
			var blur = max(i.params.w, 0.5);
			return i.color * (1 - smoothstep(-blur, blur, box(i.local, i.half, i.params.x))) * clipped;
		}
		if (mode > 1.5) return texel * i.color.w * clamp(0.5 - box(i.local, i.half, i.params.x), 0, 1) * clipped;
		if (mode > 0.5) return i.color * coverage * clipped;
		var d = box(i.local, i.half, i.params.x);
		var edge = clamp(0.5 - d, 0, 1);
		var bw = i.params.y;
		var inBorder = bw > 0 ? clamp(0.5 + d + bw, 0, 1) : 0.0;
		return mix(i.color, i.border, inBorder) * edge * clipped;
	}
}
