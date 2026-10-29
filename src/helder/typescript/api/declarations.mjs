// Writes helder's TypeScript declaration files from its Haxe types
// (helder.typescript.api.Declarations): src/helder/view/index.d.ts and the
// others its modules' declaration classes name. `--check`: writes nothing,
// fails when one differs (the TypeScript tests run it). A program's own
// modules: their declaration classes and class paths given.
//
//   node src/helder/typescript/api/declarations.mjs [--check] [--cp dir]... [pack.Module]...
import {spawnSync} from 'node:child_process';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const src = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
export const MODULES = ['helder.view.TypeScript', 'helder.ui.TypeScript', 'helder.web.TypeScript'];

const args = process.argv.slice(2), cps = [], modules = [];
let check = false;
while (args.length > 0) {
	const a = args.shift();
	if (a === '--check') check = true;
	else if (a === '--cp') cps.push('-cp', args.shift());
	else modules.push(a);
}
const built = spawnSync(process.execPath, [path.join(src, 'helder/compiler/build.mjs'), '--quiet'], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit']});
if (built.status !== 0) process.exit(1);
const compiler = built.stdout.trim();
const list = modules.length > 0 ? modules : MODULES;
const call = `helder.typescript.api.Declarations.write([${list.map(m => `"${m}"`).join(', ')}]${check ? ', true' : ''})`;
const r = spawnSync(compiler, ['-cp', src, ...cps, '--macro', call, '--no-output', '--custom-target', 'hxmc=' + path.join(src, '..', 'bin', 'declarations')],
	{encoding: 'utf8', stdio: 'inherit'});
process.exit(r.status ?? 1);
