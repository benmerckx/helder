package helder.gfx.shader;

import haxe.macro.Expr;

// A slot object (ShaderMath.slots, a definition: DESIGN.md 3 in
// src/helder/compiler): a shader written once with parts a caller may
// replace (its slots, each a function with a default) and options a
// variant fixes at build time:
//
//   typedef LitOptions = {lights:Int, rim:Bool};
//   typedef Lit = {options:LitOptions, color:(LitSurface, LitParams)->Vec3};
//
//   final lit = slots({
//     options: {lights: 1, rim: false},
//     vertex: function(v:LitVertex, p:{cam:Camera}, m:Lit):LitVaryings ...,
//     fragment: function(i:LitVaryings, p:LitParams, m:Lit):Vec4 {
//       var c = m.color({uv: i.uv}, p);           // a slot: its function inlined
//       if (m.options.rim) c += rim(i);           // an option: folded
//       for (k in 0...m.options.lights) ...       // a loop over one: unrolled
//     },
//     color: function(s:LitSurface, p:{tint:Tint}):Vec3 return p.tint.color.xyz
//   });
//
//   final Lit = lit.variant({rim: true});           // a Shader
//   final Glow = lit.with({color: function(s, p:{time:Time}) return ...}).variant();
//
// The stages take the object as their third parameter: m.options.<name>
// reads an option (a constant of the variant), m.<slot>(s, p) calls a slot
// (the override's function, else the default's). A slot takes its input
// and, optionally, an object of parameters of its own: its fields are the
// stage's parameters of the same names, the others join the shader's
// uniform blocks and textures after the stage's. A variant drops what it
// never reads of the optional fields (@:optional) of the vertex (its
// attributes), of the varyings and of the stages' parameters, so that one
// combined vertex (pos, normal, uv, ?tangent, ?joints, ...) is laid out as
// each variant reads it.
//
// variant(?options): a Shader, the stages with the slots and the options
// (the defaults, those given replaced) inlined, at build time: its CPU
// stages are the object's with the same (an override whose parameters are
// not the stage's throws there: it runs on the GPU only). with(slots): the
// same object with some slots replaced, for variant (and helder.scene's
// material). The object itself is nothing at run time: its stages exist as
// its variants'.
abstract Slots(Int) {
	public inline function new()
		this = 0;

	public macro function variant(self:Expr, ?options:Expr):Expr
		return helder.gfx.shader.SlotsMacro.variant(self, options);

	public macro function with(self:Expr, overrides:Expr):Expr
		return helder.gfx.shader.SlotsMacro.with(self, overrides);

	// (with's value: the object it is made from; its slots the macro's, by id)
	@:noCompletion public static function merged(base:Slots, id:Int):Slots
		return base;
}
