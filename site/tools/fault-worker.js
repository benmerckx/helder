// The playground's worker (worker.js) with the _start of its second instance
// (the first request's, after the warmup) faulting as the WebKit of Safari
// 26.0 at times does in correct code: browser-test.mjs checks that the worker
// runs that request again in a fresh instance (Worker.engineFault).
const Instance = WebAssembly.Instance;
let n = 0;
WebAssembly.Instance = function (module, imports) {
	const inst = new Instance(module, imports);
	if (++n !== 2) return inst;
	return { exports: { ...inst.exports, _start() { throw new WebAssembly.RuntimeError('access to a null reference'); } } };
};
importScripts('worker.js');
