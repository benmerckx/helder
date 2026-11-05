// Every use of hxmc.unsafe in helder.image (src/helder/image/*.hx, and the
// two files that hand its images to the GPU and the browser:
// src/helder/asset/ImageAsset.hx, src/helder/gfx/ImageTexture.hx) against
// the reviewed list, tests/image/unsafe.txt (the image lane). A new use, or
// one gone from the code but still listed, fails: the list is reviewed
// with the change that edits it.
//
//   node tests/image/unsafe.mjs           the check
//   node tests/image/unsafe.mjs --write   the list rewritten from the code (then review it)
import { readFileSync, readdirSync, writeFileSync } from "node:fs";

const files = [
	...readdirSync("src/helder/image").filter(f => f.endsWith(".hx") && !f.endsWith(".test.hx")).sort().map(f => `src/helder/image/${f}`),
	"src/helder/asset/ImageAsset.hx",
	"src/helder/gfx/ImageTexture.hx",
];
const found = [];
for (const f of files)
	readFileSync(f, "utf8").split("\n").forEach(line => {
		const code = line.replace(/\/\/.*$/, "").trim();
		if (code.includes("hxmc.unsafe")) found.push(`${f}: ${code}`);
	});
const listPath = "tests/image/unsafe.txt";
if (process.argv.includes("--write")) {
	const head = readFileSync(listPath, "utf8").split("\n").filter(l => l.startsWith("#"));
	writeFileSync(listPath, [...head, ...found, ""].join("\n"));
	console.log(`${listPath}: ${found.length} uses`);
	process.exit(0);
}
const listed = readFileSync(listPath, "utf8").split("\n").filter(l => l.trim() !== "" && !l.startsWith("#"));
const count = a => a.reduce((m, l) => m.set(l, (m.get(l) ?? 0) + 1), new Map());
const have = count(found), want = count(listed);
const added = [...have].filter(([l, n]) => n > (want.get(l) ?? 0)).map(([l]) => l);
const gone = [...want].filter(([l, n]) => n > (have.get(l) ?? 0)).map(([l]) => l);
for (const l of added) console.log(`unsafe: not reviewed: ${l}`);
for (const l of gone) console.log(`unsafe: listed but gone: ${l}`);
if (added.length + gone.length > 0) {
	console.log(`unsafe: ${listPath} differs from the code (review the change; --write rewrites the list)`);
	process.exit(1);
}
console.log(`unsafe: ${found.length} uses of hxmc.unsafe in helder.image, each reviewed (${listPath})`);
