// tests/view's TestRenderer for the TypeScript tests: a tree of nodes written out as HTML.
declare const __haxe: {TestNode: "TestRenderer.TestNode"};

export declare class TestNode {
	static root(tag: string): TestNode;
	// calls the listener for name of the first element with tag here or below
	fire(tag: string, name: string): void;
	toHtml(): string;
}
