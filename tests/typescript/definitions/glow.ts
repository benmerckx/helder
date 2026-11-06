// A slot object and a slot overridden (helder/gfx's slots, variant, with)
// in TypeScript: the same text in every language as Haxe's (Glow.hx), the
// same CPU stages' values. lit's variants: Lit (the defaults), Glow (its
// emissive slot replaced by one with a uniform block of its own, after the
// stages'; tinted: the vertex's optional tint read, a varying kept).
import {slots, position, vec2, vec3, vec4, sin, type Vec2, type Vec3, type Vec4} from "helder/gfx";
import {print} from "./print";

type GlowVertex = {pos: Vec2, uv: Vec2, tint?: Vec4};
type GlowVaryings = {clip: Vec4, uv: Vec2, tint?: Vec4};
type GlowView = {scale: Vec4};
type GlowTint = {color: Vec4};
type GlowTime = {seconds: Vec4};
type GlowSurface = {uv: Vec2, base: Vec3};
type GlowParams = {view: GlowView, tint: GlowTint};
type GlowOptions = {tinted: boolean};
type GlowSlots = {options: GlowOptions, color: (s: GlowSurface, p: GlowParams) => Vec3, emissive: (s: GlowSurface, p: GlowParams) => Vec3};

function baseColor(s: GlowSurface, p: {tint: GlowTint}): Vec3 {
	return s.base.mul(p.tint.color.xyz);
}

function noLight(s: GlowSurface, p: {}): Vec3 {
	return vec3(0);
}

export const lit = slots({
	options: {tinted: false},
	vertex: (v: GlowVertex, p: {view: GlowView}, m: GlowSlots): GlowVaryings =>
		({clip: position(vec4(v.pos.mul(p.view.scale.xy), 0, 1)), uv: v.uv, tint: m.options.tinted ? v.tint! : vec4(1)}),
	fragment: (i: GlowVaryings, p: GlowParams, m: GlowSlots) => {
		let base = vec3(i.uv, 1);
		if (m.options.tinted) base = base.mul(i.tint!.xyz);
		const s: GlowSurface = {uv: i.uv, base: base};
		return vec4(m.color(s, p).add(m.emissive(s, p)), 1);
	},
	color: baseColor,
	emissive: noLight,
});

export const LitShader = lit.variant();
export const GlowShader = lit.with({emissive: (s: GlowSurface, p: {time: GlowTime}) => vec3(0.2, 0.6, 1).mul(sin(p.time.seconds.x) * 0.5 + 0.5)}).variant({tinted: true});

print(LitShader);
print(GlowShader);
// (the variants' writers by their parameters' names, the slot's own among them; Lit's stages on the CPU)
console.log(GlowShader.params.time.block.binding, GlowShader.params.tint.block.binding, LitShader.layout[0].stride, GlowShader.layout[0].stride);
const c = LitShader.fragment({clip: vec4(0), uv: vec2(0.5, 0.25)}, {view: {scale: vec4(1)}, tint: {color: vec4(0.5, 1, 1, 1)}});
console.log(c.x, c.y, c.z, c.w);
const o = LitShader.vertex({pos: vec2(1, 2), uv: vec2(0, 1)}, {view: {scale: vec4(2)}});
console.log(o.clip.x, o.clip.y, o.clip.z, o.clip.w);
