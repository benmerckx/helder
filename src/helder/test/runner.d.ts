// helder.test's runner for TypeScript programs (helder.typescript): what
// helder/test (src/helder/test/index.ts: test, describe, the hooks, the
// assertions, snapshots) registers and reports through, the runner of
// `*.test.hx` (helder.test.Script). A program imports helder/test, not
// this module.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Script: "helder.test.Script", Entry: "helder.test.Runner.Entry", __module: "helder.test.TypeScript"};

// helder.test's runner for TypeScript test files (helder/test, its
// index.ts, over helder/test/runner: helder.test.TypeScript): the same
// groups, hooks, filters, snapshots and report as `*.test.hx`'s. Each step
// of a TypeScript test is started with its timeout and calls done once:
// with null, with the error's text, or stopped (require and fail, their
// failure recorded already). Positions are "file:line", the call's, which
// helder's compiler gives each assertion of helder/test (the lowering's
// Definitions).
export declare class Script {
	// a test file's tests follow, its module evaluated (helder test's main
	// imports each one after this call)
	static file(path: string): void;
	static test(name: string, start: (seconds: number, done: (error: string | null, stopped: boolean) => void) => void): Entry;
	static describe(name: string, body: () => void): Entry;
	// beforeEach (0), afterEach (1), beforeAll (2), afterAll (3)
	static hook(kind: number, start: (seconds: number, done: (error: string | null, stopped: boolean) => void) => void): void;
	// an error while the file's tests or a group's are registered
	static registering(error: string): void;
	static check(): void;
	static failure(message: string, at: string): void;
	static timedOut(seconds: number): void;
	// a value's text against the file's snapshot of this name (Foo.test.ts's Foo.test.snap)
	static snapshot(name: string, value: string, at: string): void;
	static run(): void;
}

// a test or a group, as registered: marked skipped, only, or with a timeout
export declare class Entry {
	readonly name: string;
	// left out (reported as skipped)
	skip(): Entry;
	// run with the others marked only, the rest left out
	only(): Entry;
	// seconds each async step may take (a group's: each of its tests')
	timeout(seconds: number): Entry;
	// "describe > test", without the file
	fullName(): string;
}
