package hxmc.gfx.shader;

// The builtins of shader code, usable in CPU code as well (import
// hxmc.gfx.shader.ShaderMath.*): the constructors vec2, vec3, vec4 and mat4
// (as GLSL's: vec4(v.xy, 0, 1), vec3(1)), GLSL's componentwise functions on
// Float and the vectors (abs, sign, floor, ceil, fract, sqrt, inversesqrt,
// sin, cos, tan, exp, log, min, max, pow, step, mix, clamp, smoothstep) and
// the geometric ones (dot, length, distance, normalize, reflect, cross),
// and sample(t, uv), a Texture2D's colour at uv (in the fragment stage at
// the mip level its footprint needs, in the vertex stage the first), and
// sampleLevel(t, uv, level) at a mip level (fractions blend two levels with
// a sampler's mipFilter Linear).
// Written out by VecBuild.builtins.
@:build(hxmc.gfx.shader.VecBuild.builtins())
class ShaderMath {}
