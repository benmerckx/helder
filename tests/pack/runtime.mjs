// The runtime objects the pack lane's Android and iOS builds need, which
// npm does not install on this machine, into <dir>/<target>/{rt,ssl,uv}.o
// (the lane gives the builds HXMC_RT_DIR=<dir>):
// - macos-arm64 (iOS links against it): @hxmc/darwin-arm64 at @hxmc/cli's
//   version, from npm's registry (on a Mac npm has installed it already);
// - android-arm64 and android-x86_64: not on npm, but in the GitHub release
//   rt-<16 hex> of benmerckx/hxmc that @hxmc/cli's package.json names
//   ("hxmc": {"rt"}), as helder.cli.Runtime fetches them (HELDER_RT_URL:
//   another place for the releases, <it>/<tag>/<asset>).
// - with --desktop also macos-x86_64 and windows-x86_64 (@hxmc/darwin-x64,
//   @hxmc/win32-x64), the desktop releases' builds from any host (the
//   viewer-package lane, the release workflow: helder build --package).
// What it cannot get it says, and leaves out (the lane then skips those
// builds, or fails with PACK_REQUIRE=1). curl does the downloads (it
// follows the environment's proxy settings).
//   node tests/pack/runtime.mjs <dir> [--desktop]
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const args = process.argv.slice(2);
const desktop = args.includes('--desktop');
const dir = path.resolve(args.filter((a) => !a.startsWith('--'))[0] ?? 'bin/pack/rt');
const cli = JSON.parse(fs.readFileSync(path.join(repo, 'node_modules/@hxmc/cli/package.json'), 'utf8'));
const version = cli.version;
const tag = /^rt-[0-9a-f]+$/.test(cli.hxmc?.rt ?? '') ? cli.hxmc.rt : null;
const OBJECTS = ['rt.o', 'ssl.o', 'uv.o'];
const has = (t) => OBJECTS.every((o) => fs.existsSync(path.join(dir, t, o)));
const curl = (url) => {
	try {
		return execFileSync('curl', ['-sSfL', '--retry', '3', url], { maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });
	} catch {
		return null;
	}
};
fs.mkdirSync(dir, { recursive: true });

// a target's objects from its npm package (installed here, else the registry's at @hxmc/cli's version)
const fromNpm = (pkg, target, what) => {
	const installed = path.join(repo, `node_modules/@hxmc/${pkg}/${target}`);
	if (has(target)) console.log(`runtime: ${target} there`);
	else if (fs.existsSync(path.join(installed, 'rt.o'))) {
		fs.mkdirSync(path.join(dir, target), { recursive: true });
		for (const o of OBJECTS) fs.copyFileSync(path.join(installed, o), path.join(dir, target, o));
		console.log(`runtime: ${target} from node_modules/@hxmc/${pkg}`);
	} else {
		const tgz = curl(`https://registry.npmjs.org/@hxmc/${pkg}/-/${pkg}-${version}.tgz`);
		if (!tgz) console.log(`runtime: no @hxmc/${pkg}@${version} on npm: no ${what} builds`);
		else {
			const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'helder-rt-'));
			fs.writeFileSync(path.join(tmp, 'p.tgz'), tgz);
			execFileSync('tar', ['xzf', path.join(tmp, 'p.tgz'), '-C', tmp, `package/${target}`]);
			fs.mkdirSync(path.join(dir, target), { recursive: true });
			for (const o of OBJECTS) fs.copyFileSync(path.join(tmp, `package/${target}`, o), path.join(dir, target, o));
			fs.rmSync(tmp, { recursive: true, force: true });
			console.log(`runtime: ${target} from @hxmc/${pkg}@${version}`);
		}
	}
};

// iOS's: @hxmc/darwin-arm64's macos-arm64/ (a universal macOS app's arm64 slice too)
fromNpm('darwin-arm64', 'macos-arm64', 'iOS');
if (desktop) {
	fromNpm('darwin-x64', 'macos-x86_64', 'macOS x86-64');
	fromNpm('win32-x64', 'windows-x86_64', 'Windows');
}

// Android's: the release @hxmc/cli's package.json names ("hxmc": {"rt"}),
// its assets <target>-<object>.gz gunzipped (the tag beside them: a new
// one fetches again)
const android = ['android-arm64', 'android-x86_64'];
const stamp = path.join(dir, 'android.tag');
const current = fs.existsSync(stamp) ? fs.readFileSync(stamp, 'utf8').trim() : null;
if (!tag) console.log('runtime: @hxmc/cli\'s package.json names no release ("hxmc": {"rt"}): no Android builds');
else if (current === tag && android.every(has)) console.log(`runtime: android-arm64, android-x86_64 there (${tag})`);
else {
	const base = (process.env.HELDER_RT_URL || 'https://github.com/benmerckx/hxmc/releases/download').replace(/\/+$/, '');
	fs.rmSync(stamp, { force: true });
	for (const t of android) {
		fs.rmSync(path.join(dir, t), { recursive: true, force: true });
		fs.mkdirSync(path.join(dir, t), { recursive: true });
		for (const o of OBJECTS) {
			const gz = curl(`${base}/${tag}/${t}-${o}.gz`);
			if (gz) fs.writeFileSync(path.join(dir, t, o), zlib.gunzipSync(gz));
			else console.log(`runtime: ${base}/${tag}/${t}-${o}.gz not fetched`);
		}
	}
	if (android.every(has)) fs.writeFileSync(stamp, tag + '\n');
	console.log(`runtime: ${android.filter(has).join(', ') || 'nothing'} from ${base}/${tag}`);
}
