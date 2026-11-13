// helder's npm packages (README.md, "From npm"):
//   node src/helder/cli/npm.mjs version <version>
//     package.json at that version, its platform packages at the same one as
//     its optionalDependencies (before a publish: never committed);
//   node src/helder/cli/npm.mjs <os>-<cpu> ...
//     bin/npm/<os>-<cpu>: @helder.build/<os>-<cpu> at package.json's
//     version, the CLI (helder.cli.Cli) and helder's compiler
//     (src/helder/compiler/build.mjs) built by hxmc for that machine, from
//     any host (the target's runtime objects from @hxmc/<os>-<cpu>, here or
//     from npm), with their licenses.
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const TARGETS = {
	'darwin-arm64': 'macos-arm64',
	'darwin-x64': 'macos-x86_64',
	'linux-x64': 'linux-x86_64',
	'linux-arm64': 'linux-arm64',
	'win32-x64': 'windows-x86_64',
	'win32-arm64': 'windows-arm64',
};
const read = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const pkg = read(path.join(root, 'package.json'));
const hxmc = read(path.join(root, 'node_modules/@hxmc/cli/package.json'));
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const [command, ...rest] = process.argv.slice(2);

if (command === 'version') {
	const version = rest[0];
	if (!version) throw new Error('npm.mjs version: no version');
	pkg.version = version;
	pkg.optionalDependencies = Object.fromEntries(Object.keys(TARGETS).map((p) => [`@helder.build/${p}`, version]));
	fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify(pkg, null, 2) + '\n');
	console.log(`helder ${version}`);
	process.exit(0);
}

const platforms = command ? [command, ...rest] : [];
for (const p of platforms) if (!TARGETS[p]) throw new Error(`npm.mjs: no platform ${p} (${Object.keys(TARGETS).join(', ')})`);
if (platforms.length === 0) throw new Error(`npm.mjs: a platform (${Object.keys(TARGETS).join(', ')}) or version <version>`);

// @hxmc/<os>-<cpu> at @hxmc/cli's version: this install's, else npm's into bin/npm/hxmc
function hxmcPackage(p) {
	const own = path.join(root, 'node_modules/@hxmc', p);
	if (fs.existsSync(path.join(own, TARGETS[p], 'rt.o'))) return own;
	const dir = path.join(root, 'bin/npm/hxmc', p);
	if (fs.existsSync(path.join(dir, TARGETS[p], 'rt.o'))) return dir;
	fs.mkdirSync(dir, { recursive: true });
	// (a shell for npm.cmd on Windows: node will not spawn a .cmd without one)
	const tgz = execFileSync(npm, ['pack', `@hxmc/${p}@${hxmc.version}`, '--silent', '--pack-destination', dir], { encoding: 'utf8', shell: process.platform === 'win32' }).trim().split('\n').pop();
	execFileSync('tar', ['xzf', path.join(dir, tgz), '-C', dir, '--strip-components=1']);
	fs.rmSync(path.join(dir, tgz));
	return dir;
}

function run(what, cmd, args, env) {
	const t0 = Date.now();
	const r = spawnSync(cmd, args, { cwd: root, stdio: ['ignore', 'inherit', 'inherit'], env: { ...process.env, ...env } });
	if (r.status !== 0) throw new Error(`${what}: the build failed`);
	console.error(`built ${what} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}

const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
// (@hxmc/cli's version ends in the commit of hxmc it was built from)
const hxmcCommit = hxmc.version.split('.').pop();
const license = (name) => fs.readFileSync(path.join(root, name), 'utf8');

for (const p of platforms) {
	const target = TARGETS[p], ext = p.startsWith('win32') ? '.exe' : '';
	const dir = path.join(root, 'bin/npm', p), bin = path.join(dir, 'bin');
	const rt = hxmcPackage(p);
	fs.rmSync(dir, { recursive: true, force: true });
	fs.mkdirSync(bin, { recursive: true });
	const env = { HXMC_RT_DIR: rt };
	const launcher = path.join(root, 'node_modules/@hxmc/cli/hxmc/bootstrap/haxe.mjs');
	run(`${p}/bin/helder`, process.execPath, [launcher, '-cp', 'src', '-main', 'helder.cli.Cli', '-D', `hxmc.target=${target}`, '--custom-target', `hxmc=${path.join(bin, 'helder' + ext)}`], env);
	run(`${p}/bin/helder-compiler`, process.execPath, [path.join(root, 'src/helder/compiler/build.mjs'), '--quiet', '--target', target, '-o', path.join(bin, 'helder-compiler' + ext)], env);
	const [os, cpu] = p.split('-');
	fs.writeFileSync(path.join(dir, 'package.json'), JSON.stringify({
		name: `@helder.build/${p}`,
		version: pkg.version,
		description: `helder's command and compiler for ${p}`,
		license: 'MIT AND GPL-2.0-or-later',
		repository: pkg.repository,
		os: [os],
		cpu: [cpu],
		files: ['bin/', 'LICENSE*', 'COPYING', 'README.md'],
	}, null, 2) + '\n');
	fs.copyFileSync(path.join(root, 'LICENSE'), path.join(dir, 'LICENSE'));
	fs.copyFileSync(path.join(root, 'node_modules/@hxmc/source/COPYING'), path.join(dir, 'COPYING'));
	for (const f of ['LICENSE.libuv', 'LICENSE.mbedtls']) fs.copyFileSync(path.join(rt, f), path.join(dir, f));
	fs.writeFileSync(path.join(dir, 'README.md'), `# @helder.build/${p}

helder's command for ${p}, installed by the package \`helder\` (an optional
dependency of the same version), which runs it: \`npx helder\`.

- \`bin/helder${ext}\`: the helder CLI (helder.cli.Cli), MIT (LICENSE).
- \`bin/helder-compiler${ext}\`: helder's compiler, hxmc's compiler (the Haxe
  compiler ported to Haxe) with helder's hooks and frontends linked in,
  GPL-2.0-or-later (COPYING), as hxmc's compiler is. A separate
  executable: the GPL compiler is not linked into the MIT CLI. Its sources:
  - hxmc's at ${hxmcCommit}: https://github.com/benmerckx/hxmc/tree/${hxmcCommit}
    (npm: @hxmc/source@${hxmc.version});
  - helder's at ${commit.slice(0, 7)}: https://github.com/helder/helder/tree/${commit}/src
    (src/helder/compiler, built by src/helder/compiler/build.mjs).

Both link hxmc's runtime: libuv (LICENSE.libuv) and Mbed TLS (LICENSE.mbedtls).
`);
	const size = fs.readdirSync(bin).reduce((n, f) => n + fs.statSync(path.join(bin, f)).size, 0);
	console.log(`bin/npm/${p}: @helder.build/${p}@${pkg.version} (${(size / 1e6).toFixed(1)} MB)`);
}
