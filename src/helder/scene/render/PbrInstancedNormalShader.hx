package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrNormalShader;
import helder.scene.render.PbrShader.shadeAt;
import helder.scene.render.PbrShader.uvOf;

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

final PbrInstancedNormalShader = shader({
	vertex: function(v:PbrInstanceNormalVertex, p:{frame:PbrFrame}):PbrNormalVaryings {
		var model = mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), v.m3);
		var world = model * vec4(v.pos, 1);
		return {
			clip: position(p.frame.viewProj * world),
			world: world.xyz,
			normal: (model * vec4(v.normal, 0)).xyz,
			uv: v.uv,
			tangent: vec4((model * vec4(v.tangent.xyz, 0)).xyz, v.tangent.w),
			up: v.m1.xyz,
			tint: vec3(1 + v.m0.w, 1 + v.m1.w, 1 + v.m2.w)
		};
	},
	fragment: function(i:PbrNormalVaryings, p:{frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D, metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D, normalTexture:Texture2D}):Vec4 {
		var ng = normalize(i.normal);
		var t = normalize(i.tangent.xyz - ng * dot(ng, i.tangent.xyz));
		var b = cross(ng, t) * i.tangent.w;
		var uv = uvOf(p.material, i.uv);
		var m = sample(p.normalTexture, uv).xyz * 2 - 1;
		var scale = p.material.params.z;
		var n = normalize(t * (m.x * scale) + b * (m.y * scale) + ng * m.z);
		return shadeAt(n, i.world, uv, normalize(i.up), i.tint, p.frame, p.material, p.baseColorTexture, p.metallicRoughnessTexture, p.emissiveTexture, p.occlusionTexture,
			p.shadowMap, p.shadowMapFar, p.environmentMap);
	}
});
