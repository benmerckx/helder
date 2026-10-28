// Builds helder-ts, hxmc's compiler with helder's TypeScript frontend
// (helder.typescript.Compiler), for the installed @hxmc/cli, and prints its
// path: node src/helder/typescript/build.mjs [--quiet] (--sources: hxmc's
// sources' path instead, for tests that link them too)
//
// It links hxmc's compiler sources: @hxmc/source, at @hxmc/cli's version,
// or HXMC_SRC naming a checkout. The executable is kept in the user's cache
// per hxmc version and per hash of helder.typescript's sources.
import {spawnSync} from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';

const src = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const quiet = process.argv.includes('--quiet');
const log = m => { if (!quiet) console.error(m); };

function find(rel) {
	for (let d = process.cwd(); ; d = path.dirname(d)) {
		if (fs.existsSync(path.join(d, rel))) return path.join(d, rel);
		if (path.dirname(d) === d) break;
	}
	for (let d = src; ; d = path.dirname(d)) {
		if (fs.existsSync(path.join(d, rel))) return path.join(d, rel);
		if (path.dirname(d) === d) return null;
	}
}
const cli = find('node_modules/@hxmc/cli/package.json');
if (!cli) throw new Error('helder-ts: @hxmc/cli is not installed');
const version = JSON.parse(fs.readFileSync(cli, 'utf8')).version;
const cache = process.env.HELDER_CACHE ?? (process.platform === 'win32' ? path.join(process.env.LOCALAPPDATA ?? os.homedir(), 'helder', 'cache')
	: process.platform === 'darwin' ? path.join(os.homedir(), 'Library/Caches/helder') : path.join(process.env.XDG_CACHE_HOME ?? path.join(os.homedir(), '.cache'), 'helder'));

let hxmc = process.env.HXMC_SRC;
if (!hxmc) {
	const source = find('node_modules/@hxmc/source/package.json');
	if (!source) throw new Error(`helder-ts: @hxmc/source is not installed (add @hxmc/source@${version}, or set HXMC_SRC to hxmc's sources)`);
	const sourceVersion = JSON.parse(fs.readFileSync(source, 'utf8')).version;
	if (sourceVersion !== version) throw new Error(`helder-ts: @hxmc/source ${sourceVersion} does not match @hxmc/cli ${version}`);
	hxmc = path.dirname(source);
}

if (process.argv.includes('--sources')) {
	console.log(hxmc);
	process.exit(0);
}

function hashTree(dir, h) {
	for (const e of fs.readdirSync(dir, {withFileTypes: true}).sort((a, b) => a.name < b.name ? -1 : 1)) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) hashTree(p, h);
		else if (e.name.endsWith('.hx')) h.update(e.name).update(fs.readFileSync(p));
	}
	return h;
}
const key = hashTree(path.join(src, 'helder/typescript'), crypto.createHash('sha256')).update(version).update(hxmc).digest('hex').slice(0, 16);
const exe = path.join(cache, 'typescript', `${key}`, process.platform === 'win32' ? 'helder-ts.exe' : 'helder-ts');
if (!fs.existsSync(exe)) {
	const t0 = Date.now();
	fs.mkdirSync(path.dirname(exe), {recursive: true});
	const tmp = `${exe}.${process.pid}`;
	const launcher = path.join(path.dirname(cli), 'hxmc/bootstrap/haxe.mjs');
	const args = ['-cp', src, '-cp', path.join(hxmc, 'haxe/src'), '-cp', path.join(hxmc, 'hxmc/src'), '-main', 'helder.typescript.Compiler',
		'-D', 'disable-parallelism', '-D', 'hih_no_generators', ...(process.platform === 'linux' ? ['-D', 'hxmc.libc=glibc'] : []), '--custom-target', `hxmc=${tmp}`];
	log(`building helder-ts (hxmc ${version})`);
	const b = spawnSync(process.execPath, [launcher, ...args], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
	if (b.status !== 0) {
		process.stderr.write(b.stdout + b.stderr);
		process.exit(1);
	}
	fs.renameSync(tmp, exe);
	log(`built ${exe} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}
console.log(exe);
