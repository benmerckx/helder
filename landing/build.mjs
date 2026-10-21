// The landing page (landing/, README.md there): builds bin/landing, a static
// site for GitHub Pages. Nothing is compiled ahead: the page gets the
// compiler (@hxmc/wasm's haxe.wasm), the std, the packages' sources and the
// runtime objects of each native target (@hxmc/cli's), and compiles the
// examples in the browser.
//
//   node landing/build.mjs [out]      (make landing; out: bin/landing)
//
// The npm packages are the nightly of the hxmc commit the Makefile pins
// (HXMC_REV; HXMC_NPM_VERSION=<version> picks another), fetched with npm into
// bin/landing-npm/<version>.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.resolve(process.argv[2] ?? path.join(root, 'bin/landing'));
const here = path.join(root, 'landing');

// the targets a download can be for: [id, rt directory]
// (Linux: the glibc mode, which loads the GPU's drivers)
export const TARGETS = [
	['linux-x86_64', 'linux-x86_64-glibc'],
	['linux-arm64', 'linux-arm64-glibc'],
	['macos-arm64', 'macos-arm64'],
	['macos-x86_64', 'macos-x86_64'],
	['windows-x86_64', 'windows-x86_64'],
	['windows-arm64', 'windows-arm64'],
];

// the examples' packages: their class paths (dependencies first), defines and
// browser modules (site/src/Examples.hx has the same)
const PACKAGES = {
	os: { cp: ['os'], imports: ['os'] },
	gfx: { cp: ['os', 'gfx'], imports: ['os', 'gfx'] },
	'3d': { cp: ['os', 'gfx', 'text', 'ui', '3d'], imports: ['os', 'gfx'] },
	physics: { cp: ['os', 'gfx', '3d', 'physics'], imports: ['os', 'gfx'] },
	text: { cp: ['os', 'gfx', 'text'], imports: ['os', 'gfx', 'text'], fonts: true },
	ui: {
		cp: ['os', 'gfx', 'text', 'view', 'ui', 'theme'],
		defines: ['hxmc.view.renderer.ui=hxmc.ui.view.NodeRenderer'],
		imports: ['os', 'gfx', 'text', 'ui'],
		fonts: true,
	},
};
PACKAGES.theme = { ...PACKAGES.ui };
// the gallery's order
const ORDER = ['gfx', 'physics', '3d', 'ui', 'theme', 'os'];
const FONT_DIRS = ['/usr/share/fonts/truetype/dejavu', '/usr/share/fonts/TTF', '/usr/share/fonts/dejavu', '/Library/Fonts'];
// upstream std's directories no hxmc build reads (the other targets')
const STD_SKIP = new Set(['cpp', 'cs', 'flash', 'hl', 'java', 'js', 'jvm', 'lua', 'neko', 'php', 'python']);

function npmPackages() {
	const rev = fs.readFileSync(path.join(root, 'Makefile'), 'utf8').match(/^HXMC_REV \?= (\w+)/m)[1];
	let version = process.env.HXMC_NPM_VERSION;
	if (!version) {
		const all = JSON.parse(execFileSync('npm', ['view', '@hxmc/wasm', 'versions', '--json'], { encoding: 'utf8' }));
		version = all.filter((v) => v.endsWith('.' + rev.slice(0, 7))).pop();
		if (!version) throw new Error(`landing: no nightly of @hxmc/wasm for hxmc ${rev.slice(0, 7)} (HXMC_NPM_VERSION=<version> picks one)`);
	}
	const dir = path.join(root, 'bin/landing-npm', version);
	for (const name of ['cli', 'wasm']) {
		const to = path.join(dir, name);
		if (fs.existsSync(path.join(to, 'package/package.json'))) continue;
		fs.mkdirSync(to, { recursive: true });
		const tgz = execFileSync('npm', ['pack', `@hxmc/${name}@${version}`, '--silent'], { cwd: to, encoding: 'utf8' }).trim().split('\n').pop();
		execFileSync('tar', ['xzf', tgz], { cwd: to });
		fs.rmSync(path.join(to, tgz));
	}
	return { version, rev, cli: path.join(dir, 'cli/package'), wasm: path.join(dir, 'wasm/package') };
}

// the files under dir, relative to it, sorted
function walk(dir, keep = () => true, rel = '') {
	const files = [];
	for (const e of fs.readdirSync(path.join(dir, rel), { withFileTypes: true }).sort((a, b) => (a.name < b.name ? -1 : 1))) {
		const r = rel ? `${rel}/${e.name}` : e.name;
		if (!keep(r, e)) continue;
		if (e.isDirectory()) files.push(...walk(dir, keep, r));
		else files.push(r);
	}
	return files;
}

// a pack (wasi.js, unpack) of [path, bytes]
function pack(entries) {
	const index = Buffer.from(JSON.stringify(entries.map(([p, b]) => [p, b.length])));
	const head = Buffer.alloc(4);
	head.writeUInt32LE(index.length);
	return Buffer.concat([head, index, ...entries.map(([, b]) => b)]);
}

function write(rel, data) {
	const f = path.join(out, rel);
	fs.mkdirSync(path.dirname(f), { recursive: true });
	fs.writeFileSync(f, data);
	return data.length;
}

const HEADER = /^\/\/ *(title|summary|tags|demo): *(.*)$/;

// the examples with a demo the page can show (a canvas, a sound), as
// site/src/Examples.hx reads them
function examples() {
	const list = [];
	for (const pkg of ORDER) {
		const dir = path.join(root, 'packages', pkg, 'examples');
		const names = fs.readdirSync(dir).filter((n) => n.endsWith('.hx')).sort();
		for (const n of names) {
			const head = {};
			for (const line of fs.readFileSync(path.join(dir, n), 'utf8').split('\n')) {
				if (!line.startsWith('//')) break;
				const m = line.trim().match(HEADER);
				if (m) head[m[1]] = m[2].trim();
			}
			if (!head.title || !head.demo) continue;
			const canvas = head.demo.match(/^canvas +(\d+)x(\d+)$/);
			if (!canvas && head.demo !== 'sound') continue;
			const main = n.slice(0, -3);
			const p = PACKAGES[pkg];
			list.push({
				id: `${pkg}-${main.toLowerCase()}`,
				pkg,
				main,
				title: head.title,
				summary: head.summary ?? '',
				tags: (head.tags ?? pkg).split(',').map((t) => t.trim()),
				demo: canvas ? { canvas: [+canvas[1], +canvas[2]] } : { sound: true },
				source: `packages/${pkg}/examples/${n}`,
				sources: used(dir, n, names).map((m) => `packages/${pkg}/examples/${m}`),
				args: [
					...p.cp.flatMap((c) => ['-cp', `/lib/src/packages/${c}/src`]),
					...(p.defines ?? []).flatMap((d) => ['-D', d]),
					'-cp', `/lib/src/packages/${pkg}/examples`,
					'-main', main,
				],
				imports: p.imports.map((i) => `${i}/imports.mjs`),
				fonts: !!p.fonts,
			});
		}
	}
	return list;
}

// the files of the folder an example names (CubeShader for Cube), and theirs
function used(dir, file, names) {
	const found = [];
	const todo = [file];
	while (todo.length) {
		const src = fs.readFileSync(path.join(dir, todo.shift()), 'utf8');
		for (const n of names) {
			if (n === file || found.includes(n)) continue;
			if (new RegExp(`\\b${n.slice(0, -3)}\\b`).test(src)) {
				found.push(n);
				todo.push(n);
			}
		}
	}
	return found;
}

function build() {
	const npm = npmPackages();
	fs.rmSync(out, { recursive: true, force: true });
	fs.mkdirSync(out, { recursive: true });
	const sizes = {};

	for (const f of ['index.html', 'style.css', 'app.js', 'sky.js', 'compiler.js', 'compile.js', 'wasi.js', 'zip.js', 'favicon.svg'])
		fs.copyFileSync(path.join(here, f), path.join(out, f));
	fs.writeFileSync(path.join(out, '.nojekyll'), '');

	// the compiler
	sizes['haxe.wasm'] = write('haxe.wasm', fs.readFileSync(path.join(npm.wasm, 'haxe.wasm')));

	// the std: upstream's (without the other targets') and hxmc's merged one
	const stdDir = path.join(npm.cli, 'haxe/upstream/std');
	const hxmcStd = path.join(npm.cli, 'hxmc/bootstrap/hxmc-std');
	const std = [
		...walk(stdDir, (r, e) => !(e.isDirectory() && !r.includes('/') && STD_SKIP.has(r))).map((r) => [`std/${r}`, fs.readFileSync(path.join(stdDir, r))]),
		...walk(hxmcStd).map((r) => [`hxmc-std/${r}`, fs.readFileSync(path.join(hxmcStd, r))]),
	];
	sizes['std.pack'] = write('std.pack', pack(std));

	// the packages' sources and examples (what the page compiles, with the
	// files macros read: theme's sheets, 3d's models); the examples' files are
	// also served, for the programs that load them (Model.of)
	const src = [];
	for (const p of fs.readdirSync(path.join(root, 'packages')).sort()) {
		for (const sub of ['src', 'examples']) {
			const d = path.join(root, 'packages', p, sub);
			if (!fs.existsSync(d)) continue;
			for (const r of walk(d)) {
				const rel = `packages/${p}/${sub}/${r}`;
				src.push([rel, fs.readFileSync(path.join(d, r))]);
				if (sub === 'examples' && !r.endsWith('.hx')) write(rel, fs.readFileSync(path.join(d, r)));
			}
		}
	}
	sizes['src.pack'] = write('src.pack', pack(src));

	// each target's runtime objects (fetched when a download asks for that target)
	const rtDir = path.join(npm.cli, 'hxmc/bootstrap/rt');
	for (const [id, dir] of TARGETS) {
		const files = walk(path.join(rtDir, dir)).map((r) => [`${dir}/${r}`, fs.readFileSync(path.join(rtDir, dir, r))]);
		files.push(['HASH', fs.readFileSync(path.join(rtDir, 'HASH'))]);
		sizes[`rt/${id}.pack`] = write(`rt/${id}.pack`, pack(files));
	}

	// the browser modules the programs run with
	fs.mkdirSync(path.join(out, 'os'), { recursive: true });
	fs.copyFileSync(path.join(root, 'packages/os/browser.mjs'), path.join(out, 'os/browser.mjs'));
	for (const p of ['os', 'gfx', 'text', 'ui']) {
		fs.mkdirSync(path.join(out, p), { recursive: true });
		fs.copyFileSync(path.join(root, 'packages', p, 'imports.mjs'), path.join(out, p, 'imports.mjs'));
	}
	for (const f of ['DejaVuSans.ttf', 'DejaVuSans-Bold.ttf']) {
		const d = FONT_DIRS.find((d) => fs.existsSync(path.join(d, f)));
		if (!d) throw new Error(`landing: ${f} not found (install fonts-dejavu-core) in ${FONT_DIRS.join(', ')}`);
		fs.mkdirSync(path.join(out, 'fonts'), { recursive: true });
		fs.copyFileSync(path.join(d, f), path.join(out, 'fonts', f));
	}

	const list = examples();
	const commit = (() => {
		try {
			return execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root, encoding: 'utf8' }).trim();
		} catch {
			return 'unknown';
		}
	})();
	const manifest = { hxmc: { version: npm.version, rev: npm.rev }, commit, targets: TARGETS.map(([id]) => id), sizes, examples: list };
	write('manifest.json', JSON.stringify(manifest, null, '\t'));

	for (const [f, n] of Object.entries(sizes)) console.log(`${f.padEnd(24)} ${(n / 1048576).toFixed(2).padStart(7)} MB`);
	console.log(`landing: ${list.length} examples, hxmc ${npm.version}, into ${path.relative(process.cwd(), out) || '.'}`);
}

if (process.argv[1] === fileURLToPath(import.meta.url)) build();
