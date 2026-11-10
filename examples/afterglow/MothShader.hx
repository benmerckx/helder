import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The moth: a paper cutout seen side on, drawn from shapes as the
// reference's moth is (its wings folded down and back like a cape, fern
// antennae in a V, a round head with a dark eye, thin legs), breathing
// where it stands; and its aura, a soft violet light about it (additive). Both are
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
	var color:Vec4; // rgb: the aura's colour, w: which way the moth faces (1: right, -1: left)
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
		// (side on, facing color.w: +1 right, -1 left; standing on its feet
		// at the quad's foot, the wings folded down and back like a cape)
		q = vec2(q.x * p.view.color.w, q.y);
		var shoulder = vec2(0.14, 0.2);
		var breathe = 1 + 0.025 * sin(t * 1.4);
		var wq = shoulder + (q - shoulder) / breathe;
		var near = nearWing(wq);
		var far = farWing(wq);
		var body = ellipse(q, vec2(0.15, -0.1), vec2(0.075, 0.27), -0.08);
		var head = length(q - vec2(0.27, 0.27)) - 0.105;
		var eye = length(q - vec2(0.31, 0.275)) - 0.04;
		// (antennae: two fern fronds in a V from the head, swaying a little)
		var sway = sin(t * 0.9) * 0.03;
		var back = frond(q, vec2(0.22, 0.36), vec2(-0.22 + sway, 0.84));
		var front = frond(q, vec2(0.3, 0.36), vec2(0.75 + sway, 0.78));
		var fronds = min(back, front);
		// (thin dark legs to the ground)
		var legs = min(min(segment(q, vec2(0.08, -0.36), vec2(-0.16, -0.6)).x, segment(q, vec2(0.12, -0.38), vec2(0.0, -0.61)).x),
			segment(q, vec2(0.18, -0.38), vec2(0.2, -0.6)).x) - 0.014;
		var shape = min(min(min(near, far), min(body, head)), min(fronds, legs));
		var edge = 0.012;
		var a = 1 - smoothstep(-edge, edge, shape);
		if (a <= 0.01) discard();
		// (back to front: legs, far wing, body, near wing, fronds, head)
		var cream = vec3(1.0, 0.95, 0.86), lilac = vec3(0.6, 0.48, 0.92);
		var c = vec3(0.16, 0.11, 0.26);
		if (far < 0) {
			c = mix(cream, vec3(0.8, 0.74, 0.92), 0.35) * mix(0.72, 0.92, smoothstep(-0.45, 0.1, q.y));
			var ring = abs(length((q - vec2(0.34, -0.12)) / vec2(1, 1.8)) - 0.07);
			c = mix(c, lilac, smoothstep(0.022, 0.008, ring) * 0.8);
			c = mix(c, lilac, smoothstep(-0.03, -0.008, far) * 0.6);
		}
		if (body < 0 && near > 0) c = vec3(0.56, 0.48, 0.72);
		if (near < 0) {
			c = cream * mix(0.8, 1.0, smoothstep(-0.45, 0.15, wq.y));
			// (lilac crescents and a loop, as painted on the reference's wing)
			var c1 = abs(length(wq - vec2(-0.17, -0.06)) - 0.17);
			c1 = max(c1, -(length(wq - vec2(-0.24, -0.15)) - 0.15));
			var c2 = abs(length(wq - vec2(-0.5, -0.24)) - 0.09);
			c2 = max(c2, -(length(wq - vec2(-0.55, -0.31)) - 0.08));
			var loop = abs(length((wq - vec2(-0.12, -0.3)) / vec2(1, 2.6)) - 0.15);
			var marks = min(min(c1, c2), loop * 0.6);
			c = mix(c, lilac, smoothstep(0.024, 0.01, marks) * 0.85);
			// (veins from the shoulder, faint; a lilac hem)
			var d = wq - shoulder;
			var vein = abs(sin(d.y / max(length(d), 0.01) * 14));
			c = mix(c, lilac, smoothstep(0.1, 0.0, vein) * 0.15 * smoothstep(0.25, 0.6, length(d)));
			c = mix(c, lilac, smoothstep(-0.035, -0.01, near) * 0.55);
		}
		if (fronds < 0 && head > 0) c = vec3(0.86, 0.8, 0.98);
		if (head < 0) {
			c = cream * mix(0.86, 1.0, smoothstep(0.17, 0.36, q.y + q.x * 0.3));
			c = mix(c, vec3(0.05, 0.03, 0.1), smoothstep(0.006, -0.006, eye));
			c = mix(c, vec3(0.9, 0.86, 1.0), smoothstep(0.016, 0.004, length(q - vec2(0.322, 0.29))));
		}
		if (legs < 0 && min(min(near, far), body) > 0) c = vec3(0.16, 0.11, 0.26);
		return vec4(c * 0.95 * a, a);
	}
});

// the near wing, swept back and down from the shoulder to a long tip, its
// hem scalloped
function nearWing(q:Vec2):Float {
	var d = triangle(q, vec2(0.13, 0.22), vec2(-0.76, -0.33), vec2(0.08, -0.44)) - 0.03;
	d = min(d, ellipse(q, vec2(-0.3, -0.33), vec2(0.42, 0.11), -0.12));
	var along = dot(q - vec2(-0.76, -0.33), vec2(0.993, -0.12));
	return d + 0.03 * pow(abs(cos(along * 11)), 10) * smoothstep(-0.18, -0.36, q.y);
}

// the far wing, hanging behind the body on the other side
function farWing(q:Vec2):Float {
	var d = min(ellipse(q, vec2(0.33, -0.15), vec2(0.15, 0.31), 0.22), triangle(q, vec2(0.17, 0.22), vec2(0.42, -0.05), vec2(0.17, -0.25)));
	return d + 0.025 * pow(abs(cos(q.x * 30)), 10) * smoothstep(-0.3, -0.44, q.y);
}

// a feathered antenna from a to b: a stem, its barbs slanting towards the tip, longest midway
function frond(q:Vec2, a:Vec2, b:Vec2):Float {
	var ab = b - a, len = length(ab), dir = ab / len;
	var r = q - a;
	var u = dot(r, dir), v = r.x * dir.y - r.y * dir.x;
	var h = clamp(u / len, 0, 1);
	var stem = length(r - dir * (h * len)) - 0.012;
	var w = 0.11 * pow(sin(h * 3.14159), 0.7) * (0.4 + 0.6 * h);
	var barb = abs(fract((u - abs(v) * 0.9) * 22) - 0.5) / 22 - 0.008;
	var inside = max(abs(v) - w, max(-u, u - len));
	return min(stem, max(barb, inside));
}

// a triangle's signed distance
function triangle(p:Vec2, p0:Vec2, p1:Vec2, p2:Vec2):Float {
	var e0 = p1 - p0, e1 = p2 - p1, e2 = p0 - p2;
	var v0 = p - p0, v1 = p - p1, v2 = p - p2;
	var q0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0, 1);
	var q1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0, 1);
	var q2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0, 1);
	var s = sign(e0.x * e2.y - e0.y * e2.x);
	var d = min(min(dot(q0, q0), dot(q1, q1)), dot(q2, q2));
	var inside = min(min(s * (v0.x * e0.y - v0.y * e0.x), s * (v1.x * e1.y - v1.y * e1.x)), s * (v2.x * e2.y - v2.y * e2.x));
	return inside > 0 ? -sqrt(d) : sqrt(d);
}

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
