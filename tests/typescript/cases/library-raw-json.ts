{
const J=JSON as any;
for(const text of ["123456789012345678901234567890","-0","1e400","true","false","null",'"hello"','"\\ud800"']) {
 const raw=J.rawJSON(text);console.log(J.isRawJSON(raw),Object.getPrototypeOf(raw)===null,Object.isFrozen(raw),Object.keys(raw),JSON.stringify({raw}),JSON.stringify([raw]));
}
for(const text of [""," 1","1 ","{}","[]","01","NaN","undefined","-","1."])try{J.rawJSON(text);}catch(e:any){console.log(text,e.name);}
console.log(J.isRawJSON({rawJSON:"1"}),J.isRawJSON(Object.create(J.rawJSON("1"))),J.isRawJSON(null));
console.log(JSON.stringify({v:1},(_,v)=>v===1?J.rawJSON("9007199254740993"):v));
console.log(J.rawJSON.name,J.rawJSON.length,J.isRawJSON.name,J.isRawJSON.length);
const thrower=Object.getOwnPropertyDescriptor(Function.prototype,"caller")!;
console.log(thrower.get===thrower.set,thrower.enumerable,thrower.configurable,Object.isFrozen(thrower.get),thrower.get!.name,thrower.get!.length);
try {thrower.get!.call(null);}catch(e:any){console.log(e.name);}
const E=Error as any;const error=new TypeError("x");Object.setPrototypeOf(error,null);
console.log(E.isError(error),E.isError(new AggregateError([])),E.isError(Error.prototype),E.isError(Object.create(Error.prototype)),E.isError({[Symbol.toStringTag]:"Error"}));
}
