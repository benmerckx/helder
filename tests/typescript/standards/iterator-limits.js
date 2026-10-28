// Current specification bounds finite limits at Number.MAX_SAFE_INTEGER.
// Node 24 still accepts larger finite values; Infinity remains valid.
for(const kind of ["take","drop"]){
 let order="";
 const input={get next(){order+="N";return ()=>({done:true});},return(){order+="R";return {};}};
 try{Iterator.prototype[kind].call(input,{valueOf(){order+="L";return 2**53;}});throw new Error("Missing RangeError");}
 catch(e){if(!(e instanceof RangeError))throw e;}
 if(order!=="LR")throw new Error("Limit validation must precede next lookup and close the iterator");
 const helper=Iterator.prototype[kind].call({next(){return {done:true};}},Infinity);
 if(!helper.next().done)throw new Error("Infinity must be accepted");
}
console.log("Iterator limit checks passed");
