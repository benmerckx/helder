// helder.web for TypeScript programs (helder.typescript): static pages
// rendered at build time, with islands of WebAssembly (see helder/view; the
// web's elements are lower-case TSX, their attributes as helder.web's
// README has them). Each class is the Haxe class of its name in helder.web,
// or the one __haxe names.
import type {Child, View} from "helder/view";

// when the loader starts an island (data-load): once it scrolls into view,
// once the browser is idle, at once, on the first click or key press inside it
export type Load = "visible" | "idle" | "load" | "click";

// Static pages: content rendered to HTML (the static renderer), written at build time
export declare class Static {
	// content as HTML
	static render(content: Child): string;
	// a whole page: <!doctype html> and content (an <html> element)
	static document(content: Child): string;
	// writes a page (or any text), its directories made
	static write(path: string, text: string): void;
	// copies a file, its directories made
	static copy(from: string, to: string): void;
}

// <Island.Wasm>'s props: a canvas (width x height) the loader (loader.js)
// hands to src, a wasm32-wasi module, run by runner (helder.os's
// browser.mjs) with imports (each package's imports.mjs), args, fonts (files
// helder.text may use) and assets (the URL of the build's
// <module>.assets.json: the files it reads before main); canvas false: none
// (a sound); children shown with the canvas
export interface WasmProps {
	src: string;
	imports?: string[];
	args?: string[];
	runner?: string;
	load?: Load;
	id?: string;
	width?: number;
	height?: number;
	fonts?: string[];
	assets?: string;
	canvas?: boolean;
	stop?: "offscreen";
	children?: Child;
}

// islands: the interactive parts of a static page
export declare class Island {
	// a WebAssembly island: a wasm32-wasi module on a canvas of the page
	static Wasm(props: WasmProps): View;
}

// <Surface>'s props: a ui program (its root ui's <Surface>) on a canvas the page's styles size
export interface SurfaceProps {
	src: string;
	imports?: string[];
	fonts?: string[];
	args?: string[];
	runner?: string;
	load?: Load;
	id?: string;
	className?: string;
	style?: string;
	children?: Child;
}

export declare class WebTags {
	// a ui program on the page: a <canvas> 100% of its element, running src
	static Surface(props: SurfaceProps): View;
}

export declare const Surface: typeof WebTags.Surface;
