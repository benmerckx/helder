package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;

// The shadow map's pass (Shadows): each caster seen from the light, its
// depth (0 near the light, 1 far) written to an R32F target.
@:structInit @:publicFields class ShadowVaryings {
	var clip:Vec4;
	var depth:Float;
}

@:structInit @:publicFields class ShadowCaster {
	var mvp:Mat4; // the light's view-projection times the node's world matrix
}

final ShadowShader = shader({
	vertex: function(v:PbrVertex, caster:ShadowCaster):ShadowVaryings {
		var clip = caster.mvp * vec4(v.pos, 1);
		return {clip: position(clip), depth: clip.z / clip.w};
	},
	fragment: function(i:ShadowVaryings):Vec4
		return vec4(i.depth, 0, 0, 1)
});
