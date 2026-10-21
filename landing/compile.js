// One build by the compiler (haxe.wasm) over a MemFS (wasi.js): the worker's
// (compiler.js) and the checks' (test.mjs). The file system holds the std
// (/std, /hxmc-std), the packages' sources (/src) and the runtime objects
// of the targets fetched so far (/rt); builds go to /out, and stay there:
// a later build of the same program for the same target reuses its objects.
import { wasi } from './wasi.js';

// the compiler's arguments for an example (manifest.json) and a target
// (wasm32-wasi: the page's; legacy exception handling, as the site's)
export function args(example, target, out) {
	return [
		'haxe',
		...example.args,
		'-cp', '/lib/hxmc-std',
		'--custom-target', `hxmc=${out}`,
		'-D', `hxmc.target=${target}`,
		...(target === 'wasm32-wasi' ? ['-D', 'hxmc.wasm-eh=legacy'] : []),
		...(target.startsWith('linux') ? ['-D', 'hxmc.libc=glibc'] : []),
	];
}

// builds; {ok, bytes, file, assets: [[path, bytes]], log, ms}. onOpen(path, writing): the files the
// compiler opens as it goes
export async function compile({ module, fs, example, target, onOpen = () => {} }) {
	const out = `/work/out/${example.id}/${target}/${example.main}`;
	const file = target.startsWith('windows') ? out + '.exe' : out;
	fs.mkdirs('/work');
	fs.remove(file);
	const log = [];
	const w = wasi({
		args: args(example, target, out),
		env: { HAXE_STD_PATH: '/lib/std', HXMC_STD: '/lib/hxmc-std', HXMC_RT_DIR: '/lib/rt', PWD: '/work', HOME: '/home' },
		fs,
		stdout: (l) => log.push(l),
		stderr: (l) => log.push(l),
		onOpen,
	});
	const t0 = performance.now();
	const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: w.imports });
	let code;
	try {
		code = w.start(instance);
	} catch (e) {
		log.push(String(e?.stack ?? e));
		code = -1;
	}
	const ms = performance.now() - t0;
	const bytes = fs.read(file);
	// the files the program loads from beside it (Model.of's): <out>.assets.json
	const dir = out.slice(0, out.lastIndexOf('/'));
	const list = fs.read(out + '.assets.json');
	const assets = list ? JSON.parse(new TextDecoder().decode(list)).map((rel) => [rel, fs.read(`${dir}/${rel}`)?.slice()]) : [];
	return { ok: code === 0 && bytes !== null, bytes: bytes && bytes.slice(), file: file.split('/').pop(), assets, log, ms };
}
