// promises, async/await, microtask and timer order, combinators, thenables, async methods
declare function setImmediate(callback: () => void): number;
const order: string[] = [];
setTimeout(() => order.push("timeout"), 0);
setImmediate(() => order.push("immediate"));
Promise.resolve().then(() => order.push("micro1")).then(() => order.push("micro2"));
queueMicrotask(() => order.push("queued"));
(async () => { order.push("async-start"); await null; order.push("after-await"); })();
order.push("sync");
const sleep = (ms: number) => new Promise<number>(r => setTimeout(() => r(ms), ms));
async function work(id: number): Promise<string> { const t = await sleep(id * 3); if (id === 2) throw new Error("fail " + id); return `done ${id}:${t}`; }
async function main() {
  console.log(await work(1));
  try { await work(2); } catch (e: any) { console.log("caught", e.message); }
  const all = await Promise.all([work(1), work(3), Promise.resolve("x")]); console.log(all.join("|"));
  const settled = await Promise.allSettled([work(2), work(1)]); console.log(settled.map(s => s.status).join());
  console.log(await Promise.race([sleep(20).then(() => "slow"), sleep(1).then(() => "fast")]));
  try { await Promise.any([Promise.reject(1), Promise.reject(2)]); } catch (e: any) { console.log(e.constructor.name, e.errors.join()); }
  const thenable = { then(res: (v: number) => void) { res(42); } }; console.log(await thenable);
  for (const x of [1, 2]) { await sleep(1); console.log("loop", x); }
  let n = 0; const id = setInterval(() => { if (++n === 3) { clearInterval(id); console.log("interval", n); } }, 1);
  await new Promise(r => setTimeout(r, 20));
  console.log(order.join(","));
  return "main done";
}
main().then(v => console.log(v)).finally(() => console.log("finally"));
class Api { private base = 10; async get(x: number) { await null; return this.base + x; } static async create() { return new Api(); } }
Api.create().then(a => a.get(5)).then(v => console.log("api", v));
