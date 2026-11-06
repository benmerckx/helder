// helder.async's tasks from TypeScript (helder/async): each a promise, on
// the same loop as the program's own timers and promises.
import { delay } from "helder/async";

const t0 = Date.now();
setTimeout(() => console.log("timer 20 ms"), 20);
async function main() {
	await delay(0.05);
	console.log("delay 50 ms", Date.now() - t0 >= 45);
	const p = delay(0.01);
	console.log(p instanceof Promise);
	await Promise.all([p, delay(0.02)]);
	console.log("both");
}
main().then(() => console.log("done"));
