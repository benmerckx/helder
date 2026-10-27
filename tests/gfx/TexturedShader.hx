import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A shader with textures in both stages (sample, sampleLevel), one of them shared and one passed
// on to a helper, next to a uniform block (slots: height 0, Fade 1, albedo
// 2), for the shader macro's tests (ShaderTest: run on the CPU, the emitted
// source against test/shader/; GfxTest and WebTest: compiled by each back end).
@:structInit @:publicFields class TexVertex {
	var pos:Vec2;
	var uv:Vec2;
}

@:structInit @:publicFields class TexVaryings {
	@:position var pos:Vec4;
	var uv:Vec2;
	var lift:Float;
}

@:structInit @:publicFields class Fade {
	var amount:Float;
}

class TexturedShader implements Shaders {
	@:vertex static function vs(v:TexVertex, height:Texture2D):TexVaryings
		return {pos: vec4(v.pos, 0, 1), uv: v.uv, lift: sample(height, v.uv).x};

	@:fragment static function fs(i:TexVaryings, fade:Fade, albedo:Texture2D, height:Texture2D):Vec4
		return mix(tinted(albedo, i.uv), sampleLevel(height, i.uv, 1.5), fade.amount) * i.lift;

	static function tinted(t:Texture2D, uv:Vec2):Vec4
		return sample(t, uv * 2) * vec4(1, 0.5, 0.5, 1);
}
