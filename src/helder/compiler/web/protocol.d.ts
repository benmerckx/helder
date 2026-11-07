// helder.compiler.web: the compiler worker's message protocol (README.md).
// The page (the studio's web build, its preview host) posts requests to the
// worker (worker.mjs) and gets one reply per request, by id; the worker also
// posts events (no id) and asks the page to reach the running preview
// ("running"). client.mjs wraps it as promises.
//
// Paths are the worker's file system's: absolute, "/" separated. The page
// writes the project under /work (any directory works); helder's sources,
// hxmc's std and Haxe's std are preloaded (/helder/src, /hxmc/std,
// /haxe/std); /cache persists in OPFS when it is available; builds write
// under /out unless `out` says otherwise.

/** The protocol's version: a reply's `protocol` in `init`. Additions keep it; a change of meaning bumps it. */
export declare const PROTOCOL: 1;

export type Request =
	| InitRequest
	| WriteRequest
	| ReadRequest
	| ListRequest
	| CheckRequest
	| BuildRequest
	| InvalidateRequest
	| EditRequest
	| ReloadRequest
	| StatsRequest;

interface Base {
	/** the page's number for the request; the reply carries it */
	id: number;
}

/** Loads and starts the toolchain; the first request. Others wait for it. */
export interface InitRequest extends Base {
	type: "init";
	/** where the toolchain's files are (default: beside worker.mjs) */
	assets?: {
		/** helder's compiler as wasm32-wasi (hxmc with helder's hooks): helder-compiler.wasm */
		compiler?: string;
		/** TypeScript's API as a wasip1 reactor (@typescript/typescript-wasip1-wasm's tsc.wasm); none: no TypeScript */
		typescript?: string | null;
		/** the sources' bundle (helder's src, hxmc's std, Haxe's std, TypeScript's lib files): sources.bundle */
		bundle?: string;
	};
	/** keep /cache in OPFS across sessions (default true where OPFS exists) */
	persist?: boolean;
}

/** Files written (string: UTF-8 text; bytes as they are) or removed (null), each marked changed for the next check or build. */
export interface WriteRequest extends Base {
	type: "write";
	files: Record<string, string | Uint8Array | null>;
}

export interface ReadRequest extends Base {
	type: "read";
	path: string;
}

export interface ListRequest extends Base {
	type: "list";
	/** a directory: its entries, recursively, files only */
	dir: string;
}

/** The program typed (and TypeScript's check), nothing written. */
export interface CheckRequest extends Base {
	type: "check";
	/** a project as `helder build` takes it: a directory, a .hx or .ts/.tsx file */
	entry: string;
	/** files changed since the last request (written ones are already) */
	changed?: string[];
	/** compiler arguments added after the entry's */
	args?: string[];
}

/** A build for the web (wasm32-wasi): the preview. */
export interface BuildRequest extends Base {
	type: "build";
	entry: string;
	/** a dev build (-D hxmc.dev): live literals' tables kept, so `edit` can patch; default true */
	dev?: boolean;
	/** the module's path (default /out/<name>.wasm) */
	out?: string;
	changed?: string[];
	args?: string[];
}

/** Files changed outside `write` (the server compares times, which two saves in one millisecond share). */
export interface InvalidateRequest extends Base {
	type: "invalidate";
	files: string[];
}

/**
 * Saved files compared with the sources the last dev build was made from:
 * when only live literals' values changed, they are patched in the running
 * preview (through `running`: Hot.literals) and nothing is built.
 */
export interface EditRequest extends Base {
	type: "edit";
	/** the files' new contents, written first (or `changed`: already written) */
	files?: Record<string, string>;
	changed?: string[];
}

/** Runtime.reload sent to the running preview (through `running`): whether it saved and handed over. */
export interface ReloadRequest extends Base {
	type: "reload";
	params?: unknown;
}

export interface StatsRequest extends Base {
	type: "stats";
}

/** Haxe's columns: characters from 1, end exclusive (helder.compiler.service.Diagnostic). */
export interface Diagnostic {
	file: string | null;
	line: number;
	column: number;
	endColumn: number;
	severity: "error" | "warning" | "info";
	message: string;
}

export interface InitResult {
	protocol: 1;
	/** hxmc's and TypeScript's versions */
	versions: {hxmc: string; typescript: string | null};
	/** whether codegen runs on threads (wasm threads: cross-origin isolated); false: one thread */
	threads: boolean;
	/** whether /cache is kept in OPFS */
	persistent: boolean;
	/** download, compile (WebAssembly.compile of both modules), unpack (the bundle), warm (the first request) */
	ms: {download: number; compile: number; unpack: number; warm: number; total: number};
	/** bytes downloaded (as served: compressed where the server compresses) */
	bytes: {compiler: number; typescript: number; bundle: number};
}

export interface CheckResult {
	ok: boolean;
	diagnostics: Diagnostic[];
	ms: number;
}

export interface BuildResult {
	ok: boolean;
	diagnostics: Diagnostic[];
	/** the compiler's messages, its text */
	messages: string;
	/** what the build printed (trace, Sys.println) */
	printed: string;
	ms: number;
	/** the module's path in the worker's file system */
	out: string;
	/** the module (transferred), when ok */
	wasm?: Uint8Array;
	/** files the module reads before main (helder.asset's), path to bytes */
	assets?: Record<string, Uint8Array>;
}

export type EditResult =
	/** live literals patched in the running preview, nothing built */
	| {kind: "patched"; literals: {id: string; source: string}[]; ms: number}
	/** saved as it was built */
	| {kind: "unchanged"; ms: number}
	/** a build's: why */
	| {kind: "build"; why: string; ms: number};

export interface StatsResult {
	/** the compiler's linear memory, TypeScript's, in bytes */
	memory: {compiler: number; typescript: number};
	/** files and bytes in the file system */
	files: number;
	bytes: number;
	builds: number;
}

export type Reply =
	| {id: number; type: "result"; result: unknown}
	| {id: number; type: "error"; message: string};

/** Events from the worker, no id. */
export type Event =
	/** a line the compiler printed on its own (not a build's) */
	| {type: "log"; text: string}
	/** init's progress */
	| {type: "progress"; phase: "download" | "compile" | "unpack" | "warm"; loaded?: number; total?: number}
	/**
	 * A devtools request for the running preview (helder's devtools protocol,
	 * src/helder/devtools/README.md: Hot.literals, Runtime.reload). The page
	 * answers with a RunningResponse of the same rid: the program's JSON-RPC
	 * response, or null when no preview runs.
	 */
	| {type: "running"; rid: number; request: {method: string; params: unknown}};

export interface RunningResponse {
	type: "running";
	rid: number;
	response: {result?: unknown; error?: {code: number; message: string}} | null;
}
