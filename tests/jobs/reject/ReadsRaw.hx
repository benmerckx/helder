import helder.async.Async;
import helder.jobs.Job;
import helder.jobs.Jobs;

// a GC-free job is a checked kernel: one reading raw memory is rejected by
// hxmc (the jobs lane expects "Mem, Atomic and C functions need @:hxmc.unsafe")
class ReadsRaw {
	@:hxmc.kernel @:hxmc.callback static function peek(job:Job):Int
		return hxmc.unsafe.Mem.getI32(hxmc.unsafe.Ptr.nil(), 0);

	static function main() {
		Async.run(_ -> Jobs.job(peek).run());
	}
}
