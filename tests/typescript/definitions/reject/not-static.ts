// A definition's argument is static (in Haxe: RejectNotStatic.hx).
// expect: shader: stages is not static
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
const stages = {vertex: (v: V): O => ({pos: position(vec4(v.pos, 0, 1))}), fragment: (o: O) => o.pos};
export const S = shader(stages);
