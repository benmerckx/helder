package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrNormalShader;

// The normal-mapped material drawn many times in one call (NormalMaps,
// for Renderer's instanced runs): PbrNormalShader's vertex with each
// instance's world matrix by columns from a third buffer (the mesh's
// vertices, its tangents, the instances'), normals and tangents turned by
// the matrix's upper 3x3 (uniform scales only, as PbrInstancedShader's);
// the fragment is PbrNormalShader's.
@:structInit @:publicFields class PbrInstanceNormalVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var tangent:Vec4;
	// per instance: the world matrix's columns
	var m0:Vec4;
	var m1:Vec4;
	var m2:Vec4;
	var m3:Vec4;
}

class PbrInstancedNormalShader implements Shaders {
	@:vertex static function vs(v:PbrInstanceNormalVertex, frame:PbrFrame):PbrNormalVaryings {
		var model = mat4(v.m0, v.m1, v.m2, v.m3);
		var world = model * vec4(v.pos, 1);
		return {
			clip: frame.viewProj * world,
			world: world.xyz,
			normal: (model * vec4(v.normal, 0)).xyz,
			uv: v.uv,
			tangent: vec4((model * vec4(v.tangent.xyz, 0)).xyz, v.tangent.w)
		};
	}

	@:fragment static function fs(i:PbrNormalVaryings, frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D,
			metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D, normalTexture:Texture2D):Vec4 {
		var ng = normalize(i.normal);
		var t = normalize(i.tangent.xyz - ng * dot(ng, i.tangent.xyz));
		var b = cross(ng, t) * i.tangent.w;
		var m = sample(normalTexture, i.uv).xyz * 2 - 1;
		var scale = material.params.z;
		var n = normalize(t * (m.x * scale) + b * (m.y * scale) + ng * m.z);
		return PbrShader.shadeAt(n, i.world, i.uv, frame, material, baseColorTexture, metallicRoughnessTexture, emissiveTexture, occlusionTexture,
			shadowMap, shadowMapFar, environmentMap);
	}
}
