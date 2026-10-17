import hxmc.gfx.shader.*;
import hxmc.gfx.shader.ShaderMath.*;

// The mip maps' shaders (Mips.hx): the floor, its texture read at the mip
// level each fragment's footprint needs (sample in a fragment stage), fading
// into the clear colour with distance; the swatches, a texture read at a given level
// (sampleLevel).
@:structInit @:publicFields class FloorVertex {
	var pos:Vec3;
	var uv:Vec2;
}

@:structInit @:publicFields class FloorVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
	var far:Float; // 0 near, 1 at the far end (Mips.DEPTH)
}

@:structInit @:publicFields class FloorCamera {
	var mvp:Mat4;
}

class FloorShader implements Shaders {
	@:vertex static function vs(v:FloorVertex, cam:FloorCamera):FloorVaryings
		return {pos: cam.mvp * vec4(v.pos, 1), uv: v.uv, far: -v.pos.z / 40};

	@:fragment static function fs(i:FloorVaryings, checks:Texture2D):Vec4
		return vec4(mix(sample(checks, i.uv).xyz, vec3(0.1, 0.1, 0.12), smoothstep(0.01, 0.25, i.far)), 1);
}

@:structInit @:publicFields class SwatchVertex {
	var pos:Vec2; // clip space
	var uv:Vec2;
}

@:structInit @:publicFields class SwatchVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class Swatch {
	var level:Float;
}

class SwatchShader implements Shaders {
	@:vertex static function vs(v:SwatchVertex):SwatchVaryings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv};

	@:fragment static function fs(i:SwatchVaryings, s:Swatch, levels:Texture2D):Vec4
		return vec4(sampleLevel(levels, i.uv, s.level).xyz, 1);
}
