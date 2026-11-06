// helder.test for TypeScript programs: `*.test.ts` and `*.test.tsx` files,
// found and run by `helder test` beside the `*.test.hx` ones, natively and
// as wasm32-wasi, through the same runner (helder.test.Runner: its groups,
// hooks, filters, snapshots and report). Tests register at a file's top
// level, as bun's and jest's:
//
//   import { describe, test, equals, snapshot } from "helder/test";
//
//   describe("todos", () => {
//     test("adds", () => equals(add([], "milk").length, 1));
//     test("later", async () => { await delay(1); equals(1, 1); }).timeout(1);
//   });
//
// A body is a function, or an async one (its promise awaited, within its
// timeout). An assertion's failure is located at its call: helder's
// compiler gives each one its file and line (its last parameter, `at`,
// never written by hand: the lowering's Definitions). `equals` compares
// JavaScript values deeply (primitives by SameValueZero, arrays, plain
// objects and instances of the same prototype by their own enumerable
// properties, Map, Set, Date, typed arrays), shown as `show` writes them;
// `snapshot` checks a string, or a value shown, against the file's
// `.snap` beside it (Foo.test.ts's Foo.test.snap; `helder test -u`
// rewrites it). TSX mounts headless with helder/story's `tree`, its
// tree as text, which a snapshot keeps.
import { Script, Entry } from "helder/test/runner";

export type { Entry };

// (thrown by require and fail: the test stops, its failure recorded)
class Stop extends Error {}

type Body = () => void | Promise<unknown>;
type Start = (seconds: number, done: (error: string | null, stopped: boolean) => void) => void;

function errorText(e: unknown): string {
	if (e instanceof Error) return e.name === "Error" ? e.message : `${e.name}: ${e.message}`;
	return show(e);
}

// (a body as the runner's step: its errors and its promise reported once,
// a promise within the step's timeout)
function step(body: Body): Start {
	return (seconds, done) => {
		let finished = false;
		const end = (error: unknown, failed: boolean) => {
			if (finished) return;
			finished = true;
			if (!failed) done(null, false);
			else if (error instanceof Stop) done(null, true);
			else done(errorText(error), false);
		};
		let r: unknown;
		try {
			r = body();
		} catch (e) {
			end(e, true);
			return;
		}
		if (!(r instanceof Promise)) {
			end(undefined, false);
			return;
		}
		const timer = setTimeout(() => {
			if (finished) return;
			Script.timedOut(seconds);
			end(undefined, false);
		}, seconds * 1000);
		r.then(() => {
			clearTimeout(timer);
			end(undefined, false);
		}, (e: unknown) => {
			clearTimeout(timer);
			end(e, true);
		});
	};
}

// a test: its body run with the group's hooks around it
export function test(name: string, body: Body): Entry {
	return Script.test(name, step(body));
}

// a group: body registers its tests, hooks and groups at once
export function describe(name: string, body: () => void): Entry {
	return Script.describe(name, () => {
		try {
			body();
		} catch (e) {
			Script.registering(errorText(e));
		}
	});
}

// before each test of this group (or file) and its groups, outer ones first
export function beforeEach(body: Body): void {
	Script.hook(0, step(body));
}

// after each test, inner ones first, also after a failure
export function afterEach(body: Body): void {
	Script.hook(1, step(body));
}

// once before the group's first test (a failure leaves its tests out)
export function beforeAll(body: Body): void {
	Script.hook(2, step(body));
}

// once after its last
export function afterAll(body: Body): void {
	Script.hook(3, step(body));
}

// --- assertions: a failure is recorded and the test goes on, except for
// require and fail, which stop it. `at`, the call's file and line, is
// given by helder's compiler.

function failure(message: string, at?: string): void {
	Script.failure(message, at ?? "(unknown)");
}

// a failure if false
export function assert(cond: boolean, msg?: string, at?: string): void {
	Script.check();
	if (!cond) failure(msg ?? "assertion failed", at);
}

// deeply equal: both values shown, and where they differ (.list[0].a)
export function equals<T>(actual: T, expected: T, msg?: string, at?: string): void {
	Script.check();
	const where = diff(actual, expected, "");
	if (where === null) return;
	const lines = [msg ?? "not equal", `  expected: ${show(expected)}`, `  actual:   ${show(actual)}`];
	if (where !== "") lines.push(`  (differing at ${where})`);
	failure(lines.join("\n"), at);
}

export function notEquals<T>(actual: T, expected: T, msg?: string, at?: string): void {
	Script.check();
	if (diff(actual, expected, "") === null) failure(`${msg ?? "equal, expected a difference"}\n  both: ${show(actual)}`, at);
}

// |actual - expected| <= epsilon
export function approx(actual: number, expected: number, epsilon?: number, msg?: string, at?: string): void {
	Script.check();
	const e = epsilon ?? 1e-6;
	if (!(Math.abs(actual - expected) <= e)) failure(`${msg ?? "not within " + e}\n  expected: ${expected}\n  actual:   ${actual}`, at);
}

// the error f throws (as thrown); a failure if none
export function throws(f: () => void, msg?: string, at?: string): unknown {
	Script.check();
	try {
		f();
	} catch (e) {
		if (e instanceof Stop) throw e;
		return e;
	}
	failure(msg ?? "nothing thrown", at);
	return undefined;
}

// the error f's promise rejects with; a failure if it fulfils
export async function rejects(f: () => Promise<unknown>, msg?: string, at?: string): Promise<unknown> {
	Script.check();
	try {
		await f();
	} catch (e) {
		if (e instanceof Stop) throw e;
		return e;
	}
	failure(msg ?? "nothing thrown", at);
	return undefined;
}

// v, not null or undefined; else the test stops
export function require<T>(v: T | null | undefined, msg?: string, at?: string): T {
	Script.check();
	if (v === null || v === undefined) {
		failure(msg ?? `required a value, got ${v}`, at);
		throw new Stop("required");
	}
	return v;
}

// a failure, the test stopped
export function fail(msg: string, at?: string): never {
	failure(msg, at);
	throw new Stop(msg);
}

// value (a string, or shown) against the snapshot of this name in the
// test file's .snap: written when missing, rewritten by `helder test -u`
export function snapshot(name: string, value: unknown, at?: string): void {
	Script.snapshot(name, typeof value === "string" ? value : show(value), at ?? "(unknown)");
}

// --- values

// where a and b differ ("" at the top, ".a[1]" inside), null when deeply equal
export function diff(a: unknown, b: unknown, path: string): string | null {
	if (a === b || (a !== a && b !== b)) return null;
	if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return path;
	if (Object.getPrototypeOf(a) !== Object.getPrototypeOf(b)) return path;
	if (a instanceof Date && b instanceof Date) return a.getTime() === b.getTime() ? null : path;
	if (Array.isArray(a) && Array.isArray(b)) {
		if (a.length !== b.length) return path;
		for (let i = 0; i < a.length; i++) {
			const d = diff(a[i], b[i], `${path}[${i}]`);
			if (d !== null) return d;
		}
		return null;
	}
	if (ArrayBuffer.isView(a) && ArrayBuffer.isView(b)) {
		const x = new Uint8Array(a.buffer, a.byteOffset, a.byteLength), y = new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
		if (x.length !== y.length) return path;
		for (let i = 0; i < x.length; i++) if (x[i] !== y[i]) return `${path}[${i}]`;
		return null;
	}
	if (a instanceof Map && b instanceof Map) {
		if (a.size !== b.size) return path;
		for (const [k, v] of a) {
			if (!b.has(k)) return path;
			const d = diff(v, b.get(k), `${path}[${show(k)}]`);
			if (d !== null) return d;
		}
		return null;
	}
	if (a instanceof Set && b instanceof Set) {
		if (a.size !== b.size) return path;
		for (const v of a) if (!b.has(v)) return path;
		return null;
	}
	const ka = Object.keys(a), kb = Object.keys(b);
	if (ka.length !== kb.length) return path;
	for (const k of ka) {
		if (!Object.prototype.hasOwnProperty.call(b, k)) return `${path}.${k}`;
		const d = diff((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k], `${path}.${k}`);
		if (d !== null) return d;
	}
	return null;
}

// a value as a literal: strings quoted, arrays, objects ({a: 1}), Map, Set,
// Date, typed arrays, an instance by its class's name
export function show(v: unknown): string {
	return text(v, 0);
}

// (a key written bare: an identifier's characters, not starting with a digit)
function plainKey(k: string): boolean {
	if (k === "") return false;
	for (let i = 0; i < k.length; i++) {
		const c = k.charCodeAt(i);
		const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95 || c === 36;
		if (!letter && !(i > 0 && c >= 48 && c <= 57)) return false;
	}
	return true;
}

function text(v: unknown, depth: number): string {
	if (typeof v === "string") return JSON.stringify(v);
	if (typeof v === "function") return `[Function ${v.name || "(anonymous)"}]`;
	if (typeof v !== "object" || v === null) return String(v);
	if (depth > 8) return "...";
	if (v instanceof Date) return `Date(${v.toISOString()})`;
	if (v instanceof Error) return `${v.name}(${JSON.stringify(v.message)})`;
	if (Array.isArray(v)) return `[${v.map(x => text(x, depth + 1)).join(", ")}]`;
	if (ArrayBuffer.isView(v)) {
		const bytes = new Uint8Array(v.buffer, v.byteOffset, v.byteLength);
		return `${v.constructor.name} [${Array.from(bytes).join(", ")}]`;
	}
	if (v instanceof Map) return `Map {${Array.from(v).map(([k, x]) => `${text(k, depth + 1)} => ${text(x, depth + 1)}`).join(", ")}}`;
	if (v instanceof Set) return `Set {${Array.from(v).map(x => text(x, depth + 1)).join(", ")}}`;
	const proto = Object.getPrototypeOf(v);
	const name = proto === null || proto === Object.prototype ? "" : (proto.constructor?.name ?? "") + " ";
	const fields = Object.keys(v).map(k => `${plainKey(k) ? k : JSON.stringify(k)}: ${text((v as Record<string, unknown>)[k], depth + 1)}`);
	return `${name}{${fields.join(", ")}}`;
}
