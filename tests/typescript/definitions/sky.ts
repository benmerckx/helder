// helder.scene's sky (src/helder/scene/render/SkyShader.hx) in TypeScript:
// the same text in every language as Haxe's (Sky.hx prints that one).
import {shader, position, vec2, vec3, vec4, mix, normalize, pow, clamp, max, dot, type Vec2, type Vec3, type Vec4, type Mat4} from "helder/gfx";
import {print} from "./print";

type SkyVertex = {pos: Vec2};
type SkyVaryings = {clip: Vec4, ndc: Vec2};
type SkyParams = {invViewProj: Mat4, eye: Vec4, zenith: Vec4, horizon: Vec4, ground: Vec4, sun: Vec4, sunColor: Vec4};

function output(c: Vec3, hdr: number): Vec3 {
	let result = c;
	if (hdr < 0.5) result = encode(aces(c));
	return result;
}

function aces(x: Vec3): Vec3 {
	return clamp(x.mul(x.mul(2.51).add(0.03)).div(x.mul(x.mul(2.43).add(0.59)).add(0.14)), 0, 1);
}

function encode(c: Vec3): Vec3 {
	return pow(c, vec3(1 / 2.2));
}

export const SkyShader = shader({
	vertex: (v: SkyVertex): SkyVaryings => ({clip: position(vec4(v.pos, 0.9999, 1)), ndc: v.pos}),
	fragment: (i, sky: SkyParams) => {
		const far = sky.invViewProj.mul(vec4(i.ndc, 1, 1));
		const d = normalize(far.xyz.div(far.w).sub(sky.eye.xyz));
		const up = d.y;
		const above = mix(sky.horizon.xyz, sky.zenith.xyz, pow(clamp(up, 0, 1), 0.5));
		const below = mix(sky.horizon.xyz, sky.ground.xyz, pow(clamp(-up, 0, 1), 0.4));
		let color = up > 0 ? above : below;
		const s = max(dot(d, sky.sun.xyz), 0);
		color = color.add(sky.sunColor.xyz.mul(pow(s, 600) * 8 + pow(s, 12) * 0.25));
		return vec4(output(color.mul(sky.sun.w), sky.sunColor.w), 1);
	},
});

print(SkyShader);
console.log(SkyShader.vertexBytes([{pos: vec2(0.5, -1)}]).join(","));
