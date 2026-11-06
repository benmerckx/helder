package helder.scene.render;

import helder.scene.render.ShadowShader;

// The shadow map's pass for instanced sets (Shadows, InstancedMesh): each
// instance's world matrix from the instance buffer (pbr's instanced
// layout), the caster's block the light's view-projection alone
// (shadowCaster's instanced).
final ShadowInstancedShader = shadowCaster.variant({instanced: true});
