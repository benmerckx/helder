// The helder command from this checkout (`bun run helder <command> ...`):
// bin/cli/helder built by hxmc (helder.cli.Cli, on helder.async) when a
// source of it is newer, then run in the working directory with the
// arguments. The binary on npm comes later.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

// (fileURLToPath: a URL's pathname is /C:/... on Windows)
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const exe = path.join(root, 'bin/cli', process.platform === 'win32' ? 'helder.exe' : 'helder');
// (the compiler through its launcher, run by this node: node will not spawn a
// .cmd without a shell, node_modules/.bin's haxe.cmd on Windows)
const haxe = process.env.HAXE ? [process.env.HAXE] : [process.execPath, path.join(root, 'node_modules/@hxmc/cli/hxmc/bootstrap/haxe.mjs')];

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

const sources = Math.max(newest(path.join(root, 'src/helder/cli')), newest(path.join(root, 'src/helder/async')));
if (!fs.existsSync(exe) || fs.statSync(exe).mtimeMs < sources) {
	const t0 = Date.now();
	// (built beside it, then renamed over it: a running one, `helder dev`'s, cannot be written over)
	const tmp = exe.replace(/(\.exe)?$/, `.${process.pid}$1`);
	const b = spawnSync(haxe[0], [...haxe.slice(1), '-cp', 'src', '-main', 'helder.cli.Cli', '--custom-target', `hxmc=${tmp}`], { cwd: root, encoding: 'utf8' });
	if (b.status === 0) fs.renameSync(tmp, exe);
	if (b.status !== 0) {
		process.stderr.write((b.stdout ?? '') + (b.stderr ?? '') + (b.error ? String(b.error) + '\n' : ''));
		console.error('helder: bin/cli/helder: the build failed');
		process.exit(1);
	}
	console.error(`helder: bin/cli/helder built (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
}
const r = spawnSync(exe, process.argv.slice(2), { stdio: 'inherit' });
process.exit(r.status ?? 1);
