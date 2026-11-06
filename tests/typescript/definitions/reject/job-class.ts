// a job's input is Sendable (in Haxe: RejectJobClass.hx).
// expect: job: helder.jobs: area's input cannot be sent: .corner: Point is a class (shared mutable state)
import {job} from "helder/jobs";

class Point {
	x = 0;
}

function area(r: {corner: Point, side: number}): number {
	return r.side * r.side;
}

export const j = job(area);
