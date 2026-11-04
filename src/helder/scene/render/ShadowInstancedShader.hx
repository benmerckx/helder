package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrInstancedShader;
import helder.scene.render.ShadowShader;

// The shadow map's pass for instanced sets (Shadows, InstancedMesh): each
// instance's world matrix from the instance buffer (PbrInstancedShader's
// layout), the caster's block the light's view-projection alone.
class ShadowInstancedShader implements Shaders {
	@:vertex static function vs(v:PbrInstanceVertex, caster:ShadowCaster):ShadowVaryings {
		var model = mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), v.m3);
		var clip = caster.mvp * (model * vec4(v.pos, 1));
		return {clip: clip, depth: clip.z / clip.w};
	}

	@:fragment static function fs(i:ShadowVaryings):Vec4
		return vec4(i.depth, 0, 0, 1);
}
