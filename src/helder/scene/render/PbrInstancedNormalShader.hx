package helder.scene.render;

import helder.scene.render.PbrShader;

// The normal-mapped material drawn many times in one call (NormalMaps, for
// Renderer's instanced runs): the instance's world matrix from a third
// buffer (the mesh's vertices, its tangents, the instances'), tangents
// turned by its upper 3x3, normals by its inverse transpose (pbr's
// instanced and normalMap).
final PbrInstancedNormalShader = pbr.variant({instanced: true, normalMap: true});
