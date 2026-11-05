// The converted WPT tests' results (wpt.ts's lines, from a file) against
// the known failures (failing.txt): a new failure fails, and so does a
// listed test that passes (the list is kept exact)
//
//   node tests/canvas/wpt/check.mjs bin/canvas/wpt.txt
import { readFileSync } from "node:fs";

const lines = readFileSync(process.argv[2], "utf8").split("\n");
const known = new Map(readFileSync("tests/canvas/wpt/failing.txt", "utf8").split("\n").filter(l => l.trim() !== "" && !l.startsWith("#")).map(l => [l.split(":")[0].trim(), l]));
const failed = lines.filter(l => l.startsWith("FAIL ")), passed = lines.filter(l => l.startsWith("PASS ")).map(l => l.slice(5).trim());
const fresh = failed.filter(l => !known.has(l.slice(5).split(":")[0].trim()));
const fixed = passed.filter(n => known.has(n));
for (const l of fresh) console.log("wpt: a new failure: " + l);
for (const n of fixed) console.log("wpt: passes now, remove it from tests/canvas/wpt/failing.txt: " + n);
console.log(`wpt: ${passed.length} of ${passed.length + failed.length} pass (${known.size} known failures)`);
if (fresh.length > 0 || fixed.length > 0) process.exit(1);
