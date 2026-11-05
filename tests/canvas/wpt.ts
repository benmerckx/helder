// The converted WPT tests (wpt/cases.ts) on helder.canvas's DOM facade,
// natively: a line each, PASS or FAIL and why (wpt/check.mjs compares the
// failures with the known ones, wpt/failing.txt)
import { Canvas } from "helder/canvas";
import { cases } from "./wpt/cases";

let passed = 0;
for (const c of cases) {
	const canvas = new Canvas(c.width, c.height);
	const ctx = canvas.getContext("2d")!;
	try {
		c.run(canvas, ctx);
		passed++;
		console.log("PASS " + c.name);
	} catch (e) {
		console.log("FAIL " + c.name + ": " + String((e as any)?.message ?? e));
	}
}
console.log("wpt: " + passed + " of " + cases.length + " passed");
