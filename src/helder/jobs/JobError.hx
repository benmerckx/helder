package helder.jobs;

// A job's failure, thrown in the awaiting task: a GC-free job's code (its
// result < 0), or a GC job's exception (code -1, its message; the
// exception itself stays on the thread or in the worker that threw it).
class JobError extends haxe.Exception {
	public final code:Int;

	public function new(code:Int, ?message:String) {
		super(message ?? 'job failed: $code');
		this.code = code;
	}
}
