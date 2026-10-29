// helder.view for TypeScript programs (helder.typescript): signals,
// computations, markup (TSX) and its control flow, on helder.view.graph
// (DESIGN.md). Each class is the Haxe class `__haxe` names; a function is one
// of a class's statics (typeof Class.name), called directly by the compiled
// program, its values converted by the types Haxe declares (the manifest,
// DESIGN.md 7.3); a signal, a memo or a Read comes to the program as a
// function.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Render: "helder.view.Render", Graph: "helder.view.graph.Graph", Scheduler: "helder.view.graph.Scheduler", Flow: "helder.view.Flow", __module: "helder.view.TypeScript"};

// A value in the graph (DESIGN.md 3.1): called to read it (tracked inside
// a computation), called with a value to write it, with a function to
// update it from the latest value written (a write is committed at the
// next flush: reads see the committed value until then). Made by
// Graph.signal: a value, or a function for a value derived from what it
// reads that can also be written. Never a function itself.
export interface Signal<T> {
	(): T;
	// (update before write: an argument of no static type, Dynamic, is then a
	// write (Haxe picks the last overload it fits), a function literal an
	// update; chosen by the static type, never the value: a Dynamic that is
	// a function at run time is an error (Node.set), not written, not an update)
	(f: ((arg0: T) => T)): void;
	(value: T): void;
	// the committed value, not tracked
	peek(): T;
}

// A derived value (DESIGN.md 2, Memos): called to read it, computed when
// first read and again when read after what it read changed; its readers
// are marked only when the result differs.
export interface Memo<T> {
	(): T;
	// the value, not tracked
	peek(): T;
}

// A prop that reads (DESIGN.md 3.2): a constant, a signal, a memo or a
// function, each read by calling it (`props.step()`), tracked as what it
// reads is. Markup binds a prop of this type the way Solid binds props: a
// hole that may read (3.3) is given as a function of it, so the component
// reads the value when it uses it, not when it is made:
//
//   function Counter(props:{step:Read<Int>}) ...
//   <Counter step={1}/>  <Counter step={size}/>  <Counter step={a() + b()}/>
//
// A constant is a small cell, not a closure; a signal or a memo is its node.
declare const readBrand: unique symbol;
export interface Read<T> {
	readonly [readBrand]: T;
	(): T;
}

// what makes a Read: a TSX site's component props take one of these (JSX.LibraryManagedAttributes)
export type ReadFrom<T> = Read<T> | Signal<T> | Memo<T> | (() => T) | T;

// A markup literal's value: what mounts its nodes. Write markup in a class
// that implements Markup (every literal in it is compiled), or through
// view(<...>):
//
//   class App implements Markup {
//     static function main()
//       Render.render(<view padding={8}>
//         <text>Hello {name}!</text>
//         {[for (i in items) <text>{i}</text>]}
//         <Button label="OK" onClick={() -> trace("ok")}/>
//       </view>, root);
//   }
//
// The literal's holes ({expr} children and attribute values) are evaluated
// where it is; mount then makes its elements (the renderer's, by tag:
// lowercase names), sets their attributes and inserts them, each time it is
// mounted, by the renderer that owns the place it is mounted in (each
// literal is compiled for the renderer that owns it, or for each the
// program reaches). Other names
// are components: Button(props) called when mounted, untracked, in an
// owner of its own, props an object of its attributes (children: the
// content, a View), checked against Button's argument.
export declare class View {
	private readonly view: never;
}

// Mounting content: render and insert go to the runtime (ViewRuntime) of the
// renderer whose nodes parent is, chosen by its type when compiling (its
// class's @:rendered, HostMacro.rendererOf); what is mounted there is made
// by that renderer, components and all, and a literal given here is
// compiled for it. A component that makes a node of one renderer and
// renders into it with another is a boundary (<Scene>: a ui node, scene
// nodes in it); content passes through it unchanged. open mounts content
// with no parent: a program's root, components making roots of their own
// (<Surface>s).
export declare class Render {
	// renders content into parent (its root: dispose removes it and stops its effects)
	static render: (content: unknown, parent: unknown) => () => void;
	// inserts content into parent before a node (null: at the end); the nodes made
	static insert: (content: unknown, parent: unknown, before: unknown) => unknown[];
}

// helder.view's reactive graph (DESIGN.md): Solid 2's semantics on a
// runtime of helder's own. Signals hold values, memos derive them, effects
// run in two halves (compute tracked, apply after the commit). Writes are
// deferred: committed together at the next flush (the loop's task ending,
// or flush()), reads seeing the committed value until then. Computations
// form an ownership tree: those made while another runs belong to it and
// are disposed before it runs again.
//
//   var count = signal(0);
//   var double = memo(() -> count() * 2);
//   effect(() -> double(), v -> trace(v));
//   count(c -> c + 1);
export declare class Graph {
	// (a value's signal, as TypeScript's signal(v) calls it: index.d.ts)
	static signalValue<T>(value: T extends Function ? never : T): Signal<T>;
	static memo<T>(fn: (prev: T | null) => T, options?: { equals?: (arg0: T, arg1: T) => boolean; unobserved?: () => void; ownedWrite?: boolean }): Memo<T>;
	// compute runs now and again when what it read changes; apply after the
	// commit, given its value and the previous one (the first: at the next
	// flush); error, when given, takes compute's errors (else the nearest
	// error boundary, else flush throws them)
	static effect<T>(compute: (prev: T | null) => T, apply: (value: T, prev: T | null) => void | (() => void), error?: ((arg0: any) => void)): void;
	// as effect, its apply in the render phase: before every effect's
	static renderEffect<T>(compute: (prev: T | null) => T, apply: (value: T, prev: T | null) => void | (() => void), error?: ((arg0: any) => void)): void;
	// fn run once the current commit has landed (its applies done), not
	// tracked: after the nodes being rendered are in the tree (Solid 2's
	// onSettled, onMount's successor); disposed with the current owner
	static onSettled(fn: (() => void)): void;
	// a new ownership tree, owned by the current owner if any: fn gets its dispose
	static root<T>(fn: ((dispose: (() => void)) => T)): T;
	// fn's reads not tracked
	static untrack<T>(fn: (() => T)): T;
	// fn runs when the current owner is disposed or runs again
	static onCleanup(fn: (() => void)): void;
	// whether what fn reads has a new value on its way (a held change, an
	// async answer to a new question): looks ahead of the hold, never holds
	// it; a first load gives no verdict (false; tracked, it suspends as the
	// read would); an error in fn is false
	static isPending(fn: (() => unknown)): boolean;
}

export declare const signal: typeof Graph.signalValue;
export declare const memo: typeof Graph.memo;
export declare const effect: typeof Graph.effect;
export declare const renderEffect: typeof Graph.renderEffect;
export declare const untrack: typeof Graph.untrack;
export declare const root: typeof Graph.root;
export declare const onCleanup: typeof Graph.onCleanup;
export declare const onSettled: typeof Graph.onSettled;
export declare const isPending: typeof Graph.isPending;

// When writes are committed and effects run (DESIGN.md 2, Writes and
// commits; Holds). A write queues its node; a flush stages the pending
// writes in a transaction, runs what they make stale for it (owned memos,
// then render effects' computes, then the others', parents first), and
// settles it: committed when nothing it renders waits (its effects'
// applies then, render effects first), else parked until its async lands.
// An async answer lands into the transaction that asked, the same way. A
// flush comes from flush(), or, after a write outside one, from `later`
// (helder.async's loop: when the task running ends, as Solid 2's
// microtask; unset, nothing flushes until flush() is called).
export declare class Scheduler {
	static flush(): void;
}

export declare const flush: typeof Scheduler.flush;

// Control flow components for markup (import helder.view.Flow.*), Solid 2's:
//
//   <For each={todos}>{t -> <Item todo={t}/>}</For>
//   <For each={names} keyed={false}>{name -> <text>{name()}</text>}</For>
//   <Repeat count={3}>{i -> <dot/>}</Repeat>
//   <Show when={count() > 0} fallback="none">{...}</Show>
//   <Switch fallback="other"><Match when={a()}>A</Match><Match when={b()}>B</Match></Switch>
//   <Provider context={theme} value={dark}>{...}</Provider>
//   <Errored fallback={(e, reset) -> ...}>{...}</Errored>
//   <Loading fallback={<text>loading</text>}>{...}</Loading>
//
// For's row is its child function, given the item as a Read: keyed by the
// item itself (the default), a row is kept and moved while its item is in
// the list, its Read the item; keyed={false}, a row per index, its Read
// what is at that index (Solid 1's Index). Repeat makes a row per number
// below count. Show and Switch render a branch again only when the branch
// chosen changes (not on every change of what chooses it): `when` is
// truthy when not null and not false. Provider sets a context for its
// children (Graph.use). Errored shows fallback instead of its children
// when making them throws, or a computation inside them does later; reset
// tries again. Loading shows fallback instead of its children while what
// they read on their first load is pending (an async memo, helder.asset's
// Asset); once it has shown them it keeps them shown, a later change held
// until it lands (Graph.isPending says one is on its way). Its children
// are made once: what reads a value not ready waits inside the graph.
export declare class Flow {
	static For<T>(props: { each: Read<T[]>; keyed?: boolean; children: (arg0: Read<T>) => unknown }): unknown;
	static Repeat(props: { count: Read<number>; children: (arg0: number) => unknown }): unknown;
	static Show<T>(props: { when: Read<T>; fallback?: unknown; children?: unknown }): unknown;
	static Match<T>(props: { when: Read<T>; children?: unknown }): unknown;
	static Switch(props: { fallback?: unknown; children?: unknown }): unknown;
	static Errored(props: { fallback: (error: any, reset: (() => void)) => unknown; children?: unknown }): unknown;
	static Loading(props: { fallback?: unknown; children?: unknown }): unknown;
}

export declare const For: typeof Flow.For;
export declare const Repeat: typeof Flow.Repeat;
export declare const Show: typeof Flow.Show;
export declare const Switch: typeof Flow.Switch;
export declare const Match: typeof Flow.Match;
export declare const Loading: typeof Flow.Loading;
export declare const Errored: typeof Flow.Errored;

declare global {
	namespace JSX {
		type Element = View;
		// components may return any content
		type ElementType = string | ((props: any) => unknown);
		interface ElementChildrenAttribute {
			children: {};
		}
		// a component's props: Read as what makes one
		type LibraryManagedAttributes<C, P> = {[K in keyof P]: NonNullable<P[K]> extends Read<infer T> ? ReadFrom<T> | Extract<P[K], undefined> : P[K]};
		// a renderer's elements: their attributes are the renderer's to check
		interface IntrinsicElements {
			[tag: string]: {[attribute: string]: unknown};
		}
	}
}
