package helder.jobs;

#if (hxmc.target == "wasm32-wasi")
import hxmc.unsafe.Callback;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.LibC;
import hxmc.unsafe.Ptr;

// The page's side of jobs on WebAssembly (src/helder/jobs/imports.mjs,
// module "helder_jobs"): the program's own module instantiated again in
// Web Workers (node's worker_threads under node), a job named by its
// callback's index in the function table, the same in every instance. Its
// input is copied out of this instance's memory into a transferred
// ArrayBuffer and into the worker's, its output back the same way. A
// worker's instance runs the static initializers up to WebJobs' __init__,
// which serves jobs from then on instead of running main.
@:hxmc.c @:hxmc.lib("helder_jobs") extern class JobsHost {
	// 1 in a worker's instance
	static function worker():Int;
	// (a worker's) jobs from now on: execute(fn, inputLength) runs one
	static function serve(execute:Ptr):Void;
	// (the page's) arrived(kind, id, status, length) from now on, for what
	// comes back (0 a job's result, 1 a channel's message, 2 its close); the
	// workers it will use, wanted or the cores but one (-1), 0 for none
	static function start(arrived:Ptr, wanted:Int):Int;
	static function submit(id:Int, fn:Int, input:Ptr, length:Int):Void;
	// whether it was dropped (queued, or its worker ended: no result comes)
	static function cancel(id:Int):Int;
	// what arrived (arrived's call), copied to p
	static function take(p:Ptr):Void;
	// (a worker's) the job's input copied to p; its result (p nil: none)
	static function input(p:Ptr):Void;
	static function output(status:Int, p:Ptr, length:Int):Void;
	// (a worker's) a channel's message, its close: to the page
	static function send(channel:Int, p:Ptr, length:Int):Void;
	static function close(channel:Int):Void;
}

@:allow(helder.jobs)
class WebJobs {
	static var workers = -2;
	static final runs = new Map<Int, Run>();

	static function __init__() {
		if (JobsHost.worker() == 1) {
			JobsHost.serve(Callback.addr(execute));
			Sys.exit(0);
		}
	}

	// whether this is a worker's instance
	public static inline function inWorker():Bool
		return JobsHost.worker() == 1;

	static function submit(r:Run):Bool {
		if (workers == -2) workers = JobsHost.start(Callback.addr(arrived), Jobs.workers);
		if (workers <= 0) return false;
		runs.set(r.id, r);
		var input = r.job.input;
		var p:Ptr = cast input;
		JobsHost.submit(r.id, r.fn.toI64().toInt(), p.isNull() ? Ptr.nil() : input.ptr, p.isNull() ? -1 : input.length);
		// (moved: the worker has its copy)
		r.job.dropInput();
		return true;
	}

	static function cancel(r:Run):Bool {
		if (!runs.exists(r.id)) return false;
		runs.remove(r.id);
		JobsHost.cancel(r.id);
		return true;
	}

	// (the page: a job's result, a channel's message or close)
	@:hxmc.callback static function arrived(kind:Int, id:Int, status:Int, n:Int):Int {
		var b:IoBuffer = cast Ptr.nil();
		if (n >= 0) {
			b = IoBuffer.alloc(n);
			JobsHost.take(b.ptr);
		}
		switch kind {
			case 0:
				var r = runs.get(id);
				runs.remove(id);
				if (r != null) r.arrive(status, b) else if (n >= 0) b.free();
			case 1:
				ChannelBase.deliver(id, b);
			case _:
				ChannelBase.closedBy(id);
		}
		Sys.stdout().flush();
		return 0;
	}

	// (a worker's: one job, its input copied in, its output copied out)
	@:hxmc.callback static function execute(fn:Int, n:Int):Int {
		var input:IoBuffer = cast Ptr.nil();
		if (n >= 0) {
			input = IoBuffer.alloc(n);
			JobsHost.input(input.ptr);
		}
		var job = Job.make(input);
		var s = Run.GcCall.call(Ptr.ofI64(fn), job.ptr());
		var out = job.takeOutput();
		var o:Ptr = cast out;
		JobsHost.output(s, o.isNull() ? Ptr.nil() : out.ptr, o.isNull() ? -1 : out.length);
		job.free();
		if (!o.isNull()) out.free();
		Sys.stdout().flush();
		return s;
	}
}
#end
