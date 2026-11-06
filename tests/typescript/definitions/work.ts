// job(f) in TypeScript (Work.hx prints the same): module-level functions
// run on a worker, their input and result copied across (an object of a
// string and an array, a number, nothing), a constant the function reads
// sent with it, the function it calls compiled for the worker too.
import {job} from "helder/jobs";

type Text = {text: string, sep: string};
type Counted = {count: number, long: string[], last: string | null};

const shortest = 3;

function upper(s: string): string {
	return s.toUpperCase();
}

function words(t: Text): Counted {
	const ws = t.text.split(t.sep).filter((w) => w.length >= shortest);
	return {count: ws.length, long: ws.map(upper), last: ws.length > 0 ? ws[ws.length - 1] : null};
}

function square(x: number): number {
	return x * x;
}

function answer(): number {
	return 42;
}

async function main() {
	const r = await job(words).run({text: "a fleet of ships at sea", sep: " "});
	console.log(`${r.count} ${r.long.join(",")} ${r.last}`);
	const none = await job(words).run({text: "a b", sep: " "});
	console.log(`${none.count} ${none.last}`);
	console.log(`${await job(square).run(12)} ${await job(answer).run()}`);
}
main();
