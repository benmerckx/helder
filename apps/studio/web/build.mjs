// helder studio for the browser: the page, built into a directory to serve
// as it is (any static host; tests/studio-web serves it):
//
//   node apps/studio/web/build.mjs <out> [--compiler <dir>] [project[=label]...]
//
//   <out>/index.html, studio.mjs          the page (apps/studio/web)
//   <out>/new/app.helder                  a new project (?new, the welcome's)
//   <out>/studio.wasm, helder/...         the studio built for the web, its packages' browser modules
//   <out>/helder/story/web/worker.mjs     the preview host's worker (helder.story.web.Preview)
//   <out>/fonts/                          DejaVu Sans, the previews' text
//   <out>/examples/index.json             the examples bundled, each examples/<name>/ (project.json,
//                                         preview.wasm: `helder studio <project> -- --export-web`)
//
// The projects bundled: examples/todo by default, else the directories given.
// --compiler: helder.compiler.web's toolchain (its build.mjs's output, e.g.
// bin/compiler-web) served as <out>/compiler-web (a link), its worker beside
// the page's modules: structural edits built in the browser.
import { spawnSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const argv = process.argv.slice(2);
const ci = argv.indexOf('--compiler');
const compilerDir = ci >= 0 ? path.resolve(argv.splice(ci, 2)[1]) : null;
const [out, ...given] = argv;
if (!out) {
	console.error('node apps/studio/web/build.mjs <out> [project...]');
	process.exit(2);
}
const projects = given.length ? given : [path.join(repo, 'examples/todo')];
const cli = path.join(repo, 'src/helder/cli/run.mjs');
mkdirSync(out, { recursive: true });

function step(args, what) {
	const t0 = Date.now();
	const r = spawnSync(process.execPath, [cli, ...args], { stdio: 'inherit', cwd: repo });
	if (r.status !== 0) throw new Error(`${what}: exit ${r.status}`);
	console.log(`studio-web: ${what} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
}

// the studio, for the web (its page's modules and fonts beside it)
step(['build', 'apps/studio', '--target', 'web', '-o', path.resolve(out, 'studio.wasm')], 'the studio built for the web');
const html = readFileSync(path.join(out, 'studio.html'), 'utf8');
const imports = JSON.parse(html.match(/const IMPORTS = (\[.*?\]);/)[1]).map((u) => u.match(/helder\/([^/]+)\/imports\.mjs/)[1]);

// the studio's fonts (its module embeds them; the page's own text fields use them too)
for (const f of ['HankenGrotesk-Regular.ttf', 'HankenGrotesk-Medium.ttf', 'GeistMono-Regular.ttf']) cpSync(path.join(repo, 'apps/studio/fonts', f), path.join(out, 'fonts', f));

// the preview host's worker, and the browser modules a preview may use
for (const f of ['worker.mjs', 'imports.mjs']) cpSync(path.join(repo, 'src/helder/story/web', f), path.join(out, 'helder/story/web', f));
for (const p of ['async', 'gfx', 'os', 'text', 'ui', 'image', 'canvas', 'jobs', 'asset'])
	for (const f of ['imports.mjs', 'browser.mjs', 'worker.mjs'])
		if (existsSync(path.join(repo, 'src/helder', p, f))) cpSync(path.join(repo, 'src/helder', p, f), path.join(out, 'helder', p, f));

// the compiler's worker (helder.compiler.web) and its toolchain, when given: structural edits built in the browser
if (compilerDir) {
	for (const f of ['worker.mjs', 'client.mjs', 'toolchain.mjs', 'vfs.mjs']) cpSync(path.join(repo, 'src/helder/compiler/web', f), path.join(out, 'helder/compiler/web', f));
	rmSync(path.join(out, 'compiler-web'), { recursive: true, force: true });
	symlinkSync(compilerDir, path.join(out, 'compiler-web'));
}

// the examples
const index = [];
for (const given of projects) {
	const [dir, label] = given.split('=');
	const name = path.basename(path.resolve(dir));
	const dest = path.resolve(out, 'examples', name);
	step(['studio', path.resolve(dir), '--', '--export-web', dest], `${name}'s preview built for the web`);
	const meta = JSON.parse(readFileSync(path.join(dest, 'project.json'), 'utf8'));
	index.push({ name, label: label ?? meta.label, summary: meta.summary ?? undefined, screens: meta.screens });
}
writeFileSync(path.join(out, 'examples/index.json'), JSON.stringify(index, null, '\t') + '\n');

// the page, and a new project's template
cpSync(path.join(here, 'studio.mjs'), path.join(out, 'studio.mjs'));
cpSync(path.join(here, 'new'), path.join(out, 'new'), { recursive: true });
writeFileSync(path.join(out, 'index.html'), readFileSync(path.join(here, 'index.html'), 'utf8').replace('/*IMPORTS*/[]', JSON.stringify(imports)));
console.log(`studio-web: ${out}: the studio, ${index.length} example(s)`);
