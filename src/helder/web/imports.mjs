// The JavaScript side of helder.web in a wasm32-wasi module: the imports of
// the module "hxmc_web" (src/helder/web/WasmBridge.hx), loaded by helder.os's
// browser.mjs. host.web.exports: the module's Exports by name, each the
// address of a @:hxmc.callback (host.call(address, ...args) calls it), which
// helder.web.WasmModule calls.
export default (host) => {
	const exports = {};
	host.web = { exports };
	return {
		hxmc_web: {
			define(name, fn) {
				exports[host.string(name)] = fn;
			},
		},
	};
};
