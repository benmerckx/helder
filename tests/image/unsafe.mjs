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
	// (the reasons kept for the lines still there; new ones to explain)
	const old = new Map(readFileSync(listPath, "utf8").split("\n").filter(l => / {2}# /.test(l)).map(l => [l.replace(/  # .*$/, ""), l]));
	const head = readFileSync(listPath, "utf8").split("\n").filter(l => l.startsWith("#"));
	writeFileSync(listPath, [...head, ...found.map(l => old.get(l) ?? l + "  # TODO: why"), ""].join("\n"));
	console.log(`${listPath}: ${found.length} uses`);
	process.exit(0);
}
const entries = readFileSync(listPath, "utf8").split("\n").filter(l => l.trim() !== "" && !l.startsWith("#"));
const unexplained = entries.filter(l => !/  # \S/.test(l));
for (const l of unexplained) console.log(`unsafe: listed without its reason ("  # why"): ${l}`);
if (unexplained.length > 0) process.exit(1);
const listed = entries.map(l => l.replace(/  # .*$/, ""));
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

// The decoders read their input through ByteReader only (every read checked
// against the file's end): a Bytes read (get, getString, getInt32...,
// addBytes, blit) in them is on a buffer of their own, named here; any
// other is a raw read of untrusted input, and fails.
const own = {
	"GifDecoder.hx": ["data", "indices", "out"], // (data: the frame's joined sub-blocks, read within its length)
	"JpegDecoder.hx": ["out", "src", "this"], // (this: Coeffs, its own buffer)
	"WebpDecoder.hx": ["a", "canvas", "d.rgba", "inner"],
	"Vp8Decoder.hx": ["P", "U", "V", "Y", "b", "ws"],
	"Exif.hx": ["rgba"],
	"PngDecoder.hx": ["canvas", "info", "out"],
	"Image.hx": ["dst", "px", "src"], // (over: a decoder's own canvas and frame)
	"AnimatedImage.hx": ["image.pixels"],
};
let raw = 0;
for (const [f, names] of Object.entries(own))
	readFileSync(`src/helder/image/${f}`, "utf8").split("\n").forEach((line, i) => {
		const code = line.replace(/\/\/.*$/, "");
		for (const m of code.matchAll(/([A-Za-z_0-9.]+)\.(get|getString|getInt32|getUInt16|getInt64|getFloat|getDouble|addBytes|blit)\(/g))
			if (!names.includes(m[1])) {
				console.log(`reads: src/helder/image/${f}:${i + 1}: ${m[1]}.${m[2]}: not through ByteReader`);
				raw++;
			}
	});
if (raw > 0) process.exit(1);
console.log(`reads: the decoders' input through ByteReader only (${Object.keys(own).length} files)`);
