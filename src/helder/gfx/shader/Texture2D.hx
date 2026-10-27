package helder.gfx.shader;

import haxe.io.Bytes;

// A texture and the sampler that reads it, as a shader's parameter (after
// the stage's input, as uniform blocks are: a slot of its own, set with
// Encoder.setTexture), read with ShaderMath's sample(t, uv): GLSL's
// sampler2D, WGSL's texture_2d<f32> and sampler, MSL's texture2d<float> and
// sampler, HLSL's Texture2D and SamplerState. Shader code passes it on to
// other functions only (no locals, fields or results of this type). In CPU
// code: RGBA8 texels, rows top to bottom (v = 0 the first row), read at the
// nearest texel, repeating.
class Texture2D {
	public final width:Int;
	public final height:Int;
	public final texels:Bytes;

	public function new(width:Int, height:Int, texels:Bytes) {
		this.width = width;
		this.height = height;
		this.texels = texels;
	}

	// the texel at uv, its channels 0..1 (sample on the CPU)
	public function read(uv:Vec2):Vec4 {
		var x = Std.int((uv.x - Math.ffloor(uv.x)) * width), y = Std.int((uv.y - Math.ffloor(uv.y)) * height);
		var p = 4 * (y * width + x);
		return new Vec4(texels.get(p) / 255, texels.get(p + 1) / 255, texels.get(p + 2) / 255, texels.get(p + 3) / 255);
	}
}
