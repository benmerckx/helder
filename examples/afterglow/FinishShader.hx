import Mood.hash2;
import Mood.noise2;
import Mood.fbm2;
import Mood.mist;
import Mood.haze;
import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The painted finish: the frame drawn small (Afterglow's pixel scale) is
// shown in big pixels, its darks pulled towards indigo, its colours
// posterized with an ordered dither (a pixel painter's grain) and a
// slow, faint grain on top.
@:structInit @:publicFields class FinishVertex {
	var pos:Vec2;
}

@:structInit @:publicFields class FinishVaryings {
	var clip:Vec4;
}

@:structInit @:publicFields class FinishView {
	var size:Vec4; // xy: the small frame's pixels, z: pixels a small pixel, w: seconds
	var look:Vec4; // x: levels, y: the dither's strength, z: the indigo's share, w: grain
}

function bayer2(a:Vec2):Float
	return fract(a.x / 2 + a.y * a.y * 0.75);

function bayer4(a:Vec2):Float
	return bayer2(a * 0.5) * 0.25 + bayer2(a);

final FinishShader = shader({
	vertex: function(v:FinishVertex):FinishVaryings
		return {clip: position(vec4(v.pos, 0, 1))},
	fragment: function(i:FinishVaryings, p:{view:FinishView, frame:Texture2D}):Vec4 {
		var px = floor(i.clip.xy / p.view.size.z);
		var c = sample(p.frame, (px + vec2(0.5)) / p.view.size.xy).xyz;
		// (a brush's dabs: short strokes across, a painter's grain)
		var dab = noise2(px * vec2(0.3, 1.1) + vec2(0, floor(px.x * 0.3) * 0.37));
		c *= 0.92 + 0.16 * dab;
		var lum = dot(c, vec3(0.3, 0.5, 0.2));
		var indigo = vec3(0.07, 0.05, 0.17);
		c = c + indigo * (pow(1 - lum, 4) * p.view.look.z);
		var grain = (hash2(px + vec2(floor(p.view.size.w * 6) * 13.7, 0)) - 0.5) * p.view.look.w;
		var levels = p.view.look.x;
		var d = (bayer4(px) - 0.5) * p.view.look.y;
		c = floor(c * levels + vec3(0.5 + d + grain)) / levels;
		return vec4(c, 1);
	}
});
