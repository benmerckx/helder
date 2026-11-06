// helder/test on itself, from TypeScript (the test lane: natively and as
// wasm32-wasi): diff and show on JavaScript's values, the assertions that
// pass, hooks in order, an async test, a snapshot.
import { describe, test, beforeAll, beforeEach, afterEach, afterAll, assert, equals, notEquals, approx, throws, rejects, require, snapshot, diff, show } from "helder/test";

class Point {
	constructor(readonly x: number, readonly y: number) {}
}

describe("diff", () => {
	test("equal values", () => {
		equals(diff(1, 1, ""), null);
		equals(diff(NaN, NaN, ""), null);
		equals(diff({ a: [1, { b: "x" }] }, { a: [1, { b: "x" }] }, ""), null);
		equals(diff(new Map([["k", 1]]), new Map([["k", 1]]), ""), null);
		equals(diff(new Set([1, 2]), new Set([2, 1]), ""), null);
		equals(diff(new Uint8Array([1, 2]), new Uint8Array([1, 2]), ""), null);
		equals(diff(new Point(1, 2), new Point(1, 2), ""), null);
	});
	test("where they differ", () => {
		equals(diff({ n: 1, list: [{ a: "x" }] }, { n: 1, list: [{ a: "y" }] }, ""), ".list[0].a");
		equals(diff([1, 2], [1, 2, 3], ""), "");
		equals(diff({ a: 1 }, { b: 1 }, ""), ".a");
		equals(diff(new Point(1, 2), { x: 1, y: 2 }, ""), "");
		equals(diff(new Map([["k", 1]]), new Map([["k", 2]]), ""), '["k"]');
		equals(diff(1, "1", ""), "");
	});
});

describe("show", () => {
	test("values as literals", () => {
		equals(show("a\"b"), '"a\\"b"');
		equals(show([1, "x", null, undefined, true]), '[1, "x", null, undefined, true]');
		equals(show({ a: { b: [] }, "c d": 1 }), '{a: {b: []}, "c d": 1}');
		equals(show(new Point(3, 4)), "Point {x: 3, y: 4}");
		equals(show(new Map([["k", [1]]])), 'Map {"k" => [1]}');
		equals(show(new Set([1])), "Set {1}");
		equals(show(new Uint8Array([1, 2])), "Uint8Array [1, 2]");
	});
});

describe("assertions", () => {
	test("that pass", () => {
		assert(1 < 2);
		equals({ x: [1] }, { x: [1] });
		notEquals([1], [2]);
		approx(0.1 + 0.2, 0.3);
		approx(1, 1.005, 0.01);
		equals((throws(() => { throw new Error("boom"); }) as Error).message, "boom");
		equals(throws(() => { throw "a string"; }), "a string");
		equals(require(new Map([["a", 1]]).get("a")) + 1, 2);
	});
	test("rejects", async () => {
		const e = await rejects(async () => {
			await new Promise(r => setTimeout(r, 1));
			throw new Error("later");
		});
		equals((e as Error).message, "later");
	});
	test("snapshot", () => {
		snapshot("a value", { list: [1, 2], name: "x" });
		snapshot("a string", "line 1\nline 2");
	});
});

const log: string[] = [];
describe("hooks", () => {
	beforeAll(() => { log.push("beforeAll"); });
	beforeEach(() => { log.push("before"); });
	afterEach(async () => {
		await new Promise(r => setTimeout(r, 1));
		log.push("after");
	});
	afterAll(() => { log.push("afterAll"); });
	test("first", () => { log.push("first"); });
	test("second", () => { log.push("second"); });
});

test("hooks ran in order", () => {
	equals(log, ["beforeAll", "before", "first", "after", "before", "second", "after", "afterAll"]);
});

test("skipped", () => assert(false)).skip();
