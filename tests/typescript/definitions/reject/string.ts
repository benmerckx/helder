// Strings are not shader values (in Haxe: RejectString.hx).
// expect: shader: a String is not a shader value
import {shader, position, vec4, type Vec2, type Vec3, type Vec4} from "helder/gfx";

type V = {pos: Vec2};
type O = {pos: Vec4};
export const S = shader({vertex: (v: V): O => {
	const s = "pos";
	return {pos: position(vec4(v.pos, s.length, 1))};
}, fragment: (o: O) => o.pos});
