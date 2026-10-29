// A wasm32-wasi program run by node's WASI (the 3d lane's unit tests):
//   node --stack-size=65500 tests/wasi.mjs <module.wasm> [args...]
// with the working directory preopened as itself, the environment passed on,
// exiting with the program's code. Other modules' imports (helder_async's,
// linked by what the program never runs here) are functions doing nothing.
import fs from 'node:fs';
import process from 'node:process';
import { WASI } from 'node:wasi';

const [file, ...args] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [file, ...args], env: process.env, preopens: { '.': '.' }, returnOnExit: true });
const module = await WebAssembly.compile(fs.readFileSync(file));
const imports = wasi.getImportObject();
for (const i of WebAssembly.Module.imports(module))
	if (i.kind === 'function' && !(i.module in imports && i.name in imports[i.module])) (imports[i.module] ??= {})[i.name] = () => 0;
const instance = await WebAssembly.instantiate(module, imports);
process.exitCode = wasi.start(instance);
