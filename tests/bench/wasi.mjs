// The benchmark as wasm32-wasi under node (as tests/wasi.mjs), its imports
// besides WASI's (helder.text's browser fonts, hxmc_text) answered with 0:
//   node --stack-size=65500 tests/bench/wasi.mjs <module.wasm> [args...]
import fs from 'node:fs';
import process from 'node:process';
import { WASI } from 'node:wasi';

const [file, ...args] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [file, ...args], env: process.env, preopens: { '.': '.' }, returnOnExit: true });
const module = await WebAssembly.compile(fs.readFileSync(file));
const imports = wasi.getImportObject();
for (const i of WebAssembly.Module.imports(module))
	if (!(i.module in imports)) imports[i.module] = {};
for (const i of WebAssembly.Module.imports(module))
	if (i.kind === 'function' && !(i.name in imports[i.module])) imports[i.module][i.name] = () => 0;
const instance = await WebAssembly.instantiate(module, imports);
process.exitCode = wasi.start(instance);
