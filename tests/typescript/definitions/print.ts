// A shader as the definitions' tests print it, the same lines as Print.hx.
import type {ShaderCode} from "helder/gfx";

export function print(s: {vertexCode: ShaderCode, fragmentCode: ShaderCode, uniforms: {name: string, binding: number, size: number}[], textures: {name: string, binding: number}[], layout: {stride: number, attributes: {location: number, format: number, offset: number}[]}[]}) {
	for (const [stage, code] of [["vertex", s.vertexCode], ["fragment", s.fragmentCode]] as const)
		for (const l of ["glsl", "wgsl", "msl", "hlsl"] as const) {
			const text = code[l];
			if (text !== undefined) console.log(`--- ${stage} ${l}\n${text}`);
		}
	for (const l of s.layout) console.log(`layout ${l.stride}: ${l.attributes.map((a) => `${a.location} ${a.format} ${a.offset}`).join(", ")}`);
	for (const u of s.uniforms) console.log(`uniform ${u.name} ${u.binding} ${u.size}`);
	for (const t of s.textures) console.log(`texture ${t.name} ${t.binding}`);
}
