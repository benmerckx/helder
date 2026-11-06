// A uniform's value is read in a stage, passed on to what it calls (in Haxe: RejectUniformHelper.hx).
// expect: shader: time.value: a uniform is read in a stage (its value passed on to the functions it calls)
import {shader, uniform, position, vec4, type Vec2, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
export const time = uniform(0);

function later(o: O): Vec4 {
	return o.pos.mul(time.value);
}

export const S = shader({vertex: (v: V): O => ({pos: position(vec4(v.pos, 0, 1))}), fragment: (o: O) => later(o)});
