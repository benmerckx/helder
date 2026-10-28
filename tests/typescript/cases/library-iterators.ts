{
console.log(Iterator.from([1,2,3,4]).map((v,i)=>v*2+i).filter(v=>v>3).drop(1).take(1).toArray());
console.log(Iterator.from("a😀b").toArray());
console.log(Iterator.from([1,2,3]).flatMap((v,i)=>[v,i]).toArray());
console.log(Iterator.from([1,2,3]).reduce((a,v,i)=>a+v*i,0));
console.log(Iterator.from([1,2,3]).some(x=>x===2),Iterator.from([1,2,3]).every(x=>x>0),Iterator.from([1,2,3]).find(x=>x>1));
let sum=0;Iterator.from([1,2,3]).forEach((v,i)=>{sum+=v+i;});console.log(sum);
class Source extends Iterator<number>{index=0;next():IteratorResult<number>{return {done:this.index>2,value:this.index++};}}
const source=new Source();console.log(Iterator.from(source)===source,source.toArray());
let closes=0;function* values(){try{yield 1;yield 2;yield 3;}finally{closes++;}}
console.log(values().take(1).toArray(),closes);
const never:any=Iterator.from({next(){throw new Error("unexpected next");},return(){closes++;return {done:true,value:undefined};}}).map(v=>v);never.return();console.log(closes);
try{values().map(()=>{throw "mapper";}).next();}catch(e){console.log(e,closes);}
let pulled=0;const cached=Iterator.from({get next(){pulled++;return ()=>({done:true,value:undefined});}});cached.next();cached.next();console.log(pulled);
let reentrant:any;reentrant=Iterator.from([1]).map(()=>{try{reentrant.next();}catch(e:any){return e.name;}});console.log(reentrant.toArray());
console.log(Iterator.prototype[Symbol.iterator].call(3 as any));
}
