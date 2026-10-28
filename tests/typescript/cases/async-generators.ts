// async generators and for await (async and sync iterables, return(), errors)
const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));
async function* ticker(n: number) { for (let i = 0; i < n; i++) { await sleep(1); yield i; } return "end"; }
async function* mapped<T, U>(src: AsyncIterable<T>, f: (x: T) => U) { for await (const x of src) yield f(x); }
async function main() {
  for await (const t of ticker(3)) console.log("tick", t);
  const out: string[] = []; for await (const s of mapped(ticker(4), x => `#${x}`)) out.push(s); console.log(out.join());
  for await (const v of [Promise.resolve(1), 2, sleep(1).then(() => 3)]) console.log("v", v);
  const g = ticker(2); console.log(JSON.stringify(await g.next()), JSON.stringify(await g.return("stop")), JSON.stringify(await g.next()));
  const results = await Promise.all([ticker(2).next(), ticker(2).next()]); console.log(results.map(r => r.value).join());
  const custom = { async *[Symbol.asyncIterator]() { yield "a"; yield await Promise.resolve("b"); } };
  for await (const c of custom) console.log(c);
  async function* failing() { yield 1; throw new Error("gen failure"); }
  try { for await (const x of failing()) console.log("got", x); } catch (e: any) { console.log("caught", e.message); }
}
main();
