package helder.scene.render;

import helder.scene.render.PbrShader;

// The standard material on a skinned mesh (Skin): the vertex moved by its
// four joints' matrices, weighted, read from the skin's texture (16 R32F
// texels a joint: Skin.update), then by the node's matrices (pbr's skinned).
final PbrSkinnedShader = pbr.variant({skinned: true});
