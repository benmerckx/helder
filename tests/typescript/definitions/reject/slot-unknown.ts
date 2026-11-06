// with(...) replaces the slots a slot object has (in Haxe: RejectSlotUnknown.hx).
// expect: shader: the slot object has no slot colour (it has color)
import {slots, position, vec3, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
type M = {options: {}, color: (s: Vec3, p: {}) => Vec3};

function white(s: Vec3, p: {}): Vec3 {
	return vec3(1);
}

const lit = slots({
	options: {},
	vertex: (v: V, p: {}, m: M): O => ({pos: position(vec4(v.pos, 0, 1))}),
	fragment: (o: O, p: {}, m: M) => vec4(m.color(o.pos.xyz, p), 1),
	color: white,
});
export const S = lit.with({colour: white} as any).variant();
