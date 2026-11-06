package helder.scene.render;

import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;
import helder.scene.render.PbrShader;
import helder.scene.render.PbrShader.shadeAt;
import helder.scene.render.PbrShader.uvOf;

// The standard material on a skinned mesh (Skin): the vertex moved by its
// four joints' matrices, weighted, read from the skin's texture (16 R32F
// texels a joint: Skin.update), then by the node's matrices as PbrShader's.
// The fragment is shadeAt's.
@:structInit @:publicFields class PbrSkinVertex {
	var pos:Vec3;
	var normal:Vec3;
	var uv:Vec2;
	var joints:Vec4;
	var weights:Vec4;
}

@:structInit @:publicFields class PbrSkinInfo {
	var rows:Vec4; // x: the joints' count
}

// joint k's matrix from its row of the texture (rows of them)
function joint(t:Texture2D, k:Float, rows:Float):Mat4 {
	var y = (k + 0.5) / rows;
	return mat4(vec4(texel(t, 0, y), texel(t, 1, y), texel(t, 2, y), texel(t, 3, y)), vec4(texel(t, 4, y), texel(t, 5, y), texel(t, 6, y), texel(t, 7, y)),
		vec4(texel(t, 8, y), texel(t, 9, y), texel(t, 10, y), texel(t, 11, y)),
		vec4(texel(t, 12, y), texel(t, 13, y), texel(t, 14, y), texel(t, 15, y)));
}

function texel(t:Texture2D, x:Float, y:Float):Float
	return sampleLevel(t, vec2((x + 0.5) / 16, y), 0).x;

final PbrSkinnedShader = shader({
	vertex: function(v:PbrSkinVertex, params:{frame:PbrFrame, object:PbrObject, skin:PbrSkinInfo, jointMatrices:Texture2D}):PbrVaryings {
		var j0 = joint(params.jointMatrices, v.joints.x, params.skin.rows.x), j1 = joint(params.jointMatrices, v.joints.y, params.skin.rows.x);
		var j2 = joint(params.jointMatrices, v.joints.z, params.skin.rows.x), j3 = joint(params.jointMatrices, v.joints.w, params.skin.rows.x);
		var p = vec4(v.pos, 1), nr = vec4(v.normal, 0);
		var pos = (j0 * p) * v.weights.x + (j1 * p) * v.weights.y + (j2 * p) * v.weights.z + (j3 * p) * v.weights.w;
		var normal = (j0 * nr) * v.weights.x + (j1 * nr) * v.weights.y + (j2 * nr) * v.weights.z + (j3 * nr) * v.weights.w;
		var world = params.object.model * vec4(pos.xyz, 1);
		return {
			clip: position(params.frame.viewProj * world),
			world: world.xyz,
			normal: (params.object.normalMatrix * vec4(normal.xyz, 0)).xyz,
			uv: v.uv,
			up: (params.object.model * vec4(0, 1, 0, 0)).xyz,
			tint: params.object.tint.xyz
		};
	},
	fragment: function(i:PbrVaryings, p:{frame:PbrFrame, material:PbrMaterial, baseColorTexture:Texture2D, metallicRoughnessTexture:Texture2D, emissiveTexture:Texture2D, occlusionTexture:Texture2D, shadowMap:Texture2D, shadowMapFar:Texture2D, environmentMap:Texture2D}):Vec4
		return shadeAt(normalize(i.normal), i.world, uvOf(p.material, i.uv), normalize(i.up), i.tint, p.frame, p.material, p.baseColorTexture, p.metallicRoughnessTexture, p.emissiveTexture,
			p.occlusionTexture, p.shadowMap, p.shadowMapFar, p.environmentMap)
});
