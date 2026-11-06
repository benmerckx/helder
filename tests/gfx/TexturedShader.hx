import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A shader with textures in both stages (sample, sampleLevel), one of them shared and one passed
// on to a helper, next to a uniform block (slots: height 0, Fade 1, albedo
// 2), for the shader definition's tests (ShaderTest: run on the CPU, the emitted
// source against test/shader/; GfxTest and WebTest: compiled by each back end).
@:structInit @:publicFields class TexVertex {
	var pos:Vec2;
	var uv:Vec2;
}

@:structInit @:publicFields class TexVaryings {
	var pos:Vec4;
	var uv:Vec2;
	var lift:Float;
}

@:structInit @:publicFields class Fade {
	var amount:Float;
}

function tinted(t:Texture2D, uv:Vec2):Vec4
	return sample(t, uv * 2) * vec4(1, 0.5, 0.5, 1);

final TexturedShader = shader({
	vertex: function(v:TexVertex, p:{height:Texture2D}):TexVaryings
		return {pos: position(vec4(v.pos, 0, 1)), uv: v.uv, lift: sample(p.height, v.uv).x},
	fragment: function(i:TexVaryings, p:{fade:Fade, albedo:Texture2D, height:Texture2D}):Vec4
		return mix(tinted(p.albedo, i.uv), sampleLevel(p.height, i.uv, 1.5), p.fade.amount) * i.lift
});
