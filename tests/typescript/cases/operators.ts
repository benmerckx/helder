// compound and logical assignment, **, comma, void, templates, nested functions
let a=2;a**=10;let b=5;b<<=2;b>>=1;let c=-16;c>>>=28;let d=6;d&=3;d|=8;d^=1;console.log(a,b,c,d,2**-1,(-2)**3,1**NaN,NaN**0,(-8)**(1/3));
let o:any=null;o??=4;let p:any=0;p||=7;let q:any=1;q&&=9;let r:any=5;r??=(console.log("no"),1);console.log(o,p,q,r);
const obj:any={v:1};obj.v+=2;obj["w"]??=3;obj.v**=2;console.log(obj.v,obj.w);let s="a";s+=1;s+=null;console.log(s);
const n=3;console.log(`a${n}b${n*2}c`,`x`,`${"s"}${null}${undefined}`);
function outer(n:number){function inner(x:number):number{return x<=0?0:x+inner(x-1)}return inner(n)}console.log(outer(4));console.log(hoisted());function hoisted(){return "h"}
let k=0;const v=(k++,k+1);console.log(v,void k,`${v}${`n${k}`}`);
