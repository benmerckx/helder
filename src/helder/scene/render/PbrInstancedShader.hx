package helder.scene.render;

import helder.scene.render.PbrShader;

// The standard material drawn many times in one call (Renderer: the
// primitives of a frame that share a mesh and a material): each instance's
// world matrix by columns from a second buffer that steps per instance
// (layout), normals turned by its upper 3x3's inverse transpose (any
// scale, uneven too: pbr's instanceNormal; pbr's instanced).
final PbrInstancedShader = pbr.variant({instanced: true});
