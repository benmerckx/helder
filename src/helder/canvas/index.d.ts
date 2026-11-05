// helder.canvas for TypeScript programs (helder.typescript): the DOM's
// Canvas 2D (helder.canvas.dom), as skia-canvas and @napi-rs/canvas have
// it, so code written for the browser's canvas runs natively. Each class
// is the Haxe class `__haxe` names. useGpu() draws every canvas made after
// it on the GPU (helder.canvas.gpu), useWeb() by the browser's own canvas
// (helder.canvas.web, in a web build), the CPU back end otherwise.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Canvas: "helder.canvas.dom.Canvas", CanvasRenderingContext2D: "helder.canvas.dom.CanvasRenderingContext2D", Path2D: "helder.canvas.dom.Path2D", CanvasGradient: "helder.canvas.dom.CanvasGradient", CanvasPattern: "helder.canvas.dom.CanvasPattern", ImageData: "helder.canvas.dom.ImageData", DOMMatrix: "helder.canvas.dom.DOMMatrix", Image: "helder.canvas.dom.Image", TextMetrics: "helder.canvas.dom.TextMetrics", FontLibrary: "helder.canvas.dom.FontLibrary", Gpu: "helder.canvas.gpu.Gpu", Web: "helder.canvas.web.Web", __module: "helder.canvas.TypeScript"};

// A canvas as skia-canvas's and @napi-rs/canvas's (and the browser's
// OffscreenCanvas): `new Canvas(width, height)`, its 2D context
// (getContext("2d"): CanvasRenderingContext2D, drawn by helder.canvas on
// the CPU), its pixels as a file (toBuffer("png"), saveAs("out.jpg"),
// toDataURL()). Code written for the browser's Canvas 2D runs on it.
// Setting width or height clears it and resets its context, as the
// browser's.
export declare class Canvas {
	constructor(width?: number, height?: number);
	width: number;
	height: number;
	// a page after the others (a PDF's next; this canvas's pixels the new page's), its context
	newPage(width?: number, height?: number): CanvasRenderingContext2D;
	readonly pageCount: number;
	// "2d" (any other: null, as the browser's for a kind it lacks)
	getContext(kind: string, options?: any): CanvasRenderingContext2D | null;
	// the pixels as a file: "png", "jpg" or "jpeg" (also their MIME
	// types; quality 0 to 1 for JPEG, 0.92), or the drawing as vectors:
	// "pdf" (every page), "svg" (the last)
	toBuffer(format?: string, quality?: number): unknown;
	// the pixels written to a file, its format by its extension unless given
	saveAs(path: string, format?: string, quality?: number): void;
	toDataURL(type?: string, quality?: number): string;
}

// The browser's CanvasRenderingContext2D on helder.canvas: the standard
// API (paths, fills and strokes, transforms, clips, gradients, patterns,
// images, compositing, text, pixels), its string-valued state parsed as
// the browser parses it (an invalid value ignored). The default path is
// kept in the user units of the transform now: a change of transform moves
// it, so it stays where it was drawn, as the browser's.
export declare class CanvasRenderingContext2D {
	constructor(canvas: Canvas);
	readonly canvas: Canvas;
	save(): void;
	restore(): void;
	// everything back to its initial state, the pixels transparent
	reset(): void;
	isContextLost(): boolean;
	getContextAttributes(): any;
	translate(x: number, y: number): void;
	scale(x: number, y: number): void;
	rotate(angle: number): void;
	transform(a: number, b: number, c: number, d: number, e: number, f: number): void;
	// (a, b, c, d, e, f), a DOMMatrix or {a...f}, or nothing (the identity)
	setTransform(a?: any, b?: number, c?: number, d?: number, e?: number, f?: number): void;
	resetTransform(): void;
	getTransform(): DOMMatrix;
	fillStyle: any;
	strokeStyle: any;
	globalAlpha: number;
	globalCompositeOperation: string;
	imageSmoothingEnabled: boolean;
	imageSmoothingQuality: string;
	// shadows and filter: the draw into a layer composited through them (Filter's DropShadow, Blur, colour matrices)
	shadowBlur: number;
	shadowColor: string;
	shadowOffsetX: number;
	shadowOffsetY: number;
	filter: string;
	lineWidth: number;
	lineCap: string;
	lineJoin: string;
	miterLimit: number;
	lineDashOffset: number;
	setLineDash(segments: number[]): void;
	getLineDash(): number[];
	font: string;
	textAlign: string;
	textBaseline: string;
	direction: string;
	letterSpacing: string;
	wordSpacing: string;
	fontKerning: string;
	fontStretch: string;
	fontVariantCaps: string;
	textRendering: string;
	createLinearGradient(x0: number, y0: number, x1: number, y1: number): CanvasGradient;
	createRadialGradient(x0: number, y0: number, r0: number, x1: number, y1: number, r1: number): CanvasGradient;
	createConicGradient(startAngle: number, x: number, y: number): CanvasGradient;
	// image: an Image or a Canvas (its pixels now); repetition: "repeat" (null, ""), "repeat-x", "repeat-y", "no-repeat"
	createPattern(image: any, repetition?: string): CanvasPattern | null;
	beginPath(): void;
	closePath(): void;
	moveTo(x: number, y: number): void;
	lineTo(x: number, y: number): void;
	quadraticCurveTo(cpx: number, cpy: number, x: number, y: number): void;
	bezierCurveTo(cp1x: number, cp1y: number, cp2x: number, cp2y: number, x: number, y: number): void;
	arc(x: number, y: number, radius: number, startAngle: number, endAngle: number, anticlockwise?: boolean): void;
	arcTo(x1: number, y1: number, x2: number, y2: number, radius: number): void;
	ellipse(x: number, y: number, radiusX: number, radiusY: number, rotation: number, startAngle: number, endAngle: number, anticlockwise?: boolean): void;
	rect(x: number, y: number, w: number, h: number): void;
	roundRect(x: number, y: number, w: number, h: number, radii?: any): void;
	fill(a?: any, b?: any): void;
	stroke(a?: Path2D): void;
	clip(a?: any, b?: any): void;
	fillRect(x: number, y: number, w: number, h: number): void;
	strokeRect(x: number, y: number, w: number, h: number): void;
	clearRect(x: number, y: number, w: number, h: number): void;
	// whether (x, y), in the canvas's pixels, is inside the path: (x, y, rule?) or (path, x, y, rule?)
	isPointInPath(a: any, b: any, c?: any, d?: any): boolean;
	// whether (x, y) is inside the path's stroke with the line styles now: (x, y) or (path, x, y)
	isPointInStroke(a: any, b: any, c?: any): boolean;
	// (image, dx, dy), (image, dx, dy, dw, dh), (image, sx, sy, sw, sh, dx, dy, dw, dh)
	drawImage(image: any, a: number, b: number, c?: number, d?: number, e?: number, f?: number, g?: number, h?: number): void;
	createImageData(a: any, h?: number): ImageData;
	getImageData(sx: number, sy: number, sw: number, sh: number): ImageData;
	putImageData(data: ImageData, dx: number, dy: number, dirtyX?: number, dirtyY?: number, dirtyW?: number, dirtyH?: number): void;
	fillText(text: string, x: number, y: number, maxWidth?: number): void;
	strokeText(text: string, x: number, y: number, maxWidth?: number): void;
	measureText(text: string): TextMetrics;
	// the text's glyphs as a path, laid out as fillText would draw it at (x, y) (skia-canvas's outlineText)
	outlineText(text: string, x?: number, y?: number): Path2D;
}

// The browser's Path2D: a path of its own, filled, stroked or clipped by
// a context with its transform at that time. Made empty, from another
// Path2D, or from SVG path data ("M 10 10 h 80 v 80 Z").
export declare class Path2D {
	constructor(init?: any);
	// another path's subpaths, through a transform when given
	addPath(other: Path2D, transform?: DOMMatrix): void;
	// skia-canvas's extras: boolean operations (each a new path), simplify,
	// and effects (rounded corners, trimmed by length, jittered), a move and a transform
	union(other: Path2D): Path2D;
	intersect(other: Path2D): Path2D;
	difference(other: Path2D): Path2D;
	xor(other: Path2D): Path2D;
	complement(other: Path2D): Path2D;
	simplify(rule?: string): Path2D;
	round(radius: number): Path2D;
	trim(start: number, end: number, inverted?: boolean): Path2D;
	jitter(segmentLength: number, amount: number, seed?: number): Path2D;
	dash(segments: number[], offset?: number): Path2D;
	offset(dx: number, dy: number): Path2D;
	transform(m: DOMMatrix): Path2D;
	closePath(): void;
	moveTo(x: number, y: number): void;
	lineTo(x: number, y: number): void;
	quadraticCurveTo(cpx: number, cpy: number, x: number, y: number): void;
	bezierCurveTo(cp1x: number, cp1y: number, cp2x: number, cp2y: number, x: number, y: number): void;
	arc(x: number, y: number, radius: number, startAngle: number, endAngle: number, anticlockwise?: boolean): void;
	arcTo(x1: number, y1: number, x2: number, y2: number, radius: number): void;
	ellipse(x: number, y: number, radiusX: number, radiusY: number, rotation: number, startAngle: number, endAngle: number, anticlockwise?: boolean): void;
	rect(x: number, y: number, w: number, h: number): void;
	// radii: a number, or one to four numbers or {x, y} points (upper left first, clockwise)
	roundRect(x: number, y: number, w: number, h: number, radii?: any): void;
}

// The browser's CanvasGradient: linear, radial or conic (a context's
// createLinearGradient...), its stops added with CSS colours
export declare class CanvasGradient {
	constructor(gradient: unknown);
	addColorStop(offset: number, color: string): void;
}

// The browser's CanvasPattern: an image repeated (createPattern), placed by setTransform
export declare class CanvasPattern {
	constructor(pattern: unknown);
	setTransform(transform?: DOMMatrix): void;
}

// The browser's ImageData: straight RGBA pixels, rows of width. `data`
// is its bytes as numbers (a copy: helder's TypeScript has no typed
// arrays yet, so a TypeScript program makes new pixels with
// new ImageData(array, width)); Haxe reads and writes `bytes`.
export declare class ImageData {
	// (width, height): transparent; (array, width, height?): its bytes
	constructor(a: any, b: number, c?: number);
	readonly width: number;
	readonly height: number;
	readonly colorSpace: string;
	readonly data: number[];
}

// The browser's DOMMatrix, its 2D part (a to f, m11 to m42): what
// getTransform gives, setTransform and a pattern's setTransform take. The
// *Self methods change it, the others return a new one.
export declare class DOMMatrix {
	// (none: the identity; six numbers: a to f)
	constructor(init?: number[]);
	a: number;
	b: number;
	c: number;
	d: number;
	e: number;
	f: number;
	m11: number;
	m12: number;
	m21: number;
	m22: number;
	m41: number;
	m42: number;
	readonly is2D: boolean;
	readonly isIdentity: boolean;
	multiplySelf(o: DOMMatrix): DOMMatrix;
	preMultiplySelf(o: DOMMatrix): DOMMatrix;
	translateSelf(tx?: number, ty?: number): DOMMatrix;
	scaleSelf(sx?: number, sy?: number): DOMMatrix;
	// (degrees, as the browser's)
	rotateSelf(deg?: number): DOMMatrix;
	skewXSelf(deg?: number): DOMMatrix;
	skewYSelf(deg?: number): DOMMatrix;
	invertSelf(): DOMMatrix;
	multiply(o: DOMMatrix): DOMMatrix;
	translate(tx?: number, ty?: number): DOMMatrix;
	scale(sx?: number, sy?: number): DOMMatrix;
	rotate(deg?: number): DOMMatrix;
	skewX(deg?: number): DOMMatrix;
	skewY(deg?: number): DOMMatrix;
	inverse(): DOMMatrix;
	// a point's x and y through it, as [x, y]
	transformPoint(x?: number, y?: number): number[];
	toFloat64Array(): number[];
	toString(): string;
}

// An image as skia-canvas's and @napi-rs/canvas's Image: set src to a
// file's path (or a data: URL), and it is decoded (helder.image: PNG,
// JPEG, GIF, WebP) at once; width, height and complete then say so.
// loadImage(src) gives one decoded.
export declare class Image {
	constructor();
	// an image decoded from a file's path or a data: URL (throws when it is not one)
	static load(src: string): Image;
	readonly width: number;
	readonly height: number;
	readonly complete: boolean;
	src: string;
	onload: (() => void) | null;
	onerror: ((error: string) => void) | null;
}

export declare const loadImage: typeof Image.load;

// The browser's TextMetrics (measureText): the advance, the ink's box
// from the alignment point, the font's and the em box's ascent and
// descent, the baselines from textBaseline's
export declare class TextMetrics {
	constructor();
	readonly width: number;
	readonly actualBoundingBoxLeft: number;
	readonly actualBoundingBoxRight: number;
	readonly actualBoundingBoxAscent: number;
	readonly actualBoundingBoxDescent: number;
	readonly fontBoundingBoxAscent: number;
	readonly fontBoundingBoxDescent: number;
	readonly emHeightAscent: number;
	readonly emHeightDescent: number;
	readonly hangingBaseline: number;
	readonly alphabeticBaseline: number;
	readonly ideographicBaseline: number;
}

// The fonts a context's `font` names, as skia-canvas's FontLibrary: files
// registered under a family (their own name, or an alias), chosen by the
// weight and style the font asks for; families it does not have are the
// system's (helder.text's SystemFonts).
export declare class FontLibrary {
	// every face of the files at paths, under family (null: each file's own family name); their family names
	static use(family: string | null, paths: string[]): string[];
	static has(family: string): boolean;
	static families(): string[];
	static reset(): void;
}

// The DOM facade's canvases drawn on the GPU from now on (GpuCanvas, each
// on a headless device of its size): `useGpu()` in helder/canvas. A class
// apart, so that a program that never calls it keeps no GPU code.
export declare class Gpu {
	static use(): void;
}

export declare const useGpu: typeof Gpu.use;

// The DOM facade's canvases drawn by the browser's own Canvas 2D from now
// on (WebCanvas): `useWeb()` in helder/canvas, for a web build
// (wasm32 with src/helder/canvas/imports.mjs). A class apart: a program
// that never calls it keeps none of it.
export declare class Web {
	static use(): void;
}

export declare const useWeb: typeof Web.use;
