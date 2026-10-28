if (typeof tshxUndeclaredGlobal !== "undefined") throw new Error("Unknown global typeof");
if (typeof (((tshxUndeclaredGlobal))) !== "undefined") throw new Error("Parenthesized global typeof");
if (typeof Math !== "object" || typeof Array !== "function") throw new Error("Builtin global typeof");
let called=0;
try { typeof ({get value(){called++;throw "getter";}}).value; throw new Error("Getter did not throw"); }
catch(e) { if(e !== "getter") throw e; }
if(called !== 1) throw new Error("Getter count");
try { typeof tshxUndeclaredGlobal.value; throw new Error("Unknown base did not throw"); }
catch(e) { if(!(e instanceof ReferenceError)) throw e; }
console.log("typeof global checks passed");
