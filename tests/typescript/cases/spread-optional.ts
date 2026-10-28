// rest parameters, spread, optional chaining and arguments
{
function sum(...xs:number[]){return xs.reduce((a,b)=>a+b,0)}console.log(sum(1,2,3),sum(...[4,5]));const a=[1,2];const b=[...a,3];const o={...{x:1},y:2};console.log(b.join(),JSON.stringify(o),Math.max(...b));
}
{
const o:any={a:{b:1}};console.log(o?.a?.b,o?.x?.y,o.f?.(),o.a?.["b"]);function f(x?:number){return x??7}console.log(f(),f(1));interface I{a?:number}const i:I={};console.log(i.a);
}
{
function f(a?:number,b?:number){return arguments.length+":"+a+":"+b}console.log((f as any)(1),(f as any)(1,2,3),f());
function g(this:any,x=5,...r:number[]){const inner=()=>arguments[0];return [x,r.length,inner(),arguments.length].join()}console.log(g(),g(1,2,3));
}
{
const m=new Map([["a",1],["b",2]]);for(const [k,v] of m)console.log(k,v);m.forEach((v,k)=>console.log(k,v));const s=new Set("hello");console.log([...s].join(""),[...m.entries()].length);
}
