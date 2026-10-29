// A headless Ui for the TypeScript tests (tests/typescript/helder/ui.tsx):
// UiProbe, the root it gives a ui Node (opaque, helder.ui's renderer's).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Node: "helder.ui.Node", UiProbe: "UiProbe", __module: "UiTypeScript"};

// A node of the UI tree: a box laid out by its parent's flexbox (Layout),
// drawn by a renderer (Canvas) and receiving events (Ui). Its children are
// in drawing order (the last on top). x, y, width and height are the
// layout's result in pixels, relative to the parent's border box (rounded
// to whole pixels: absX, absY are the window's), valid after Ui.update. A
// change to the tree or to a layout property of the style marks the node
// and its ancestors for layout; a paint property asks only for a frame.
// Subclasses with content (TextNode) measure it (measureContent) and draw it
// (paintContent).
// (helder.view's markup: its renderer, NodeRenderer)
export declare class Node {
	private readonly node: never;
}

// A headless Ui for the TypeScript tests (tests/typescript/helder/ui.tsx,
// declared to them by UiTypeScript): its root to render into, pointer,
// keys and text sent to it as a window would, its tree written out (each
// node's tag, a text's text, what it is to assistive technology).
export declare class UiProbe {
	// a Ui of width x height (MonoText's text), its root
	static root(width: number, height: number): Node;
	// a click on the first node with tag (laid out first)
	static click(tag: string): void;
	// text typed into the focused node
	static type(text: string): void;
	// a key pressed (Key's codes)
	static key(code: number): void;
	// the tree: a node a line, indented by its depth
	static dump(): string;
}
