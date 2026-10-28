// Current Array.fromAsync / AsyncFromSyncIteratorContinuation semantics.
// Node 24.22 invokes return() twice in the first case and once in the second;
// the current ECMA algorithm requires one and zero, respectively.
async function testClosing() {
    let syncClosed = 0;
    const sync = {
        [Symbol.iterator]() { return this; },
        next() { return {done:false,value:Promise.reject("value")}; },
        return() { syncClosed++; return {done:true}; }
    };
    try { await Array.fromAsync(sync as any); } catch (e) { if(e !== "value") throw e; }
    if(syncClosed !== 1) throw new Error("Sync wrapper must close the underlying iterator exactly once");
    let asyncClosed = 0;
    const asyncInput = {
        [Symbol.asyncIterator]() { return this; },
        next() { return Promise.reject("next"); },
        return() { asyncClosed++; return {done:true}; }
    };
    try { await Array.fromAsync(asyncInput as any); } catch(e) { if(e !== "next") throw e; }
    if(asyncClosed !== 0) throw new Error("A failed next() must not trigger AsyncIteratorClose");
    console.log("Array.fromAsync iterator-closing checks passed");
}
testClosing();
