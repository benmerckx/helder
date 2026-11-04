package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;

// The standard material drawn many times in one call (Renderer: the
// primitives of a frame that share a mesh and a material): the vertex as
// PbrShader's, then each instance's world matrix by columns from a second
// buffer that steps per instance (layout); normals turned by the matrix's
// upper 3x3 (exact for rotations and uniform scales; a non-uniform scale
// is drawn without instancing). The fragment is PbrShader.shadeAt's.
@:structInit @:publicFields class PbrInstanceVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	// per instance: the world matrix's columns (their w the node's tint
	// less 1 in the first three: an affine matrix's last row is 0, 0, 0, 1)
	var m0:Vec4;
	var m1:Vec4;
	var m2:Vec4;
	var m3:Vec4;
}

class PbrInstancedShader implements Shaders {
	@:vertex static function vs(v:PbrInstanceVertex, frame:PbrFrame):PbrVaryings {
		var model = mat4(vec4(v.m0.xyz, 0), vec4(v.m1.xyz, 0), vec4(v.m2.xyz, 0), v.m3);
		var world = model * vec4(v.pos, 1);
		return {
			clip: frame.viewProj * world,
			world: world.xyz,
			normal: (model * vec4(v.normal, 0)).xyz,
			uv: v.uv,
			up: v.m1.xyz,
			tint: vec3(1 + v.m0.w, 1 + v.m1.w, 1 + v.m2.w)
		};
	}

	@:fragment static function fs(i:PbrVaryings, frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D, metallicRoughnessTexture:Texture2D,
			emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D):Vec4
		return PbrShader.shadeAt(normalize(i.normal), i.world, PbrShader.uvOf(material, i.uv), normalize(i.up), i.tint, frame, material, baseColorTexture, metallicRoughnessTexture, emissiveTexture,
			occlusionTexture, shadowMap, shadowMapFar, environmentMap);

}
