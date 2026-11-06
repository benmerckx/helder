// WPT's canvas harness's functions as the converted tests (cases.ts) call
// them: a failure throws (wpt.ts and chrome.mjs --wpt catch it per test)
import { Canvas } from "helder/canvas";

function fail(message: string): never {
	throw new Error(message);
}

export function _assert(cond: boolean, text?: string): void {
	if (!cond) fail("assert failed: " + (text ?? ""));
}

export function _assertSame(a: any, b: any, ta?: string, tb?: string): void {
	if (!Object.is(a, b) && !(a === b)) fail(ta + " === " + tb + ": got " + String(a) + ", expected " + String(b));
}

export function _assertDifferent(a: any, b: any, ta?: string, tb?: string): void {
	if (a === b) fail(ta + " !== " + tb + ": both " + String(a));
}

export function assert_equals(a: any, b: any, text?: string): void {
	if (!Object.is(a, b) && !(a === b)) fail("assert_equals: got " + String(a) + ", expected " + String(b) + " " + (text ?? ""));
}

export function assert_not_equals(a: any, b: any, text?: string): void {
	if (a === b) fail("assert_not_equals: " + String(a) + " " + (text ?? ""));
}

export function assert_true(v: any, text?: string): void {
	if (v !== true) fail("assert_true " + (text ?? ""));
}

export function assert_false(v: any, text?: string): void {
	if (v !== false) fail("assert_false " + (text ?? ""));
}

function pixel(canvas: Canvas, x: number, y: number): Uint8ClampedArray {
	return canvas.getContext("2d")!.getImageData(x, y, 1, 1).data;
}

export function _assertPixel(canvas: Canvas, x: number, y: number, r: number, g: number, b: number, a: number): void {
	const p = pixel(canvas, x, y);
	if (p[0] !== r || p[1] !== g || p[2] !== b || p[3] !== a) fail(`pixel ${x},${y}: got ${p[0]},${p[1]},${p[2]},${p[3]}, expected ${r},${g},${b},${a}`);
}

export function _assertPixelApprox(canvas: Canvas, x: number, y: number, r: number, g: number, b: number, a: number, tolerance: number): void {
	const p = pixel(canvas, x, y);
	if (Math.abs(p[0] - r) > tolerance || Math.abs(p[1] - g) > tolerance || Math.abs(p[2] - b) > tolerance || Math.abs(p[3] - a) > tolerance)
		fail(`pixel ${x},${y}: got ${p[0]},${p[1]},${p[2]},${p[3]}, expected ${r},${g},${b},${a} +/- ${tolerance}`);
}

// (the error's kind is not checked: helder's errors cross into TypeScript as errors, their class aside)
export function assert_throws_js(kind: any, f: () => void, text?: string): void {
	let threw = false;
	try { f(); } catch (e) { threw = true; }
	if (!threw) fail("expected a throw " + (text ?? ""));
}

export function assert_throws_dom(kind: string, f: () => void, text?: string): void {
	let threw = false;
	try { f(); } catch (e) { threw = true; }
	if (!threw) fail("expected " + kind + " " + (text ?? ""));
}
