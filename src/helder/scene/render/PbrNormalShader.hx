package helder.scene.render;

import helder.scene.render.PbrShader;

// The standard material with a tangent-space normal map (NormalMaps): the
// vertex's tangent from a second buffer (the primitive's tangents: x, y, z
// and the bitangent's sign), turned by the node's matrix; the fragment's
// normal read from the map (pbr's normalMap).
final PbrNormalShader = pbr.variant({normalMap: true});
