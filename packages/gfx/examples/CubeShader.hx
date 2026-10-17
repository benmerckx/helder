import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The cube's shaders (Cube.hx): a backdrop over the clear colour, lighter at
// the top and darker towards the foot and the corners, from the fragment's
// position (in pixels from the top left, the same on every back end:
// Shaders, the conventions), a soft shadow on the ground under the cube,
// then the textured, lit cube.
@:structInit @:publicFields class CubeVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
}

@:structInit @:publicFields class CubeVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
	var light:Float;
}

@:structInit @:publicFields class CubeCamera {
	var mvp:Mat4;
	var model:Mat4;
}

class CubeShader implements Shaders {
	@:vertex static function vs(v:CubeVertex, cam:CubeCamera):CubeVaryings {
		var n = (cam.model * vec4(v.normal, 0)).xyz;
		return {pos: cam.mvp * vec4(v.pos, 1), uv: v.uv, light: 0.45 + 0.55 * max(dot(n, normalize(vec3(0.3, 0.6, 0.75))), 0)};
	}

	@:fragment static function fs(i:CubeVaryings, tex:Texture2D):Vec4
		return vec4(sample(tex, i.uv).xyz * i.light, 1);
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
