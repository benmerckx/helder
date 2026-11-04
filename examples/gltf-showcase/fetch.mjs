// Khronos' glTF sample models, fetched (not vendored: tens of MB) from
// https://github.com/KhronosGroup/glTF-Sample-Assets at a pinned commit into
// examples/gltf-showcase/models/ (git-ignored), each as one self-contained
// .glb (a .gltf's buffers and images packed into its binary chunk, as
// helder.scene's Model.load reads), with its metadata (<name>.json: the
// licences and credits) and the sample viewer's reference render
// (<name>.screenshot.png or .jpg) beside it.
//
//   node examples/gltf-showcase/fetch.mjs [names...]   (default: the showcase's)
//
// Also imported (fetchModel) by examples/sponza/fetch.mjs. Files already
// there are kept.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const COMMIT = '8f492390ddc7a2ae221a1369ef560589cf8c70fb';
const BASE = `https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/${COMMIT}/Models`;
const here = path.dirname(fileURLToPath(import.meta.url));

// name: the .glb variant when the repository has one, else the .gltf (packed here)
export const SHOWCASE = [
	['DamagedHelmet', 'glTF-Binary/DamagedHelmet.glb'],
	['FlightHelmet', 'glTF/FlightHelmet.gltf'],
	['SciFiHelmet', 'glTF/SciFiHelmet.gltf'],
	['MetalRoughSpheres', 'glTF-Binary/MetalRoughSpheres.glb'],
	['TextureTransformTest', 'glTF/TextureTransformTest.gltf'],
	['EmissiveStrengthTest', 'glTF-Binary/EmissiveStrengthTest.glb'],
	['ClearCoatTest', 'glTF-Binary/ClearCoatTest.glb'],
	['TransmissionTest', 'glTF-Binary/TransmissionTest.glb'],
];

async function get(url) {
	for (let attempt = 0; ; attempt++) {
		try {
			const r = await fetch(url);
			if (!r.ok) throw new Error(`${r.status} ${url}`);
			return Buffer.from(await r.arrayBuffer());
		} catch (e) {
			if (attempt >= 3 || /^4\d\d /.test(e.message)) throw e;
			await new Promise((ok) => setTimeout(ok, 1000 * (attempt + 1)));
		}
	}
}

const pad4 = (b, fill) => (b.length % 4 ? Buffer.concat([b, Buffer.alloc(4 - (b.length % 4), fill)]) : b);

// a .gltf with its files as one .glb: every buffer and image one buffer view of buffer 0
export function pack(json, files) {
	const parts = [];
	let offset = 0;
	const add = (bytes) => {
		const view = { buffer: 0, byteOffset: offset, byteLength: bytes.length };
		parts.push(pad4(bytes, 0));
		offset += parts[parts.length - 1].length;
		return view;
	};
	const views = json.bufferViews ?? [];
	// (the buffers' own views moved by where each buffer lands)
	const starts = (json.buffers ?? []).map((b) => {
		const v = add(files(b.uri));
		return v.byteOffset;
	});
	for (const v of views) {
		v.byteOffset = (v.byteOffset ?? 0) + starts[v.buffer];
		v.buffer = 0;
	}
	for (const im of json.images ?? []) {
		if (im.uri === undefined) continue;
		const v = add(files(im.uri));
		views.push(v);
		im.bufferView = views.length - 1;
		im.mimeType = im.mimeType ?? (/\.png$/i.test(im.uri) ? 'image/png' : 'image/jpeg');
		delete im.uri;
	}
	json.bufferViews = views;
	const bin = Buffer.concat(parts);
	json.buffers = [{ byteLength: bin.length }];
	const text = pad4(Buffer.from(JSON.stringify(json)), 0x20);
	const head = Buffer.alloc(12);
	head.writeUInt32LE(0x46546c67, 0);
	head.writeUInt32LE(2, 4);
	head.writeUInt32LE(12 + 8 + text.length + 8 + bin.length, 8);
	const chunk = (type, data) => {
		const h = Buffer.alloc(8);
		h.writeUInt32LE(data.length, 0);
		h.writeUInt32LE(type, 4);
		return Buffer.concat([h, data]);
	};
	return Buffer.concat([head, chunk(0x4e4f534a, text), chunk(0x004e4942, bin)]);
}

// one model into dir: <name>.glb, <name>.md (its README), <name>.screenshot.<ext>
export async function fetchModel(name, variant, dir) {
	fs.mkdirSync(dir, { recursive: true });
	const glb = path.join(dir, `${name}.glb`);
	if (!fs.existsSync(glb)) {
		const url = `${BASE}/${name}/${variant}`;
		let bytes;
		if (variant.endsWith('.glb')) bytes = await get(url);
		else {
			const json = JSON.parse((await get(url)).toString('utf8'));
			const folder = url.slice(0, url.lastIndexOf('/') + 1);
			const uris = [...(json.buffers ?? []).map((b) => b.uri), ...(json.images ?? []).map((i) => i.uri)].filter((u) => u !== undefined);
			const got = new Map();
			await Promise.all(uris.map(async (u) => got.set(u, await get(folder + u.split('/').map(encodeURIComponent).join('/')))));
			bytes = pack(json, (u) => got.get(u));
		}
		fs.writeFileSync(glb, bytes);
	}
	// (its metadata: the licences and credits, legal[])
	const metaFile = path.join(dir, `${name}.json`);
	if (!fs.existsSync(metaFile)) fs.writeFileSync(metaFile, await get(`${BASE}/${name}/metadata.json`));
	const meta = JSON.parse(fs.readFileSync(metaFile, 'utf8'));
	if (!fs.readdirSync(dir).some((f) => f.startsWith(`${name}.screenshot.`))) {
		const s = meta.screenshot ?? 'screenshot/screenshot.jpg';
		fs.writeFileSync(path.join(dir, `${name}.screenshot${s.slice(s.lastIndexOf('.'))}`), await get(`${BASE}/${name}/${s}`));
	}
	return { name, glb, bytes: fs.statSync(glb).size, legal: meta.legal ?? [] };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
	const names = process.argv.slice(2);
	const list = names.length ? SHOWCASE.filter(([n]) => names.includes(n)) : SHOWCASE;
	for (const [name, variant] of list) {
		const m = await fetchModel(name, variant, path.join(here, 'models'));
		console.log(`${name.padEnd(22)} ${(m.bytes / 1048576).toFixed(1).padStart(6)} MB  ${m.legal.map((l) => `${l.spdx ?? l.license} ${l.artist}`).join('; ')}`);
	}
}
