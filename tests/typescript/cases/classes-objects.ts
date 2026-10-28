// classes, getters, object literal methods, closures over this, errors, strings, inspection
{
class A{static count=0;#p=1;constructor(public x:number){A.count++}get double(){return this.x*2}set double(v){this.x=v/2}static make(){return new A(1)}peek(){return this.#p}}class B extends A{constructor(x:number,public y:number){super(x)}toString(){return `B(${this.x},${this.y})`}}const b=new B(2,3);console.log(b.double,A.count,String(b),A.make().x,b.peek());b.double=10;console.log(b.x,b instanceof A);
}
{
class A{hi(){return "A"}}class B extends A{hi(){return super.hi()+"B"}}console.log(new B().hi());abstract class S{abstract f():number;g(){return this.f()+1}}class T extends S{f(){return 1}}console.log(new T().g());
}
{
class P{private _v=0;get v(){return this._v}set v(n){this._v=n*2}}const p=new P();p.v=3;console.log(p.v);
}
{
const o={n:2,get g():number{return this.n*2},m(){return this.n},["k"+1]:5};console.log(o.g,o.m(),o.k1);const p=Object.entries({a:1,b:2}).map(([k,v])=>k+v).join();console.log(p);
}
{
class C{n=1;f=()=>this.n;g(){return [1,2].map(x=>x+this.n)}}const c=new C();const f=c.f;console.log(f(),c.g().join());
}
{
function id<T>(x:T):T{return x}class Box<T>{constructor(public v:T){}map<U>(f:(x:T)=>U):Box<U>{return new Box(f(this.v))}}console.log(id(3),new Box(2).map(x=>x+"!").v);
}
{
class MyErr extends Error{constructor(m:string){super(m);this.name="MyErr"}}try{throw new MyErr("boom")}catch(e){if(e instanceof MyErr)console.log(e.name,e.message,e instanceof Error)}try{(null as any).x}catch(e:any){console.log(e instanceof TypeError)}
}
{
console.log({a:1,b:"x"},[1,[2,3]],null,undefined,true);
}
{
const s="Hello";console.log(s.toUpperCase(),s.indexOf("l"),s.split("").reverse().join(""),s.localeCompare("A")>0,s.at(-1),[..."héllo"].length,s.charAt(1),"a".concat("b",1 as any),"%"+s.length);
}
{
let c=0;const v=(c++,c+1);console.log(typeof null,void 0,v,2**10,"abc"[1],[1,2,3].at(-1),Number("12px"),String(12.5),(255).toString(16),(3.14159).toFixed(2),[3,1,2].sort().join());let x:unknown=5;if(typeof x==="number")console.log(x+1);label:{console.log("in");if(c)break label;console.log("no")}
}
