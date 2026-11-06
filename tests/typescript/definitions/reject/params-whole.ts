// A stage's object of parameters is read by its fields (in Haxe: RejectParamsWhole.hx).
// expect: shader: p, the stage's parameters, is read by its fields (p.name): it is no shader value
import {shader, position, vec4, type Vec2, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
type Tint = {color: Vec4};
export const S = shader({vertex: (v: V): O => ({pos: position(vec4(v.pos, 0, 1))}), fragment: (o: O, p: {tint: Tint}) => {
	const q = p;
	return q.tint.color;
}});
