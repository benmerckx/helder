import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// The mip maps' shaders (Mips.hx): the floor, its texture read at the mip
// level each fragment's footprint needs (sample in a fragment stage), fading
// into the clear colour with distance; the swatches, a texture read at a given level
// (sampleLevel).
@:structInit @:publicFields class FloorVertex {
	var pos:Vec3;
	var uv:Vec2;
}

@:structInit @:publicFields class FloorVaryings {
	var pos:Vec4;
	var uv:Vec2;
	var far:Float; // 0 near, 1 at the far end (Mips.DEPTH)
}

@:structInit @:publicFields class FloorCamera {
	var mvp:Mat4;
}

final FloorShader = shader({
	vertex: function(v:FloorVertex, p:{cam:FloorCamera}):FloorVaryings
		return {pos: position(p.cam.mvp * vec4(v.pos, 1)), uv: v.uv, far: -v.pos.z / 40},
	fragment: function(i:FloorVaryings, p:{checks:Texture2D}):Vec4
		return vec4(mix(sample(p.checks, i.uv).xyz, vec3(0.1, 0.1, 0.12), smoothstep(0.01, 0.25, i.far)), 1)
});

@:structInit @:publicFields class SwatchVertex {
	var pos:Vec2; // clip space
	var uv:Vec2;
}

@:structInit @:publicFields class SwatchVaryings {
	var pos:Vec4;
	var uv:Vec2;
}

@:structInit @:publicFields class Swatch {
	var level:Float;
}

final SwatchShader = shader({
	vertex: function(v:SwatchVertex):SwatchVaryings
		return {pos: position(vec4(v.pos, 0, 1)), uv: v.uv},
	fragment: function(i:SwatchVaryings, p:{s:Swatch, levels:Texture2D}):Vec4
		return vec4(sampleLevel(p.levels, i.uv, p.s.level).xyz, 1)
});
