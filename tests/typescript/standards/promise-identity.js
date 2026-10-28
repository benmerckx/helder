// Current specification preserves promise identity and calls the callback
// before constructing a new capability. Node 24 still uses earlier semantics.
const existing=Promise.resolve(1);if(Promise.try(()=>existing)!==existing)throw new Error("Promise identity");
class Sub extends Promise {}const sub=Sub.resolve(2);if(Sub.try(()=>sub)!==sub)throw new Error("Subclass identity");
let order=[];class Ordered extends Promise{constructor(executor){order.push("construct");super(executor);}}
Ordered.try(()=>{order.push("callback");return 3;});if(order.join()!=="callback,construct")throw new Error("Callback order");
const objectCtor={};const custom=Promise.resolve(4);Object.defineProperty(custom,"constructor",{value:objectCtor});if(Promise.try.call(objectCtor,()=>custom)!==custom)throw new Error("PromiseResolve identity before constructor check");
const sentinel={};const getter=Promise.resolve(5);Object.defineProperty(getter,"constructor",{get(){throw sentinel;}});
try{Promise.try(()=>getter);throw new Error("Getter must throw synchronously");}catch(e){if(e!==sentinel)throw e;}
let called=0;try{Promise.try.call(null,()=>called++);}catch(e){if(!(e instanceof TypeError))throw e;}if(called!==0)throw new Error("Primitive receiver validation");
try{Promise.try.call({},()=>{called++;return 1;});}catch(e){if(!(e instanceof TypeError))throw e;}if(called!==1)throw new Error("Object receiver callback order");
console.log("Promise.try specification checks passed");
