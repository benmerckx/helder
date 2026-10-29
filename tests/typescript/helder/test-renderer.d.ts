// tests/view's TestRenderer for the TypeScript tests (tests/typescript/helder):
// a tree of nodes written out as HTML. A program's own Haxe classes declared
// to it as helder's are: a module's declaration class (helder.typescript.api.Modules),
// its declarations generated (tests/typescript/run.mjs checks them).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {TestNode: "TestRenderer.TestNode", __module: "TestTypeScript"};

export declare class TestNode {
	// (for programs that render into a tree of their own: helder.typescript's tests)
	static root(tag: string): TestNode;
	// calls the listener for name of the first element with tag here or below
	fire(tag: string, name: string): void;
	toHtml(): string;
}
