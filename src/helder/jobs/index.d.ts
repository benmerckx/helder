// helder.jobs for TypeScript programs (helder.typescript): job(f), a
// module-level function of the program run on a worker, its input, its
// result and the constants it reads Sendable (a definition: checked and
// compiled with the program, as Haxe's Jobs.job); run(input) a promise of
// its result.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Job: "helder.jobs.script.Job", __module: "helder.jobs.TypeScript"};

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
export declare class Job<In, Out> {
	// f's job (a definition: its calls are compiled, this is never called)
	static of<In, Out>(f: (arg0: In) => Out): Job<In, Out>;
	// f run on a worker with input: its result (its exception a JobError)
	run(input?: In): Promise<Out>;
}

export declare const job: typeof Job.of;
