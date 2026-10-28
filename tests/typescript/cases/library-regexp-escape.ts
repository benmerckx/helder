{
for(const text of ["abc-[]\n😀\ud800","a+b?","\ufeff","\u00a0","\t\v\f\r\n",",-=<>#&!%:;@~'`\"","1foo","é","","\u2028\u2029","\u3000","\ud800x\udfff"]){const escaped=RegExp.escape(text);console.log(JSON.stringify(escaped));console.log(new RegExp(escaped,"u").test(text));}
for(const value of [null,1,{},new String("x")])try{RegExp.escape(value as any);}catch(e:any){console.log(e.name);}
console.log(RegExp.escape.name,RegExp.escape.length,RegExp[Symbol.species]===RegExp);
}
