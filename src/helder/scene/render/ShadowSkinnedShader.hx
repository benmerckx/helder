package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrSkinnedShader;
import helder.scene.render.ShadowShader;
import helder.scene.render.PbrSkinnedShader.joint;

// A skinned caster in the shadow map's pass (Skinning with Shadows): the
// vertex moved by its joints as PbrSkinnedShader moves it, then seen from
// the light; its depth written as ShadowShader writes it.
final ShadowSkinnedShader = shader({
	vertex: function(v:PbrSkinVertex, params:{caster:ShadowCaster, skin:PbrSkinInfo, jointMatrices:Texture2D}):ShadowVaryings {
		var j0 = joint(params.jointMatrices, v.joints.x, params.skin.rows.x), j1 = joint(params.jointMatrices, v.joints.y, params.skin.rows.x);
		var j2 = joint(params.jointMatrices, v.joints.z, params.skin.rows.x), j3 = joint(params.jointMatrices, v.joints.w, params.skin.rows.x);
		var p = vec4(v.pos, 1);
		var pos = (j0 * p) * v.weights.x + (j1 * p) * v.weights.y + (j2 * p) * v.weights.z + (j3 * p) * v.weights.w;
		var clip = params.caster.mvp * vec4(pos.xyz, 1);
		return {clip: position(clip), depth: clip.z / clip.w};
	},
	fragment: function(i:ShadowVaryings):Vec4
		return vec4(i.depth, 0, 0, 1)
});
