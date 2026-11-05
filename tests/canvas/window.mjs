// examples/canvas-window's 30th frame (its --shot): the sky's gradient,
// the clipped layer's green over it, the star's glow in the middle
//
//   node tests/canvas/window.mjs <png>
import { readFileSync } from "node:fs";
const { decode } = await import("./compare.mjs");
const img = decode(readFileSync(process.argv[2]));
const at = (x, y) => Array.from(img.px.subarray((y * img.w + x) * 4, (y * img.w + x) * 4 + 4));
const layer = at(100, 90), top = at(400, 5), bottom = at(400, 470), middle = at(320, 240);
const ok = layer[1] > layer[0] + 30 && bottom[2] > top[2] + 60 && middle[0] > 200;
console.log(`canvas-window: layer ${layer}, sky ${top} to ${bottom}, star ${middle}: ${ok ? "ok" : "FAIL"}`);
if (!ok) process.exit(1);
