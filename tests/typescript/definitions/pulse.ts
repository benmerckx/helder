// uniform(value) in TypeScript: the shader that reads its value gets it in
// a block of its own (Uniforms: offset, then time, as first read), the
// same text in every language as Haxe's (Pulse.hx), the same bytes.
import {shader, uniform, position, sin, vec2, vec4, type Vec2, type Vec4} from "helder/gfx";
import {print} from "./print";

type PulseVertex = {pos: Vec2};
type PulseVaryings = {clip: Vec4, uv: Vec2};
type PulseTint = {color: Vec4};

export const time = uniform(0);
export const offset = uniform(vec2(0, 0));

export const PulseShader = shader({
	vertex: (v: PulseVertex): PulseVaryings => ({clip: position(vec4(v.pos.add(offset.value), 0, 1)), uv: v.pos}),
	fragment: (i, p: {tint: PulseTint}) => vec4(p.tint.color.xyz.mul(sin(time.value) * 0.5 + 0.5), 1),
});

print(PulseShader);
time.value = 1.5;
offset.value = vec2(0.25, -0.5);
// (the block with the values now; the stages on the CPU read them as they are)
console.log(PulseShader.uniformBinding, PulseShader.params.tint.block.binding, Array.from(PulseShader.uniformBytes()!).join(","));
const o = PulseShader.vertex({pos: vec2(1, 1)});
console.log(o.clip.x, o.clip.y);
