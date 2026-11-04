// Crytek's Sponza (glTF-Sample-Assets' glTF version: Crytek's CRYENGINE
// Limited License Agreement, not in the repository) fetched into
// examples/sponza/models/Sponza.glb (examples/gltf-showcase/fetch.mjs's
// fetchModel: its buffers and 69 images packed into one .glb), then packed
// for the GPUs by helder.scene's asset step (Pack: --textures bc and astc):
// models/Sponza.bc.hxm3d (BC1/BC3, desktops and the web where it has
// texture-compression-bc) and models/Sponza.astc.hxm3d (ASTC 4x4, phones),
// and models/Sponza.hxm3d with the images as the file has them (PNG/JPEG:
// the rest).
//
//   node examples/sponza/fetch.mjs
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { fetchModel } from '../gltf-showcase/fetch.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const models = path.join(here, 'models');
const m = await fetchModel('Sponza', 'glTF/Sponza.gltf', models);
console.log(`Sponza.glb ${(m.bytes / 1048576).toFixed(1)} MB  ${m.legal.map((l) => l.license + ' ' + l.artist).join('; ')}`);
// (Pack built natively first, bin/pack/Pack: the 69 images decoded and compressed in seconds, not Eval's minutes)
const haxe = process.env.HAXE ?? path.join(root, 'node_modules/.bin/haxe');
const pack = path.join(root, 'bin/pack/Pack');
const target = process.platform === 'darwin' ? `macos-${process.arch === 'arm64' ? 'arm64' : 'x86_64'}` : `linux-${process.arch === 'arm64' ? 'arm64' : 'x86_64'}`;
const sources = ['src/helder/scene/gltf/Pack.hx', 'src/helder/image/BlockCompress.hx'].map((f) => fs.statSync(path.join(root, f)).mtimeMs);
if (!fs.existsSync(pack) || fs.statSync(pack).mtimeMs < Math.max(...sources)) {
	const r = spawnSync(haxe, ['-cp', 'src', '-main', 'helder.scene.gltf.Pack', '-D', `hxmc.target=${target}`, ...(target.startsWith('linux') ? ['-D', 'hxmc.libc=glibc'] : []),
		'--custom-target', `hxmc=${pack}`], { cwd: root, stdio: 'inherit' });
	if (r.status !== 0) process.exit(r.status ?? 1);
}
for (const [suffix, args] of [['', []], ['.bc', ['--textures', 'bc']], ['.astc', ['--textures', 'astc']]]) {
	const out = path.join(models, `Sponza${suffix}.hxm3d`);
	if (fs.existsSync(out) && fs.statSync(out).mtimeMs > fs.statSync(pack).mtimeMs) continue;
	const r = spawnSync(pack, [m.glb, out, ...args], { cwd: root, stdio: 'inherit' });
	if (r.status !== 0) process.exit(r.status ?? 1);
}
