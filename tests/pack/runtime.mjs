// The runtime objects the pack lane's Android and iOS builds need, which
// npm does not install on this machine, into <dir>/<target>/{rt,ssl,uv}.o
// (the lane gives the builds HXMC_RT_DIR=<dir>):
// - macos-arm64 (iOS links against it): @hxmc/darwin-arm64 at @hxmc/cli's
//   version, from npm's registry (on a Mac npm has installed it already);
// - android-arm64 and android-x86_64: not on npm, but in the GitHub release
//   rt-<hash> of hxmc's runtime objects; the one whose linux-x86_64 rt.o is
//   the one @hxmc/linux-x64 installed (the same sources), from
//   HXMC_RT_RELEASE when it names one, else the newest rt-* releases'
//   (GitHub's API; GITHUB_TOKEN when there).
// What it cannot get it says, and leaves out (the lane then skips those
// builds, or fails with PACK_REQUIRE=1). curl does the downloads (it
// follows the environment's proxy settings).
//   node tests/pack/runtime.mjs <dir>
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dir = path.resolve(process.argv[2] ?? 'bin/pack/rt');
const version = JSON.parse(fs.readFileSync(path.join(repo, 'node_modules/@hxmc/cli/package.json'), 'utf8')).version;
const OBJECTS = ['rt.o', 'ssl.o', 'uv.o'];
const has = (t) => OBJECTS.every((o) => fs.existsSync(path.join(dir, t, o)));
const curl = (url, headers = []) => {
	try {
		return execFileSync('curl', ['-sSfL', '--retry', '3', ...headers.flatMap((h) => ['-H', h]), url], { maxBuffer: 1 << 30, stdio: ['ignore', 'pipe', 'pipe'] });
	} catch {
		return null;
	}
};
fs.mkdirSync(dir, { recursive: true });

// iOS's: @hxmc/darwin-arm64's macos-arm64/
const installed = path.join(repo, 'node_modules/@hxmc/darwin-arm64/macos-arm64');
if (has('macos-arm64')) console.log('runtime: macos-arm64 there');
else if (fs.existsSync(path.join(installed, 'rt.o'))) {
	fs.mkdirSync(path.join(dir, 'macos-arm64'), { recursive: true });
	for (const o of OBJECTS) fs.copyFileSync(path.join(installed, o), path.join(dir, 'macos-arm64', o));
	console.log('runtime: macos-arm64 from node_modules/@hxmc/darwin-arm64');
} else {
	const tgz = curl(`https://registry.npmjs.org/@hxmc/darwin-arm64/-/darwin-arm64-${version}.tgz`);
	if (!tgz) console.log(`runtime: no @hxmc/darwin-arm64@${version} on npm: no iOS builds`);
	else {
		const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'helder-rt-'));
		fs.writeFileSync(path.join(tmp, 'p.tgz'), tgz);
		execFileSync('tar', ['xzf', path.join(tmp, 'p.tgz'), '-C', tmp, 'package/macos-arm64']);
		fs.mkdirSync(path.join(dir, 'macos-arm64'), { recursive: true });
		for (const o of OBJECTS) fs.copyFileSync(path.join(tmp, 'package/macos-arm64', o), path.join(dir, 'macos-arm64', o));
		fs.rmSync(tmp, { recursive: true, force: true });
		console.log(`runtime: macos-arm64 from @hxmc/darwin-arm64@${version}`);
	}
}

// Android's: the rt-* release of the same sources as the installed compiler's
const android = ['android-arm64', 'android-x86_64'];
if (android.every(has)) console.log('runtime: android-arm64, android-x86_64 there');
else {
	const mine = path.join(repo, 'node_modules/@hxmc/linux-x64/linux-x86_64/rt.o');
	const repoName = process.env.HXMC_RT_REPO || 'benmerckx/hxmc';
	const auth = process.env.GITHUB_TOKEN ? [`Authorization: Bearer ${process.env.GITHUB_TOKEN}`] : [];
	let tags = process.env.HXMC_RT_RELEASE ? [process.env.HXMC_RT_RELEASE] : [];
	if (tags.length === 0) {
		const list = curl(`https://api.github.com/repos/${repoName}/releases?per_page=100`, auth);
		try {
			tags = JSON.parse(list).map((r) => r.tag_name).filter((t) => /^rt-[0-9a-f]+$/.test(t));
		} catch {
			console.log(`runtime: ${repoName}'s releases not listed (GitHub's API; HXMC_RT_RELEASE names one)`);
		}
	}
	let found = null;
	const base = (t) => `https://github.com/${repoName}/releases/download/${t}/`;
	if (!fs.existsSync(mine)) console.log('runtime: no @hxmc/linux-x64 here to match a release against: no Android builds (HXMC_RT_DIR names Android\'s)');
	else {
		const want = fs.readFileSync(mine);
		for (const t of tags.slice(0, 20)) {
			const gz = curl(base(t) + 'linux-x86_64-rt.o.gz');
			if (gz && zlib.gunzipSync(gz).equals(want)) {
				found = t;
				break;
			}
		}
	}
	if (!found) console.log('runtime: no rt-* release matches the installed compiler: no Android builds');
	else {
		for (const t of android) {
			fs.mkdirSync(path.join(dir, t), { recursive: true });
			for (const o of OBJECTS) {
				const gz = curl(base(found) + `${t}-${o}.gz`);
				if (gz) fs.writeFileSync(path.join(dir, t, o), zlib.gunzipSync(gz));
			}
		}
		console.log(`runtime: ${android.filter(has).join(', ')} from ${repoName}'s ${found}`);
	}
}
