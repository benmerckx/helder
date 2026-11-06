package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;

// The shadow map's pass (Shadows): each caster seen from the light, its
// depth (0 near the light, 1 far) written to an R32F target. A slot object
// of options only, shadowCaster, whose variants are the plain caster's
// (ShadowShader), a skinned one's (ShadowSkinnedShader: the vertex moved by
// its joints as pbr's skinned variant moves it) and an instanced set's
// (ShadowInstancedShader: each instance's world matrix from the instance
// buffer, pbr's instanced layout; the caster's block the light's
// view-projection alone). The vertex is pbr's, laid out as each reads it.
typedef ShadowVaryings = {
	var clip:Vec4;
	var depth:Float;
}

typedef ShadowCaster = {
	var mvp:Mat4; // the light's view-projection times the node's world matrix
}

typedef ShadowParams = {
	var caster:ShadowCaster;
	@:optional var skin:PbrSkinInfo;
	@:optional var jointMatrices:Texture2D;
}

typedef ShadowOptions = {skinned:Bool, instanced:Bool};
typedef Shadow = {options:ShadowOptions};

final shadowCaster = slots({
	options: {skinned: false, instanced: false},
	vertex: function(v:PbrVertex, p:ShadowParams, m:Shadow):ShadowVaryings {
		var pos = v.pos;
		if (m.options.skinned) {
			var j0 = joint(p.jointMatrices, v.joints.x, p.skin.rows.x), j1 = joint(p.jointMatrices, v.joints.y, p.skin.rows.x);
			var j2 = joint(p.jointMatrices, v.joints.z, p.skin.rows.x), j3 = joint(p.jointMatrices, v.joints.w, p.skin.rows.x);
			var q = vec4(v.pos, 1);
			pos = ((j0 * q) * v.weights.x + (j1 * q) * v.weights.y + (j2 * q) * v.weights.z + (j3 * q) * v.weights.w).xyz;
		}
		var clip = m.options.instanced ? p.caster.mvp * (mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), v.m3) * vec4(pos, 1)) : p.caster.mvp * vec4(pos, 1);
		return {clip: position(clip), depth: clip.z / clip.w};
	},
	fragment: function(i:ShadowVaryings, p:{}, m:Shadow):Vec4
		return vec4(i.depth, 0, 0, 1)
});

final ShadowShader = shadowCaster.variant();
