package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.SkyShader;
import helder.scene.render.PbrShader.output;
import helder.scene.render.Equirect;

// The environment's background (Environment): as the sky's quad, each
// pixel the environment map's colour along its view direction (an
// equirectangular image: longitude across, latitude down), times the
// environment's intensity, tone mapped and encoded as the standard
// material is (Equirect: also the standard material's lookup).
@:structInit @:publicFields class EnvironmentParams {
	var invViewProj:Mat4;
	var eye:Vec4;
	var params:Vec4; // x: intensity times exposure, y: 1 into an HDR target, z: an atlas's levels (0: none), w: half a texel of its row
}

final EnvironmentShader = shader({
	vertex: function(v:SkyVertex):SkyVaryings
		return {clip: position(vec4(v.pos, 0.9999, 1)), ndc: v.pos},
	fragment: function(i:SkyVaryings, env:EnvironmentParams, environmentMap:Texture2D):Vec4 {
		var far = env.invViewProj * vec4(i.ndc, 1, 1);
		var d = normalize(far.xyz / far.w - env.eye.xyz);
		var color = pow(sampleLevel(environmentMap, equirect(d), 0).xyz, vec3(2.2)) * env.params.x;
		if (env.params.z > 0) color = pow(atlas(environmentMap, equirect(d), 0, env.params.z, env.params.w), vec3(2.2)) * env.params.x;
		return vec4(output(color, env.params.y), 1);
	}
});
