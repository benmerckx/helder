package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.SkyShader;
import helder.scene.render.PbrShader.output;
import helder.scene.render.PbrShader.fogAmount;
import helder.scene.render.Equirect;

// The environment's background (Environment): as the sky's quad, each
// pixel the environment map's colour along its view direction (an
// equirectangular image: longitude across, latitude down), times the
// environment's intensity, in the fog to the far plane (Fog), tone mapped and encoded as the standard
// material is (Equirect: also the standard material's lookup).
@:structInit @:publicFields class EnvironmentParams {
	var invViewProj:Mat4;
	var eye:Vec4;
	var params:Vec4; // x: intensity times exposure, y: 1 into an HDR target, z: an atlas's levels (0: none), w: half a texel of its row
	var fog:Vec4; // the renderer's (Fog.colorOf, its colour times the exposure; shapeOf)
	var fogShape:Vec4;
}

final EnvironmentShader = shader({
	vertex: function(v:SkyVertex):SkyVaryings
		return {clip: position(vec4(v.pos, 0.9999, 1)), ndc: v.pos},
	fragment: function(i:SkyVaryings, p:{env:EnvironmentParams, environmentMap:Texture2D}):Vec4 {
		var far = p.env.invViewProj * vec4(i.ndc, 1, 1);
		var d = normalize(far.xyz / far.w - p.env.eye.xyz);
		var color = pow(sampleLevel(p.environmentMap, equirect(d), 0).xyz, vec3(2.2)) * p.env.params.x;
		if (p.env.params.z > 0) color = pow(atlas(p.environmentMap, equirect(d), 0, p.env.params.z, p.env.params.w), vec3(2.2)) * p.env.params.x;
		color = mix(color, p.env.fog.xyz, fogAmount(p.env.fog, p.env.fogShape, p.env.eye.xyz, far.xyz / far.w));
		return vec4(output(color, p.env.params.y), 1);
	}
});
