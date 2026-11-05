// "helder/canvas" in Chromium (chrome.mjs bundles scenes.ts with it): the
// browser's own canvas behind skia-canvas's shapes. Images and fonts are
// loaded by the page before the scenes run (loadImage gives them at once,
// as helder's does).
export class Canvas {
	constructor(width = 300, height = 150) {
		const c = document.createElement("canvas");
		c.width = width;
		c.height = height;
		return c;
	}
}
export const Path2D = globalThis.Path2D;
export const DOMMatrix = globalThis.DOMMatrix;
export const CanvasRenderingContext2D = globalThis.CanvasRenderingContext2D;
export class ImageData extends globalThis.ImageData {
	constructor(a, b, c) {
		if (Array.isArray(a)) super(new Uint8ClampedArray(a), b, c);
		else super(a, b);
	}
}
export const FontLibrary = { use: (family, paths) => [family] };
export function loadImage(src) {
	const img = globalThis.__canvasImages?.[src.split("/").pop()];
	if (!img) throw new Error("not loaded: " + src);
	return img;
}
export const CanvasGradient = globalThis.CanvasGradient;
export const CanvasPattern = globalThis.CanvasPattern;
