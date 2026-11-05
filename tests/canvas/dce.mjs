// The canvas lane's DCE check: Tiny (a path filled, a PNG) and Full
// (everything), each built with -dce full, with symbols (-D hxmc.symbols)
// and without: Tiny's symbols hold none of what it does not use, Full's
// all of it; both sizes reported (bin/canvas/dce.md)
//
//   node tests/canvas/dce.mjs <Tiny> <Tiny with symbols> <Full> <Full with symbols>
import { execFileSync } from "node:child_process";
import { statSync, writeFileSync } from "node:fs";

const [tiny, tinySym, full, fullSym] = process.argv.slice(2);
const symbols = f => execFileSync("nm", [f], { encoding: "utf8", maxBuffer: 1 << 28 }).split("\n").map(l => l.split(" ").pop());
// (what Tiny leaves out, each a symbol prefix of hxmc's: F_<package>_<class>_)
const unused = {
	"the JPEG encoder": "helder_image_JpegEncoder", "gradients": "helder_canvas_Gradient", "linear gradients": "helder_canvas_LinearGradient",
	"radial gradients": "helder_canvas_RadialGradient", "conic gradients": "helder_canvas_ConicGradient", "patterns": "helder_canvas_Pattern",
	"Porter-Duff's operators": "helder_canvas_PorterDuff", "separable blend modes": "helder_canvas_Separable", "multiply": "helder_canvas_Multiply",
	"non-separable blend modes": "helder_canvas_NonSeparable", "the stroker": "helder_canvas_Stroker", "round joins": "helder_canvas_RoundJoin",
	"dashes": "helder_canvas_Dash", "masks": "helder_canvas_Mask", "text": "helder_canvas_Glyphs", "helder.text": "helder_text_",
	"the DOM facade": "helder_canvas_dom_",
};
const t = symbols(tinySym), f = symbols(fullSym);
let bad = 0;
const rows = [];
for (const [what, prefix] of Object.entries(unused)) {
	const inTiny = t.filter(s => s.includes(prefix)), inFull = f.some(s => s.includes(prefix));
	if (inTiny.length > 0) { bad++; console.log(`dce: Tiny keeps ${what}: ${inTiny.slice(0, 3).join(", ")}`); }
	if (!inFull && prefix !== "helder_canvas_dom_") { bad++; console.log(`dce: Full has no ${what} (${prefix}): the check checks nothing`); }
	rows.push(`| ${what} | ${inTiny.length === 0 ? "left out" : "KEPT"} | ${inFull ? "kept" : "-"} |`);
}
const kb = p => Math.round(statSync(p).size / 1024);
const report = [`Tiny (a path filled, a PNG): ${kb(tiny)} KB; Full (every paint, blend mode, join and cap, dashes, clips, layers, images, text, PNG and JPEG): ${kb(full)} KB (-dce full, stripped)`, "",
	"| | Tiny | Full |", "| --- | --- | --- |", ...rows].join("\n");
writeFileSync("bin/canvas/dce.md", report + "\n");
console.log(report);
if (bad > 0) process.exit(1);
