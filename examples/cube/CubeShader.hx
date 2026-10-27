import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The cube's shaders (Cube.hx): a backdrop over the clear colour, lighter at
// the top and darker towards the foot and the corners, from the fragment's
// position (in pixels from the top left, the same on every back end:
// Shaders, the conventions), a soft shadow on the ground under the cube,
// then the textured cube, its edges rounded by its shading alone: a
// rounded box's normal (flat faces bending over their last tenth) lit by a
// key light from the top left, a soft sky and ground light and a
// highlight, in linear light (the texture's sRGB colours decoded, the
// result encoded again: the frame's format is not an sRGB one).
@:structInit @:publicFields class CubeVertex {
	var pos:Vec3;
	var uv:Vec2;
}

@:structInit @:publicFields class CubeVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
	var local:Vec3; // the point on the cube, -1 to 1
	var world:Vec3;
}

@:structInit @:publicFields class CubeCamera {
	var mvp:Mat4;
	var model:Mat4;
}

class CubeShader implements Shaders {
	@:vertex static function vs(v:CubeVertex, cam:CubeCamera):CubeVaryings
		return {pos: cam.mvp * vec4(v.pos, 1), uv: v.uv, local: v.pos, world: (cam.model * vec4(v.pos, 1)).xyz};

	@:fragment static function fs(i:CubeVaryings, cam:CubeCamera, tex:Texture2D):Vec4 {
		// (from the nearest point of the box shrunk by 0.12: the face's
		// normal, turned up to 45 degrees at an edge)
		var p = i.local, e = 0.88;
		var n = normalize((cam.model * vec4(p - vec3(clamp(p.x, -e, e), clamp(p.y, -e, e), clamp(p.z, -e, e)), 0)).xyz);
		var l = normalize(vec3(-0.45, 0.8, 0.55));
		var v = normalize(vec3(0, -0.3, 4.6) - i.world);
		var albedo = gamma(sample(tex, i.uv).xyz, 2.2);
		// (a sky and a ground, a key light, a warm fill from the right, a highlight)
		var light = mix(vec3(0.07, 0.04, 0.03), vec3(0.2, 0.2, 0.23), n.y * 0.5 + 0.5) + vec3(1, 0.95, 0.88) * max(dot(n, l), 0)
			+ vec3(0.3, 0.22, 0.17) * max(dot(n, normalize(vec3(0.9, 0.1, 0.45))), 0);
		var spec = pow(max(dot(n, normalize(l + v)), 0), 32) * 0.3;
		// (not over 1 written as 1: the target is 8 bits a channel)
		return vec4(gamma(albedo * light + spec, 1 / 2.2), 1);
	}

	// each channel to the power k: sRGB decoded (2.2), encoded (1 / 2.2)
	static function gamma(c:Vec3, k:Float):Vec3
		return vec3(pow(c.x, k), pow(c.y, k), pow(c.z, k));
}

@:structInit @:publicFields class BackdropVertex {
	var pos:Vec2; // clip space: the whole target
}

@:structInit @:publicFields class BackdropVaryings {
	@:position var pos:Vec4;
}

@:structInit @:publicFields class Target {
	var size:Vec2; // in pixels
}

class BackdropShader implements Shaders {
	@:vertex static function vs(v:BackdropVertex):BackdropVaryings
		return {pos: vec4(v.pos, 0, 1)};

	// blended over the clear colour: a cool light from above, fading by the
	// middle, then a shade towards the foot and the corners
	@:fragment static function fs(i:BackdropVaryings, t:Target):Vec4 {
		var p = i.pos.xy / t.size;
		var c = p - vec2(0.5, 0.45);
		var top = max(1 - p.y * 1.6, 0);
		var light = 0.24 * top * top * (1 - 2 * c.x * c.x);
		var shade = 0.1 * p.y * p.y + 0.4 * smoothstep(0.35, 0.8, length(c));
		var a = 1 - (1 - light) * (1 - shade);
		return vec4(vec3(0.62, 0.68, 0.85) * light * (1 - shade) / max(a, 0.001), a);
	}
}

@:structInit @:publicFields class ShadowVertex {
	var pos:Vec3;
	var at:Vec2; // from the shadow's centre, -1 to 1
}

@:structInit @:publicFields class ShadowVaryings {
	@:position var pos:Vec4;
	var at:Vec2;
}

@:structInit @:publicFields class Ground {
	var mvp:Mat4;
}

class ShadowShader implements Shaders {
	@:vertex static function vs(v:ShadowVertex, g:Ground):ShadowVaryings
		return {pos: g.mvp * vec4(v.pos, 1), at: v.at};

	// darkest under the cube, fading to nothing at the quad's inscribed circle
	@:fragment static function fs(i:ShadowVaryings):Vec4 {
		var s = 1 - smoothstep(0, 1, length(i.at));
		return vec4(0, 0, 0, 0.7 * s * s);
	}
}
