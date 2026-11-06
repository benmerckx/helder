// The fragment stage takes what the vertex stage returns (in Haxe: RejectMismatch.hx).
// expect: shader: stage interface mismatch: the fragment function takes Other, but the vertex function returns O
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
type Other = {pos: Vec4, color: Vec3};
export const S = shader({vertex: (v: V): O => ({pos: position(vec4(v.pos, 0, 1))}), fragment: ((o: Other) => vec4(o.color, 1)) as any});
