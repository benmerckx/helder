// a job takes one argument at most (in TypeScript: job-arguments.ts).
// expect: job: add takes 2 arguments (a job takes one at most: an anonymous structure for more)
import helder.jobs.Jobs;

class RejectJobArguments {
	static function main() {
		trace(Jobs.job(add));
	}

	static function add(a:Float, ?b:Float):Float {
		return a + (b ?? 0);
	}
}
