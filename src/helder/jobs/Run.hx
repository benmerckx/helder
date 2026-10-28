package helder.jobs;

import haxe.coro.IContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import helder.async.Async;
import helder.async.Loop;
import hxmc.unsafe.Blocking;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;

// A job's run, on the loop of the task that awaits it: its record (Job),
// handed to the pool (Pool), a browser's workers (WebJobs) or run on the
// loop; done there, it resumes the task, or frees what it made when the task
// was cancelled meanwhile.
@:allow(helder.jobs)
class Run implements IDispatchObject {
	static var nextId = 1;

	final id = nextId++;
	final fn:Ptr;
	final gcFree:Bool;
	final job:Job;
	final loop:Loop;
	var cont:Null<IContinuation<Run>>;
	var abandoned = false;
	var finished = false;
	// (the loop held while a worker has it)
	var held = false;
	// the result: the status, the output (the awaiter's once taken)
	var status = 0;
	var output:IoBuffer;

	function new(fn, gcFree, input:IoBuffer, loop, cont) {
		this.fn = fn;
		this.gcFree = gcFree;
		this.loop = loop;
		this.cont = cont;
		job = Job.make(input);
		output = cast Ptr.nil();
	}

	// the run, done (its error thrown)
	@:coroutine static function await(fn:Ptr, gcFree:Bool, input:IoBuffer):Run {
		var r = Async.suspendCancellable(cont -> {
			var run = new Run(fn, gcFree, input, Async.loopOf(cont.context), cont);
			run.start();
			return _ -> run.cancel();
		});
		if (r.status < 0) {
			var m = null;
			if (!gcFree && !(cast r.output : Ptr).isNull()) m = try new Wire.Reader(r.output).string() catch (_:Dynamic) null;
			if (!(cast r.output : Ptr).isNull()) r.output.free();
			r.output = cast Ptr.nil();
			throw new JobError(r.status, m);
		}
		return r;
	}

	function start() {
		// (held first: the worker's post may come at once)
		loop.hold();
		if (#if (hxmc.target == "wasm32-wasi") WebJobs.submit(this) #else Pool.submit(this) #end) {
			held = true;
			return;
		}
		loop.release();
		// (no workers: on the loop, at its next turn)
		loop.dispatch(this);
	}

	// (dispatched: run on the loop)
	public function onDispatch() {
		if (!abandoned) execute();
		finish();
	}

	// (on a worker thread, or on the loop): the job's call, in a safe region if it is GC-free
	function execute() {
		var j = job.ptr(), f = fn, s = 0;
		if (job.cancelled) s = CANCELLED else if (gcFree) {
			var region = Blocking.enter();
			s = FreeCall.call(f, j);
			Blocking.leave(region);
		} else
			s = GcCall.call(f, j);
		job.status = s;
		job.dropInput();
	}

	// (on the loop: the job is over)
	function finish()
		arrive(job.status, job.takeOutput());

	// (on the loop: the result)
	function arrive(status:Int, out:IoBuffer) {
		if (finished) {
			if (!(cast out : Ptr).isNull()) out.free();
			return;
		}
		finished = true;
		job.free();
		if (held) loop.release();
		held = false;
		if (abandoned) {
			if (!(cast out : Ptr).isNull()) out.free();
			return;
		}
		this.status = status;
		output = out;
		var c = cont;
		cont = null;
		c.resume(this, null);
	}

	// (the awaiting task cancelled: resumed already by its cancellation)
	function cancel() {
		if (finished) return;
		abandoned = true;
		cont = null;
		job.cancel();
		#if (hxmc.target == "wasm32-wasi")
		if (WebJobs.cancel(this)) {
			finished = true;
			job.free();
			if (held) loop.release();
			held = false;
		}
		#end
	}

	// (the status of a job skipped: cancelled before it started)
	static inline var CANCELLED = -0x7FFF;
}

// (the calls of a job by its address: a GC-free one in the caller's safe
// region, a GC one in a region its callback's wrapper leaves for its Haxe)
@:hxmc.c @:hxmc.fast extern class FreeCall {
	@:hxmc.indirect static function call(f:Ptr, job:Ptr):Int;
}

@:hxmc.c extern class GcCall {
	@:hxmc.indirect static function call(f:Ptr, job:Ptr):Int;
}
