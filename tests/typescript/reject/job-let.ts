// A job reads module-level constants only (sent with its input): not a let.
// expect: job: a job cannot read `count`: a let or var (a job reads module-level constants, sent with its input)
import {job} from "helder/jobs";

let count = 1;
function next(x: number): number {
	return x + count;
}
export const j = job(next);
