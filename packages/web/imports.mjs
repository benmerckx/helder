// The JavaScript side of @hxmc/web in a wasm32-wasi module: the imports of
// the module "hxmc_web" (src/hxmc/web/WasmBridge.hx), loaded by @hxmc/os's
// browser.mjs. host.web.exports: the module's Exports by name, each the
// address of a @:hxmc.callback (host.call(address, ...args) calls it), which
// hxmc.web.WasmModule calls.
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
