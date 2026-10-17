import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The texture formats' shaders (Formats.hx): a gradient drawn into each
// render target from the fragment's position (the same values the example
// uploads), a triangle's depth into each depth texture, and the tiles
// showing them (a depth texture's red as grey).
@:structInit @:publicFields class GradientVertex {
	var pos:Vec2; // clip space: the whole target
}

@:structInit @:publicFields class GradientVaryings {
	@:position var pos:Vec4;
}

class GradientShader implements Shaders {
	@:vertex static function vs(v:GradientVertex):GradientVaryings
		return {pos: vec4(v.pos, 0, 1)};

	// texel (x, y) of the 16x16 target: (x / 15, y / 15, 0.5), y from the top
	@:fragment static function fs(i:GradientVaryings):Vec4
		return vec4((i.pos.xy - 0.5) / 15, 0.5, 1);
}

@:structInit @:publicFields class DepthVertex {
	var pos:Vec3; // clip space, z its depth
}

@:structInit @:publicFields class DepthVaryings {
	@:position var pos:Vec4;
}

class DepthShader implements Shaders {
	@:vertex static function vs(v:DepthVertex):DepthVaryings
		return {pos: vec4(v.pos, 1)};

	@:fragment static function fs(i:DepthVaryings):Vec4
		return vec4(1);
}

@:structInit @:publicFields class TileVertex {
	var pos:Vec2; // clip space
	var uv:Vec2;
}

@:structInit @:publicFields class TileVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class Tile {
	var grey:Float; // 1: the red channel as grey (a depth texture)
}

class TileShader implements Shaders {
	@:vertex static function vs(v:TileVertex):TileVaryings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv};

	@:fragment static function fs(i:TileVaryings, t:Tile, image:Texture2D):Vec4 {
		var c = sample(image, i.uv);
		return vec4(mix(c.xyz, vec3(c.x), t.grey), 1);
	}
}
