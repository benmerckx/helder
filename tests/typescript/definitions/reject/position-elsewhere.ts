// Position(...) marks a varying where the vertex stage builds them (in Haxe: RejectPositionElsewhere.hx).
// expect: shader: position(...) marks a field of the varyings where the vertex stage builds them
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
export const S = shader({vertex: (v: V): O => ({pos: position(vec4(v.pos, 0, 1))}), fragment: (o: O) => position(o.pos)});
