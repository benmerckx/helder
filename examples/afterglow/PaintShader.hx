import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The ruins' one shader: every surface of the diorama (Ruins) painted
// from its kind, in linear light for the HDR target. Stone is blocks
// drawn from the world's coordinates, moss creeps over the tops and drips
// down the faces, roots are near black; what glows (moss's tips, veins,
// mushrooms, sprouts, the lanterns) is emissive and lights what is near
// it through the lights' texture (Ruins.lights: two RGBA16F texels a
// light). The moth's violet aura lights too. A piece that moves is drawn
// as built, posed (moved and turned) by the view's pose.
@:structInit @:publicFields class PaintVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var kind:Vec4; // x: the kind, y: the top of its solid (moss), z: a seed, w: a kind's own
	var anchor:Vec4; // xyz: what it hangs from, w: how far it sways (radians)
}

@:structInit @:publicFields class PaintVaryings {
	var clip:Vec4;
	var world:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var kind:Vec4;
}

@:structInit @:publicFields class PaintView {
	var viewProj:Mat4;
	var eye:Vec4; // w: seconds
	var moth:Vec4; // xyz: the moth, w: its aura's radius
	var aura:Vec4; // rgb: the aura's light
	var pose:Vec4; // a piece's: x, y moved, z turned (radians) about pivot
	var pivot:Vec4; // xy: the pivot, z: a lantern's light (0 dark), w: how much the moth's light hints at it
	var flags:Vec4; // x: 1 into the reflection, y: the lights' count, z: the mist's density
}

inline var STONE = 0;
inline var ROOT = 1;
inline var STRAND = 2;
inline var CAP = 3;
inline var STEM = 4;
inline var BULB = 5;
inline var CAGE = 6;
inline var CORE = 7;
inline var VEIN = 8;
inline var PAD = 9;
inline var SKY = 10;
inline var MOSS = 11;

function acid():Vec3
	return vec3(0.55, 1.0, 0.06);

function cyan():Vec3
	return vec3(0.12, 0.55, 1.0);

function magenta():Vec3
	return vec3(1.0, 0.1, 0.62);

function violet():Vec3
	return vec3(0.55, 0.25, 1.0);


function sway(p:Vec3, anchor:Vec4, t:Float, seed:Float):Vec3 {
	if (anchor.w <= 0) return p;
	var a = sin(t * 0.9 + seed * 6.28) * anchor.w, b = sin(t * 0.7 + seed * 3.1 + 1.3) * anchor.w * 0.6;
	var r = p - anchor.xyz;
	var x = r.x * cos(a) - r.y * sin(a), y = r.x * sin(a) + r.y * cos(a);
	var z = r.z * cos(b) - y * sin(b);
	y = r.z * sin(b) + y * cos(b);
	return anchor.xyz + vec3(x, y, z);
}

// a glow's light on a point: lights' texture, two texels each
function glow(lights:Texture2D, count:Float, p:Vec3, n:Vec3):Vec3 {
	var sum = vec3(0, 0, 0);
	var k = 0.0;
	while (k < count) {
		var v = (k + 0.5) / 32;
		var a = sampleLevel(lights, vec2(0.25, v), 0), c = sampleLevel(lights, vec2(0.75, v), 0);
		var d = a.xyz - p, dist2 = dot(d, d), r2 = a.w * a.w;
		if (dist2 < r2) {
			var fall = 1 - dist2 / r2;
			var wrap = dot(n, d * inversesqrt(max(dist2, 0.0001))) * 0.6 + 0.4;
			sum += c.xyz * (c.w * fall * fall * max(wrap, 0) / (1 + dist2 * 2));
		}
		k += 1;
	}
	return sum;
}

// stone blocks on a face: (albedo's shade, mortar's 0 to 1)
function blocks(world:Vec3, n:Vec3, seed:Float):Vec2 {
	var an = abs(n);
	var flat = an.y > 0.7 ? world.xz : (an.x > an.z ? world.zy : world.xy);
	// (courses drawn by hand: wavering, blocks of uneven size)
	var uv = flat + vec2(noise2(flat * 0.9 + vec2(seed)) - 0.5, noise2(flat * 1.3 + vec2(4.1, seed)) - 0.5) * 0.14;
	var rowH = 0.3;
	var row = floor(uv.y / rowH);
	var w = 0.42 + 0.3 * hash2(vec2(row, seed + 5));
	var u = uv.x + hash2(vec2(row, seed)) * 3.0;
	var col = floor(u / w);
	var f = vec2(fract(u / w) * w, fract(uv.y / rowH) * rowH);
	var edge = min(min(f.x, w - f.x), min(f.y, rowH - f.y));
	var chip = noise2(uv * 11) * 0.04;
	var mortar = (1 - smoothstep(0.012, 0.035 + chip, edge)) * smoothstep(0.25, 0.5, noise2(uv * 2.7 + vec2(seed * 3)));
	var lip = an.y > 0.7 ? 0 : smoothstep(0.06, 0.0, rowH - f.y) * (1 - mortar);
	var shade = 0.6 + 0.6 * hash2(vec2(col, row) + vec2(seed * 7.1, 3));
	return vec2(shade * (0.75 + 0.5 * fbm2(uv * 2.3)) + lip * 0.5, mortar);
}

// the mist darkening as one looks up, the same on the ruins as behind them
function high(d:Vec3):Float
	return mix(1.0, 0.45, smoothstep(0.3, 0.85, d.y));

// the mist's colour as painted: mottled, slanted beams falling through it,
// darker upwards, and glowing low in the deep distance (far at depth)
function fog(d:Vec3, far:Float):Vec3 {
	var beams = pow(noise2(vec2(d.x * 9 + d.y * 3.5, 0.3)), 4) * smoothstep(-0.1, 0.5, d.y);
	var mottle = fbm2(vec2(d.x * 4, d.y * 7));
	var low = exp(-max(d.y + 0.02, 0) * 9) * far;
	return mist(d) * ((0.75 + 0.45 * mottle + beams * 3 + low * 1.4) * high(d));
}

final PaintShader = shader({
	vertex: function(v:PaintVertex, p:{view:PaintView}):PaintVaryings {
		var w = sway(v.pos, v.anchor, p.view.eye.w, v.kind.z);
		var n = v.anchor.w > 0 ? normalize(sway(v.pos + v.normal, v.anchor, p.view.eye.w, v.kind.z) - w) : v.normal;
		var c = cos(p.view.pose.z), s = sin(p.view.pose.z), r = w.xy - p.view.pivot.xy;
		w = vec3(p.view.pivot.x + r.x * c - r.y * s + p.view.pose.x, p.view.pivot.y + r.x * s + r.y * c + p.view.pose.y, w.z);
		n = vec3(n.x * c - n.y * s, n.x * s + n.y * c, n.z);
		return {clip: position(p.view.viewProj * vec4(w, 1)), world: w, normal: n, uv: v.uv, kind: v.kind};
	},
	fragment: function(i:PaintVaryings, p:{view:PaintView, lights:Texture2D}):Vec4 {
		if (p.view.flags.x > 0.5 && i.world.y < -0.02) discard();
		var kind = floor(i.kind.x + 0.5);
		var n = normalize(i.normal);
		var toEye = p.view.eye.xyz - i.world;
		var dist = length(toEye);
		var dir = -toEye / dist;
		if (dot(n, toEye) < 0 && kind != SKY) n = -n;
		var t = p.view.eye.w, seed = i.kind.z;
		var albedo = vec3(0.1, 0.09, 0.16);
		var emit = vec3(0, 0, 0);
		var open = 1.0;
		var detail = smoothstep(34, 10, dist);
		if (kind == STONE) {
			var b = blocks(i.world, n, seed);
			var tone = mix(0.85, b.x, detail);
			albedo = mix(vec3(0.05, 0.045, 0.1), vec3(0.13, 0.11, 0.22), clamp(tone - 0.35, 0, 1)) * (1 - b.y * 0.45 * detail);
			albedo *= 0.55 + 0.45 * smoothstep(-0.5, 3.5, i.world.y) * (0.7 + 0.6 * noise2(i.world.xy * 0.35 + vec2(seed)));
			// (moss: the mesh's share of it, its edge broken up; glowing specks in it)
			var share = i.uv.y + (fbm2(i.world.xz * 4.5 + i.world.yy * 2.5 + vec2(seed)) - 0.5) * 0.6;
			var cover = smoothstep(0.42, 0.56, share);
			// (hanging from the top above, in strands of uneven length, in clumps; their tips glow)
			var below = i.kind.y;
			var along = abs(n.x) > abs(n.z) ? i.world.z : i.world.x;
			var strand = floor(along * 26);
			var clump = smoothstep(0.25, 0.7, noise2(vec2(along * 2.3, seed * 3)));
			var len = (0.03 + 0.85 * pow(hash2(vec2(strand, seed)), 4)) * clump + 0.04;
			var hang = (below < len && below > 0.03 && n.y < 0.35) ? 1 : 0;
			var tip = smoothstep(len - 0.12, len, below) * hang;
			cover = max(cover, hang);
			var moss = mix(vec3(0.035, 0.07, 0.02), vec3(0.12, 0.24, 0.035), fbm2(i.world.xz * 6 + i.world.yy * 3));
			albedo = mix(albedo, moss, cover);
			var cell = i.world * 18;
			var spot = length(fract(cell) - vec3(0.5));
			var speck = step(0.93, hash2(floor(cell.xz) + floor(cell.yy) * 7.1 + vec2(seed))) * smoothstep(0.42, 0.15, spot);
			var fringe = smoothstep(0.3, 0.45, share) * (1 - smoothstep(0.45, 0.6, share));
			emit += acid() * ((cover * 0.012 + speck * cover * 0.9 * detail + fringe * 0.05 + tip * 0.35 * detail) * (0.75 + 0.25 * sin(t * 1.3 + seed * 9)));
			open = i.uv.x;
		} else if (kind == ROOT) {
			// (bark: long fibres, knots, and a violet sheen only where the fibres catch it)
			var fibre = noise2(vec2(i.uv.x * 3, i.uv.y * 40)) * 0.55 + noise2(vec2(i.uv.x * 11, i.uv.y * 120)) * 0.45;
			var knot = smoothstep(0.75, 0.9, noise2(vec2(i.uv.x * 4, i.uv.y * 14) + vec2(seed)));
			albedo = mix(vec3(0.015, 0.012, 0.03), vec3(0.08, 0.055, 0.13), fibre) * (1 - knot * 0.6);
			var sheen = pow(1 - abs(dot(n, dir)), 3) * smoothstep(0.35, 0.8, fibre);
			emit = vec3(0.16, 0.08, 0.4) * (sheen * 0.22);
		} else if (kind == STRAND) {
			albedo = vec3(0.05, 0.1, 0.02);
			var tip = smoothstep(0.55, 1.0, i.uv.y);
			emit = acid() * (0.03 + tip * tip * tip * 1.8 * i.kind.w) * (0.8 + 0.2 * sin(t * 1.7 + seed * 11));
		} else if (kind == CAP) {
			// (a cap: dim on top with paler spots, its rim bright, its gills glowing beneath)
			var color = i.kind.w > 0.5 ? acid() : cyan();
			var r = i.uv.x;
			var under = step(0.5, i.uv.y);
			var spots = step(0.72, noise2(vec2(r * 7, i.uv.y * 3) + vec2(seed * 20)));
			var gills = 0.55 + 0.45 * abs(sin(r * 40 + seed * 3));
			var rim = smoothstep(0.7, 1.0, r);
			albedo = color * 0.2;
			var top = 0.18 + 0.25 * r + spots * 0.35 + rim * 1.6;
			emit = color * (mix(top, 1.4 * gills, under) * (0.85 + 0.15 * sin(t * 1.1 + seed * 7)));
		} else if (kind == STEM) {
			var color = i.kind.w > 0.5 ? acid() : cyan();
			albedo = vec3(0.12, 0.13, 0.18);
			emit = color * (0.08 + 0.2 * i.uv.y);
		} else if (kind == BULB) {
			albedo = magenta() * 0.3;
			emit = magenta() * (2.2 * (0.75 + 0.25 * sin(t * 2.3 + seed * 13)));
		} else if (kind == CAGE) {
			var a = abs(fract(i.uv.x * 5 + i.uv.y * 3) - 0.5), b = abs(fract(i.uv.x * 5 - i.uv.y * 3) - 0.5);
			var ring = abs(fract(i.uv.y * 4) - 0.5);
			if (min(min(a, b), ring * 1.4) > 0.09 && i.uv.y > 0.06 && i.uv.y < 0.94) discard();
			albedo = vec3(0.05, 0.035, 0.06);
		} else if (kind == CORE) {
			emit = magenta() * (9 * p.view.pivot.z * (0.85 + 0.15 * sin(t * 1.9 + seed * 5)));
			albedo = vec3(0, 0, 0);
		} else if (kind == VEIN) {
			var pulse = 0.65 + 0.35 * sin(i.uv.y * 9 - t * 0.8 + seed * 4);
			albedo = vec3(0.1, 0.2, 0.02);
			emit = acid() * (0.9 * pulse * (0.5 + 0.5 * i.kind.w));
		} else if (kind == PAD) {
			var r = length(i.uv - vec2(0.5)) * 2;
			albedo = mix(vec3(0.03, 0.09, 0.05), vec3(0.1, 0.2, 0.06), noise2(i.uv * 12));
			emit = acid() * (smoothstep(0.82, 1.0, r) * smoothstep(0.3, 0.7, noise2(i.uv * 5 + vec2(seed * 9))) * 0.3 * i.kind.w) + acid() * 0.008;
		} else if (kind == MOSS) {
			var f = fbm2(i.world.xz * 7 + i.world.yy * 5);
			albedo = mix(vec3(0.03, 0.06, 0.015), vec3(0.1, 0.2, 0.03), f);
			var speck = step(0.985, hash2(floor(i.world.xz * 16) + vec2(floor(i.world.y * 16), seed)));
			emit = acid() * ((0.015 + speck * 1.1) * (0.8 + 0.2 * sin(t * 1.3 + seed * 9)));
		} else if (kind == SKY) {
			// (the far mist itself, brighter than the mist on the ruins: they
			// stand dark against it; darkening upwards, pale shafts falling in)
			var x = i.world.x, y = i.world.y;
			var shafts = pow(noise2(vec2(x * 0.11 + y * 0.015, 0.5)), 3) * smoothstep(-5, 50, y) * smoothstep(110, 40, y);
			var clouds = fbm2(vec2(x * 0.03, y * 0.06));
			var deep = exp(-(x * x) / 2000) * exp(-max(y - 2, 0) / 22);
			// (high up, a violet veil and the ghosts of taller ruins, upright streaks in the mist)
			var ghosts = smoothstep(0.55, 0.8, noise2(vec2(x * 0.09, 0.2))) * smoothstep(20, 60, y) * smoothstep(100, 60, y);
			var veil = exp(-((x - 10) * (x - 10)) / 900) * smoothstep(25, 70, y);
			var c = fog(dir, 1) * (0.92 + clouds * 0.35 + shafts * 3 + deep * 2.5 - ghosts * 0.35) + vec3(0.03, 0.012, 0.06) * veil;
			return vec4(c, 1);
		}
		// (light: a cool glow from the mist behind and above, the sky's ambient, the glows, the moth's aura)
		var back = normalize(vec3(0.15, 0.55, -1));
		var rim = pow(1 - max(dot(n, -dir), 0), 3) * max(dot(n, back) * 0.5 + 0.5, 0);
		var ambient = mix(vec3(0.03, 0.03, 0.07), vec3(0.12, 0.1, 0.26), n.y * 0.5 + 0.5) * 0.22;
		var light = ambient + vec3(0.08, 0.16, 0.34) * (max(dot(n, back), 0) * 0.25 + rim * 0.9);
		// (no glow reaches the far planes)
		if (i.world.z > -20) light += glow(p.lights, p.view.flags.y, i.world, n);
		var m = p.view.moth.xyz - i.world, md = length(m);
		var auraFall = clamp(1 - md / p.view.moth.w, 0, 1);
		light += p.view.aura.xyz * (auraFall * auraFall * (dot(n, m / max(md, 0.001)) * 0.5 + 0.5));
		// (a piece the moth's light is about to move: a violet edge)
		var hint = p.view.pivot.w * (0.03 + pow(1 - abs(dot(n, dir)), 3) * 0.8);
		var color = albedo * light * (0.2 + 0.8 * open) + emit + violet() * (hint * 0.22);
		var fogged = mix(color, fog(dir, smoothstep(14, 45, dist)) * 0.85, haze(dist, i.world.y, p.view.flags.z));
		return vec4(fogged, 1);
	}
});
