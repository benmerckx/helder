// a job's input is Sendable (in TypeScript: job-class.ts).
// expect: job: helder.jobs: area's input cannot be sent: .corner: Point is a class (shared mutable state)
import helder.jobs.Jobs;

class Point {
	public var x = 0;
}

class RejectJobClass {
	static function main() {
		trace(Jobs.job(area));
	}

	static function area(r:{corner:Point, side:Float}):Float {
		return r.side * r.side;
	}
}
