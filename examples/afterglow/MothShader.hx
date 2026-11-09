import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The moth: a paper cutout facing the eye, drawn from shapes (wings,
// body, feathered antennae) whose wings fold towards the body as they
// beat; and its aura, a soft violet light about it (additive). Both are
// a quad about the moth, spanned by the camera's right and up.
@:structInit @:publicFields class MothVertex {
	var corner:Vec2;
}

@:structInit @:publicFields class MothVaryings {
	var clip:Vec4;
	var q:Vec2;
}

@:structInit @:publicFields class MothView {
	var viewProj:Mat4;
	var right:Vec4; // the camera's right, w: the quad's half size
	var up:Vec4; // the camera's up, w: seconds
	var moth:Vec4; // xyz: the moth, w: 0 its aura, 1 the moth
	var color:Vec4; // rgb: the aura's colour
}

// an ellipse's distance (approximate) at q, radii r, turned by a
function ellipse(q:Vec2, c:Vec2, r:Vec2, a:Float):Float {
	var d = q - c;
	var x = d.x * cos(a) + d.y * sin(a), y = -d.x * sin(a) + d.y * cos(a);
	var k = length(vec2(x / r.x, y / r.y));
	return (k - 1) * min(r.x, r.y);
}

function segment(q:Vec2, a:Vec2, b:Vec2):Vec2 {
	var pa = q - a, ba = b - a;
	var h = clamp(dot(pa, ba) / dot(ba, ba), 0, 1);
	return vec2(length(pa - ba * h), h);
}

// a convex quad's signed distance (corners anticlockwise)
function quadShape(q:Vec2, a:Vec2, b:Vec2, c:Vec2, d:Vec2):Float {
	var e0 = segment(q, a, b).x, e1 = segment(q, b, c).x, e2 = segment(q, c, d).x, e3 = segment(q, d, a).x;
	var dist = min(min(e0, e1), min(e2, e3));
	var inside = side(q, a, b) * side(q, b, c) > 0 && side(q, c, d) * side(q, d, a) > 0 && side(q, a, b) * side(q, c, d) > 0;
	return inside ? -dist : dist;
}

function side(q:Vec2, a:Vec2, b:Vec2):Float
	return (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x);

final MothShader = shader({
	vertex: function(v:MothVertex, p:{view:MothView}):MothVaryings {
		var s = p.view.right.w;
		var w = p.view.moth.xyz + p.view.right.xyz * (v.corner.x * s) + p.view.up.xyz * (v.corner.y * s);
		return {clip: position(p.view.viewProj * vec4(w, 1)), q: v.corner};
	},
	fragment: function(i:MothVaryings, p:{view:MothView}):Vec4 {
		var t = p.view.up.w;
		var q = i.q;
		if (p.view.moth.w < 0.5) {
			var r = length(q);
			var a = exp(-r * r * 3.5) * 0.45 + exp(-r * r * 16) * 0.45;
			return vec4(p.view.color.xyz * a, 0);
		}
		// (the wings' beat: slow, a tremble at the top of each; they fold towards the body)
		var beat = sin(t * 5.5);
		var fold = 0.72 + 0.28 * (0.5 + 0.5 * beat);
		var x = abs(q.x);
		var wq = vec2(x / fold, q.y);
		var fore = quadShape(wq, vec2(0.04, 0.14), vec2(0.74, 0.46), vec2(0.62, 0.02), vec2(0.06, -0.12)) - 0.04;
		var hind = ellipse(wq, vec2(0.24, -0.26), vec2(0.27, 0.17), -0.55);
		var wing = min(fore, hind);
		var body = min(ellipse(q, vec2(0, -0.14), vec2(0.07, 0.3), 0), length(q - vec2(0, 0.18)) - 0.075);
		// (antennae: a curved stem, its feathers a comb fanning off it)
		var s = segment(vec2(x, q.y), vec2(0.03, 0.22), vec2(0.24, 0.66));
		var bentX = x - 0.05 * sin(s.y * 3.14);
		s = segment(vec2(bentX, q.y), vec2(0.03, 0.22), vec2(0.24, 0.66));
		var comb = 0.55 + 0.45 * sin(s.y * 50);
		var feather = s.x - (0.016 + 0.06 * sin(s.y * 3.0) * comb);
		var shape = min(min(wing, body), feather);
		var edge = 0.014;
		var a = 1 - smoothstep(-edge, edge, shape);
		if (a <= 0.01) discard();
		// (pale wings, lilac at their edges, two faint bands; the body warmer)
		var cream = vec3(1.0, 0.96, 0.9), lilac = vec3(0.8, 0.72, 1.0);
		var c = mix(cream, lilac, smoothstep(0.2, 0.75, length(wq - vec2(0.05, 0.05))));
		c *= mix(0.78, 1.0, smoothstep(-0.3, 0.3, q.y));
		var band = abs(length(wq - vec2(0.02, 0.1)) - 0.36);
		c *= 1 - 0.18 * smoothstep(0.03, 0.0, band) * step(fore, 0.0);
		c = mix(c, vec3(0.55, 0.48, 0.7), step(body, 0.0));
		c = mix(c, vec3(0.86, 0.82, 0.98), step(feather, 0.0) * step(0.0, min(wing, body)));
		var rim = smoothstep(-0.035, -0.004, min(wing, body));
		c = mix(c, vec3(0.42, 0.3, 0.7), rim * 0.6);
		return vec4(c * 0.95 * a, a);
	}
});

// the motes: spores and fireflies drifting in the mist, each a quad
// moved by the GPU from its seed (nothing per frame on the CPU)
@:structInit @:publicFields class MoteVertex {
	var corner:Vec2;
	var seed:Vec4; // xyz: where it drifts about, w: a seed
}

@:structInit @:publicFields class MoteVaryings {
	var clip:Vec4;
	var q:Vec2;
	var color:Vec4;
}

final MoteShader = shader({
	vertex: function(v:MoteVertex, p:{view:MothView}):MoteVaryings {
		var t = p.view.up.w, k = v.seed.w;
		var rise = fract(t * (0.012 + 0.02 * fract(k * 7.3)) + k * 3.7);
		var at = v.seed.xyz
			+ vec3(sin(t * 0.3 + k * 40) * 0.6 + sin(t * 0.71 + k * 17) * 0.25, (rise - 0.5) * 3, cos(t * 0.23 + k * 29) * 0.5);
		var size = 0.028 + 0.02 * fract(k * 13.1);
		var w = at + p.view.right.xyz * (v.corner.x * size) + p.view.up.xyz * (v.corner.y * size);
		var hue = fract(k * 5.17);
		var c = hue < 0.78 ? vec3(0.55, 1.0, 0.1) : (hue < 0.95 ? vec3(0.15, 0.6, 1.0) : vec3(1.0, 0.2, 0.7));
		var blink = max(0, sin(t * (0.8 + fract(k * 3.3)) + k * 50));
		var fade = sin(rise * 3.14159);
		return {clip: position(p.view.viewProj * vec4(w, 1)), q: v.corner, color: vec4(c * (blink * blink * fade * 4), 0)};
	},
	fragment: function(i:MoteVaryings, p:{}):Vec4 {
		var r = length(i.q);
		return vec4(i.color.xyz * max(0, 1 - r * r), 0);
	}
});
