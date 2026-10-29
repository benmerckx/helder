// The dev loop's builds are fresh builds (npm test -- dev; docs/dev.md): a
// compilation server built as `hxmc dev` asks it (-D hxmc.dev, its typed
// modules kept in memory: -D disable-hxb-cache) through edits of a copy of
// one of helder.ui's examples: its main's string, then a module it uses
// whose API changes (a static's type, a function added, a structure's
// field added, then back), then a module of markup it uses (an attribute
// changed and an element added; a component of its own and a Show, code
// the program did not use before; then back); after each, the output must
// be the bytes a one-shot build of the same sources makes
// (HXMC_DEV_HXB_CACHE=1: the server's modules read back from HXB, its
// default; HXMC_DEV_VERIFY_KEEP=<dir>: the outputs that differ copied there).
//   node tests/os/dev/dev-verify.mjs <compiler> [Counter|Todo|...] [native|web]
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, '../../..');
const [compilerArg, example = 'Counter', mode = 'native'] = process.argv.slice(2);
// (its directory: examples/native-form for NativeForm)
const exampleDir = example.replace(/[A-Z]/g, (c, i) => (i ? '-' : '') + c.toLowerCase());
const compiler = path.resolve(compilerArg ?? 'node_modules/.bin/haxe');
const web = mode === 'web';
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'hxmc-dev-verify-'));
fs.mkdirSync(path.join(work, 'app'));
const main = path.join(work, 'app', example + '.hx');
const helper = path.join(work, 'app', 'DevHelper.hx');
const original = fs.readFileSync(path.join(repo, 'examples', exampleDir, example + '.hx'), 'utf8');
const marked = original.replace('static function main() {', 'static function main() {\n\t\tvar edit = "edit 0";\n\t\ttrace(edit + DevHelper.describe() + (DevCard.view("x") != null));');
if (marked === original) throw new Error(example + ': no main');
fs.writeFileSync(main, marked);
const helpers = [
	'class DevHelper {\n\tpublic static var count = 1;\n\n\tpublic static function describe():String\n\t\treturn "h" + count;\n}\n',
	'class DevHelper {\n\tpublic static var count = 2.5;\n\n\tpublic static function describe():String\n\t\treturn "h" + count + extra();\n\n\tstatic function extra()\n\t\treturn "!";\n}\n',
	'typedef T = {a:Int, b:String};\n\nclass DevHelper {\n\tpublic static var t:T = {a: 1, b: "x"};\n\n\tpublic static function describe():String\n\t\treturn t.b + t.a;\n}\n',
	'typedef T = {a:Int, b:String, c:Bool};\n\nclass DevHelper {\n\tpublic static var t:T = {a: 1, b: "x", c: true};\n\n\tpublic static function describe():String\n\t\treturn t.b + t.a + t.c;\n}\n',
];
fs.writeFileSync(helper, helpers[0]);
// a module of markup (the markup macro: components, attributes, bindings), edited
const card = path.join(work, 'app', 'DevCard.hx');
const cardHead = 'import helder.view.*;\nimport helder.view.Flow.*;\nimport helder.view.graph.Graph.*;\n\n';
const cards = [
	cardHead + 'class DevCard implements Markup {\n\tpublic static function view(title:String):View {\n\t\tvar n = signal(0);\n\t\treturn <view padding={8} row-gap={4}>\n\t\t\t<text font-size={14}>{title}</text>\n\t\t\t<view:button role="button" focusable onPress={() -> n(c -> c + 1)}>add</view:button>\n\t\t</view>;\n\t}\n}\n',
	// (an attribute changed, an element added)
	cardHead + 'class DevCard implements Markup {\n\tpublic static function view(title:String):View {\n\t\tvar n = signal(0);\n\t\treturn <view padding={12} row-gap={4}>\n\t\t\t<text font-size={16}>{title}</text>\n\t\t\t<text>{n}</text>\n\t\t\t<view:button role="button" focusable onPress={() -> n(c -> c + 1)}>add</view:button>\n\t\t</view>;\n\t}\n}\n',
	// (a component of its own, with a prop, used twice; a Show)
	cardHead + 'class DevCard implements Markup {\n\tpublic static function view(title:String):View {\n\t\tvar n = signal(0);\n\t\treturn <view padding={12} row-gap={4}>\n\t\t\t<Row label={title}/>\n\t\t\t<Row label="two"/>\n\t\t\t<Show when={n() > 0}><text>{n}</text></Show>\n\t\t\t<view:button role="button" focusable border-width={1} onPress={() -> n(c -> c + 1)}>add</view:button>\n\t\t</view>;\n\t}\n\n\tstatic function Row(props:{label:String}):View\n\t\treturn <view direction="row" column-gap={4}><text>{props.label}</text><text padding="0 6" radius={6} background="#e4e4e7">new</text></view>;\n}\n',
];
fs.writeFileSync(card, cards[0]);
const out = web ? 'out/app.wasm' : process.platform === 'win32' ? 'out/app.exe' : 'out/app';
const ref = 'ref/' + path.basename(out);
const args = (o) => ['-cp', path.join(repo, 'src'),
	'-cp', path.join(repo, 'examples', exampleDir), '-cp', 'app', '-main', example,
	...(web ? ['-D', 'hxmc.target=wasm32-wasi'] : process.platform === 'linux' ? ['-D', 'hxmc.libc=glibc'] : []),
	'--custom-target', 'hxmc=' + o, '-D', 'hxmc.dev', ...(fs.existsSync(path.join(path.dirname(compiler), 'std')) ? ['-cp', path.join(path.dirname(compiler), 'std')] : [])];
const env = { ...process.env, HXMC_MODULE_CACHE: '0' };

const port = await new Promise((r) => {
	const s = net.createServer().listen(0, '127.0.0.1', () => {
		const p = s.address().port;
		s.close(() => r(p));
	});
});
const server = spawn(compiler, ['--wait', String(port)], { env, stdio: ['ignore', 'pipe', 'pipe'] });
let serverOutput = '';
server.stdout.on('data', (d) => (serverOutput += d));
server.stderr.on('data', (d) => (serverOutput += d));
const request = (words) => new Promise((resolve) => {
	const go = (n) => {
		const s = net.connect(port, '127.0.0.1');
		const chunks = [];
		s.on('error', () => (n > 0 ? setTimeout(() => go(n - 1), 50) : resolve('\x02 no compilation server')));
		s.on('connect', () => s.write(['--cwd', work, ...words].map((a) => a + '\n').join('') + '\0'));
		s.on('data', (d) => chunks.push(d));
		s.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
	};
	go(100);
});

let failures = 0;
async function step(what) {
	for (const file of [main, helper, card])
		await request(['--display', JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'server/invalidate', params: { file } })]);
	const answer = await request([...args(out), ...(process.env.HXMC_DEV_HXB_CACHE === '1' ? [] : ['-D', 'disable-hxb-cache'])]);
	const fresh = spawnSync(compiler, args(ref), { cwd: work, env, encoding: 'utf8' });
	const same = !answer.includes('\x02') && fresh.status === 0 && Buffer.compare(fs.readFileSync(path.join(work, out)), fs.readFileSync(path.join(work, ref))) === 0;
	console.log((same ? 'ok   ' : 'FAIL ') + `${example} ${mode}: ${what}`);
	if (!same) {
		failures++;
		console.log(answer.includes('\x02') ? answer + serverOutput.slice(-2000) : fresh.status !== 0 ? fresh.stdout + fresh.stderr : 'the outputs differ');
		if (process.env.HXMC_DEV_VERIFY_KEEP) for (const f of [out, ref]) fs.copyFileSync(path.join(work, f), path.join(process.env.HXMC_DEV_VERIFY_KEEP, failures + '-' + f.replace('/', '-')));
	}
}
try {
	await step('the first build');
	await step('no change');
	for (let i = 1; i <= 2; i++) {
		fs.writeFileSync(main, fs.readFileSync(main, 'utf8').replace(`"edit ${i - 1}"`, `"edit ${i}"`));
		await step(`main edited (${i})`);
	}
	const changes = ['a static\'s type changed, a function added', 'a structure', 'a field added to the structure'];
	for (let h = 1; h < helpers.length; h++) {
		fs.writeFileSync(helper, helpers[h]);
		await step('the module it uses: ' + changes[h - 1]);
	}
	fs.writeFileSync(helper, helpers[0]);
	await step('the module it uses: as at first');
	const cardChanges = ['an attribute changed, an element added', 'a component of its own with a prop, a Show'];
	for (let c = 1; c < cards.length; c++) {
		fs.writeFileSync(card, cards[c]);
		await step('a module of markup: ' + cardChanges[c - 1]);
	}
	fs.writeFileSync(card, cards[0]);
	await step('a module of markup: as at first');
} finally {
	server.kill();
}
fs.rmSync(work, { recursive: true, force: true });
console.log(failures === 0 ? 'dev-verify: ok' : `dev-verify: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
