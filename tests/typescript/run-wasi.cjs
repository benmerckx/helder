// Lean launcher for tshx's wasm32-wasi output: node run-wasi.cjs prog.wasm [args...]
// hxmc/hxmc/bootstrap/wasi.mjs also runs these modules; this one skips its
// compiler-hosting features (Windows paths, brotli stage0, extra imports) so
// process startup stays at plain node's.
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const emitWarning = process.emitWarning;
process.emitWarning = (w, ...rest) => { if (!String(w).includes('WASI')) emitWarning.call(process, w, ...rest); };
const { WASI } = require('node:wasi');
const [file, ...args] = process.argv.slice(2);
if (!file) { console.error('usage: node run-wasi.cjs prog.wasm [args...]'); process.exit(2); }
const bytes = fs.readFileSync(file);
let wasm;
try { wasm = new WebAssembly.Module(bytes); }
catch (e) {
	// (exception handling with exnref is behind a flag before node 24)
	require('node:v8').setFlagsFromString('--experimental-wasm-exnref');
	wasm = new WebAssembly.Module(bytes);
}
const wasi = new WASI({ version: 'preview1', args: [path.resolve(file), ...args], env: { ...process.env, PWD: process.cwd() }, preopens: { '/': '/' }, returnOnExit: true });
const imports = wasi.getImportObject();
// (an exit inside a turn: WASI's proc_exit throws its symbol, the code kept on the WASI object)
const exitCode = Object.getOwnPropertySymbols(wasi).find(k => k.description === 'kExitCode');
let instance;
const host = {
	call(f, ...a) {
		try {
			return instance.exports.__indirect_function_table.get(f)(...a);
		} catch (e) {
			if (typeof e !== 'symbol') throw e;
			process.exit(exitCode ? wasi[exitCode] : 1);
		}
	}
};
(async () => {
	// helder.async's loop turned by node's, as a page's would (src/helder/async/imports.mjs:
	// a program's timers and promises under helder's API); other modules' imports do nothing
	if (WebAssembly.Module.imports(wasm).some(i => i.module === 'helder_async')) {
		const url = require('node:url').pathToFileURL(path.join(__dirname, '../../src/helder/async/imports.mjs')).href;
		Object.assign(imports, (await import(url)).default(host));
	}
	for (const i of WebAssembly.Module.imports(wasm))
		if (i.kind === 'function' && !(i.module in imports && i.name in imports[i.module])) (imports[i.module] ??= {})[i.name] = () => 0;
	instance = new WebAssembly.Instance(wasm, imports);
	process.exitCode = wasi.start(instance) ?? 0;
})();
