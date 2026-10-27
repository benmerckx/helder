// A wasm32-wasi program run by node's WASI (the 3d lane's unit tests):
//   node --stack-size=65500 tests/wasi.mjs <module.wasm> [args...]
// with the working directory preopened as itself, the environment passed on,
// exiting with the program's code.
import fs from 'node:fs';
import process from 'node:process';
import { WASI } from 'node:wasi';

const [file, ...args] = process.argv.slice(2);
const wasi = new WASI({ version: 'preview1', args: [file, ...args], env: process.env, preopens: { '.': '.' }, returnOnExit: true });
const module = await WebAssembly.compile(fs.readFileSync(file));
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
process.exitCode = wasi.start(instance);
