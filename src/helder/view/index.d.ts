// helder.view for TypeScript programs (helder.typescript): signals,
// computations, markup (TSX) and its control flow, on helder.view.graph
// (DESIGN.md). Each class is the Haxe class of its name in this file's
// package (helder.view; another one's named in __haxe); a function is one
// of a class's statics (typeof Class.name). The compiler calls them
// through glue it writes in Haxe, which converts values by the types Haxe
// declares; a signal, a memo or a Read comes to the program as a function.

declare const __haxe: {Graph: "helder.view.graph.Graph"};

// a value: called to read it (tracked in a computation), with a value to
// write it, with a function to update it from the latest value written;
// a write lands at the next flush (the end of the event, the frame or the
// loop's turn), reads seeing the committed value until then
export interface Signal<T> {
	(): T;
	(value: T): void;
	(update: (prev: T) => T): void;
	// the value, not tracked
	peek(): T;
}

// a derived value: computed when read after what it read changed
export interface Memo<T> {
	(): T;
	peek(): T;
}

// what reads a value: a component's prop of a signal, a memo, a function or a constant
export type Read<T> = T | Signal<T> | Memo<T> | (() => T);

// a markup literal's value (TSX): what mounts its nodes
export declare class View {
	private readonly view: never;
}

// what markup holds: views, text, numbers, reactive values (followed) and lists of them
export type Child = View | string | number | boolean | null | undefined | Signal<any> | Memo<any> | (() => unknown) | readonly Child[];

export declare class Graph {
	// (signal: a value's; a signal never holds a function)
	static signalValue<T>(value: T extends Function ? never : T): Signal<T>;
	static memo<T>(fn: () => T): Memo<T>;
	// compute runs now and again when what it read changes, apply after the commit
	static effect<T>(compute: () => T, apply: (value: T, prev: T | undefined) => void): void;
	// as effect, its apply in the render phase
	static renderEffect<T>(compute: () => T, apply: (value: T, prev: T | undefined) => void): void;
	// commits the writes now and runs what they make stale
	static flush(): void;
	static untrack<T>(fn: () => T): T;
	// a new ownership tree: fn gets its dispose
	static root<T>(fn: (dispose: () => void) => T): T;
	static onCleanup(fn: () => void): void;
	// fn once the current commit has landed (the nodes in the tree)
	static onSettled(fn: () => void): void;
	// whether what fn reads has a new value on its way
	static isPending(fn: () => unknown): boolean;
}

export declare const signal: typeof Graph.signalValue;
export declare const memo: typeof Graph.memo;
export declare const effect: typeof Graph.effect;
export declare const renderEffect: typeof Graph.renderEffect;
export declare const flush: typeof Graph.flush;
export declare const untrack: typeof Graph.untrack;
export declare const root: typeof Graph.root;
export declare const onCleanup: typeof Graph.onCleanup;
export declare const onSettled: typeof Graph.onSettled;
export declare const isPending: typeof Graph.isPending;

// control flow in markup
export declare class Flow {
	// a row per item, its child function given the item as a Read: kept and moved by identity (keyed), or a row per index (keyed={false})
	static For<T>(props: {each: Read<T[]>; keyed?: boolean; children: (item: () => T) => Child}): Child;
	// a row per number below count
	static Repeat(props: {count: Read<number>; children: (i: number) => Child}): Child;
	static Show<T>(props: {when: Read<T>; fallback?: Child; children?: Child}): Child;
	static Switch(props: {fallback?: Child; children?: Child}): Child;
	static Match<T>(props: {when: Read<T>; children?: Child}): Child;
	// the fallback while what the children read on their first load is pending
	static Loading(props: {fallback?: Child; children?: Child}): Child;
	// the fallback when making the children throws, or a computation in them does
	static Errored(props: {fallback: (error: unknown, reset: () => void) => Child; children?: Child}): Child;
}

export declare const For: typeof Flow.For;
export declare const Repeat: typeof Flow.Repeat;
export declare const Show: typeof Flow.Show;
export declare const Switch: typeof Flow.Switch;
export declare const Match: typeof Flow.Match;
export declare const Loading: typeof Flow.Loading;
export declare const Errored: typeof Flow.Errored;

// mounting: content into a renderer's node (the renderer the node's class names)
export declare class Render {
	// its dispose: removes the nodes, disposes their computations
	static render(content: Child, parent: unknown): () => void;
}

declare global {
	namespace JSX {
		type Element = View;
		// components may return any content
		type ElementType = string | ((props: any) => unknown);
		interface ElementChildrenAttribute {
			children: {};
		}
		// a renderer's elements: their attributes are the renderer's to check
		interface IntrinsicElements {
			[tag: string]: {[attribute: string]: unknown};
		}
	}
}
