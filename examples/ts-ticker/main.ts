// title: Ticker
// summary: A TypeScript program ticking on a timer, rebuilt by helder dev as its files change and swapped in, its count kept
// tags: typescript, dev
// Ticks on a timer until it is stopped: helder dev rebuilds it as its files
// change and swaps it in, the count going on (a signal: fast refresh keeps
// it, by where it is made). Edit label.ts while it runs.
import { signal, effect } from "helder/view";
import { label } from "./label";

const n = signal(0);
effect(() => n(), v => console.log(label(v)));
setInterval(() => n(c => c + 1), 200);
