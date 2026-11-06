// A job runs on a worker: it does not call helder's API (the main thread's).
// expect: job: a job cannot read `delay`: helder's API (it is the main thread's)
import {job} from "helder/jobs";
import {delay} from "helder/async";

function wait(x: number): number {
	delay(x);
	return x;
}
export const j = job(wait);
