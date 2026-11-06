// helder.async for TypeScript programs (helder.typescript): a program's
// promises and timers already run on helder.async's loop (its async
// functions as the graph's async computations, DESIGN.md 7.4); these are
// helder.async's own tasks, each a promise to the program (a Task<T> is a
// Promise<T>).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Tasks: "helder.async.Tasks", __module: "helder.async.TypeScript"};

// helder.async for code that has no coroutines (a TypeScript program,
// helder/async): each a task started now on this thread's loop, which
// TypeScript awaits as a promise (cancelling the promise cancels it).
export declare class Tasks {
	// done after that many seconds
	static delay(seconds: number): Promise<unknown>;
	// a file's bytes: natively read, in the browser fetched (Fetch.bytes)
	static bytes(path: string): Promise<Uint8Array>;
}

export declare const delay: typeof Tasks.delay;
export declare const readBytes: typeof Tasks.bytes;
