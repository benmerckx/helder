// keep's key is not empty (in Haxe: RejectKeepEmptyKey.hx).
// expect: keep: the key is empty
import {keep} from "helder/dev";

export const n = keep("", () => 0);
