#!/usr/bin/env node
// The helder command (package.json's bin: `npx helder`, `bun run helder`),
// run in the working directory with the arguments:
// - installed from npm: the platform package's (@helder.build/<os>-<cpu>,
//   an optional dependency: bin/helder, helder.cli.Cli, and
//   bin/helder-compiler, helder's compiler, which HELDER_COMPILER names),
//   given what @hxmc/cli's launcher gives its compiler (the std, hxmc's,
//   the runtime objects);
// - in this checkout (`bun run helder <command> ...`): bin/cli/helder built
//   by hxmc when a source of it is newer.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

// (fileURLToPath: a URL's pathname is /C:/... on Windows)
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const ext = process.platform === 'win32' ? '.exe' : '';
const platform = `${process.platform}-${process.arch}`;
const require = createRequire(path.join(root, 'package.json'));
const resolve = (name) => {
	try {
		return path.dirname(require.resolve(`${name}/package.json`));
	} catch {
		return null;
	}
};
const prebuilt = resolve(`@helder.build/${platform}`);
if (prebuilt) {
	const { toolEnv } = await import(pathToFileURL(path.join(resolve('@hxmc/cli'), 'hxmc/bootstrap/launcher.mjs')));
	const env = toolEnv({ HELDER_COMPILER: path.join(prebuilt, 'bin', 'helder-compiler' + ext), HELDER_SRC: process.env.HELDER_SRC || path.join(root, 'src') });
	const r = spawnSync(path.join(prebuilt, 'bin', 'helder' + ext), process.argv.slice(2), { stdio: 'inherit', env });
	if (r.error) console.error(`helder: ${r.error.message}`);
	process.exit(r.status ?? 1);
}
// (an install without it: npm's --omit=optional, or no build for this machine)
if (root.split(path.sep).includes('node_modules')) {
	console.error(`helder: no helder command for ${platform} (@helder.build/${platform} is not installed)`);
	process.exit(1);
}

const exe = path.join(root, 'bin/cli', 'helder' + ext);
// (the compiler through its launcher, run by this node: node will not spawn a
// .cmd without a shell, node_modules/.bin's haxe.cmd on Windows)
const haxe = process.env.HAXE ? [process.env.HAXE] : [process.execPath, path.join(resolve('@hxmc/cli') ?? path.join(root, 'node_modules/@hxmc/cli'), 'hxmc/bootstrap/haxe.mjs')];

// (the newest .hx under the CLI's packages)
function newest(dir) {
	let t = 0;
	for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
		const p = path.join(dir, e.name);
		if (e.isDirectory()) t = Math.max(t, newest(p));
		else if (e.name.endsWith('.hx') || e.name.endsWith('.html')) t = Math.max(t, fs.statSync(p).mtimeMs);
	}
	return t;
}

// (its lines as the CLI's own, src/helder/cli/Style.hx: FORCE_COLOR, NO_COLOR, a terminal)
const force = process.env.FORCE_COLOR, no = process.env.NO_COLOR;
const color = force ? force !== '0' && force !== 'false' : !no && process.env.TERM !== 'dumb' && !!process.stderr.isTTY;
const status = (verb, sgr, text) => (color ? `\x1b[${sgr};1m${verb.padStart(9)}\x1b[0m` : verb.padStart(9)) + ' ' + text;

const sources = Math.max(...['cli', 'async', 'pack', 'image'].map((p) => newest(path.join(root, 'src/helder', p))));
if (!fs.existsSync(exe) || fs.statSync(exe).mtimeMs < sources) {
	const t0 = Date.now();
	// (built beside it, then renamed over it: a running one, `helder dev`'s, cannot be written over)
	const tmp = exe.replace(/(\.exe)?$/, `.${process.pid}$1`);
	const b = spawnSync(haxe[0], [...haxe.slice(1), '-cp', 'src', '-main', 'helder.cli.Cli', '--custom-target', `hxmc=${tmp}`], { cwd: root, encoding: 'utf8' });
	if (b.status === 0) fs.renameSync(tmp, exe);
	if (b.status !== 0) {
		process.stderr.write((b.stdout ?? '') + (b.stderr ?? '') + (b.error ? String(b.error) + '\n' : ''));
		console.error(status('failed', '31', 'bin/cli/helder: the build failed'));
		process.exit(1);
	}
	console.error(status('built', '32', `bin/cli/helder in ${((Date.now() - t0) / 1000).toFixed(1)} s`));
}
const r = spawnSync(exe, process.argv.slice(2), { stdio: 'inherit' });
process.exit(r.status ?? 1);
