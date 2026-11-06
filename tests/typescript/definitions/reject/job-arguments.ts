// a job takes one argument at most (in Haxe: RejectJobArguments.hx).
// expect: job: add takes 2 arguments (a job takes one at most: an anonymous structure for more)
import {job} from "helder/jobs";

function add(a: number, b?: number): number {
	return a + (b ?? 0);
}

export const j = job(add);
