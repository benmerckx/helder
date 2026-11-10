import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The moth and its young, the larva, drawn from a few bold shapes, the
// same for both: a round head with one large dark eye (it blinks; asleep
// it is shut), feathers of a few thick barbs, flat cream with lilac marks,
// a thin violet line about it all, so each reads small on a phone. The
// moth is the reference's: side on, standing, its pale wings swept down
// and back like a cape, their hems in scallops, feathered antennae in a V;
// in flight its wings beat about the shoulder. Its aura is a soft violet
// light about it (additive). Each is a quad about it, spanned by the
// camera's right and up.
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
	var moth:Vec4; // xyz: the moth, w: 0 its aura, 1 the moth, 2 the larva
	// the aura: rgb its colour; the moth: x flying (0 standing, 1 in
	// flight), y its wings' angle, z its lean; the larva: x how far out of
	// its shell, y its crawl's phase, z gone home; w: which way it faces (1: right, -1: left)
	var color:Vec4;
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
		if (p.view.moth.w > 1.5) return larva(q, p.view.color, t);
		// (side on, facing color.w: +1 right, -1 left; standing on its feet
		// at the quad's foot; in flight leaning and its wings turning about
		// the shoulder)
		q = vec2(q.x * p.view.color.w, q.y);
		var fly = p.view.color.x;
		q = turn(q, vec2(0.15, -0.05), -p.view.color.z);
		var shoulder = vec2(0.13, 0.2);
		var breathe = 1 + 0.025 * sin(t * 1.4) * (1 - fly);
		var wq = shoulder + turn(q - shoulder, vec2(0, 0), -p.view.color.y) / breathe;
		var fq = shoulder + turn(q - shoulder, vec2(0, 0), -p.view.color.y * 0.8) / breathe;
		var near = nearWing(wq);
		var far = farWing(fq);
		var body = ellipse(q, vec2(0.17, -0.13), vec2(0.07, 0.25), -0.08);
		var at = vec2(0.27, 0.3);
		var head = length(q - at) - 0.15;
		var sway = sin(t * 0.9) * 0.03;
		var fronds = min(frond(q, vec2(0.2, 0.42), vec2(-0.2 + sway, 0.93), 6, 0.17), frond(q, vec2(0.33, 0.43), vec2(0.8 + sway, 0.86), 6, 0.17));
		// (two short legs, tucked up in flight)
		var tuck = vec2(-0.1, 0.13) * fly;
		var legs = min(segment(q, vec2(0.12, -0.36), vec2(0.06, -0.6) + tuck).x, segment(q, vec2(0.2, -0.36), vec2(0.24, -0.6) + tuck).x) - 0.02;
		var shape = min(min(min(near, far), min(body, head)), min(fronds, legs));
		var a = 1 - smoothstep(LINE - 0.008, LINE + 0.008, shape);
		if (a <= 0.01) discard();
		// (back to front: legs, far wing, body, near wing, fronds, head)
		var c = INK;
		if (far < 0) {
			c = CREAM * vec3(0.84, 0.82, 0.95);
			// (two streaks down it, a spot, a line along its hem)
			var fall = abs(fract((fq.x - fq.y * 0.3) * 6.5 + 0.2) - 0.5) / 6.5 - 0.014;
			fall = max(fall, max(fq.y - 0.0, -0.3 - fq.y));
			var marks = min(fall, min(length(fq - vec2(0.34, 0.06)) - 0.035, abs(far + 0.055) - 0.012));
			c = mix(c, LILAC, smoothstep(0.006, -0.006, marks));
		}
		// (its body banded as its young's)
		if (body < 0 && near > 0) c = mix(CREAM * vec3(0.84, 0.82, 0.95), LILAC, smoothstep(0.1, 0.0, abs(fract(q.y * 6.5 + 0.2) - 0.5) - 0.12));
		if (near < 0) {
			c = CREAM;
			// (as painted on the reference's wing, drawn bold: two crescents,
			// one in the other, high on it; three rays running out to the
			// hem; an oval spot low by the body; a line along the hem)
			var o = wq - vec2(-0.1, 0.0);
			var half = o.y + o.x * 0.7;
			var c1 = max(abs(length(o) - 0.12) - 0.02, half - 0.02);
			var c2 = max(abs(length(o) - 0.23) - 0.023, half + 0.03);
			var ray = min(segment(wq, vec2(-0.3, -0.16), vec2(-0.56, -0.3)).x, segment(wq, vec2(-0.16, -0.24), vec2(-0.3, -0.38)).x) - 0.02;
			var spot = ellipse(wq, vec2(-0.02, -0.27), vec2(0.05, 0.095), 0.35);
			var marks = min(min(c1, c2), min(min(ray, spot), abs(near + 0.06) - 0.015));
			c = mix(c, LILAC, smoothstep(0.006, -0.006, marks));
		}
		if (fronds < 0 && head > 0) c = CREAM * vec3(0.9, 0.86, 1.0);
		if (head < 0) c = face(q - at, 0.15, t, 1);
		// (the line about it)
		c = mix(c, LINED, smoothstep(-0.006, 0.006, shape));
		return vec4(c * 0.8 * a, a);
	}
});

final CREAM = vec3(1.0, 0.95, 0.86);
final LILAC = vec3(0.4, 0.26, 0.84);
final INK = vec3(0.13, 0.09, 0.24);
final LINED = vec3(0.24, 0.16, 0.5);
// how wide the line about a shape is
final LINE = 0.016;

// a head of radius r about the origin: cream, one large dark eye with a
// spark in it, shut by how little awake it is (0: a lash), blinking
function face(q:Vec2, r:Float, t:Float, awake:Float):Vec3 {
	var blink = 1 - smoothstep(0.985, 0.998, sin(t * 1.3));
	var open = max(awake * blink, 0.1);
	var e = (q - vec2(0.3, 0.03) * r) / vec2(1, open);
	var eye = length(e) - 0.43 * r;
	var c = mix(CREAM, INK, smoothstep(0.008, -0.008, eye));
	return mix(c, vec3(0.95, 0.92, 1.0), smoothstep(0.008, -0.008, length(q - vec2(0.42, 0.2) * r) - 0.13 * r) * step(0.6, open));
}

// q turned by a about c
function turn(q:Vec2, c:Vec2, a:Float):Vec2 {
	var d = q - c, co = cos(a), si = sin(a);
	return c + vec2(d.x * co - d.y * si, d.x * si + d.y * co);
}

// the larva, side on, facing c.w: four round segments, each banded
// lilac, and the moth's head, half as large again, with two small
// feathers; a bud of light held up on its tail (it reads in the dark);
// asleep curled into a bun, its eye shut (c.x: 0), uncurling as it wakes,
// inching along as it crawls (c.y), fading as it goes into its cocoon (c.z)
function larva(p:Vec2, c:Vec4, t:Float):Vec4 {
	var q = vec2(p.x * c.w, p.y);
	var out = smoothstep(0, 1, c.x), phase = c.y;
	var best = 9.0, local = vec2(0, 0);
	var tail = vec2(0, 0);
	for (k in 0...4) {
		var f = k / 3.0;
		// (curled: a ring about its head; out: a line along the ground, a wave running up it)
		var turned = 2.6 - f * 4.4;
		var curled = vec2(-0.02 + cos(turned) * 0.3, -0.46 + sin(turned) * 0.27);
		var hump = max(sin(phase * 7 - f * 3.4), 0);
		var r = 0.165 + 0.035 * sin(f * 3.14159);
		var along = vec2(-0.6 + f * 0.72 - hump * 0.04, -0.8 + r + hump * 0.13 * sin(f * 3.14159));
		var at = mix(curled, along, out);
		var d = length(q - at) - mix(0.2, r, out);
		if (k == 0) tail = at;
		if (d < best) {
			best = d;
			local = (q - at) / r;
		}
	}
	var hr = 0.25;
	var headAt = mix(vec2(0.0, -0.5), vec2(0.48, -0.8 + hr + 0.05 + 0.015 * sin(t * 1.3)), out);
	var head = length(q - headAt) - hr;
	// (two small feathers on its head, as its mother's; laid flat asleep)
	var up = out * (0.85 + 0.15 * sin(t * 1.1));
	var feathers = min(frond(q, headAt + vec2(-0.08, 0.21), headAt + vec2(-0.08, 0.21) + vec2(-0.2, 0.36) * up, 3, 0.12),
		frond(q, headAt + vec2(0.08, 0.22), headAt + vec2(0.08, 0.22) + vec2(0.2, 0.36) * up, 3, 0.12)) + (1 - out) * 0.2;
	// (the bud on its tail: a drop of light on a short stalk)
	var budAt = tail + vec2(-0.1, 0.27) * out + vec2(-0.1, 0.1) * (1 - out);
	var stalk = segment(q, tail, budAt).x - 0.02;
	var bud = length(q - budAt) - 0.085;
	var shape = min(min(best, head), min(feathers, min(stalk, bud)));
	var a = 1 - smoothstep(LINE - 0.008, LINE + 0.008, shape);
	if (a <= 0.01) discard();
	var col = INK;
	var glow = vec3(0, 0, 0);
	if (stalk < 0) col = LILAC;
	if (best < 0) {
		// (a band about each segment, its belly in shade)
		col = mix(CREAM, LILAC, smoothstep(0.03, -0.03, abs(local.x + 0.1) - 0.2));
		col = mix(col, col * vec3(0.8, 0.76, 0.95), smoothstep(-0.25, -0.4, local.y));
	}
	if (feathers < 0) col = CREAM * vec3(0.9, 0.86, 1.0);
	if (head < 0) col = face(q - headAt, hr, t, out);
	if (bud < 0) {
		var pulse = 0.75 + 0.25 * sin(t * 1.7);
		col = vec3(1.0, 0.3, 0.75);
		glow = vec3(1.0, 0.1, 0.62) * (1.2 * pulse);
	}
	col = mix(col, LINED, smoothstep(-0.006, 0.006, shape));
	a *= 1 - c.z;
	return vec4((col * 0.8 + glow) * a, a);
}

// the near wing, swept back and down from the shoulder to a long tip, its
// hem three scallops
function nearWing(q:Vec2):Float {
	var tip = vec2(-0.8, -0.36), hem = vec2(0.1, -0.46);
	var d = triangle(q, vec2(0.13, 0.23), tip, hem) - 0.025;
	for (k in 0...3)
		d = min(d, length(q - mix(tip, hem, (k + 0.95) / 3.4) - vec2(0.02, 0.085)) - 0.15);
	return d;
}

// the far wing, hanging before the body on the other side: two scallops
function farWing(q:Vec2):Float {
	var out = vec2(0.52, -0.42), hem = vec2(0.17, -0.42);
	var d = triangle(q, vec2(0.2, 0.2), out, hem) - 0.02;
	for (k in 0...2)
		d = min(d, length(q - mix(hem, out, (k + 0.5) / 2) - vec2(0, 0.06)) - 0.115);
	return d;
}

// a feather from a to b: a stem, n thick barbs a side slanting towards
// its tip, longest past the middle (wide)
function frond(q:Vec2, a:Vec2, b:Vec2, n:Float, wide:Float):Float {
	var ab = b - a, len = max(length(ab), 0.001), dir = ab / len;
	var r = q - a;
	var u = dot(r, dir), v = abs(r.x * dir.y - r.y * dir.x);
	var d = length(vec2(u - clamp(u, 0, len), v)) - 0.017;
	var cell = len / (n + 0.6);
	for (j in 0...2) {
		var k = clamp(floor(u / cell) - j, 1, n);
		var h = k / (n + 0.6);
		var reach = wide * pow(sin(h * 3.14159), 0.6) * (0.55 + 0.45 * h) * (len / 0.65);
		d = min(d, segment(vec2(u, v), vec2(k * cell, 0), vec2(k * cell + reach * 0.55, reach)).x - 0.015);
	}
	return d;
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
