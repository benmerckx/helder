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
// in two soft steps, with a rim from what glows beside and behind it, a
// glint on what is hard, light through what is thin (wings, the
// caterpillar's skin) and a shadow under what lies over something. No
// outline, no flat fill: form through light.
//
// The moth is the reference's: side on, pale wings swept back like a
// cape, feathered antennae in a V, a small furred body, lit from within
// (violet between its segments, through its wings). A wing is one plan
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
	g = sg + lag * s * s;
	g = g < 0 ? min(g, -0.07) : max(g, 0.07);
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

// a leg: thigh and shin
function leg(q:Vec2, hip:Vec2, knee:Vec2, foot:Vec2):Float {
	var shin = segment(q, knee, foot);
	return min(segment(q, hip, knee).x - 0.014, shin.x - 0.011 + 0.006 * shin.y);
}

// the light from the camera's axes on what faces n
function around(n:Vec3, x0:Vec4, x1:Vec4, y0:Vec4, y1:Vec4, z0:Vec4, z1:Vec4):Vec3 {
	var m = n * n;
	return (n.x > 0 ? x0.xyz : x1.xyz) * m.x + (n.y > 0 ? y0.xyz : y1.xyz) * m.y + (n.z > 0 ? z0.xyz : z1.xyz) * m.z;
}

final GLOWING = vec3(0.62, 0.3, 1.0);
final EMBER = vec3(1.0, 0.5, 0.1);

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
		var a = 0.0, theta = 0.0, gone = 0.0;
		if (p.view.moth.w < 1.5) {
			var fl = smoothstep(0, 1, p.view.color.x), ph = p.view.color.y;
			var trail = p.view.more.xy, settle = p.view.more.z, reach = p.view.more.w;
			// (in flight the body leans forward and bobs against the stroke; landing it dips on its legs)
			theta = p.view.color.z - mix(0.45, 0.62, fl) + 0.1 * settle * sin(settle * 7);
			var dip = 0.07 * sin(settle * 3.14159) * settle + 0.03 * sin(clamp(p.view.color.x * 2, 0, 1) * 3.14159) * (1 - settle);
			// (drawn a little larger about its feet; its body low over them)
			q = (q - vec2(0, -0.6)) / 1.15 + vec2(0, -0.28 + dip - 0.035 * fl * cos(ph - 0.6));
			var b = turn(q, vec2(0.15, -0.2), -theta);
			var root = vec2(0.15, 0.24);
			// (the stroke: quick down, slower up; at rest the wings breathe and now and then fan)
			var idle = 0.03 * (0.5 + 0.5 * sin(t * 1.4)) + 0.3 * pow(max(sin(t * 0.43), 0), 24) * (0.5 + 0.5 * sin(t * 9))
				+ 0.45 * settle * abs(sin(settle * 10));
			var vel = cos(ph + 0.45 * sin(ph));
			var eye = b - vec2(0.268, 0.304);
			for (far in 0...2) {
				var near = far == 0 ? 0.0 : 1.0;
				var el = 0.25 + 1.1 * sin(ph + 0.45 * sin(ph) + 0.35 * (1 - near));
				var sg = mix((far == 0 ? 0.9 : 1.0) - idle, sin(el - 0.15), fl);
				var sweep = 0.16 * cos(el) * fl;
				var lag = -0.4 * vel * fl;
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
					a = a + c * (1 - a);
				}
				if (far == 0) {
					// (the body between the wings: legs, the abdomen's segments,
					// violet light between them, the furred thorax, the head)
					var tuck = fl * (1 - reach);
					var feet = vec2(0, -dip) - trail * (0.3 * fl);
					var f0 = turn(vec2(0.5, -0.28) + feet, vec2(0.15, -0.2), -theta), f1 = turn(vec2(0.36, -0.28) + feet, vec2(0.15, -0.2), -theta),
						f2 = turn(vec2(-0.1, -0.28) + feet, vec2(0.15, -0.2), -theta);
					var l = min(leg(b, vec2(0.22, 0.03), mix(vec2(0.36, 0.1), vec2(0.36, 0.0), tuck), mix(f0, vec2(0.27, -0.2), tuck)),
						min(leg(b, vec2(0.19, -0.02), mix(vec2(0.31, 0.0), vec2(0.3, -0.1), tuck), mix(f1, vec2(0.18, -0.3), tuck)),
							leg(b, vec2(0.14, -0.06), mix(vec2(0.04, -0.02), vec2(0.2, -0.2), tuck), mix(f2, vec2(0.08, -0.38), tuck))));
					var lc = cover(l, px);
					alb = mix(alb, vec3(0.3, 0.25, 0.42), lc);
					nrm = mix(nrm, vec3(0, 0, 1), lc);
					emi = mix(emi, vec3(0, 0, 0), lc);
					mat = mix(mat, vec4(0.5, 0, 1.6, 0.9), lc);
					a = a + lc * (1 - a);
					var best = vec4(0, 0, -1, 9), band = 0.0;
					for (k in 0...5) {
						var f = k / 4.0;
						var c = mix(vec2(0.155, -0.03), vec2(0.1, -0.27), f) - trail * (0.2 * f * f);
						var s = dome(b, c, vec2(0.1 - 0.05 * f, 0.075 - 0.02 * f), 0.12);
						best = vec4(best.xyz, min(best.w, s.w));
						if (s.w < 0 && s.z > best.z) {
							best = vec4(s.xyz, best.w);
							band = (b.y - c.y) / (0.075 - 0.02 * f);
						}
					}
					var bc = cover(best.w, px);
					var seam = smoothstep(0.55, 0.9, abs(band));
					alb = mix(alb, mix(vec3(0.2, 0.15, 0.32), vec3(0.05, 0.03, 0.1), seam), bc);
					nrm = mix(nrm, best.xyz, bc);
					emi = mix(emi, GLOWING * (seam * (0.55 + 0.25 * sin(t * 1.7 - b.y * 9))), bc);
					mat = mix(mat, vec4(0.45, 0.1, 1.3, 1), bc);
					a = a + bc * (1 - a);
					var th = dome(b, vec2(0.17, 0.13), vec2(0.13, 0.18), -0.12);
					var ang = atan2(b.y - 0.13, b.x - 0.17);
					var fur = noise2(vec2(ang * 11, 1.3)) * 0.6 + noise2(vec2(ang * 31, 4.1)) * 0.4;
					var tc = cover(th.w - 0.035 * (fur - 0.3), px);
					mat = vec4(mat.xyz, mat.w * (1 - 0.4 * smoothstep(0.06, 0.0, th.w) * (1 - tc)));
					var strand = noise2(vec2(ang * 24, length(b - vec2(0.17, 0.13)) * 9));
					alb = mix(alb, mix(vec3(0.16, 0.13, 0.26), vec3(0.8, 0.76, 0.9), strand * smoothstep(-0.5, 0.7, th.y + th.x * 0.5)), tc);
					nrm = mix(nrm, vec3(th.xy + vec2(cos(ang), sin(ang)) * (strand - 0.5) * 0.5, th.z), tc);
					emi = mix(emi, GLOWING * 0.03, tc);
					mat = mix(mat, vec4(0.05, 0.12, 1.5, 1), tc);
					a = a + tc * (1 - a);
					var hd = dome(b, vec2(0.25, 0.3), vec2(0.078, 0.07), 0.3);
					var hang = atan2(b.y - 0.3, b.x - 0.25);
					var palp = segment(b, vec2(0.3, 0.28), vec2(0.325, 0.262)).x - 0.02;
					var hc2 = cover(min(hd.w, palp) - 0.022 * (noise2(vec2(hang * 10, 2.2)) - 0.35), px);
					mat = vec4(mat.xyz, mat.w * (1 - 0.4 * smoothstep(0.05, 0.0, hd.w) * (1 - hc2)));
					alb = mix(alb, mix(vec3(0.1, 0.08, 0.18), vec3(0.42, 0.36, 0.58), smoothstep(-0.4, 0.8, hd.y) * (0.4 + 0.6 * noise2(b * 70))), hc2);
					nrm = mix(nrm, hd.xyz, hc2);
					emi = mix(emi, vec3(0, 0, 0), hc2);
					mat = mix(mat, vec4(0.05, 0.2, 1.4, 1), hc2);
					a = a + hc2 * (1 - a);
					// (a compound eye: a dark glossy dome, a violet spark deep in it)
					var ey = dome(eye, vec2(0.02, -0.002), vec2(0.03, 0.034), 0.2);
					var ec = cover(ey.w, px);
					alb = mix(alb, vec3(0.03, 0.02, 0.07), ec);
					nrm = mix(nrm, ey.xyz, ec);
					emi = mix(emi, vec3(0, 0, 0), ec);
					mat = mix(mat, vec4(2.2, 0, 0.5, 1), ec);
				} else {
					// (fur over the wing's root; the near antenna)
					var tg = dome(b, vec2(0.165, 0.215), vec2(0.07, 0.085), 0.5);
					var ang = atan2(b.y - 0.215, b.x - 0.165);
					var fur = noise2(vec2(ang * 9, 7.3));
					var gc = cover(tg.w - 0.03 * (fur - 0.4), px);
					alb = mix(alb, mix(vec3(0.2, 0.16, 0.3), vec3(0.85, 0.8, 0.94), fur * smoothstep(-0.5, 0.7, tg.y)), gc);
					nrm = mix(nrm, tg.xyz, gc);
					emi = mix(emi, GLOWING * 0.03, gc);
					mat = mix(mat, vec4(0.05, 0.12, 1.5, 1), gc);
					a = a + gc * (1 - a);
					alb = mix(alb, vec3(0.86, 0.8, 0.96), ac);
					nrm = mix(nrm, vec3(0, 0.25, 0.9), ac);
					emi = mix(emi, vec3(0.6, 0.52, 0.9) * (0.15 + 0.25 * an.y), ac);
					mat = mix(mat, vec4(0.1, 0.6, 1.3, 1), ac);
					a = a + ac * (1 - a);
				}
			}
			// (its own light on its body)
			emi += alb * vec3(0.17, 0.14, 0.3);
		} else {
			// (the caterpillar: twelve segments from its tail to its head, laid
			// along the ground, a hump running up them as it crawls, its
			// front raised to the light; asleep wound into a ring)
			var out = smoothstep(0, 1, p.view.color.x), crawl = p.view.color.y, moving = p.view.more.x, look = p.view.more.y;
			gone = p.view.color.z;
			var ground = -0.8;
			var op = vec2(-0.6, ground), cp = vec2(-0.02, ground + 0.1);
			var best = vec4(0, 0, -1, 9), local = vec2(0, 0), which = 0.0, radius = 0.1;
			var legs = 9.0, hairs = 9.0, tail = vec2(0, 0);
			for (k in 0...14) {
				var f = k / 13.0;
				var r = k == 13 ? 0.08 : 0.085 + 0.04 * sin(f * 2.5 + 0.35);
				var wave = 0.5 + 0.5 * sin(crawl * 7.5 - f * 5.5);
				var hump = moving * wave * wave * sin(f * 3.14159);
				var front = smoothstep(0.55, 1.0, f);
				var rise = front * front * (0.1 + 0.22 * look) * (1 - 0.5 * moving) * (1 + 0.15 * sin(t * 1.1));
				var along = vec2(op.x, ground + r + hump * 0.085 + rise);
				var curl = 0.3 + 0.48 * k;
				var c = mix(cp, along, out);
				var s = dome(q, c, vec2(r, r), 0);
				best = vec4(best.xyz, min(best.w, s.w));
				if (s.w < 0 && s.z > best.z) {
					best = vec4(s.xyz, best.w);
					local = (q - c) / r;
					which = k;
					radius = r;
				}
				if (k == 0) tail = c;
				if (k > 0 && k < 13) {
					// (a foot under it: short and thick behind, thin at the
					// front three; fine hairs on its back, leaning with its way)
					var step = 0.03 * sin(crawl * 7.5 - f * 5.5 + 1.2) * moving;
					var foot = segment(q, c + vec2(0, -r * 0.6), vec2(c.x + step, ground - 0.005 + hump * 0.05 + rise * 0.7)).x - (k > 9 ? 0.01 : (k % 2 == 0 && k < 9 ? 0.022 : -1.0));
					legs = min(legs, foot + (1 - out) * 0.2);
					var h1 = hash2(vec2(k, 3.7)), h2 = hash2(vec2(k, 9.1));
					var lean = mix(curl + 1.57, 1.57, out);
					for (j in 0...2) {
						var ha = lean + (j == 0 ? 0.5 + 0.5 * h1 : -0.2 - 0.6 * h2) + 0.25 * sin(t * 1.3 + k);
						var dir = vec2(cos(ha), sin(ha));
						hairs = min(hairs, segment(q, c + dir * (r * 0.9), c + dir * (r + 0.07 + 0.06 * (j == 0 ? h2 : h1)) + vec2(-0.03 * moving, 0)).x - 0.004);
					}
				}
				op = op + vec2(0.088 * (1 - 0.3 * hump) * (1 - 0.25 * rise), 0);
				cp = cp + vec2(cos(curl), sin(curl)) * 0.1;
			}
			// (a horn on its tail, an ember at its tip)
			var hornTip = tail + mix(vec2(-0.06, 0.1), vec2(-0.12, 0.2), out);
			var horn = segment(q, tail + vec2(-0.02, 0.05), hornTip);
			var hornC = cover(min(horn.x - 0.02 * (1 - 0.75 * horn.y), length(q - hornTip) - 0.016), px);
			alb = mix(alb, vec3(0.12, 0.08, 0.2), hornC);
			emi = mix(emi, EMBER * (pow(horn.y, 4) * 3.0 * (0.75 + 0.25 * sin(t * 1.7))), hornC);
			mat = mix(mat, vec4(0.4, 0, 1.4, 1), hornC);
			a = a + hornC * (1 - a);
			var hairC = cover(hairs, px) * 0.75;
			alb = mix(alb, vec3(0.6, 0.55, 0.8), hairC);
			mat = mix(mat, vec4(0, 0.8, 2.2, 1), hairC);
			a = a + hairC * (1 - a);
			var legC = cover(legs, px);
			alb = mix(alb, vec3(0.1, 0.07, 0.17), legC);
			emi = mix(emi, vec3(0, 0, 0), legC);
			mat = mix(mat, vec4(0.3, 0, 1.2, 0.8), legC);
			a = a + legC * (1 - a);
			var bc = cover(best.w, px);
			// (its skin: dusk on its back, darker at each segment's rear, a
			// pale line along its side, and under it a light in each segment
			// that runs up its length; its head a dark glossy capsule)
			var head = which > 12.5 ? 1.0 : 0.0;
			var skin = mix(vec3(0.5, 0.45, 0.68), vec3(0.2, 0.15, 0.36), smoothstep(0.2, 0.75, local.y));
			skin = mix(skin, vec3(0.88, 0.84, 0.95), smoothstep(0.14, 0.04, abs(local.y + 0.12)) * 0.85);
			skin = mix(skin, vec3(0.2, 0.16, 0.32), smoothstep(-0.25, -0.75, local.y) * 0.8);
			skin = mix(skin, vec3(0.1, 0.07, 0.2), smoothstep(0.2, 0.75, abs(local.x)) * smoothstep(-0.1, 0.4, local.y) * 0.85);
			skin *= (0.75 + 0.5 * noise2(q * 60)) * (1 - 0.45 * smoothstep(0.55, 0.95, abs(local.x)));
			var spot = smoothstep(0.2, 0.06, length(local - vec2(0.05, -0.36))) * (0.5 + 0.5 * cos(which * 3.14159));
			var pulse = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(t * 2.2 - which * 0.6), 2);
			alb = mix(alb, mix(skin, mix(vec3(0.5, 0.32, 0.42), vec3(0.03, 0.02, 0.05), smoothstep(0.03, -0.03, length(local - vec2(0.5, 0.0)) - 0.12)), head), bc);
			nrm = mix(nrm, best.xyz, bc);
			emi = mix(emi, GLOWING * (spot * pulse * (1 - head) * 1.2) + mix(skin * vec3(0.6, 0.5, 1.0) * 0.3, vec3(0.1, 0.06, 0.1), head), bc);
			mat = mix(mat, mix(vec4(0.35, 0.18, 1.3, 1), vec4(0.9, 0, 1.4, 1), head), bc);
			a = a + bc * (1 - a);
		}
		if (a <= 0.004) discard();
		// (the light: the six about it, the key in two soft steps, through
		// what is thin, a rim from beside and behind, a glint)
		var n = normalize(nrm);
		var co = cos(theta), si = sin(theta);
		n = vec3((n.x * co - n.y * si) * facing, n.x * si + n.y * co, n.z);
		var kd = p.view.key.xyz, kc = p.view.keyColor.xyz;
		var ndl = dot(n, kd);
		var ramp = smoothstep(-0.2, 0.05, ndl) * 0.5 + smoothstep(0.3, 0.5, ndl) * 0.5;
		var ambient = vec3(0.02, 0.024, 0.06) * (0.7 + 0.3 * n.y);
		var light = ambient + around(n, p.view.cube[0], p.view.cube[1], p.view.cube[2], p.view.cube[3], p.view.cube[4], p.view.cube[5]) * 0.5 + kc * ramp;
		var through = around(-n, p.view.cube[0], p.view.cube[1], p.view.cube[2], p.view.cube[3], p.view.cube[4], p.view.cube[5]) * 0.5 + kc * smoothstep(0.0, -0.6, ndl);
		// (what comes through is paler than what it came from)
		through = mix(through, vec3(dot(through, vec3(0.3, 0.5, 0.2))), 0.5);
		var edge = pow(1 - clamp(n.z, 0, 1), 2.0);
		var beside = normalize(vec3(n.xy, -0.55));
		var rim = around(beside, p.view.cube[0], p.view.cube[1], p.view.cube[2], p.view.cube[3], p.view.cube[4], p.view.cube[5]) * 2.4 + kc * max(dot(beside, kd), 0) + vec3(0.03, 0.06, 0.13) * (0.5 + 0.5 * n.y);
		var glint = pow(max(dot(n, normalize(kd + vec3(0, 0, 1))), 0), 48) * mat.x;
		var color = alb * (light * mat.w + through * mat.y) + (alb * 0.6 + vec3(0.4)) * rim * (edge * mat.z) + (kc + vec3(0.05, 0.06, 0.1)) * glint + emi;
		a *= 1 - gone;
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
