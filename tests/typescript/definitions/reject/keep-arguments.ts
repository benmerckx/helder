// keep's initial value takes no arguments (in Haxe: RejectKeepArguments.hx).
// expect: keep: the initial value is made by a function of no arguments (() => value), not of 1
import {keep} from "helder/dev";

export const n = keep("n", (x?: number) => x ?? 0);
