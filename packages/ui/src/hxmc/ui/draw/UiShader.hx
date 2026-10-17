package hxmc.ui.draw;

import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The renderer's one shader. Every quad is a rectangle with rounded
// corners (each its own radius: radii) given by its half size, each
// fragment's position relative to its centre (local), so that its edge is
// anti-aliased by the signed distance to it and a border drawn inside it,
// each side its own width (widths), the inner edge a rectangle with
// rounded corners too (mode 0); or a glyph, the atlas's coverage of the
// colour (mode 1); or an image, its texels (premultiplied) times the
// colour's alpha, its corners rounded as a rectangle's (mode 2); or a
// shadow, the rectangle faded over its blur (mode 3). Every fragment is
// also clipped by a rectangle with rounded corners (clip, in target pixels,
// and its corners' radii), from its own position (pixel): clips need no
// scissor and nest on the CPU. Colours are premultiplied
// (Blend.Premultiplied). Corners are top left, top right, bottom right,
// bottom left; sides top, right, bottom, left.
@:structInit @:publicFields class UiVertex {
	var pos:Vec2; // clip space
	var local:Vec2; // pixels from the rectangle's centre
	var half:Vec2; // the rectangle's half size in pixels
	var uv:Vec2; // the texture's coordinates (modes 1 and 2)
	var color:Vec4; // the fill (premultiplied)
	var border:Vec4; // the border's colour (premultiplied)
	var radii:Vec4; // the corners' radii
	var widths:Vec4; // the border's sides
	var params:Vec2; // x: mode, y: blur
	var pixel:Vec2; // the target pixel
	var clip:Vec4; // the clip: x0, y0, x1, y1 in target pixels
	var clipRadii:Vec4; // its corners' radii
}

@:structInit @:publicFields class UiVaryings {
	@:position var pos:Vec4;
	var local:Vec2;
	var half:Vec2;
	var uv:Vec2;
	var color:Vec4;
	var border:Vec4;
	var radii:Vec4;
	var widths:Vec4;
	var params:Vec2;
	var pixel:Vec2;
	var clip:Vec4;
	var clipRadii:Vec4;
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
			radii: v.radii,
			widths: v.widths,
			params: v.params,
			pixel: v.pixel,
			clip: v.clip,
			clipRadii: v.clipRadii
		};

	// the signed distance from p (relative to the centre) to a rectangle
	// with rounded corners, each corner's radius its own (y down)
	static function box(p:Vec2, half:Vec2, r:Vec4):Float {
		var rc = p.x > 0 ? (p.y > 0 ? r.z : r.y) : (p.y > 0 ? r.w : r.x);
		var rr = min(rc, min(half.x, half.y));
		var q = abs(p) - half + vec2(rr, rr);
		return length(max(q, vec2(0, 0))) + min(max(q.x, q.y), 0) - rr;
	}

	// the same for a rectangle whose corners are quarter ellipses (rad: the
	// corner's radii across and down), to the first order in the corners
	static function ellipseBox(p:Vec2, half:Vec2, rad:Vec2):Float {
		var rx = min(rad.x, half.x), ry = min(rad.y, half.y);
		var q = abs(p) - half + vec2(rx, ry);
		if (q.x > 0 && q.y > 0 && rx > 0 && ry > 0) {
			var k = length(q / vec2(rx, ry));
			return (k - 1) * k / length(q / vec2(rx * rx, ry * ry));
		}
		var e = abs(p) - half;
		return length(max(e, vec2(0, 0))) + min(max(e.x, e.y), 0);
	}

	@:fragment static function fs(i:UiVaryings, atlas:Texture2D, image:Texture2D):Vec4 {
		var coverage = sample(atlas, i.uv).x;
		var texel = sample(image, i.uv);
		var ch = (i.clip.zw - i.clip.xy) * 0.5;
		var clipped = clamp(0.5 - box(i.pixel - i.clip.xy - ch, ch, i.clipRadii), 0, 1);
		var mode = i.params.x;
		if (mode > 2.5) {
			var blur = max(i.params.y, 0.5);
			return i.color * (1 - smoothstep(-blur, blur, box(i.local, i.half, i.radii))) * clipped;
		}
		if (mode > 1.5) return texel * i.color.w * clamp(0.5 - box(i.local, i.half, i.radii), 0, 1) * clipped;
		if (mode > 0.5) return i.color * coverage * clipped;
		var d = box(i.local, i.half, i.radii);
		var edge = clamp(0.5 - d, 0, 1);
		// (the inner edge, as CSS has it: the rectangle less each side's width,
		// each corner a quarter ellipse, its radius less the side's width across
		// and the top's or bottom's down)
		var w = i.widths, r = i.radii;
		var inHalf = max(i.half - vec2((w.w + w.y) * 0.5, (w.x + w.z) * 0.5), vec2(0, 0));
		var inP = i.local - vec2((w.w - w.y) * 0.5, (w.x - w.z) * 0.5);
		var rc = inP.x > 0 ? (inP.y > 0 ? r.z : r.y) : (inP.y > 0 ? r.w : r.x);
		var rad = vec2(max(rc - (inP.x > 0 ? w.y : w.w), 0), max(rc - (inP.y > 0 ? w.z : w.x), 0));
		var inBorder = w.x + w.y + w.z + w.w > 0 ? clamp(0.5 + ellipseBox(inP, inHalf, rad), 0, 1) : 0.0;
		return mix(i.color, i.border, inBorder) * edge * clipped;
	}
}
