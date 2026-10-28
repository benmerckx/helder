// A stand-in for hxmc's runtime-object release, from what
// tests/pack/runtime.mjs fetched: <out>/<tag>/<target>-<object>.gz of
// <dir>'s Android objects, the tag @hxmc/cli's package.json names (the
// pack lane's HELDER_RT_URL=file://<out>: helder.cli.Runtime's first use)
//   node tests/pack/release.mjs <dir> <out>
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const [dir, out] = process.argv.slice(2).map((p) => path.resolve(p));
const tag = JSON.parse(fs.readFileSync(path.join(repo, 'node_modules/@hxmc/cli/package.json'), 'utf8')).hxmc.rt;
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(path.join(out, tag), { recursive: true });
for (const t of ['android-arm64', 'android-x86_64'])
	for (const o of ['rt.o', 'ssl.o', 'uv.o'])
		fs.writeFileSync(path.join(out, tag, `${t}-${o}.gz`), zlib.gzipSync(fs.readFileSync(path.join(dir, t, o))));
console.log(`release: ${out}/${tag}`);
