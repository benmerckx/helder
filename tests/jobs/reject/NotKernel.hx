import helder.async.Async;
import helder.jobs.Job;
import helder.jobs.Jobs;

// a GC-free job that is not a kernel is rejected at compile time (the jobs
// lane expects "a GC-free job is an @:hxmc.kernel @:hxmc.callback static function")
class NotKernel {
	@:hxmc.unsafe @:hxmc.callback static function raw(job:Job):Int
		return 0;

	static function main() {
		Async.run(_ -> Jobs.job(raw).run());
	}
}
