import Mood.hash2;
import Mood.noise2;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The moth and its young, the caterpillar: each a quad about it (spanned
// by the camera's right and up) on which its parts are laid back to
// front, every part with a surface of its own (a colour, a normal as if
// modelled: domes for the body's segments, the head and the eye, a
// membrane for a wing, turning as it beats, cambered between its veins),
// then lit once by the scene: the glows about it summed on the CPU into
// six lights along the camera's axes and one key light (Afterglow.lights),
// in two hard steps, a glint on what is hard, light through what is thin
// and a shadow under what lies over something. Bodies are kept dark so
// that the rim shows: a crisp band of what glows beside and behind, in
// its own colour (a lantern's pink, the moss's green, the moth's violet);
// what is pale (the wings) takes a light's tint, never its flood. No
// outline, no flat fill: form through light. Drawn once more into the
// target's alpha alone (keyColor.w), where the finish leaves the frame be.
//
// The moth is the reference's: side on, pale wings swept back like a
// cape, feathered antennae in a V, a small dark body (fur combed back, a
// pale collar, jointed legs), lit from within (violet between its
// segments, through its wings). A wing is one plan
// (root, apex, tornus) laid on the screen along the body and out from it
// by how far it is raised: folded it lies back, beating it goes from over
// the back through edge on to under the body, its tip late.
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
	var moth:Vec4; // xyz: where, w: 0 the aura, 1 the moth, 2 the caterpillar
	// the aura: rgb its colour; the moth: x flying (0 standing, 1 in
	// flight), y its wings' beat (radians), z its pitch, w which way it
	// faces (1 right, -1 left, between: turning); the caterpillar: x how far
	// uncurled, y its crawl (seconds), z gone home, w which way it faces
	var color:Vec4;
	// the moth: xy what trails (its speed's change, facing right), z just
	// landed (1, falling to 0), w reaching for the ground; the caterpillar:
	// x crawling (0 to 1), y its head raised to the light
	var more:Vec4;
	var key:Vec4; // xyz: towards the key light (right, up, to the eye), w: a pixel in q
	var keyColor:Vec4;
	// the light from the camera's right, left, above, below, before, behind
	@:length(6) var cube:Array<Vec4>;
}

function segment(q:Vec2, a:Vec2, b:Vec2):Vec2 {
	var pa = q - a, ba = b - a;
	var h = clamp(dot(pa, ba) / dot(ba, ba), 0, 1);
	return vec2(length(pa - ba * h), h);
}

// q turned by a about c
function turn(q:Vec2, c:Vec2, a:Float):Vec2 {
	var d = q - c, co = cos(a), si = sin(a);
	return c + vec2(d.x * co - d.y * si, d.x * si + d.y * co);
}

// how much of a pixel a shape covers, d its distance, px a pixel
function cover(d:Float, px:Float):Float
	return clamp(0.5 - d / px, 0, 1);

// a dome over an ellipse (centre c, radii r, turned by a): xyz its normal, w its distance
function dome(q:Vec2, c:Vec2, r:Vec2, a:Float):Vec4 {
	var d = q - c, co = cos(a), si = sin(a);
	var l = vec2((d.x * co + d.y * si) / r.x, (-d.x * si + d.y * co) / r.y);
	var k = length(l);
	var n = vec2(l.x * co - l.y * si, l.x * si + l.y * co);
	return vec4(n.x, n.y, sqrt(max(1 - k * k, 0.03)), (k - 1) * min(r.x, r.y));
}

// a side a to b of a shape whose corners go anticlockwise, bowed out by
// bow at its middle: x how far outside it, y how far along it
function bowed(q:Vec2, a:Vec2, b:Vec2, bow:Float):Vec2 {
	var ab = b - a, len = length(ab), dir = ab / len;
	var r = q - a;
	var t = clamp(dot(r, dir) / len, 0, 1);
	return vec2(r.x * dir.y - r.y * dir.x - bow * 4 * t * (1 - t), t);
}

// a wing's plan: x along the body from its root, y out from it
final WING_C = vec2(-0.1, -1.0);
final WING_D = vec2(-0.994, 0.1);
// its size
final WING = 0.86;

// where r (from the root) is on a wing's plan when it is raised by sg (1
// flat on to the eye, 0 edge on, -1 under the body), swept by k, its tip
// late by lag: xy the plan's point, z how far raised there
function plan(r:Vec2, sg:Float, k:Float, lag:Float):Vec3 {
	var c1 = (r.x * WING_D.y - r.y * WING_D.x) / (-1.004 * WING), s1 = (WING_C.x * r.y - WING_C.y * r.x) / (-1.004 * WING);
	var g = sg < 0 ? min(sg, -0.07) : max(sg, 0.07);
	var s = clamp(s1 / g, -0.3, 1.4);
	// (its tip late, but never through edge on before its root: no fold)
	var late = sg + lag * min(s * s, 1);
	g = sg < 0 ? min(late, -0.07) : max(late, 0.07);
	s = s1 / g;
	return vec3(c1 - s * k, s, g);
}

// the forewing's plan: x its distance, y its margin's (the hem: scallops,
// a fringe of hairs), z to the nearest vein, w which side of it
function forewing(p:Vec2):Vec4 {
	var inner = bowed(p, vec2(0, 0), vec2(0.71, 0), 0.03);
	var margin = bowed(p, vec2(0.71, 0), vec2(0.75, 0.9), 0.07);
	var costa = bowed(p, vec2(0.75, 0.9), vec2(0, 0), 0.085);
	var hem = margin.x + 0.016 * (1 - abs(sin(margin.y * 28.3))) - 0.03 * pow(noise2(vec2(margin.y * 85, 3.1)), 2);
	var phi = atan2(p.y, p.x) / 0.876;
	var cell = fract(phi * 7 + 0.5) - 0.5;
	return vec4(max(max(inner.x, hem), costa.x), hem, abs(cell) / 7 * 0.876 * length(p), cell);
}

// the hindwing's: rounder, shorter
function hindwing(p:Vec2):Vec4 {
	var inner = bowed(p, vec2(0.12, 0), vec2(0.86, 0), 0.02);
	var o = (p - vec2(0.5, 0.16)) / vec2(0.38, 0.46);
	var round = (length(o) - 1) * 0.38;
	var hem = round - 0.03 * pow(noise2(vec2(atan2(o.y, o.x) * 30, 7.7)), 2);
	var phi = atan2(p.y, p.x - 0.12) / 1.2;
	var cell = fract(phi * 6 + 0.5) - 0.5;
	return vec4(max(inner.x, hem), hem, abs(cell) / 6 * 1.2 * length(p - vec2(0.12, 0)), cell);
}

// a wing's own colour at p of its plan (w: its plan's, as above): pale by
// the body and the costa, dusk towards the hem, two wavering lines across
// it, a ringed spot, dark veins, dust
function wingColor(p:Vec2, w:Vec4):Vec3 {
	var dust = noise2(p * 46) * 0.6 + noise2(p * 140) * 0.4;
	var c = mix(vec3(0.9, 0.86, 0.9), vec3(0.47, 0.42, 0.7), smoothstep(-0.55, -0.02, w.y) * 0.85);
	var line = min(abs(w.y + 0.17 + 0.025 * sin(p.y * 31)) - 0.012, abs(w.y + 0.38 + 0.03 * sin(p.y * 23 + 1)) - 0.008);
	var spot = abs(length(p - vec2(0.45, 0.3)) - 0.035) - 0.012;
	c = mix(c, vec3(0.2, 0.15, 0.4), smoothstep(0.012, -0.004, min(line, spot)) * 0.6);
	c = mix(c, vec3(0.27, 0.22, 0.47), smoothstep(0.009, 0.001, w.z) * smoothstep(0.1, 0.3, length(p)) * 0.6);
	c = mix(c, vec3(0.3, 0.25, 0.5), smoothstep(-0.035, 0.0, w.y) * 0.7);
	return c * (0.78 + 0.3 * dust);
}

// a feathered antenna from a to b, bent by bend: a stem, n fine barbs a
// side slanting to its tip, longest past its middle (wide): x its
// distance, y how far along it (0 to 1)
function fern(q:Vec2, a:Vec2, b:Vec2, n:Float, wide:Float, bend:Float):Vec2 {
	var ab = b - a, len = max(length(ab), 0.001), dir = ab / len;
	var r = q - a;
	var u = dot(r, dir), side = r.x * dir.y - r.y * dir.x;
	side += bend * u * (len - u) / len;
	var v = abs(side);
	var h0 = clamp(u / len, 0, 1);
	var d = length(vec2(u - clamp(u, 0, len), v)) - 0.014 * (1 - 0.6 * h0);
	var cell = len / (n + 0.6);
	for (j in 0...3) {
		var k = clamp(floor(u / cell) - j + 1, 1, n);
		var h = k / (n + 0.6);
		var reach = wide * pow(sin(h * 3.14159), 0.55) * (0.5 + 0.5 * h);
		d = min(d, segment(vec2(u, v), vec2(k * cell, 0), vec2(k * cell + reach * 0.75, reach)).x - 0.007);
	}
	return vec2(d, h0);
}

// a leg: thigh, shin and foot
function leg(q:Vec2, hip:Vec2, knee:Vec2, ankle:Vec2, toe:Vec2):Float {
	var shin = segment(q, knee, ankle);
	return min(min(segment(q, hip, knee).x - 0.015, shin.x - 0.01 + 0.003 * shin.y), segment(q, ankle, toe).x - 0.006);
}

// a point over the ground (x along it, y above it, lift the ground's own
// place) in the frame of a body leaning by an angle (lean: its cosine and sine)
function stood(p:Vec2, lift:Vec2, lean:Vec2):Vec2 {
	var d = p + lift - vec2(0.15, -0.2);
	return vec2(0.15, -0.2) + vec2(d.x * lean.x + d.y * lean.y, d.y * lean.x - d.x * lean.y);
}

// along is the body's way (towards the head), across what is beside it
final ALONG = vec2(0.25, 0.968);
final ACROSS = vec2(0.968, -0.25);

// the light from the camera's axes on what faces n
function around(n:Vec3, x0:Vec4, x1:Vec4, y0:Vec4, y1:Vec4, z0:Vec4, z1:Vec4):Vec3 {
	var m = n * n;
	return (n.x > 0 ? x0.xyz : x1.xyz) * m.x + (n.y > 0 ? y0.xyz : y1.xyz) * m.y + (n.z > 0 ? z0.xyz : z1.xyz) * m.z;
}

final GLOWING = vec3(0.62, 0.3, 1.0);
final EMBER = vec3(1.0, 0.5, 0.1);
// the caterpillar's own light, paler than the moth's
final LILAC = vec3(0.6, 0.36, 1.0);

final MothShader = shader({
	vertex: function(v:MothVertex, p:{view:MothView}):MothVaryings {
		var s = p.view.right.w;
		var w = p.view.moth.xyz + p.view.right.xyz * (v.corner.x * s) + p.view.up.xyz * (v.corner.y * s);
		return {clip: position(p.view.viewProj * vec4(w, 1)), q: v.corner * (p.view.moth.w > 0.5 ? 1.5 : 1.0)};
	},
	fragment: function(i:MothVaryings, p:{view:MothView}):Vec4 {
		var t = p.view.up.w, px = p.view.key.w;
		var q = i.q;
		if (p.view.moth.w < 0.5) {
			var r = length(q);
			var a = exp(-r * r * 3.5) * 0.4 + exp(-r * r * 16) * 0.35;
			return vec4(p.view.color.xyz * a, 0);
		}
		var facing = p.view.color.w < 0 ? -1.0 : 1.0;
		q = vec2(q.x * facing / max(abs(p.view.color.w), 0.3), q.y);
		// (what is laid down so far: its colour, its normal, what it gives
		// off, and x how hard it glints, y how much light passes through,
		// z how much rim it catches, w how open to the light it is)
		var alb = vec3(0, 0, 0), nrm = vec3(0, 0, 1), emi = vec3(0, 0, 0), mat = vec4(0, 0, 1, 1);
		var a = 0.0, theta = 0.0, gone = 0.0, pale = 0.0;
		if (p.view.moth.w < 1.5) {
			var fl = smoothstep(0, 1, p.view.color.x), ph = p.view.color.y;
			var trail = p.view.more.xy, settle = p.view.more.z, reach = p.view.more.w;
			// (most of its quad is empty: nothing is worked out there)
			if (q.x > 1.3 || q.x < -1.3 || (p.view.color.x + settle < 0.001 && abs(q.y - 0.025) > 0.925)) discard();
			// (in flight the body leans forward and bobs against the stroke; landing it dips on its legs)
			theta = p.view.color.z - mix(0.47, 0.55, fl) + 0.1 * settle * sin(settle * 7);
			var dip = 0.07 * sin(settle * 3.14159) * settle + 0.03 * sin(clamp(p.view.color.x * 2, 0, 1) * 3.14159) * (1 - settle);
			// (drawn a little larger about its feet; standing, its body low over them)
			q = (q - vec2(0, -0.6)) / 1.15 + vec2(0, -0.28 + dip - 0.035 * fl * cos(ph - 0.6));
			var crouch = 0.05 * (1 - fl);
			var b = turn(q + vec2(0, crouch), vec2(0.15, -0.2), -theta);
			var root = vec2(0.15, 0.24);
			// (the stroke: quick down, slower up; at rest the wings breathe and now and then fan)
			var idle = 0.03 * (0.5 + 0.5 * sin(t * 1.4)) + 0.3 * pow(max(sin(t * 0.43), 0), 24) * (0.5 + 0.5 * sin(t * 9))
				+ 0.45 * settle * abs(sin(settle * 10));
			var vel = cos(ph + 0.45 * sin(ph));
			var eye = b - vec2(0.262, 0.306);
			for (far in 0...2) {
				var near = far == 0 ? 0.0 : 1.0;
				var el = 0.25 + 1.1 * sin(ph + 0.45 * sin(ph) + 0.35 * (1 - near));
				var sg = mix((far == 0 ? 0.9 : 1.0) - idle, sin(el - 0.15), fl);
				var sweep = 0.16 * cos(el) * fl;
				var lag = -0.2 * vel * fl;
				var shade = far == 0 ? 0.55 : 1.0;
				var at = root + vec2(0.04, 0.012) * (1 - near);
				// (an antenna: behind it all on the far side, before it all on the near)
				var sway = sin(t * 0.9 + near * 1.7) * 0.02 - trail.x * 0.25;
				var tip = far == 0 ? vec2(0.5 + sway, 0.74 - trail.y * 0.2) : vec2(0.1 + sway, 0.8 - trail.y * 0.2);
				var an = fern(b, vec2(0.24 + 0.04 * (1 - near), 0.385), tip, 11, 0.12, far == 0 ? 0.4 : -0.45);
				var ac = cover(an.x, px);
				if (far == 0) {
					alb = mix(alb, vec3(0.75, 0.7, 0.9), ac);
					nrm = mix(nrm, vec3(0, 0.25, 0.8), ac);
					emi = mix(emi, vec3(0.5, 0.42, 0.8) * (0.08 + 0.12 * an.y), ac);
					mat = mix(mat, vec4(0.1, 0.6, 1.2, 0.6), ac);
					pale = mix(pale, 1, ac);
					a = a + ac * (1 - a);
				}
				// (the hindwing, only in flight, then the forewing over it)
				var wr = turn(b - at, vec2(0, 0), -0.33 * (1 - fl));
				var hp = plan(wr, mix(sg, sin(el - 0.5), fl), sweep * 1.5, lag * 1.3);
				var hw = hindwing(hp.xy);
				var hc = cover(hw.x * max(abs(hp.z), 0.25) * WING, px) * fl;
				var fp = plan(wr, sg, sweep, lag);
				var fw = forewing(fp.xy);
				var fc = cover(fw.x * max(abs(fp.z), 0.25) * WING, px);
				for (hind in 0...2) {
					var pl = hind == 0 ? hp : fp;
					var w = hind == 0 ? hw : fw;
					var c = hind == 0 ? hc : fc;
					// (a shadow under it on what it lies over)
					mat = vec4(mat.xyz, mat.w * (1 - 0.45 * near * smoothstep(0.09, 0.0, w.x * max(abs(pl.z), 0.25)) * (1 - c)));
					// (turned from the eye as it comes edge on; cambered between its veins)
					var tilt = sqrt(max(1 - pl.z * pl.z, 0)) * (pl.z < 0 ? -1.0 : 1.0);
					var phi = atan2(pl.y, pl.x);
					var across = normalize(WING_C * -sin(phi) + WING_D * cos(phi));
					var lip = smoothstep(-0.07, 0.0, w.x);
					var away = pl.xy - vec2(0.5, 0.3);
					var n = vec3(WING_D * (-0.75 * tilt) + vec2(-0.12, 0.28) + across * (w.w * 0.9) + normalize(WING_C * away.x + WING_D * (away.y * pl.z)) * (lip * 1.5), max(abs(pl.z), 0.2) * (1 - 0.6 * lip));
					var col = wingColor(pl.xy, w) * (hind == 0 ? vec3(0.8, 0.76, 0.95) : vec3(1, 1, 1));
					// (lit from within, most by the body)
					var inner = exp(-length(pl.xy) * 2.0);
					alb = mix(alb, col, c);
					nrm = mix(nrm, n, c);
					emi = mix(emi, col * vec3(0.74, 0.68, 1.0) * ((0.32 + 0.85 * inner) * shade), c);
					mat = mix(mat, vec4(0.12, 0.3, 0.9, shade), c);
					pale = mix(pale, 1, c);
					a = a + c * (1 - a);
				}
				if (far == 0) {
					// (the body between the wings: jointed legs, the abdomen's
					// segments, violet light between them, the thorax's fur combed
					// back, a pale collar, the head)
					var tuck = fl * (1 - reach);
					var lift = vec2(0, -0.28 + dip + crouch) - trail * (0.3 * fl), lean = vec2(cos(theta), sin(theta));
					var l = min(leg(b, vec2(0.22, 0.03), mix(stood(vec2(0.43, 0.18), lift, lean), vec2(0.34, 0.02), tuck),
						mix(stood(vec2(0.475, 0.014), lift, lean), vec2(0.27, -0.1), tuck), mix(stood(vec2(0.525, 0), lift, lean), vec2(0.25, -0.15), tuck)),
						min(leg(b, vec2(0.19, -0.02), mix(stood(vec2(0.36, 0.12), lift, lean), vec2(0.29, -0.08), tuck),
							mix(stood(vec2(0.35, 0.014), lift, lean), vec2(0.2, -0.19), tuck), mix(stood(vec2(0.395, 0), lift, lean), vec2(0.18, -0.24), tuck)),
							leg(b, vec2(0.14, -0.06), mix(stood(vec2(0.09, 0.13), lift, lean), vec2(0.21, -0.17), tuck),
								mix(stood(vec2(0.03, 0.014), lift, lean), vec2(0.11, -0.29), tuck), mix(stood(vec2(0.075, 0), lift, lean), vec2(0.09, -0.34), tuck))));
					var lc = cover(l, px);
					alb = mix(alb, vec3(0.07, 0.05, 0.12), lc);
					nrm = mix(nrm, vec3(0, 0.5, 0.6), lc);
					emi = mix(emi, vec3(0, 0, 0), lc);
					mat = mix(mat, vec4(0.5, 0, 1.2, 0.9), lc);
					pale = mix(pale, 0, lc);
					a = a + lc * (1 - a);
					var best = vec4(0, 0, -1, 9), band = 0.0;
					for (k in 0...5) {
						var f = k / 4.0;
						var c = mix(vec2(0.155, -0.03), vec2(0.1, -0.27), f) - trail * (0.2 * f * f);
						var s = dome(b, c, vec2(0.095 - 0.05 * f, 0.075 - 0.02 * f), 0.12);
						best = vec4(best.xyz, min(best.w, s.w));
						if (s.w < 0 && s.z > best.z) {
							best = vec4(s.xyz, best.w);
							band = (b.y - c.y) / (0.075 - 0.02 * f);
						}
					}
					var bc = cover(best.w, px);
					var seam = smoothstep(0.6, 0.9, abs(band));
					alb = mix(alb, mix(vec3(0.09, 0.07, 0.16) * (0.7 + 0.6 * noise2(b * 90)), vec3(0.02, 0.01, 0.05), seam), bc);
					nrm = mix(nrm, best.xyz, bc);
					emi = mix(emi, GLOWING * (seam * (0.6 + 0.3 * sin(t * 1.7 - b.y * 9))), bc);
					mat = mix(mat, vec4(0.5, 0.05, 1.3, 1), bc);
					pale = mix(pale, 0, bc);
					a = a + bc * (1 - a);
					var td = b - vec2(0.17, 0.13);
					var along = dot(td, ALONG), across = dot(td, ACROSS);
					var th = dome(b, vec2(0.17, 0.13), vec2(0.115, 0.17), -0.2);
					// (strands lie along the body; tufts break its outline, most at its back)
					var strand = noise2(vec2(across * 75, along * 11 + 3));
					var tuft = noise2(vec2(across * 30 + 5, along * 6));
					var tc = cover(th.w - 0.034 * (tuft - 0.3) * smoothstep(0.08, -0.12, along) - 0.012 * (strand - 0.5), px);
					mat = vec4(mat.xyz, mat.w * (1 - 0.4 * smoothstep(0.06, 0.0, th.w) * (1 - tc)));
					alb = mix(alb, mix(vec3(0.05, 0.04, 0.1), vec3(0.62, 0.57, 0.8), smoothstep(0.45, 0.8, strand) * smoothstep(-0.7, 0.5, th.y + th.x * 0.4)), tc);
					nrm = mix(nrm, vec3(th.xy + ACROSS * ((strand - 0.5) * 0.8), th.z), tc);
					emi = mix(emi, vec3(0.34, 0.3, 0.52) * (smoothstep(0.45, 0.8, strand) * 0.4), tc);
					mat = mix(mat, vec4(0.05, 0.08, 0.3 + 2.2 * noise2(vec2(along * 55, across * 9)), 1), tc);
					pale = mix(pale, 0, tc);
					a = a + tc * (1 - a);
					var hd = dome(b, vec2(0.255, 0.31), vec2(0.066, 0.06), 0.3);
					var hc2 = cover(hd.w - 0.014 * (noise2(b * 60) - 0.4), px);
					mat = vec4(mat.xyz, mat.w * (1 - 0.4 * smoothstep(0.05, 0.0, hd.w) * (1 - hc2)));
					alb = mix(alb, vec3(0.05, 0.04, 0.1) + vec3(0.14, 0.12, 0.2) * (noise2(b * 80) * smoothstep(-0.2, 0.8, hd.y)), hc2);
					nrm = mix(nrm, hd.xyz, hc2);
					emi = mix(emi, vec3(0, 0, 0), hc2);
					mat = mix(mat, vec4(0.3, 0.05, 1.5 * smoothstep(-0.03, -0.005, hd.w), 1), hc2);
					pale = mix(pale, 0, hc2);
					a = a + hc2 * (1 - a);
					// (the collar: a pale ruff where the head meets the thorax)
					var cl = dome(b, vec2(0.212, 0.262), vec2(0.08, 0.026), -0.3);
					var ruff = noise2(vec2(across * 60, 8.3));
					var cc = cover(cl.w - 0.016 * (ruff - 0.4), px);
					mat = vec4(mat.xyz, mat.w * (1 - 0.35 * smoothstep(0.04, 0.0, cl.w) * (1 - cc)));
					alb = mix(alb, mix(vec3(0.3, 0.26, 0.45), vec3(0.8, 0.76, 0.92), ruff), cc);
					nrm = mix(nrm, vec3(cl.xy + ACROSS * ((ruff - 0.5) * 0.6), cl.z), cc);
					emi = mix(emi, vec3(0.4, 0.34, 0.6) * 0.12, cc);
					mat = mix(mat, vec4(0.05, 0.1, 1.2, 1), cc);
					pale = mix(pale, 0.6, cc);
					a = a + cc * (1 - a);
					// (a compound eye: a dark glossy dome, a violet spark deep in it)
					var ey = dome(eye, vec2(0.02, -0.002), vec2(0.032, 0.036), 0.2);
					var ec = cover(ey.w, px);
					alb = mix(alb, vec3(0.02, 0.015, 0.05), ec);
					nrm = mix(nrm, ey.xyz, ec);
					emi = mix(emi, GLOWING * (0.9 * smoothstep(0.014, 0.004, length(eye - vec2(0.029, 0.01)))), ec);
					mat = mix(mat, vec4(2.4, 0, 0.35, 1), ec);
					pale = mix(pale, 0, ec);
				} else {
					// (a shoulder of fur over the wing's root; the near antenna)
					var sd = b - vec2(0.16, 0.2);
					var tg = dome(b, vec2(0.16, 0.2), vec2(0.05, 0.095), 0.35);
					var fur = noise2(vec2(dot(sd, ACROSS) * 80, dot(sd, ALONG) * 10 + 7.3));
					var gc = cover(tg.w - 0.022 * (noise2(vec2(dot(sd, ACROSS) * 34, 2.1)) - 0.3) * smoothstep(0.05, -0.08, dot(sd, ALONG)), px);
					alb = mix(alb, mix(vec3(0.06, 0.05, 0.11), vec3(0.66, 0.6, 0.84), smoothstep(0.45, 0.8, fur) * smoothstep(-0.6, 0.6, tg.y)), gc);
					nrm = mix(nrm, vec3(tg.xy + ACROSS * ((fur - 0.5) * 0.8), tg.z), gc);
					emi = mix(emi, vec3(0.34, 0.3, 0.52) * (smoothstep(0.45, 0.8, fur) * 0.45), gc);
					mat = mix(mat, vec4(0.05, 0.08, 0.3 + 2.2 * noise2(vec2(dot(sd, ALONG) * 55, 4.4)), 1), gc);
					pale = mix(pale, 0, gc);
					a = a + gc * (1 - a);
					alb = mix(alb, vec3(0.86, 0.8, 0.96), ac);
					nrm = mix(nrm, vec3(0, 0.25, 0.9), ac);
					emi = mix(emi, vec3(0.6, 0.52, 0.9) * (0.15 + 0.25 * an.y), ac);
					mat = mix(mat, vec4(0.1, 0.6, 1.3, 1), ac);
					pale = mix(pale, 1, ac);
					a = a + ac * (1 - a);
				}
			}
			// (its own light on its body)
			emi += alb * vec3(0.17, 0.14, 0.3) * (0.3 + 0.7 * pale);
		} else {
			// (the caterpillar: fourteen segments from its tail to its head, laid
			// along the ground, a hump running up them as it crawls, its
			// front raised to the light; asleep wound into a ring, its back out)
			var out = smoothstep(0, 1, p.view.color.x), crawl = p.view.color.y, moving = p.view.more.x, look = p.view.more.y;
			gone = p.view.color.z;
			if (q.y > 0 || abs(q.x) > 0.95) discard();
			var ground = -0.8;
			var op = vec2(-0.6, ground), cp = vec2(-0.02, ground + 0.1);
			var best = vec4(0, 0, -1, 9), local = vec2(0, 0), which = 0.0;
			var legs = 9.0, hairs = vec2(9.0, 0), tail = vec2(0, 0);
			for (k in 0...14) {
				var f = k / 13.0;
				// (thickest behind its middle, the three by its head slighter)
				var r = k == 13 ? 0.08 : 0.072 + 0.036 * sin(f * 2.6 + 0.3) - (k > 9 ? 0.012 : 0.0);
				var wave = 0.5 + 0.5 * sin(crawl * 7.5 - f * 5.5);
				var hump = moving * wave * wave * sin(f * 3.14159);
				var front = smoothstep(0.55, 1.0, f);
				var rise = front * front * (0.1 + 0.22 * look) * (1 - 0.5 * moving) * (1 + 0.15 * sin(t * 1.1));
				var along = vec2(op.x, ground + r + hump * 0.085 + rise);
				var curl = 0.3 + 0.48 * k;
				var c = mix(cp, along, out);
				// (each a dome shorter than it is tall, so they part at deep creases)
				var ang = (curl + 3.14159) * (1 - out);
				var s = dome(q, c, vec2(k == 13 ? r : 0.076, r), ang);
				best = vec4(best.xyz, min(best.w, s.w));
				if (s.w < 0 && s.z > best.z) {
					var d = q - c, co = cos(ang), si = sin(ang);
					best = vec4(s.xyz, best.w);
					local = vec2((d.x * co + d.y * si) / (k == 13 ? r : 0.076), (d.y * co - d.x * si) / r);
					which = k;
				}
				if (k == 0) tail = c;
				if (k > 0 && k < 13) {
					// (thin jointed legs under the three by its head, four pairs
					// of thick feet under its middle, a clasper at its tail)
					var step = 0.03 * sin(crawl * 7.5 - f * 5.5 + 1.2) * moving;
					var foot = segment(q, c + vec2(0, -r * 0.6), vec2(c.x + step + (k > 9 ? 0.025 : 0.0), ground - 0.005 + hump * 0.05 + rise * 0.7)).x
						- (k > 9 ? 0.009 : ((k >= 3 && k <= 6) || k == 1 ? 0.025 : -1.0));
					legs = min(legs, foot + (1 - out) * 0.2);
					// (two bristles on its back, fanned, tapering, leaning back as it goes)
					for (j in 0...2) {
						var ha = ang + 1.5708 + (j - 0.5) * 0.7 + (hash2(vec2(k, j + 3.7)) - 0.5) * 0.5 + 0.18 * sin(t * 1.3 + k + j * 2.1) + 0.3 * moving;
						var dir = vec2(cos(ha), sin(ha));
						var hr = segment(q, c + dir * (r * 0.85), c + dir * (r + 0.03 + 0.08 * hash2(vec2(k + 0.5, j + 9.1))));
						var hd = hr.x - 0.0055 * (1 - 0.8 * hr.y);
						if (hd < hairs.x) hairs = vec2(hd, hr.y);
					}
				}
				if (k == 13) {
					// (two short feelers at its mouth)
					var fd = min(segment(q, c + vec2(0.05, -0.03), c + vec2(0.115, -0.045)).x, segment(q, c + vec2(0.04, -0.045), c + vec2(0.1, -0.075)).x) - 0.005
						+ (1 - out) * 0.2;
					if (fd < hairs.x) hairs = vec2(fd, 0.5);
				}
				op = op + vec2(0.088 * (1 - 0.3 * hump) * (1 - 0.25 * rise), 0);
				cp = cp + vec2(cos(curl), sin(curl)) * 0.1;
			}
			// (a horn on its tail, an ember at its tip)
			var hornTip = tail + mix(vec2(-0.06, 0.1), vec2(-0.12, 0.2), out);
			var horn = segment(q, tail + vec2(-0.02, 0.05), hornTip);
			var hornC = cover(min(horn.x - 0.02 * (1 - 0.75 * horn.y), length(q - hornTip) - 0.016), px);
			alb = mix(alb, vec3(0.06, 0.04, 0.1), hornC);
			nrm = mix(nrm, vec3(0.3, 0.8, 0.3), hornC);
			emi = mix(emi, EMBER * (pow(horn.y, 4) * 3.0 * (0.75 + 0.25 * sin(t * 1.7))), hornC);
			mat = mix(mat, vec4(0.4, 0, 1.2, 1), hornC);
			a = a + hornC * (1 - a);
			var hairC = cover(hairs.x, px);
			alb = mix(alb, vec3(0.3, 0.27, 0.45), hairC);
			nrm = mix(nrm, vec3(0.3, 0.8, 0.3), hairC);
			emi = mix(emi, LILAC * (0.06 + 0.3 * hairs.y * hairs.y), hairC);
			mat = mix(mat, vec4(0, 0.4, 0.8, 1), hairC);
			a = a + hairC * (1 - a);
			var legC = cover(legs, px);
			alb = mix(alb, vec3(0.05, 0.04, 0.09), legC);
			nrm = mix(nrm, vec3(0.3, 0.8, 0.3), legC);
			emi = mix(emi, vec3(0, 0, 0), legC);
			mat = mix(mat, vec4(0.3, 0, 0.3, 0.8), legC);
			a = a + legC * (1 - a);
			var bc = cover(best.w, px);
			// (its hide: dark, a paler speckled plate on each segment's back, a
			// wart where its bristles root, the belly darkest, the creases
			// deep; behind the head a pale hard shield, the moth's collar)
			var head = which > 12.5 ? 1.0 : 0.0, shield = which > 11.5 ? 1.0 - head : 0.0;
			var grit = noise2(q * 70) * 0.6 + noise2(q * 190) * 0.4;
			var crease = smoothstep(0.33, 0.58, abs(local.x));
			var skin = mix(vec3(0.05, 0.04, 0.1), vec3(0.26, 0.22, 0.4), smoothstep(0.05, 0.6, local.y) * (1 - crease) * (0.2 + 1.0 * grit));
			skin = mix(skin, vec3(0.5, 0.45, 0.7), smoothstep(0.17, 0.07, length(local - vec2(0.0, 0.66))) * 0.7);
			skin = mix(skin, vec3(0.5, 0.46, 0.7) * (0.6 + 0.6 * grit), shield * smoothstep(-0.05, 0.3, local.y) * (1 - crease));
			skin = mix(skin, vec3(0.02, 0.015, 0.04), smoothstep(-0.35, -0.8, local.y) * 0.8) * (1 - 0.6 * crease);
			// (its own light: a spot on each segment's side, running from tail
			// to head, violet deep in the creases of its back)
			var spot = smoothstep(0.14, 0.07, length(local - vec2(0.0, -0.22)));
						var pulse = 0.5 + 0.5 * pow(0.5 + 0.5 * sin(t * 2.2 - which * 0.6), 2);
			var marks = LILAC * (spot * 3.2 * pulse) + GLOWING * (smoothstep(0.44, 0.58, abs(local.x)) * smoothstep(-0.1, 0.5, local.y) * (0.5 + 0.4 * pulse));
			// (the head: a dark glossy capsule, a pale band over its crown,
			// three small eyes in an arc)
			var crown = smoothstep(0.08, 0.03, abs(length(local - vec2(-0.55, -0.25)) - 1.0)) * smoothstep(-0.5, 0.0, local.y);
			var eyes = min(length(local - vec2(0.5, 0.1)), min(length(local - vec2(0.64, -0.12)), length(local - vec2(0.5, -0.34))));
			var face = mix(vec3(0.06, 0.045, 0.11), vec3(0.55, 0.5, 0.72), crown * 0.8);
			alb = mix(alb, mix(skin, face, head), bc);
			nrm = mix(nrm, best.xyz, bc);
			emi = mix(emi, mix(marks + skin * vec3(0.6, 0.5, 1.0) * 0.2, LILAC * (smoothstep(0.13, 0.06, eyes) * 1.4) + vec3(0.3, 0.26, 0.46) * (crown * 0.35), head), bc);
			mat = mix(mat, mix(vec4(0.3, 0.06, 1.4, 1), vec4(1.3, 0, 1.6, 1), max(head, shield * 0.6)), bc);
			a = a + bc * (1 - a);
		}
		if (a <= 0.004) discard();
		a *= 1 - gone;
		// (only where it is: the finish leaves it be)
		if (p.view.keyColor.w > 0.5) return vec4(0, 0, 0, a);
		// (the light: the six about it and the key in two hard steps; what
		// is pale takes a light's tint, never its flood; through what is
		// thin; a glint; and the rim, a crisp band of what glows beside and
		// behind in its own colour, on bodies kept dark for it)
		var n = normalize(nrm);
		var co = cos(theta), si = sin(theta);
		n = vec3((n.x * co - n.y * si) * facing, n.x * si + n.y * co, n.z);
		var kd = p.view.key.xyz, kc = p.view.keyColor.xyz;
		var ndl = dot(n, kd);
		var ramp = smoothstep(-0.08, 0.06, ndl) * 0.45 + smoothstep(0.38, 0.5, ndl) * 0.55;
		var ambient = vec3(0.02, 0.024, 0.06) * (0.7 + 0.3 * n.y);
		var lit = around(n, p.view.cube[0], p.view.cube[1], p.view.cube[2], p.view.cube[3], p.view.cube[4], p.view.cube[5]) * 0.5 + kc * ramp;
		var grey = dot(lit, vec3(0.3, 0.5, 0.2));
		lit = mix(lit, vec3(grey), 0.55 * pale) / (1 + grey * 1.6 * pale) * mix(0.6, 1.0, pale);
		var light = ambient + lit;
		var through = around(-n, p.view.cube[0], p.view.cube[1], p.view.cube[2], p.view.cube[3], p.view.cube[4], p.view.cube[5]) * 0.5 + kc * smoothstep(0.0, -0.6, ndl);
		// (what comes through is paler than what it came from)
		grey = dot(through, vec3(0.3, 0.5, 0.2));
		through = mix(through, vec3(grey), 0.6) / (1 + grey * 1.6 * pale);
		var edge = mix(smoothstep(0.5, 0.66, 1 - clamp(n.z, 0, 1)), pow(1 - clamp(n.z, 0, 1), 2.0), pale);
		var beside = normalize(vec3(n.xy, -0.45));
		var glow = around(beside, p.view.cube[0], p.view.cube[1], p.view.cube[2], p.view.cube[3], p.view.cube[4], p.view.cube[5]) * 1.2 + kc * (smoothstep(0.15, 0.6, dot(beside, kd)) * 2.6);
		grey = dot(glow, vec3(0.3, 0.5, 0.2));
		glow = max(mix(vec3(grey), glow, mix(1.5, 0.5, pale)), vec3(0, 0, 0)) * mix(1.0, 0.6, pale) + vec3(0.03, 0.06, 0.14) * (0.5 + 0.5 * n.y);
		var glint = pow(max(dot(n, normalize(kd + vec3(0, 0, 1))), 0), 48) * mat.x;
		var color = alb * (light * mat.w + through * mat.y) + mix(vec3(1, 1, 1), alb * 0.6 + vec3(0.4), pale) * glow * (edge * mat.z)
			+ (kc + vec3(0.05, 0.06, 0.1)) * glint + emi;
		return vec4(color * a, a);
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
