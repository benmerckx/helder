// The varyings have one position(...) (in Haxe: RejectNoPosition.hx).
// expect: shader: the vertex function: exactly one field of NoPosition is the clip-space position, marked by position(...) where it is built (it has 0)
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
type NoPosition = {color: Vec4};
export const S = shader({vertex: (v: V): NoPosition => ({color: vec4(v.pos, 0, 1)}), fragment: (o: NoPosition) => o.color});
