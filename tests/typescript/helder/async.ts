// TypeScript's async functions on helder's graph (DESIGN.md 7.4): an async
// function given to memo is an async computation (its value the answer,
// what it reads before its first await tracked), a run superseded is
// cancelled (its pending await throws an AbortError, its finally blocks
// run, the async call it awaits cancelled with it), writes after an await
// commit at the end of the loop's turn (helder.async's loop, which runs the
// program's timers and promises).
import { signal, memo, effect, flush } from "helder/view";

function wait(ms: number): Promise<void> {
	return new Promise(resolve => setTimeout(resolve, ms));
}

async function load(n: number): Promise<string> {
	try {
		await wait(30);
		return "user " + n;
	} catch (e) {
		console.log("load", n, (e as Error).name);
		throw e;
	}
}

const id = signal(1);
const user = memo(async () => {
	const n = id();
	console.log("run", n);
	try {
		const name = await load(n);
		return name.toUpperCase();
	} finally {
		console.log("finally", n);
	}
});
effect(() => user(), v => console.log("answer", v));
flush();

// (a write after an await: committed at the end of the turn, no flush called)
const count = signal(0);
effect(() => count(), v => console.log("count", v));
flush();
async function tick() {
	await wait(5);
	count(c => c + 1);
	count(c => c + 1);
}
tick();

// (run 1 superseded while it waits: cancelled, its load with it)
setTimeout(() => id(2), 10);
setTimeout(() => id(3), 100);
