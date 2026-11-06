package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrShader.shadeAt;
import helder.scene.render.PbrShader.uvOf;

// The standard material with a tangent-space normal map (NormalMaps): the
// vertex as PbrShader's and its tangent from a second buffer (the
// primitive's tangents: x, y, z and the bitangent's sign), turned by the
// node's matrix; the fragment's normal read from the map (glTF's: x and y
// scaled by the material's normal scale, the bitangent n x t times the
// sign, green up the image), then shadeAt.
@:structInit @:publicFields class PbrNormalVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var tangent:Vec4;
}

@:structInit @:publicFields class PbrNormalVaryings {
	var clip:Vec4;
	var world:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var tangent:Vec4;
	var up:Vec3;
	var tint:Vec3;
}

final PbrNormalShader = shader({
	vertex: function(v:PbrNormalVertex, p:{frame:PbrFrame, object:PbrObject}):PbrNormalVaryings {
		var world = p.object.model * vec4(v.pos, 1);
		return {
			clip: position(p.frame.viewProj * world),
			world: world.xyz,
			normal: (p.object.normalMatrix * vec4(v.normal, 0)).xyz,
			uv: v.uv,
			tangent: vec4((p.object.model * vec4(v.tangent.xyz, 0)).xyz, v.tangent.w),
			up: (p.object.model * vec4(0, 1, 0, 0)).xyz,
			tint: p.object.tint.xyz
		};
	},
	fragment: function(i:PbrNormalVaryings, p:{frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D, metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D, normalTexture:Texture2D}):Vec4 {
		var ng = normalize(i.normal);
		// (the tangent made at right angles to the interpolated normal)
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
