// A shader takes the fields it knows (in Haxe: RejectUnknownField.hx).
// expect: shader: the argument has no field vertx (it has vertex, fragment)
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
export const S = shader({vertx: (v: V): O => ({pos: position(vec4(v.pos, 0, 1))}), fragment: (o: O) => o.pos} as any);
