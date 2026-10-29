// title: Ticker
// summary: A TypeScript program ticking on a timer, rebuilt by helder dev as its files change and swapped in
// tags: typescript, dev
// Ticks on a timer until it is stopped: helder dev rebuilds it as its files change.
import { label } from "./label";

let n = 0;
setInterval(() => console.log(label(++n)), 200);
