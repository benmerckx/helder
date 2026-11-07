// helder.compiler.web's toolchain in node, no browser (the compiler-web
// lane's first half): build.mjs's modules started through toolchain.mjs as
// the worker starts them, then todo and ts-todo checked and built to wasm32,
// built again warm, a type error found by the check, and a check writing
// nothing (--no-output in the server).
//   node tests/compiler-web/node.mjs [dir: build.mjs's output, bin/compiler-web]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../..');
const dir = path.resolve(process.argv[2] ?? path.join(repo, 'bin/compiler-web'));
const transport = await import(new URL('typescript/dist/wasm/index.js', 'file://' + dir + '/').href);
const { Toolchain } = await import('../../src/helder/compiler/web/toolchain.mjs');

let failed = 0;
const check = (what, ok, detail) => {
	if (!ok) failed++;
	console.log(`node.mjs: ${ok ? 'ok' : 'FAIL'}: ${what}${!ok && detail !== undefined ? ': ' + String(detail).slice(0, 3000) : ''}`);
};

const t0 = performance.now();
const t = await Toolchain.start({
	compiler: fs.readFileSync(path.join(dir, 'helder-compiler.wasm')),
	typescript: fs.readFileSync(path.join(dir, 'tsc.wasm')),
	bundle: fs.readFileSync(path.join(dir, 'sources.bundle')),
	transport,
	persist: false,
	log: (l) => console.log('node.mjs: [compiler] ' + l),
});
console.log(`node.mjs: started in ${Math.round(performance.now() - t0)} ms ${JSON.stringify(Object.fromEntries(Object.entries(t.ms).map(([k, v]) => [k, Math.round(v)])))}, ${t.version}`);

const copy = (ex) => {
	for (const f of fs.readdirSync(path.join(repo, 'examples', ex))) {
		const p = path.join(repo, 'examples', ex, f);
		if (fs.statSync(p).isFile()) t.write(`/work/${ex}/${f}`, fs.readFileSync(p));
	}
};
const isWasm = (b) => b && b[0] === 0 && b[1] === 0x61 && b[2] === 0x73 && b[3] === 0x6d;

for (const ex of ['todo', 'ts-todo']) {
	copy(ex);
	const c = t.check({ entry: '/work/' + ex });
	check(`${ex}: checked (${c.ms} ms)`, c.ok, JSON.stringify(c.diagnostics));
	check(`${ex}: the check wrote nothing`, t.vfs.list('/out').length === 0, t.vfs.list('/out').join(', '));
	const b = t.build({ entry: '/work/' + ex });
	check(`${ex}: built (${b.ms} ms, tsgo ${b.tsgoMs} ms, ${b.wasm?.length} bytes)`, b.ok && isWasm(b.wasm), b.messages);
	const again = t.build({ entry: '/work/' + ex });
	check(`${ex}: built again, warm (${again.ms} ms)`, again.ok && isWasm(again.wasm), again.messages);
	for (const p of t.vfs.list('/out')) t.vfs.remove(p);
}

// a type error in ts-todo's TypeScript: the check's diagnostic, at its file
{
	const file = '/work/ts-todo/todos.ts';
	const text = t.vfs.readText(file);
	t.write(file, text + '\nexport const wrong: number = "text";\n');
	const c = t.check({ entry: '/work/ts-todo' });
	check(`ts-todo: the type error found (${c.ms} ms)`, !c.ok && c.diagnostics.some((d) => /todos\.ts$/.test(d.file ?? '')), JSON.stringify(c.diagnostics));
	t.write(file, text);
	const ok = t.check({ entry: '/work/ts-todo' });
	check('ts-todo: fixed, checked again', ok.ok, JSON.stringify(ok.diagnostics));
}
console.log('node.mjs: ' + JSON.stringify(t.stats()));
if (failed) {
	console.log(`node.mjs: ${failed} failed`);
	process.exit(1);
}
