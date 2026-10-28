{
async function main() {
  const order: string[] = [];
  const values = await Array.fromAsync([Promise.resolve(1), 2, Promise.resolve(3)], async function(this: {n:number}, value, index) { order.push(value+":"+index);await null;return value*this.n; }, {n:4});
  console.log(values, order.join());
  console.log(await Array.fromAsync({0:Promise.resolve("a"),2:"c",length:3}));
  async function* source() { yield 5; await null; yield 6; }
  console.log(await Array.fromAsync(source(), (v,i)=>v+i));
  const promise=Promise.resolve(9);let at=0;
  const raw={ [Symbol.asyncIterator]() { return this; }, async next() { return at++?{done:true,value:undefined}:{done:false,value:promise}; } };
  const collected=await Array.fromAsync(raw);console.log(collected[0]===promise);at=0;
  console.log(await Array.fromAsync(raw,v=>v));
  let closed=0;
  const closing={ [Symbol.asyncIterator]() { return this; }, async next() { return {done:false,value:1}; },async return() {closed++;return {}; } };
  try {await Array.fromAsync(closing as any,()=>{throw new Error("map");});}catch(e:any){console.log(e.message,closed);}
  let syncClosed=0;
  const sync={ [Symbol.iterator]() { return this; }, next() {return {done:false,value:Promise.reject("value rejection")};},return(){syncClosed++;return {};} };
  try {await Array.fromAsync(sync as any);}catch(e){console.log(e,syncClosed>0);}
  class Custom { [key:number]:unknown;length:number;constructor(length?:number){this.length=length??-1;} }
  const custom=await (Array.fromAsync as any).call(Custom,[1,2]);console.log(custom instanceof Custom, custom[0], custom[1], custom.length);
  const arrayLike=await (Array.fromAsync as any).call(Custom,{0:"x",length:1});console.log(arrayLike instanceof Custom, arrayLike.length,arrayLike[0]);
  for(const input of [null,{[Symbol.asyncIterator]:1}]) {try {await Array.fromAsync(input as any);}catch(e:any){console.log(e.name);}}
  try {await Array.fromAsync([1],null as any);}catch(e:any){console.log(e.name);}
  try {await (Array.fromAsync as any).call({}, {length:2**32,get 0(){throw new Error("must not read");}});}catch(e:any){console.log(e.name);}
  const large:any={length:2**32};large[2**32-1]="last";
  console.log(Array.prototype.at.call(large,-1));
  const bigArray=new Array(2**31);console.log(bigArray.length);
  const inf={size:Infinity,has(v:number){return v===1;},keys(){throw new Error("unused");}};
  console.log(new Set([1]).isSubsetOf(inf));
  console.log(Number.isInteger(2**32),Number.isSafeInteger(2**53-1),Number.isSafeInteger(2**53));
  console.log(Array.fromAsync.name, Array.fromAsync.length);
}
main();
}
