// title: Hello, TypeScript
// summary: A TypeScript program checked by tsgo and lowered straight to hxmc's IR, native or wasm: a class with a private field, modules, a promise and a timer
// tags: typescript
// A TypeScript program built by helder (helder.typescript): checked by
// tsgo, lowered straight to hxmc's IR, native or wasm.
import { greet, Counter } from "./greet";

const counter = new Counter();
for (const name of ["helder", "TypeScript"]) console.log(greet(name, counter.next()));

async function later(): Promise<string> {
	await new Promise(resolve => setTimeout(resolve, 10));
	return "done";
}
later().then(value => console.log(value));
