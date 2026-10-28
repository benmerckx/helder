// destructuring declarations, parameters, assignments, for-of and catch
{
const [a,b=2,...rest]=[1,undefined,3,4];const {x,y:z=5,...o}={x:1,w:2,q:3} as any;console.log(a,b,rest.join(),x,z,JSON.stringify(o));function f({p,q}:{p:number,q:number},[r]:number[]){return p+q+r}console.log(f({p:1,q:2},[3]));let m=1,n=2;[m,n]=[n,m];console.log(m,n);for(const [k,v] of [[1,2],[3,4]])console.log(k,v);
}
{
const {a:{b:[c,,d=4]},...others}={a:{b:[1,2]},e:5,f:6} as any;console.log(c,d,JSON.stringify(others));
let x:any,y:any,z:any;({x,y=3,...z}={x:1,q:2,r:3});console.log(x,y,JSON.stringify(z));
const arr:any[]=[];[arr[0],arr[1]]=["p","q"];console.log(arr.join());
const o:any={};({k:o.k,m:o["m"]=9}={k:7});console.log(o.k,o.m);
function g([a,b]:number[]=[1,2],{c=3}:{c?:number}={}){return a+b+c}console.log(g(),g([5,5],{c:0}));
var [v1,v2]="hi";console.log(v1,v2);
try{const {n}=null as any;console.log(n)}catch(e:any){console.log(e instanceof TypeError)}
const f=(...r:any[])=>r.length;console.log(f(),f(1,2,3));const h=function(first:number,...more:number[]){return first+more.length};console.log(h(1),h(1,2,3));
for(const {k,v} of [{k:1,v:2}])console.log(k,v);for(const [i,ch] of Array.from("ab").entries())console.log(i,ch);
let q:any;for(q of [7,8]);console.log(q);let w:any[]=[];for([w[0]] of [[1],[2]]);console.log(w[0]);
try{throw {code:42}}catch(e){const {code}=e as any;console.log(code)}
}
