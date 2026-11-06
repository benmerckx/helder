package helder.scene.render;

import helder.scene.render.ShadowShader;

// A skinned caster in the shadow map's pass (Skinning with Shadows): the
// vertex moved by its joints, then seen from the light (shadowCaster's skinned).
final ShadowSkinnedShader = shadowCaster.variant({skinned: true});
