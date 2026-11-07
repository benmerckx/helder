package helder.ui.draw;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The renderer's one shader, an instanced "uber-quad" (after Rune's,
// anomalyco/rune, MIT): a frame's quads are instances of one quad (its
// corner: the vertex buffer's four), each instance a kind of quad (mode)
// and all it needs, so that a frame is one draw. Every quad is a
// rectangle with rounded corners (each its own radius: radii) given by its
// half size and corners grown by a margin (rect, extent: its anti-aliased
// pixel, a shadow's blur), each fragment's position relative to its centre
// (local), so that its edge is anti-aliased by the signed distance to it
// and a border drawn inside it, each side its own width (widths), the
// inner edge a rectangle with rounded corners too (mode 0); or a glyph, the
// atlas's coverage of the colour, read filtered (params.z: where a
// transform turns it) or at its texels' centres (widths.xy: the atlas's
// size) (mode 1); or an image, its texels (premultiplied) times the
// colour's alpha, its corners rounded as a rectangle's, read clamped to its
// texels' centres (widths: an atlas page's part that is the image's) (mode
// 2); or a shadow, the rectangle blurred by a Gaussian (its standard
// deviation: blur), as Skia blurs CSS's box shadows, not under the box that
// casts it (the rectangle moved back by widths' x, y and shrunk by z: CSS
// clips an outer shadow to outside the border box) (mode 3); or an inset
// shadow, the rectangle's padding box darkened from outside a rectangle
// offset and shrunk by widths' x, y and z (mode 4). Its corners are given
// in clip space and the target's pixels (three of them: a parallelogram,
// the rectangle turned by a transform), as the CPU placed them. Every fragment is also clipped by a
// rectangle with rounded corners (clip, in target pixels, and its corners'
// radii), from its own position (pixel), anti-aliased over a pixel: clips
// need no scissor, nest on the CPU and never split the draw. Colours are
// premultiplied (Blend.Premultiplied). Corners are top left, top right,
// bottom right, bottom left; sides top, right, bottom, left.
@:structInit @:publicFields class UiVertex {
	var corner:Vec2; // the quad's corner: 0 or 1 across and down (the vertex buffer's)
	// (the instance's, one buffer of them: Renderer's)
	var a:Vec4; // its top left corner (grown by the margin): in clip space, then in target pixels
	var b:Vec4; // its top right corner
	var c:Vec4; // its bottom left corner (the bottom right: b + c - a)
	var uv:Vec4; // the texture's coordinates at the top left and bottom right (modes 1 and 2)
	var extent:Vec4; // the rectangle's half size, then the corners' place from its centre (the half size plus the margin)
	var color:Vec4; // the fill (premultiplied)
	var border:Vec4; // the border's colour (premultiplied)
	var radii:Vec4; // the corners' radii
	var widths:Vec4; // the border's sides
	var params:Vec4; // x: mode, y: blur, z: the texture (mode 1: filtered, mode 2: its slot)
	var clip:Vec4; // the clip: x0, y0, x1, y1 in target pixels
	var clipRadii:Vec4; // its corners' radii
}

@:structInit @:publicFields class UiVaryings {
	var pos:Vec4;
	var local:Vec2;
	var half:Vec2;
	var uv:Vec2;
	var color:Vec4;
	var border:Vec4;
	var radii:Vec4;
	var widths:Vec4;
	var params:Vec4;
	var pixel:Vec2;
	var clip:Vec4;
	var clipRadii:Vec4;
}

// the signed distance from p (relative to the centre) to a rectangle
// with rounded corners, each corner's radius its own (y down)
function box(p:Vec2, half:Vec2, r:Vec4):Float {
	var rc = p.x > 0 ? (p.y > 0 ? r.z : r.y) : (p.y > 0 ? r.w : r.x);
	var rr = min(rc, min(half.x, half.y));
	var q = abs(p) - half + vec2(rr, rr);
	return length(max(q, vec2(0, 0))) + min(max(q.x, q.y), 0) - rr;
}

// the same for a rectangle whose corners are quarter ellipses (rad: the
// corner's radii across and down), to the first order in the corners
function ellipseBox(p:Vec2, half:Vec2, rad:Vec2):Float {
	var rx = min(rad.x, half.x), ry = min(rad.y, half.y);
	var q = abs(p) - half + vec2(rx, ry);
	if (q.x > 0 && q.y > 0 && rx > 0 && ry > 0) {
		var k = length(q / vec2(rx, ry));
		return (k - 1) * k / length(q / vec2(rx * rx, ry * ry));
	}
	var e = abs(p) - half;
	return length(max(e, vec2(0, 0))) + min(max(e.x, e.y), 0);
}

// erf, approximated (Abramowitz and Stegun 7.1.27), on two values
function erf2(x:Vec2):Vec2 {
	var s = sign(x), a = abs(x);
	var r = vec2(1, 1) + (vec2(0.278393, 0.278393) + (vec2(0.230389, 0.230389) + a * a * 0.078108) * a) * a;
	r = r * r;
	return s - s / (r * r);
}

// a row of the blurred rectangle: its coverage at x, y blurred along x
// (the row's half width narrowed by the corner)
function blurRow(x:Float, y:Float, sigma:Float, corner:Float, half:Vec2):Float {
	var delta = min(half.y - corner - abs(y), 0);
	var curved = half.x - corner + sqrt(max(0, corner * corner - delta * delta));
	var integral = vec2(0.5, 0.5) + erf2((vec2(x, x) + vec2(-curved, curved)) * (0.70710678 / sigma)) * 0.5;
	return integral.y - integral.x;
}

function gauss(y:Float, sigma:Float):Float
	return exp(-(y * y) / (2 * sigma * sigma)) / (2.5066283 * sigma);

// a rectangle with rounded corners blurred by a Gaussian at p (from its
// centre): rows blurred exactly, summed over the column at four points
function blurred(p:Vec2, half:Vec2, r:Vec4, sigma:Float):Float {
	var rc = p.x > 0 ? (p.y > 0 ? r.z : r.y) : (p.y > 0 ? r.w : r.x);
	var corner = min(rc, min(half.x, half.y));
	var low = p.y - half.y, high = p.y + half.y;
	var y0 = clamp(-3 * sigma, low, high), y1 = clamp(3 * sigma, low, high);
	var dy = (y1 - y0) / 4;
	var y = y0 + dy * 0.5;
	var a = blurRow(p.x, p.y - y, sigma, corner, half) * gauss(y, sigma);
	a += blurRow(p.x, p.y - (y + dy), sigma, corner, half) * gauss(y + dy, sigma);
	a += blurRow(p.x, p.y - (y + 2 * dy), sigma, corner, half) * gauss(y + 2 * dy, sigma);
	a += blurRow(p.x, p.y - (y + 3 * dy), sigma, corner, half) * gauss(y + 3 * dy, sigma);
	return a * dy;
}

final UiShader = shader({
	vertex: function(v:UiVertex):UiVaryings {
		// (the bottom right corner from the others: exactly theirs where the quad is not turned)
		var c = v.corner, e = v.extent, a = v.a, b = v.b, l = v.c;
		var d = vec4(b.x + (l.x - a.x), l.y + (b.y - a.y), b.z + (l.z - a.z), l.w + (b.w - a.w));
		var q = c.x > 0.5 ? (c.y > 0.5 ? d : b) : (c.y > 0.5 ? l : a);
		return {
			pos: position(vec4(q.x, q.y, 0, 1)),
			local: vec2(c.x > 0.5 ? e.z : -e.z, c.y > 0.5 ? e.w : -e.w),
			half: e.xy,
			uv: vec2(c.x > 0.5 ? v.uv.z : v.uv.x, c.y > 0.5 ? v.uv.w : v.uv.y),
			color: v.color,
			border: v.border,
			radii: v.radii,
			widths: v.widths,
			params: v.params,
			pixel: q.zw,
			clip: v.clip,
			clipRadii: v.clipRadii
		};
	},
	fragment: function(i:UiVaryings, p:{atlas:Texture2D, image:Texture2D}):Vec4 {
		// (the textures read only by the modes that draw them, filtered: a
		// glyph at its texels' centres where not, an image clamped to its texels)
		var ch = (i.clip.zw - i.clip.xy) * 0.5;
		var clipped = clamp(0.5 - box(i.pixel - i.clip.xy - ch, ch, i.clipRadii), 0, 1);
		var mode = i.params.x;
		if (mode > 3.5) {
			// (the padding box less the blurred inner rectangle)
			var o = i.widths;
			var inner = max(i.half - vec2(o.z, o.z), vec2(0, 0));
			var ir = max(i.radii - vec4(o.z, o.z, o.z, o.z), vec4(0, 0, 0, 0));
			var q = i.local - o.xy;
			var lit = i.params.y > 0.01 ? blurred(q, inner, ir, i.params.y) : clamp(0.5 - box(q, inner, ir), 0, 1);
			return i.color * (1 - lit) * clamp(0.5 - box(i.local, i.half, i.radii), 0, 1) * clipped;
		}
		if (mode > 2.5) {
			var a = i.params.y > 0.01 ? blurred(i.local, i.half, i.radii, i.params.y) : clamp(0.5 - box(i.local, i.half, i.radii), 0, 1);
			var o = i.widths;
			var caster = max(i.half - vec2(o.z, o.z), vec2(0, 0));
			var cr = max(i.radii - vec4(o.z, o.z, o.z, o.z), vec4(0, 0, 0, 0));
			var under = o.w > 0 ? clamp(0.5 - box(i.local + o.xy, caster, cr), 0, 1) : 0.0;
			return i.color * a * (1 - under) * clipped;
		}
		if (mode > 1.5) {
			var uv = clamp(i.uv, i.widths.xy, i.widths.zw);
			return sample(p.image, uv) * i.color.w * clamp(0.5 - box(i.local, i.half, i.radii), 0, 1) * clipped;
		}
		if (mode > 0.5) {
			var size = i.widths.xy;
			var uv = i.params.z > 0.5 ? i.uv : (floor(i.uv * size) + vec2(0.5, 0.5)) / size;
			return i.color * sample(p.atlas, uv).x * clipped;
		}
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
});
