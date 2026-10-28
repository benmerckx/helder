package helder.jobs;

#if macro
import haxe.macro.Expr;
#else
import helder.jobs.Wire.Reader;
import helder.jobs.Wire.Writer;
import hxmc.unsafe.IoBuffer;
import hxmc.unsafe.Ptr;
#end

// Background work, awaited from a coroutine: a job runs on another thread
// (natively a pool's, in a browser a worker's instance of the program's own
// module) and its result resumes the awaiting coroutine on its own loop
// (helder.async: a coroutine never changes thread, only data crosses).
//
//   // GC-free, the engine's: an @:hxmc.unsafe callback over off-heap memory
//   var pixels:IoBuffer = Jobs.run(PngJob.decode, IoBuffer.ofBytes(png));
//   // a GC job, user code: values that can be sent in and out (Sendable)
//   var n:Int = Jobs.run(Words.count, text);
//   var t = task.async(_ -> Jobs.run(Words.count, text));   // a Task
//
// Two tiers:
// - a GC-free job is a static `@:hxmc.unsafe @:hxmc.callback function (job:Job):Int`:
//   its input an IoBuffer moved into the run, its output one it allocates
//   (Job.output), the awaiting task's to free; a result < 0 is a JobError.
//   Natively it runs in a safe region (hxmc.unsafe.Blocking), so the
//   collector never waits for it: no pause of other threads' frames.
// - a GC job is any static function of one sendable argument (or none) to a
//   sendable result (or Void), its argument and result copied across
//   (Sendable, checked at compile time); its exception a JobError. Natively
//   it joins the shared heap's collections, which then wait for its
//   longest loop without an allocation (a 4K PNG's: 35-55 ms): for short
//   work. In a browser's worker it has a heap of its own.
//
// Cancelling the awaiting task resumes it at once (a CancellationException);
// natively the job sees Job.cancelled and may return early, in a browser a
// queued job is dropped and a running one's worker ended (and made again
// for the next). Where there are no workers (workers = 0, a WASI host
// without helder_jobs, a browser without Worker) jobs run on the loop
// instead, at its next turn, with the same results.
class Jobs {
	// the pool's threads or a browser's workers, read at the first job: -1
	// for the cores but one (at least one); 0 for none: jobs run on the loop
	// (also once set later)
	public static var workers = -1;

	// f's run with input (see above): a GC-free job's output, a GC job's result
	public static macro function run(f:Expr, rest:Array<Expr>):Expr
		return Sendable.job(f, rest);

	#if !macro
	// whether this runs in a job on a worker (natively a thread other than
	// the main one, in a browser a worker's instance)
	public static function onWorker():Bool
		return #if (hxmc.target == "wasm32-wasi") WebJobs.inWorker() #else hxmc.NativeThread.current() != 1 #end;

	// (Jobs.run's: a GC-free job by its address)
	@:coroutine public static function runFree(fn:Ptr, input:IoBuffer):IoBuffer {
		var r = Run.await(fn, true, input);
		var out = r.output;
		r.output = cast Ptr.nil();
		return out;
	}

	// (a GC job: its input written, its result's bytes, read where it was
	// run: a closure could not return a struct as a type parameter's value)
	@:coroutine public static function runGc(fn:Ptr, input:IoBuffer):IoBuffer {
		var r = Run.await(fn, false, input);
		var out = r.output;
		r.output = cast Ptr.nil();
		return out;
	}

	@:coroutine public static function runGcVoid(fn:Ptr, input:IoBuffer):Void {
		var r = Run.await(fn, false, input);
		free(r.output);
		r.output = cast Ptr.nil();
	}

	// (a GC job's wrapper: an exception as the run's error, its message the output)
	public static function failed(job:Job, e:Dynamic):Int {
		var m = e is haxe.Exception ? (e : haxe.Exception).message : Std.string(e);
		var w = new Writer();
		w.string(m);
		job.setOutput(w.done());
		return -1;
	}

	public static inline function free(b:IoBuffer)
		if (!(cast b : Ptr).isNull()) b.free();

	// (the size the pool will be: workers, else the cores but one)
	@:allow(helder.jobs) static function size():Int
		return workers >= 0 ? workers : #if (hxmc.target == "wasm32-wasi") -1 #else Pool.Cores.count() > 1 ? Pool.Cores.count() - 1 : 1 #end;
	#end
}
