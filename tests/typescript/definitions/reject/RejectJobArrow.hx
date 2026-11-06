// a job's function is named (in TypeScript: job-arrow.ts).
// expect: job: a job is a static or module-level function, named (Class.field, field)
import helder.jobs.Jobs;

class RejectJobArrow {
	static function main() {
		trace(Jobs.job((x:Int) -> x + 1));
	}
}
