package helder.gfx.shader;

import haxe.macro.Expr;

// The builtins of shader code, usable in CPU code as well (import
// helder.gfx.shader.ShaderMath.*): the constructors vec2, vec3, vec4 and mat4
// (as GLSL's: vec4(v.xy, 0, 1), vec3(1)), GLSL's componentwise functions on
// Float and the vectors (abs, sign, floor, ceil, fract, sqrt, inversesqrt,
// sin, cos, tan, exp, log, min, max, pow, step, mix, clamp, smoothstep) and
// the geometric ones (dot, length, distance, normalize, reflect, cross),
// and sample(t, uv), a Texture2D's colour at uv (in the fragment stage at
// the mip level its footprint needs, in the vertex stage the first), and
// sampleLevel(t, uv, level) at a mip level (fractions blend two levels with
// a sampler's mipFilter Linear); discard(), in the fragment stage, drops the
// fragment (alpha testing: nothing on the CPU). Written out by
// VecBuild.builtins.
//
// And the shader definition, shader({vertex, fragment}) (Shader), with
// position(v), which marks the varyings' clip-space position where the
// vertex stage builds them ({clip: position(m * p), uv: v.uv}).
#if !macro
@:build(helder.gfx.shader.VecBuild.builtins())
#end
class ShaderMath {
	// a pipeline's two stages, compiled at build time (Shader)
	@:definition public static macro function shader(def:Expr):Expr
		return helder.gfx.shader.ShaderMacro.shader(def);

	#if !macro
	// the clip-space position among a vertex stage's varyings (its value as it is)
	public static inline function position(v:Vec4):Vec4
		return v;
	#end
}
