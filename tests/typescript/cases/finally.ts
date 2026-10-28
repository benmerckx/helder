// finally with exceptions, break, continue and return passing through
function f(){try{return 1;}finally{console.log("fin");}}console.log(f());try{try{throw new Error("x")}finally{console.log("a")}}catch(e:any){console.log(e.message)}
function a(){for(let i=0;i<3;i++){try{if(i==1)continue;if(i==2)break;console.log("body",i)}finally{console.log("fin",i)}}return "done"}console.log(a());
function b(){try{try{return "inner"}finally{console.log("f1")}}finally{console.log("f2")}}console.log(b());
function c(){outer:for(const x of [1,2]){try{for(const y of [1,2]){if(y==2)continue outer;console.log(x,y)}}finally{console.log("f",x)}}}c();
function d():number{try{throw 1}catch(e){return 2}finally{console.log("d")}}console.log(d());
function e(){try{return 1}finally{return 2}}console.log(e());
