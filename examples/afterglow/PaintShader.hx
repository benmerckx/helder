import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import Mood.bricks;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The ruins' one shader: every surface of the diorama (Ruins) painted
// from its kind, in linear light for the HDR target. Stone is blocks
// drawn from the world's coordinates, moss creeps over the tops and drips
// down the faces, roots are near black; what glows (moss's tips, veins,
// mushrooms, sprouts, the lanterns) is emissive and lights what is near
// it: the glows that stay are summed into each vertex when it is built
// (Builder.bake), those of the moment (a woken lantern, the home's) are
// the view's. The moth's violet aura lights too. A piece that moves is drawn
// as built, posed (moved and turned) by the view's pose.
@:structInit @:publicFields class PaintVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var kind:Vec4; // x: the kind, y: the top of its solid (moss), z: a seed, w: a kind's own
	var anchor:Vec4; // xyz: what it hangs from, w: how far it sways (radians)
	var light:Vec3; // the glows' light on it
}

@:structInit @:publicFields class PaintVaryings {
	var clip:Vec4;
	var world:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var kind:Vec4;
	var light:Vec3;
}

@:structInit @:publicFields class PaintView {
	var viewProj:Mat4;
	var eye:Vec4; // w: seconds
	var moth:Vec4; // xyz: the moth, w: its aura's radius
	var aura:Vec4; // rgb: the aura's light
	var pose:Vec4; // a piece's: x, y moved, z turned (radians) about pivot
	var pivot:Vec4; // xy: the pivot, z: a lantern's light (0 dark), w: how much the moth's light hints at it
	var flags:Vec4; // x: 1 into the reflection, z: the mist's density
	// the glows of the moment: xyz where, w its radius (0: none); rgb, w its power
	@:length(4) var glowAt:Array<Vec4>;
	@:length(4) var glowColor:Array<Vec4>;
}

inline var STONE = 0;
inline var ROOT = 1;
inline var STRAND = 2;
inline var CAP = 3;
inline var STEM = 4;
inline var BULB = 5;
inline var CAGE = 6;
inline var VEIN = 8;
inline var PAD = 9;
inline var SKY = 10;

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

// a glow's light on a point (Builder.bake sums the same for those that stay)
function glow(at:Vec4, color:Vec4, p:Vec3, n:Vec3):Vec3 {
	var d = at.xyz - p, dist2 = dot(d, d), r2 = at.w * at.w;
	if (dist2 >= r2) return vec3(0, 0, 0);
	var fall = 1 - dist2 / r2;
	var wrap = dot(n, d * inversesqrt(max(dist2, 0.0001))) * 0.6 + 0.4;
	return color.xyz * (color.w * fall * fall * max(wrap, 0) / (1 + dist2 * 2));
}

// the mist darkening as one looks up, the same on the ruins as behind them
function high(d:Vec3):Float
	return mix(1.0, 0.45, smoothstep(0.3, 0.85, d.y));

// the mist's colour as painted: mottled, slanted beams falling through it,
// darker upwards, and glowing low in the deep distance (far at depth)
function fog(d:Vec3, far:Float):Vec3 {
	var beams = pow(noise2(vec2(d.x * 9 + d.y * 3.5, 0.3)), 4) * smoothstep(-0.1, 0.5, d.y);
	var mottle = noise2(vec2(d.x * 4, d.y * 7));
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
		return {clip: position(p.view.viewProj * vec4(w, 1)), world: w, normal: n, uv: v.uv, kind: v.kind, light: v.light};
	},
	fragment: function(i:PaintVaryings, p:{view:PaintView}):Vec4 {
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
		var bevel = 0.0;
		if (kind == STONE) {
			var an = abs(n);
			var up = an.y > 0.7 ? 1.0 : 0.0;
			var f = up > 0.5 ? i.world.xz : (an.x > an.z ? i.world.zy : i.world.xy);
			// (the blocks the mesh has in relief: their joints, each its own tone, a few gone)
			var k = bricks(f, seed);
			var joint = (1 - smoothstep(0.01, 0.035, k.x)) * detail;
			var gone = step(0.95, k.z) * (1 - up) * detail;
			var grainy = noise2(f * 3.1 + vec2(seed)) * 0.65 + noise2(f * 9.3) * 0.35;
			var tone = 0.25 + 0.5 * mix(0.5, k.y, detail) + (grainy - 0.5) * 0.5;
			albedo = mix(vec3(0.05, 0.045, 0.1), vec3(0.2, 0.17, 0.34), clamp(tone, 0, 1));
			albedo *= (1 - joint * 0.6) * (1 - gone * 0.55);
			// (a block's upper edge catches the mist's light)
			bevel = smoothstep(0.78, 0.93, k.w) * (1 - joint) * (1 - up) * detail;
			// (stained where the water was)
			var damp = smoothstep(1.4, -0.2, i.world.y + noise2(i.world.xz * 1.5) * 0.5);
			albedo = mix(albedo, albedo * vec3(0.45, 0.8, 0.75), damp * 0.7);
			// (moss: the mesh's share of it, its edge broken up; glowing specks in it)
			var patchy = fbm2(i.world.xz * 4.5 + i.world.yy * 2.5 + vec2(seed));
			var share = i.uv.y + (patchy - 0.5) * 0.6;
			var cover = smoothstep(0.42, 0.56, share);
			// (hanging from the top above: a fringe, and drips of uneven
			// length in clumps, bright where they start, their tips glowing)
			var below = i.kind.y;
			var along = an.x > an.z ? i.world.z : i.world.x;
			var u = along * 7 + noise2(vec2(along * 1.7, seed)) * 1.5;
			var id = floor(u), fx = abs(fract(u) - 0.5);
			var clump = smoothstep(0.4, 0.7, noise2(vec2(along * 0.9, seed * 3)));
			var len = (0.06 + 0.85 * pow(hash2(vec2(id, seed)), 3)) * (0.15 + 0.85 * clump);
			var t01 = clamp(below / len, 0, 1);
			var width = 0.4 * sqrt(1 - t01) + 0.06;
			var face = (below > -0.06 && n.y < 0.5) ? 1.0 : 0.0;
			var drip = smoothstep(width, width - 0.1, fx) * step(below, len) * face;
			var fringe = smoothstep(0.07, 0.03, below - 0.07 * noise2(vec2(along * 5, seed)) * clump) * face;
			var hang = max(drip, fringe);
			cover = max(cover, hang);
			var moss = mix(vec3(0.03, 0.065, 0.02), vec3(0.11, 0.22, 0.03), patchy * 0.55 + grainy * 0.45);
			moss = mix(moss, mix(vec3(0.16, 0.3, 0.03), vec3(0.03, 0.08, 0.02), t01), hang);
			albedo = mix(albedo, moss, cover);
			bevel *= 1 - cover;
			var cell = i.world * 18;
			var spot = length(fract(cell) - vec3(0.5));
			var speck = step(0.93, hash2(floor(cell.xz) + floor(cell.yy) * 7.1 + vec2(seed))) * smoothstep(0.42, 0.15, spot);
			var edge = smoothstep(0.3, 0.45, share) * (1 - smoothstep(0.45, 0.6, share));
			var tip = smoothstep(0.7, 1.0, t01) * drip;
			var lit = fringe * 0.22 + drip * (1 - t01) * 0.12 + tip * 0.4;
			emit += acid() * ((cover * 0.012 + speck * cover * 0.9 * detail + edge * 0.05 + lit * detail) * (0.75 + 0.25 * sin(t * 1.3 + seed * 9 + along * 3)));
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
			// (a lantern: a lattice of bars about a glowing heart, the heart
			// seen through its lower cells, as cells of light)
			var a = abs(fract(i.uv.x * 7 + i.uv.y * 4.5) - 0.5), b = abs(fract(i.uv.x * 7 - i.uv.y * 4.5) - 0.5);
			var bar = 1 - smoothstep(0.1, 0.14, min(a, b));
			bar = max(bar, max(smoothstep(0.12, 0.08, i.uv.y), smoothstep(0.9, 0.94, i.uv.y)));
			var heart = exp(-(i.uv.y - 0.66) * (i.uv.y - 0.66) * 48) * pow(max(dot(n, -dir), 0), 1.5);
			var lightUp = p.view.pivot.z * (0.85 + 0.15 * sin(t * 1.9 + seed * 5));
			albedo = mix(vec3(0.012, 0.008, 0.03), vec3(0.3, 0.26, 0.5), bar);
			emit = mix(magenta() * (heart * 3.0) + vec3(0.3, 0.05, 0.5) * 0.03, magenta() * (heart * 0.1), bar) * lightUp;
		} else if (kind == VEIN) {
			var pulse = 0.65 + 0.35 * sin(i.uv.y * 9 - t * 0.8 + seed * 4);
			albedo = vec3(0.1, 0.2, 0.02);
			emit = acid() * (0.9 * pulse * (0.5 + 0.5 * i.kind.w));
		} else if (kind == PAD) {
			var r = length(i.uv - vec2(0.5)) * 2;
			albedo = mix(vec3(0.03, 0.09, 0.05), vec3(0.1, 0.2, 0.06), noise2(i.uv * 12));
			emit = acid() * (smoothstep(0.82, 1.0, r) * smoothstep(0.3, 0.7, noise2(i.uv * 5 + vec2(seed * 9))) * 0.3 * i.kind.w) + acid() * 0.008;
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
		var ambient = mix(vec3(0.02, 0.02, 0.05), vec3(0.1, 0.11, 0.3), n.y * 0.5 + 0.5) * 0.3;
		var light = ambient + vec3(0.08, 0.16, 0.34) * (max(dot(n, back), 0) * 0.25 + rim * 0.9) + i.light;
		for (k in 0...4)
			light += glow(p.view.glowAt[k], p.view.glowColor[k], i.world, n);
		light += vec3(0.1, 0.13, 0.3) * (bevel * 0.5);
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
