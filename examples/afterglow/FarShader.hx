import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.haze;
import Mood.mist;
import PaintShader.PaintView;
import PaintShader.high;
import PaintShader.acid;
import PaintShader.cyan;
import PaintShader.magenta;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The ruins far off, as a painter lays them in: each plane one upright
// quad, its ruin a silhouette worked out a pixel (tiers of arcades, tall
// narrow arches under small ones, their tops fallen in steps, a few posts
// left standing, the thickness of a pier seen in each opening), its edge
// a pixel soft at any size, paler with the mist between; small glows of
// what grows there. Drawn back to front over the sky and the water.
@:structInit @:publicFields class FarVertex {
	var pos:Vec3;
	var plane:Vec4; // x: its scale (units a storey's), y: a seed, z: how much of it stands, w: its glows' strength
}

@:structInit @:publicFields class FarVaryings {
	var clip:Vec4;
	var world:Vec3;
	var plane:Vec4;
}

// a tier of arches: the distance to its stone (x: the front's, y: with the
// piers' thickness seen through the openings from the side)
function tier(q:Vec2, bay:Float, r:Float, y0:Float, spring:Float, top:Float, thick:Float):Vec2 {
	var wall = max(q.y - top, y0 - q.y);
	var ex = (fract(q.x / bay) - 0.5) * bay, dy = q.y - spring;
	var hole = dy > 0 ? length(vec2(ex, dy)) - r : abs(ex) - r;
	var ex2 = (fract((q.x + thick) / bay) - 0.5) * bay;
	var hole2 = dy > 0 ? length(vec2(ex2, dy)) - r : abs(ex2) - r;
	return vec2(max(wall, -hole), max(wall, -max(hole, hole2)));
}

// a noise along a line
function wave(x:Float, seed:Float):Float {
	var i = floor(x), f = x - i;
	return mix(hash2(vec2(i, seed)), hash2(vec2(i + 1, seed)), f * f * (3 - 2 * f));
}

// how high the ruin still stands in the column at x (columns 0.55 wide):
// whole tiers by a slow noise, the last of each rising in steps, a few
// courses gone from each top
function stands(x:Float, seed:Float, much:Float):Float {
	var c = floor(x / 0.55);
	var level = clamp((wave(c * 0.045 + seed * 17.3, seed) * 1.5 + wave(c * 0.21, seed * 3.1) * 0.35 - 0.45) * 4.4 * much, 0, 3.999);
	var n = floor(level), f = level - n;
	var a = n < 0.5 ? 0.35 : (n < 1.5 ? 4.3 : (n < 2.5 ? 7.3 : 9.6));
	var b = n < 0.5 ? 4.3 : (n < 1.5 ? 7.3 : (n < 2.5 ? 9.6 : 12.4));
	var rise = floor(smoothstep(0.7, 1.0, f) * 5) / 5;
	var gone = floor(pow(hash2(vec2(c, seed + 2)), 3) * 3.2) * 0.26;
	return a + (b - a) * rise - gone * step(0.5, n + rise);
}

final FarShader = shader({
	vertex: function(v:FarVertex, p:{view:PaintView}):FarVaryings
		return {clip: position(p.view.viewProj * vec4(v.pos, 1)), world: v.pos, plane: v.plane},
	fragment: function(i:FarVaryings, p:{view:PaintView}):Vec4 {
		if (p.view.flags.x > 0.5 && i.world.y < 0) discard();
		var toEye = p.view.eye.xyz - i.world;
		var dist = length(toEye);
		var dir = -toEye / dist;
		var s = i.plane.x, seed = i.plane.y;
		var q = vec2(i.world.x, i.world.y + 1.0) / s + vec2(seed * 37.7, 0);
		if (q.y > 15.8) discard();
		// (a pixel, in the plane's units)
		var px = dist * p.view.flags.w / s;
		var c = floor(q.x / 0.55), fx = q.x - c * 0.55;
		var h = stands(q.x, seed, i.plane.z);
		// (the columns beside it matter only a pixel from its side)
		var hl = h, hr = h;
		if (fx < px * 1.5) hl = stands(q.x - 0.55, seed, i.plane.z);
		if (fx > 0.55 - px * 1.5) hr = stands(q.x + 0.55, seed, i.plane.z);
		var skyline = q.y > h
			? min(q.y - h, min(q.y < hl ? fx : 99.0, q.y < hr ? 0.55 - fx : 99.0))
			: -min(h - q.y, min(q.y > hl ? fx : 99.0, q.y > hr ? 0.55 - fx : 99.0));
		if (skyline > px * 2 + 4.2) discard();
		// (which way a pier's thickness shows: from where the eye is)
		var thick = (i.world.x > p.view.eye.x ? -0.16 : 0.16);
		// (the tier it is in: tall arches, small ones over them, and again)
		var storey = q.y < 4.3
			? tier(q, 2.9, 0.92, -1, 2.9, 4.3, thick)
			: (q.y < 7.3
				? tier(q + vec2(0.4, 0), 1.45, 0.42, 4.3, 6.2, 7.3, thick)
				: (q.y < 9.6 ? tier(q + vec2(0.9, 0), 2.9, 0.75, 7.3, 8.5, 9.6, thick) : tier(q, 1.45, 0.4, 9.6, 11.3, 12.4, thick)));
		var front = max(storey.x, skyline);
		var all = max(storey.y, skyline);
		// (a post left standing on its top, here and there)
		var post = hash2(vec2(c, seed + 5));
		var stand = max(max(abs(fx - 0.275) - 0.045, q.y - h - 0.5 - post * 3), h - 0.2 - q.y);
		var cap = max(max(abs(fx - 0.275) - 0.09, q.y - h - 0.52 - post * 3), h + 0.42 + post * 3 - q.y);
		if (post > 0.82 && h > 1) {
			front = min(front, min(stand, cap));
			all = min(all, min(stand, cap));
		}
		var alpha = 1 - smoothstep(-px, px, all);
		// (what grows there: a small glow on a top, here and there)
		var grow = hash2(vec2(c, seed + 9));
		var bud = length(vec2(fx - 0.2 - 0.2 * post, q.y - h - 0.1)) - 0.05 - 0.04 * post;
		var lit = (grow > 0.86 && h > 1) ? (1 - smoothstep(-px, px, bud)) * i.plane.w : 0.0;
		if (alpha + lit <= 0.004) discard();
		// (stone: streaked down by rain, darker in an opening's depth, its tops mossed)
		var streak = noise2(vec2(q.x * 2.3, q.y * 0.35 + seed));
		var side = smoothstep(-px, px, front);
		var mossy = smoothstep(0.35, 0.0, h - q.y) * step(1, h);
		var stone = mix(vec3(0.045, 0.045, 0.1), vec3(0.02, 0.022, 0.055), side) * (0.7 + 0.6 * streak);
		stone = mix(stone, vec3(0.03, 0.07, 0.035), mossy * 0.7);
		var far = smoothstep(14, 45, dist);
		var veil = mist(dir) * ((0.98 + far * exp(-max(dir.y + 0.02, 0) * 9) * 1.4) * high(dir) * 0.85);
		var amount = haze(dist, i.world.y, p.view.flags.z);
		var hue = grow > 0.95 ? magenta() : (grow > 0.9 ? cyan() : acid());
		var glow = hue * (lit * 2.2 * (0.7 + 0.3 * sin(p.view.eye.w * 1.3 + c)) * (1 - amount * 0.7));
		return vec4(mix(stone, veil, amount) * alpha + glow, max(alpha, lit));
	}
});
