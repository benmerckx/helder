import helder.gfx.shader.*;
import helder.gfx.shader.ShaderMath.*;

// A slot object and a slot overridden (ShaderMath.slots, variant, with) as
// Haxe compiles them: glow.ts prints the same.
typedef GlowVertex = {
	var pos:Vec2;
	var uv:Vec2;
	@:optional var tint:Vec4;
}

typedef GlowVaryings = {
	var clip:Vec4;
	var uv:Vec2;
	@:optional var tint:Vec4;
}

typedef GlowView = {scale:Vec4};
typedef GlowTint = {color:Vec4};
typedef GlowTime = {seconds:Vec4};
typedef GlowSurface = {uv:Vec2, base:Vec3};
typedef GlowParams = {view:GlowView, tint:GlowTint};
typedef GlowOptions = {tinted:Bool};
typedef GlowSlots = {options:GlowOptions, color:(GlowSurface, GlowParams) -> Vec3, emissive:(GlowSurface, GlowParams) -> Vec3};

function baseColor(s:GlowSurface, p:{tint:GlowTint}):Vec3
	return s.base * p.tint.color.xyz;

function noLight(s:GlowSurface, p:{}):Vec3
	return vec3(0);

final lit = slots({
	options: {tinted: false},
	vertex: function(v:GlowVertex, p:{view:GlowView}, m:GlowSlots):GlowVaryings
		return {clip: position(vec4(v.pos * p.view.scale.xy, 0, 1)), uv: v.uv, tint: m.options.tinted ? v.tint : vec4(1)},
	fragment: function(i:GlowVaryings, p:GlowParams, m:GlowSlots):Vec4 {
		var base = vec3(i.uv, 1);
		if (m.options.tinted) base = base * i.tint.xyz;
		var s:GlowSurface = {uv: i.uv, base: base};
		return vec4(m.color(s, p) + m.emissive(s, p), 1);
	},
	color: baseColor,
	emissive: noLight
});

final LitShader = lit.variant();
final GlowShader = lit.with({emissive: function(s:GlowSurface, p:{time:GlowTime}):Vec3 return vec3(0.2, 0.6, 1) * (sin(p.time.seconds.x) * 0.5 + 0.5)})
	.variant({tinted: true});

class Glow {
	static function main() {
		Print.shader(LitShader);
		Print.shader(GlowShader);
		Sys.println('${GlowShader.params.time.block.binding} ${GlowShader.params.tint.block.binding} ${LitShader.layout[0].stride} ${GlowShader.layout[0].stride}');
		var c = LitShader.fragment({clip: vec4(0), uv: vec2(0.5, 0.25)}, {view: {scale: vec4(1)}, tint: {color: vec4(0.5, 1, 1, 1)}});
		Sys.println('${c.x} ${c.y} ${c.z} ${c.w}');
		var o = LitShader.vertex({pos: vec2(1, 2), uv: vec2(0, 1)}, {view: {scale: vec4(2)}});
		Sys.println('${o.clip.x} ${o.clip.y} ${o.clip.z} ${o.clip.w}');
	}
}
