package helder.jobs;

import haxe.coro.IContinuation;
import haxe.coro.dispatchers.IDispatchObject;
import helder.async.Async;
import helder.async.Loop;
import hxmc.Buffer;
import hxmc.I64;
import hxmc.unsafe.Blocking;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;

// A job's run, on the loop of the task that awaits it: its record (Job),
// handed to the pool (Pool), a browser's workers (WebJobs) or run on the
// loop; done there, it resumes the task, or frees what it made when the task
// was cancelled meanwhile. Its awaiter holds GC values only (the function's
// address as a number, the input as a Buffer or a Writer, the result as a
// Buffer or a Reader): the raw ones stay in its trusted methods.
@:allow(helder.jobs)
@:hxmc.unsafe(gc)
class Run implements IDispatchObject {
	static var nextId = 1;

	final id = nextId++;
	final fn:I64;
	final gcFree:Bool;
	final job:JobRecord;
	final loop:Loop;
	var cont:Null<IContinuation<Run>>;
	var abandoned = false;
	var finished = false;
	// (the loop held while a worker has it)
	var held = false;
	// the result: the status, the output (the awaiter's once taken)
	var status = 0;
	var output:IoBuffer;

	// (its input moved into the record: a GC-free job's Buffer detached, a GC
	// job's bytes written; none: nil)
	function new(fn:I64, gcFree:Bool, input:Null<Buffer>, written:Null<Wire.Writer>, loop:Loop, cont:IContinuation<Run>) {
		this.fn = fn;
		this.gcFree = gcFree;
		this.loop = loop;
		this.cont = cont;
		job = JobRecord.make(input != null ? input.detach() : written != null ? written.done() : cast Ptr.nil());
		output = cast Ptr.nil();
	}

	// the run, done (its error thrown)
	@:coroutine static function await(fn:I64, gcFree:Bool, input:Null<Buffer>, written:Null<Wire.Writer>):Run {
		var r = Async.suspendCancellable(cont -> {
			var run = new Run(fn, gcFree, input, written, Async.loopOf(cont.context), cont);
			run.start();
			return _ -> run.cancel();
		});
		if (r.status < 0) throw r.error();
		return r;
	}

	// (a failed run's error: a GC job's message its output; the output freed)
	function error():JobError {
		var m = null;
		if (!gcFree && !(cast output : Ptr).isNull()) m = try new Wire.Reader(output).string() catch (_:Dynamic) null;
		discard();
		return new JobError(status, m);
	}

	// its output, the awaiter's from here: a GC-free job's (empty when it made none)
	function result():Buffer {
		var o = output;
		output = cast Ptr.nil();
		return (cast o : Ptr).isNull() ? new Buffer(0) : Buffer.adopt(o);
	}

	// (a GC job's: its bytes to read, freed with the reader)
	function reader():Wire.Reader {
		var o = output;
		output = cast Ptr.nil();
		return new Wire.Reader(o, true);
	}

	// (none wanted: freed)
	function discard() {
		if (!(cast output : Ptr).isNull()) output.free();
		output = cast Ptr.nil();
	}

	function start() {
		// (held first: the worker's post may come at once)
		loop.hold();
		#if (hxmc.target == "wasm32-wasi")
		if (WebJobs.submit(this)) {
			held = true;
			return;
		}
		#else
		// (its end promised first, as the worker may post it at once)
		loop.promise();
		if (Pool.submit(this)) {
			held = true;
			return;
		}
		loop.unpromise();
		#end
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
		var j = job.ptr(), f:Ptr = Ptr.ofI64(fn), s = 0;
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
		if (c != null) c.resume(this, null);
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
