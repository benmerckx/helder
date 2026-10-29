// helder.view for TypeScript programs (helder.typescript): signals,
// computations, markup (TSX) and its control flow. Each class is the Haxe
// class of its name in this file's package (helder.view; another one's
// named in __haxe); a function is one of a class's statics (typeof
// Class.name). The compiler calls them through glue it writes in Haxe,
// which converts values by the types Haxe declares.

// a value: reading it inside a computation tracks it; writing a different one notifies
export declare class Signal<T> {
	constructor(value: T);
	value: T;
	get(): T;
	set(value: T): void;
	// sets it from its current value (untracked)
	update(f: (value: T) => T): void;
	// the value, not tracked
	peek(): T;
	// notifies even though the value is the same object (it was changed inside)
	changed(): void;
}

// a derived value: recomputed when read after its sources changed
export declare class Memo<T> {
	constructor(fn: () => T);
	readonly value: T;
}

// what a computation and an owner's cleanups belong to
export declare class Owner {
	dispose(): void;
	readonly isDisposed: boolean;
}

export declare class Computation extends Owner {
}

// a markup literal's value (TSX): what mounts its nodes
export declare class View {
	private readonly view: never;
}

// what markup holds: views, text, numbers, reactive values (followed) and lists of them
export type Child = View | string | number | boolean | null | undefined | Signal<any> | Memo<any> | (() => unknown) | readonly Child[];

export declare class Reactive {
	static signal<T>(value: T): Signal<T>;
	static memo<T>(fn: () => T): Memo<T>;
	// runs fn now and whenever what it read changes
	static effect(fn: () => void): Computation;
	static batch(fn: () => void): void;
	static untrack<T>(fn: () => T): T;
	// a new ownership tree: fn gets its dispose
	static root<T>(fn: (dispose: () => void) => T): T;
	static onCleanup(fn: () => void): void;
	static onMount(fn: () => void): void;
}

export declare const signal: typeof Reactive.signal;
export declare const memo: typeof Reactive.memo;
export declare const effect: typeof Reactive.effect;
export declare const batch: typeof Reactive.batch;
export declare const untrack: typeof Reactive.untrack;
export declare const root: typeof Reactive.root;
export declare const onCleanup: typeof Reactive.onCleanup;
export declare const onMount: typeof Reactive.onMount;

// control flow in markup
export declare class Flow {
	// a row per item, kept and moved by identity
	static For<T>(props: {each: Signal<T[]> | Memo<T[]> | (() => T[]) | T[]; render: (item: T) => Child}): Child;
	// a row per index, its item a signal
	static Index<T>(props: {each: Signal<T[]> | Memo<T[]> | (() => T[]) | T[]; render: (item: Signal<T>, index: number) => Child}): Child;
	static Show(props: {when: unknown; fallback?: Child; children?: Child}): Child;
	static Switch(props: {fallback?: Child; children?: Child}): Child;
	static Match(props: {when: unknown; children?: Child}): Child;
}

export declare const For: typeof Flow.For;
export declare const Index: typeof Flow.Index;
export declare const Show: typeof Flow.Show;
export declare const Switch: typeof Flow.Switch;
export declare const Match: typeof Flow.Match;

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
