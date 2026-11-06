// keep(key, () => initial) in TypeScript (Kept.hx prints the same): a
// value kept across a reload under helder dev; without -D hxmc.dev, its
// initial value, made once where it is written.
import {keep} from "helder/dev";

const state = keep("state", () => ({count: 0, label: "ticks"}));
state.count += 2;
console.log(`${state.label} ${state.count}`);
const steps = keep("steps", () => [1, 2, 3]);
steps.push(4);
console.log(steps.join(","));
function made(): number {
	return keep("made", () => 40) + 2;
}
console.log(`made ${made()} ${made()}`);
