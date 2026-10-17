// GfxTest's comparison (GfxTest.hx: compare) in JavaScript, for the WebGPU
// and WebGL2 tests in a browser (web.mjs, hxmc/web/tools/browser-test.mjs):
// a pixel matches when no channel differs by more than TOLERANCE, and at
// most MAX_OFF of the pixels may differ by more (the edges); the centre
// must not be the clear colour, a corner must be (probe [x, y, 'contrast']:
// another pixel, for a light scene only far from the corner's colour).
export const TOLERANCE = 2;
export const MAX_OFF = 0.005;

// the golden image's pixels (RGBA8), decoded by the browser as they are
export async function decode(url) {
	const img = await createImageBitmap(await (await fetch(url)).blob(), { colorSpaceConversion: 'none', premultiplyAlpha: 'none' });
	const c = new OffscreenCanvas(img.width, img.height).getContext('2d');
	c.drawImage(img, 0, 0);
	return { width: img.width, height: img.height, data: c.getImageData(0, 0, img.width, img.height).data };
}

// {ok, text}: px and golden are {width, height, data}
export function compare(what, px, golden, probe) {
	const { width, height } = golden;
	if (px.width !== width || px.height !== height) return { ok: false, text: `${what}: FAIL: ${px.width}x${px.height}, not ${width}x${height}` };
	let off = 0, differ = 0, max = 0;
	for (let p = 0; p < width * height; p++) {
		let d = 0;
		for (let k = 0; k < 3; k++) d = Math.max(d, Math.abs(px.data[4 * p + k] - golden.data[4 * p + k]));
		if (d > 0) differ++;
		if (d > TOLERANCE) off++;
		max = Math.max(max, d);
	}
	const [x, y, mode] = probe ?? [width >> 1, height >> 1];
	const c = 4 * (y * width + x);
	const diff = Math.abs(px.data[c] - px.data[0]) + Math.abs(px.data[c + 1] - px.data[1]) + Math.abs(px.data[c + 2] - px.data[2]);
	const lit = mode === 'contrast' ? diff > 150 : diff > 30 && px.data[0] < 40;
	const ok = lit && off <= MAX_OFF * width * height;
	return {
		ok,
		text: `${what}: ${ok ? 'ok' : 'FAIL'}` + (differ === 0 ? ' (exact)' : ` (${differ} pixels differ, ${off} by more than ${TOLERANCE}, at most ${max})`) + (lit ? '' : ' (nothing drawn)'),
	};
}
