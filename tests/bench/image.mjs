// helder.image against vips (vips, vipsthumbnail: libvips' CLI) and Bun.Image
// where they are installed, on the same files (the image-bench lane): a table
// in bin/bench/image.md. Each time the median of five runs; vips' and bun's
// include their process start or file writes where noted.
//
//   node tests/bench/image.mjs bin/bench/ImageBench photo.jpg large.png
import { execFileSync, spawnSync } from "node:child_process";
import { writeFileSync, mkdirSync } from "node:fs";

const [helder, jpg, png] = process.argv.slice(2);
const rows = execFileSync(helder, [jpg, png], { encoding: "utf8" }).trim().split("\n").map(l => JSON.parse(l));
const median = f => {
	const ts = [];
	for (let i = 0; i < 5; i++) {
		const t = performance.now();
		f();
		ts.push(performance.now() - t);
	}
	return Math.round(ts.sort((a, b) => a - b)[2] * 10) / 10;
};
const has = cmd => spawnSync(cmd, ["--version"]).status === 0;
mkdirSync("bin/bench/image", { recursive: true });
const other = [];
if (has("vips")) {
	const v = (...a) => execFileSync("vips", a);
	other.push({ task: "jpeg decode (vips avg: decode and a mean)", tool: "vips", ms: median(() => v("avg", jpg)) });
	other.push({ task: "jpeg to a 256 px thumbnail", tool: "vipsthumbnail", ms: median(() => execFileSync("vipsthumbnail", [jpg, "-s", "256", "-o", process.cwd() + "/bin/bench/image/thumb.png"])) });
	other.push({ task: "jpeg to 50%", tool: "vips resize", ms: median(() => v("resize", jpg, "bin/bench/image/half.v", "0.5")) });
	other.push({ task: "png decode (vips avg)", tool: "vips", ms: median(() => v("avg", png)) });
}
if (spawnSync("bun", ["-e", "process.exit(typeof Bun.Image == 'function' ? 0 : 1)"]).status === 0) {
	const script = `
const [jpg, png] = process.argv.slice(1);
const m = async f => { const ts = []; for (let i = 0; i < 5; i++) { const t = performance.now(); await f(); ts.push(performance.now() - t); } return Math.round(ts.sort((a, b) => a - b)[2] * 10) / 10; };
console.log(JSON.stringify([
	{task: "jpeg decode (and its re-encode: buffer())", ms: await m(() => new Bun.Image(Bun.file(jpg)).buffer())},
	{task: "jpeg to a 256 px thumbnail", ms: await m(() => new Bun.Image(Bun.file(jpg)).resize(256).png().bytes())},
	{task: "jpeg to 50%", ms: await (async () => { const w = (await new Bun.Image(Bun.file(jpg)).metadata()).width >> 1; return m(() => new Bun.Image(Bun.file(jpg)).resize(w).png().bytes()); })()},
	{task: "png decode (and its re-encode: buffer())", ms: await m(() => new Bun.Image(Bun.file(png)).buffer())},
]));`;
	for (const r of JSON.parse(execFileSync("bun", ["-e", script, jpg, png], { encoding: "utf8" }))) other.push({ ...r, tool: `Bun.Image (${execFileSync("bun", ["--version"], { encoding: "utf8" }).trim()})` });
}
const lines = ["| task | tool | ms |", "| --- | --- | ---: |", ...rows.map(r => `| ${r.task} | helder.image | ${r.ms} |`), ...other.map(r => `| ${r.task} | ${r.tool} | ${r.ms} |`)];
writeFileSync("bin/bench/image.md", lines.join("\n") + "\n");
console.log(lines.join("\n"));
