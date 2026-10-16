package hxmc.gfx.shader;

// The builtins of shader code, usable in CPU code as well (import
// hxmc.gfx.shader.ShaderMath.*): the constructors vec2, vec3, vec4 and mat4
// (as GLSL's: vec4(v.xy, 0, 1), vec3(1)), GLSL's componentwise functions on
// Float and the vectors (abs, sign, floor, ceil, fract, sqrt, inversesqrt,
// sin, cos, tan, exp, log, min, max, pow, step, mix, clamp, smoothstep),
// the geometric ones (dot, length, distance, normalize, reflect, cross) and
// texture(t, uv), a Texture2D's colour (level 0, as textureLod).
// Written out by VecBuild.builtins.
@:build(hxmc.gfx.shader.VecBuild.builtins())
class ShaderMath {}
