// a job's function is named (in Haxe: RejectJobArrow.hx).
// expect: job: a job is a static or module-level function, named (Class.field, field)
import {job} from "helder/jobs";

export const j = job((x: number) => x + 1);
