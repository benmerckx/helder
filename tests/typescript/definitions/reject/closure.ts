// A closure is not shader code (in Haxe: RejectClosure.hx).
// expect: shader: a closure is not supported in a shader
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
export const S = shader({vertex: (v: V): O => {
	const f = (x: number) => x * 2;
	return {pos: position(vec4(v.pos, f(0.5), 1))};
}, fragment: (o: O) => o.pos});
