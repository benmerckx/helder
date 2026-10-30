package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The post-process chain's shaders (PostProcess): each a triangle over the
// whole target, reading the pass before.
//
//   BloomDownShader   a level of the bloom's chain from the one above:
//                     Jimenez's 13 taps (Call of Duty: Advanced Warfare,
//                     "Next generation post processing", 2014), the
//                     first level's in Karis' average (each group of four
//                     weighted by 1 / (1 + its luma): no fireflies)
//   BloomUpShader     the level below's tent filter (3x3) added to a level
//                     (additive blending), up the chain
//   CompositeShader   the frame: the scene and its bloom mixed (energy
//                     kept: the scene less what bloom spreads), exposed,
//                     tone mapped (AgX, or ACES as the 8-bit path's), graded (saturation,
//                     contrast, lift and gain), vignetted, grain added
//                     (and dithered), encoded for an 8-bit target
@:structInit @:publicFields class PostVertex {
	var pos:Vec2; // clip space
}

@:structInit @:publicFields class PostVaryings {
	@:position var clip:Vec4;
	var uv:Vec2;
}

// a bloom pass: x, y a texel of the source, z the up filter's radius (in
// its texels), w 1 for the first level down (Karis' average)
@:structInit @:publicFields class BloomParams {
	var texel:Vec4;
}

@:structInit @:publicFields class CompositeParams {
	var exposure:Vec4; // x: exposure, y: bloom's share, z: the tone curve (0 AgX, 1 ACES, 2 none), w: time (the grain's)
	var grade:Vec4; // x: saturation, y: contrast, z: vignette, w: grain
	var lift:Vec4; // rgb: added to the shadows (graded, display values); w: 1 / the bloom's levels
	var gain:Vec4; // rgb: times the colour
	var size:Vec4; // xy: the target's size in pixels, z: its aspect, w: the scene's alpha kept (1) or opaque (0)
}

class BloomDownShader implements Shaders {
	@:vertex static function vs(v:PostVertex):PostVaryings
		return fullscreen(v);

	// (a target's uv at a corner of the triangle over it: its top left 0, 0)
	public static function fullscreen(v:PostVertex):PostVaryings
		return {clip: vec4(v.pos, 0, 1), uv: vec2(v.pos.x * 0.5 + 0.5, 0.5 - v.pos.y * 0.5)};

	@:fragment static function fs(i:PostVaryings, p:BloomParams, source:Texture2D):Vec4 {
		var t = p.texel.xy;
		var uv = i.uv;
		var a = tap(source, uv + t * vec2(-2, -2));
		var b = tap(source, uv + t * vec2(0, -2));
		var c = tap(source, uv + t * vec2(2, -2));
		var d = tap(source, uv + t * vec2(-2, 0));
		var e = tap(source, uv);
		var f = tap(source, uv + t * vec2(2, 0));
		var g = tap(source, uv + t * vec2(-2, 2));
		var h = tap(source, uv + t * vec2(0, 2));
		var k = tap(source, uv + t * vec2(2, 2));
		var j = tap(source, uv + t * vec2(-1, -1));
		var l = tap(source, uv + t * vec2(1, -1));
		var m = tap(source, uv + t * vec2(-1, 1));
		var n = tap(source, uv + t * vec2(1, 1));
		// (the five groups of four: the centre's 0.5, the corners' 0.125 each)
		var g0 = (j + l + m + n) * 0.25;
		var g1 = (a + b + d + e) * 0.25;
		var g2 = (b + c + e + f) * 0.25;
		var g3 = (d + e + g + h) * 0.25;
		var g4 = (e + f + h + k) * 0.25;
		var w0 = 0.5;
		var w1 = 0.125;
		var w2 = 0.125;
		var w3 = 0.125;
		var w4 = 0.125;
		if (p.texel.w > 0.5) {
			w0 = 0.5 / (1 + luma(g0));
			w1 = 0.125 / (1 + luma(g1));
			w2 = 0.125 / (1 + luma(g2));
			w3 = 0.125 / (1 + luma(g3));
			w4 = 0.125 / (1 + luma(g4));
		}
		var sum = g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4;
		return vec4(sum / (w0 + w1 + w2 + w3 + w4), 1);
	}

	// (a texel's colour, past a ceiling no bright speck reaches: half floats'
	// infinities and NaNs kept out)
	static function tap(t:Texture2D, uv:Vec2):Vec3
		return clamp(sampleLevel(t, uv, 0).xyz, 0, 256);

	public static function luma(c:Vec3):Float
		return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

class BloomUpShader implements Shaders {
	@:vertex static function vs(v:PostVertex):PostVaryings
		return BloomDownShader.fullscreen(v);

	@:fragment static function fs(i:PostVaryings, p:BloomParams, source:Texture2D):Vec4 {
		var t = p.texel.xy * p.texel.z;
		var uv = i.uv;
		var sum = sampleLevel(source, uv, 0).xyz * 4
			+ (sampleLevel(source, uv + t * vec2(0, -1), 0).xyz + sampleLevel(source, uv + t * vec2(-1, 0), 0).xyz
				+ sampleLevel(source, uv + t * vec2(1, 0), 0).xyz + sampleLevel(source, uv + t * vec2(0, 1), 0).xyz) * 2
			+ sampleLevel(source, uv + t * vec2(-1, -1), 0).xyz + sampleLevel(source, uv + t * vec2(1, -1), 0).xyz
			+ sampleLevel(source, uv + t * vec2(-1, 1), 0).xyz + sampleLevel(source, uv + t * vec2(1, 1), 0).xyz;
		return vec4(sum / 16, 1);
	}
}

class CompositeShader implements Shaders {
	@:vertex static function vs(v:PostVertex):PostVaryings
		return BloomDownShader.fullscreen(v);

	@:fragment static function fs(i:PostVaryings, p:CompositeParams, scene:Texture2D, bloom:Texture2D):Vec4 {
		var s = sampleLevel(scene, i.uv, 0);
		var hdr = clamp(s.xyz, 0, 65000);
		var spread = sampleLevel(bloom, i.uv, 0).xyz * p.lift.w;
		var color = mix(hdr, spread, p.exposure.y) * p.exposure.x;
		var curve = p.exposure.z;
		var mapped = PbrShader.encode(clamp(color, 0, 1));
		if (curve < 1.5) mapped = PbrShader.encode(PbrShader.aces(color));
		if (curve < 0.5) mapped = agx(color);
		// (the grade, on display values)
		var y = dot(mapped, vec3(0.2126, 0.7152, 0.0722));
		mapped = mix(vec3(y), mapped, p.grade.x);
		mapped = (mapped - 0.5) * p.grade.y + 0.5;
		mapped = clamp(mapped * p.gain.xyz + p.lift.xyz * (1 - mapped), 0, 1);
		// (the vignette: the corners darker, by the target's shape)
		var at = (i.uv - 0.5) * vec2(p.size.z, 1);
		var r = length(at) / length(vec2(p.size.z, 1) * 0.5);
		mapped *= 1 - p.grade.z * smoothstep(0.35, 1.05, r);
		// (alpha: the scene's coverage, or bloom's light where nothing was drawn)
		var alpha = 1.0;
		if (p.size.w > 0.5) alpha = clamp(max(s.w, max(mapped.x, max(mapped.y, mapped.z))), 0, 1);
		// (grain, most in the middle tones, and a dither below an 8-bit step)
		var px = floor(i.uv * p.size.xy);
		var noise = hash(px + vec2(fract(p.exposure.w * 0.61) * 1931, fract(p.exposure.w * 0.37) * 727)) - 0.5;
		var mid = 1 - abs(y * 2 - 1);
		mapped += vec3(noise * (p.grade.w * (0.35 + 0.65 * mid) + 1.0 / 255)) * alpha;
		return vec4(clamp(mapped, 0, 1), alpha);
	}

	// (a pixel's random value in 0..1)
	static function hash(p:Vec2):Float {
		var q = fract(p * vec2(0.1031, 0.1030));
		var d = dot(q, vec2(q.y + 33.33, q.x + 33.33));
		q = q + vec2(d, d);
		return fract((q.x + q.y) * q.x);
	}

	// AgX (Sobotka's; Wrensch's fit of its sigmoid): the colour into AgX's
	// inset primaries, its log2 between -12.47 and 4.03 stops, the curve,
	// back out: highlights desaturate towards white as film does, hues
	// stay; display values (sRGB's encoding), 0..1
	public static function agx(c:Vec3):Vec3 {
		var v = vec3(dot(c, vec3(0.842479062253094, 0.0784335999999992, 0.0792237451477643)),
			dot(c, vec3(0.0423282422610123, 0.878468636469772, 0.0791661274605434)),
			dot(c, vec3(0.0423756549057051, 0.0784336, 0.879142973793104)));
		var lo = -12.47393;
		var hi = 4.026069;
		v = clamp(log(max(v, vec3(0.0000001))) * 1.4426950, lo, hi);
		v = (v - lo) / (hi - lo);
		var v2 = v * v;
		var v4 = v2 * v2;
		v = 15.5 * v4 * v2 - 40.14 * v4 * v + 31.96 * v4 - 6.868 * v2 * v + 0.4298 * v2 + 0.1191 * v - 0.00232;
		// (the inset's inverse)
		var o = vec3(dot(v, vec3(1.19687900512017, -0.0980208811401368, -0.0990297440797205)),
			dot(v, vec3(-0.0528968517574562, 1.15190312990417, -0.0989611768448433)),
			dot(v, vec3(-0.0529716355144438, -0.0980434501171241, 1.15107367264116)));
		return clamp(o, 0, 1);
	}
}
