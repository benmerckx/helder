import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The cube's shaders (Cube.hx): a textured, lit cube, then a translucent
// panel drawn over it in pixels from the top left, fading downwards with
// the fragment's position (the same on every back end: Shaders, the
// conventions).
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

@:structInit @:publicFields class PanelVertex {
	var pos:Vec2; // pixels from the top left
	var color:Vec4;
}

@:structInit @:publicFields class PanelVaryings {
	@:position var pos:Vec4;
	var color:Vec4;
}

@:structInit @:publicFields class Target {
	var size:Vec2; // the target's, in pixels
	var top:Float; // the panel's, where it fades from
	var height:Float;
}

class PanelShader implements Shaders {
	@:vertex static function vs(v:PanelVertex, t:Target):PanelVaryings
		return {pos: vec4(v.pos.x / t.size.x * 2 - 1, 1 - v.pos.y / t.size.y * 2, 0, 1), color: v.color};

	@:fragment static function fs(i:PanelVaryings, t:Target):Vec4
		return vec4(i.color.xyz, i.color.w * clamp(1 - (i.pos.y - t.top) / t.height * 0.7, 0, 1));
}
