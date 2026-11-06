package helder.jobs.script;

import helder.async.Async;
import helder.async.Task;

// A TypeScript program's job (helder/jobs: job(f), a definition compiled
// by helder.typescript.lower's Definitions, its Sendable check
// helder.jobs.JobDefinition's, Haxe's Jobs.job the same): f, a module-level
// function of the program, run on a worker (natively a pool's thread, in a
// browser a Web Worker's instance of the program's module) with its input
// and the module-level constants it reads, copied in; its result copied
// back. run(input) is a promise of it (a Task to Haxe).
//
//   import {job} from "helder/jobs";
//   function count(text: string): number { return text.split(" ").length; }
//   const n = await job(count).run("one two three");
class Job<In, Out> {
	// (the program's job: its function's case in Entry.call, as the lowering numbered them)
	final index:Int;
	// (the constants it reads, as they were when it was made)
	final captures:Array<Dynamic>;

	function new(index:Int, captures:Array<Dynamic>) {
		this.index = index;
		this.captures = captures;
	}

	// f's job (a definition: its calls are compiled, this is never called)
	public static function of<In, Out>(f:In->Out):Job<In, Out> {
		// (make, which the lowering calls, kept with it: the manifest's keep)
		if (helder.typescript.js.Interop.keeping()) return cast make(0, null);
		throw "helder.jobs: job(f) is compiled with the program (a definition)";
	}

	// f run on a worker with input: its result (its exception a JobError)
	public function run(?input:In):Task<Out>
		return Async.launch(@:coroutine function(_) return Entry.run(index, captures, input));

	// (the lowering's: job(f)'s value, the constants it reads JavaScript's)
	@:noCompletion public static function make(index:Int, captures:Dynamic):Job<Dynamic, Dynamic>
		return new Job(index, helder.typescript.js.Interop.toHaxe(captures));
}
