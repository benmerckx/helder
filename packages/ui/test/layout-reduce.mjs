// A difference layout-fuzz.mjs found, reduced: the case's tree with one node
// or one style property dropped at a time, each variant drawn by Chromium
// (layout-ref.mjs) and laid out by LayoutFuzz, the first that still differs
// kept, until none does (make ui-layout-reduce CASE='fuzz 41-87'). It prints
// the reduced tree and Chromium's boxes: a case for layout-cases.mjs once
// what differs is understood (a variant may differ for another reason than
// the case did: check it against the original).
//   node packages/ui/test/layout-reduce.mjs <cases.json> <case name> <work dir>
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { boxes } from './layout-ref.mjs';

const [file, name, dir] = process.argv.slice(2);
const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../..');
let cur = JSON.parse(fs.readFileSync(file)).find((c) => c.name === name);
if (!cur) throw new Error(`no case ${name} in ${file}`);
fs.mkdirSync(dir, { recursive: true });

// (each node with its parent and place, in the tree's order)
function nodes(tree) {
	const out = [];
	(function walk(n, parent, i) {
		out.push([n, parent, i]);
		(n.children ?? []).forEach((ch, j) => walk(ch, n, j));
	})(tree, null, -1);
	return out;
}

// (the case with one node, not the root, or one style property dropped)
function variants(c) {
	const edits = [];
	nodes(c.tree).forEach(([n, parent], k) => {
		if (parent) edits.push({ k, drop: true });
		for (const p of Object.keys(n.style ?? {})) edits.push({ k, prop: p });
	});
	return edits.map((e) => {
		const t = structuredClone(c);
		const [n, parent, i] = nodes(t.tree)[e.k];
		if (e.drop) parent.children.splice(i, 1);
		else delete n.style[e.prop];
		t.name = JSON.stringify(e);
		return t;
	});
}

// (the cases LayoutFuzz lays out differently from Chromium's boxes; shown: its differences printed)
function differing(cases, expected, shown = false) {
	fs.writeFileSync(path.join(dir, 'layout-cases.json'), JSON.stringify(cases));
	fs.writeFileSync(path.join(dir, 'layout-expected.json'), JSON.stringify(expected));
	let out;
	try {
		out = execFileSync('bash', ['-c', `ulimit -s unlimited; bin/hxmc/hxmc -cp packages/text/src -cp packages/ui/src -cp packages/ui/test --run LayoutFuzz ${dir}`],
			{ cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
	} catch (e) {
		out = e.stdout;
	}
	const bad = new Set();
	for (const l of out.split('\n')) {
		const m = /FAIL: layout: (.*?): box/.exec(l);
		if (m) bad.add(m[1]);
		if (m && shown) console.log(l);
	}
	return bad;
}

for (;;) {
	const vs = variants(cur);
	const { expected } = await boxes(vs);
	const bad = differing(vs, expected);
	const kept = vs.find((v) => bad.has(v.name));
	if (!kept) break;
	console.log('dropped', kept.name);
	cur = kept;
}
cur.name = name + ' reduced';
const { expected } = await boxes([cur]);
console.log(JSON.stringify(cur.tree));
console.log('Chromium', JSON.stringify(expected[cur.name]));
differing([cur], expected, true);
