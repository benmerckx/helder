// Writes tests/image/webp/: WebP files of the kinds WebpDecoder reads
// (lossless: photographic, few colours for colour indexing at 1, 2, 4 and 8
// bits, with alpha, each encoder method; lossy: qualities, odd sizes, with
// alpha raw or compressed and each alpha filter; an animation's first
// frame; an animation's frames), each with the RGBA8 pixels libwebp decodes from it (<case>.rgba,
// through ImageMagick's decoder: libwebp's defaults, as Chromium has them;
// cases.json: names and sizes), which WebpDecoder must give exactly.
// ImageTest decodes them (bun run test image).
//   node tests/image/webp-cases.mjs   (needs ImageMagick with WebP)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, 'webp');
const tmp = fs.mkdtempSync(path.join(process.env.TMPDIR ?? '/tmp', 'webp-cases-'));
fs.mkdirSync(out, { recursive: true });

// sources: RGBA8
function photo(w, h, alpha) {
	const px = Buffer.alloc(w * h * 4);
	for (let y = 0; y < h; y++)
		for (let x = 0; x < w; x++) {
			const o = 4 * (y * w + x);
			let r = (x * 255) / Math.max(1, w - 1), g = (y * 255) / Math.max(1, h - 1), b = 128 + 127 * Math.sin((x + y) / 3);
			if ((x >> 2) % 3 === 0 && y > h / 2) [r, g, b] = [230, 20, 40];
			if (x > w * 0.7 && y < h * 0.3) [r, g, b] = [10, 200, 90];
			px[o] = r;
			px[o + 1] = g;
			px[o + 2] = b;
			px[o + 3] = alpha ? Math.max(0, Math.min(255, Math.round(255 * (1 - Math.hypot(x - w / 2, y - h / 2) / (Math.min(w, h) * 0.6))))) : 255;
		}
	return px;
}
function palette(w, h, n) {
	const colors = Array.from({ length: n }, (_, i) => [(i * 97) & 255, (i * 53 + 40) & 255, (i * 191 + 7) & 255, i % 5 == 4 ? 128 : 255]);
	const px = Buffer.alloc(w * h * 4);
	for (let y = 0; y < h; y++)
		for (let x = 0; x < w; x++) {
			const c = colors[((x >> 1) + (y >> 2) * 3) % n];
			px.set(c, 4 * (y * w + x));
		}
	return px;
}

const cases = [];
function add(name, src, w, h, args) {
	const raw = path.join(tmp, name + '.rgba'), file = path.join(out, name + '.webp');
	fs.writeFileSync(raw, src);
	execFileSync('convert', ['-size', `${w}x${h}`, '-depth', '8', 'rgba:' + raw, ...args, file]);
	const decoded = execFileSync('convert', [file, '-depth', '8', 'rgba:-'], { maxBuffer: 1 << 28 });
	if (decoded.length != w * h * 4) throw new Error(name + ': decoded ' + decoded.length);
	fs.writeFileSync(path.join(out, name + '.rgba'), decoded);
	cases.push({ name, width: w, height: h });
}
const lossless = ['-define', 'webp:lossless=true', '-define', 'webp:exact=true'];
add('lossless-photo', photo(64, 48, false), 64, 48, [...lossless]);
for (const m of [0, 3, 6]) add(`lossless-method${m}`, photo(40, 30, false), 40, 30, [...lossless, '-define', `webp:method=${m}`]);
add('lossless-alpha', photo(50, 40, true), 50, 40, [...lossless]);
for (const n of [2, 4, 16, 200]) add(`lossless-palette${n}`, palette(37, 23, n), 37, 23, [...lossless]);
add('lossless-tiny', photo(1, 1, false), 1, 1, [...lossless]);
add('lossless-odd', photo(13, 7, true), 13, 7, [...lossless]);
add('lossless-large', photo(160, 100, false), 160, 100, [...lossless, '-define', 'webp:method=4']);
for (const q of [30, 90]) add(`lossy-q${q}`, photo(64, 48, false), 64, 48, ['-quality', String(q)]);
add('lossy-odd', photo(17, 9, false), 17, 9, ['-quality', '75']);
add('lossy-large', photo(160, 100, false), 160, 100, ['-quality', '80']);
add('lossy-alpha', photo(50, 40, true), 50, 40, ['-quality', '80']);
add('lossy-alpha-raw', photo(31, 22, true), 31, 22, ['-quality', '60', '-define', 'webp:alpha-compression=0']);
for (const f of ['none', 'fast', 'best']) add(`lossy-alpha-${f}`, photo(33, 21, true), 33, 21, ['-quality', '70', '-define', `webp:alpha-filter=${f}`]);
add('lossy-sharp', photo(48, 32, false), 48, 32, ['-quality', '85', '-define', 'webp:sns-strength=0', '-define', 'webp:filter-strength=60', '-define', 'webp:filter-sharpness=3']);
add('lossy-simple-filter', photo(40, 24, false), 40, 24, ['-quality', '70', '-define', 'webp:filter-type=0']);
add('lossy-segments', photo(64, 64, false), 64, 64, ['-quality', '50', '-define', 'webp:segments=4', '-define', 'webp:partitions=3']);

// an animation (lossless frames; alpha 0 or 255, where every compositor
// agrees): an opaque frame, one transparent but for a square (blended over
// it), another opaque; each frame as ImageMagick composes them (-coalesce;
// transparent pixels zeroed, as libwebp leaves them)
// into <case>.frames.rgba, their durations and the repetitions
{
	const raw = path.join(tmp, 'anim.rgba'), f = [1, 2, 3].map((i) => path.join(tmp, `f${i}.png`));
	fs.writeFileSync(raw, photo(24, 16, false));
	execFileSync('convert', ['-size', '24x16', '-depth', '8', 'rgba:' + raw, f[0]]);
	execFileSync('convert', ['-size', '24x16', 'xc:none', '-fill', '#e01030', '-draw', 'rectangle 6,4 13,10', f[1]]);
	execFileSync('convert', ['-size', '24x16', 'xc:#3366ff', f[2]]);
	const file = path.join(out, 'animated.webp');
	execFileSync('convert', ['-delay', '20', f[0], '-delay', '5', f[1], '-delay', '30', f[2], '-define', 'webp:lossless=true', '-loop', '3', file]);
	fs.writeFileSync(path.join(out, 'animated.rgba'), execFileSync('convert', [file + '[0]', '-depth', '8', 'rgba:-']));
	// (transparent pixels as libwebp and Chromium leave a disposed rectangle: 0, 0, 0, 0; ImageMagick keeps their colours)
	const frames = execFileSync('convert', [file, '-coalesce', '-depth', '8', 'rgba:-']);
	for (let i = 0; i < frames.length; i += 4) if (frames[i + 3] == 0) frames.fill(0, i, i + 4);
	fs.writeFileSync(path.join(out, 'animated.frames.rgba'), frames);
	cases.push({ name: 'animated', width: 24, height: 16, durations: [0.2, 0.05, 0.3], repetition: 2 });
}

fs.writeFileSync(path.join(out, 'cases.json'), JSON.stringify(cases, null, '\t') + '\n');
fs.rmSync(tmp, { recursive: true });
console.log(`webp-cases.mjs: ${cases.length} cases in ${out}`);
