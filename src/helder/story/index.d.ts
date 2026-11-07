// helder.story for TypeScript programs (helder.typescript): story({name,
// render, seed, store, caption, background, color}), a definition (its
// fields checked where they are written, as Haxe's helder.story.Story.story;
// nothing in a release build), each story's view made from its Controls;
// tree(story), its tree mounted headless as helder test snapshots it
// (its markup helder.ui's: the neutral elements, its renderer); screens
// (stories), the studio's program of a project's screens (Screens).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Event} from "helder/ui";
import type {Signal, View} from "helder/view";

declare const __haxe: {Story: "helder.story.Story", Controls: "helder.story.Story.Controls", Stories: "helder.story.Stories", Screens: "helder.story.Screens", __module: "helder.story.TypeScript"};

export declare class Story {
	private readonly story: never;
}

// story({...})'s fields, as a TypeScript program gives them (helder/story:
// Stories.define, the definition checked them where they are written)
export type StoryDef = { name: string; render: (arg0: Controls) => View; seed?: number; width?: number; height?: number; store?: boolean; caption?: string; background?: number; color?: number };

// A story's controls: each a signal its view reads, recorded with its name
// and kind for an editor (the values a store screenshot uses are their
// defaults); random, a generator of the story's seed; settled, false while
// the scene is not ready (a store screenshot waits for it)
export declare class Controls {
	constructor(seed?: number);
	readonly seed: number;
	readonly list: Array<{ name: string; kind: string; value: any; options?: string[] }>;
	readonly settled: Signal<boolean>;
	number(name: string, value: number): Signal<number>;
	bool(name: string, value: boolean): Signal<boolean>;
	text(name: string, value: string): Signal<string>;
	choice(name: string, options: string[], value?: string): Signal<string>;
	// 0xAARRGGBB
	color(name: string, value: number): Signal<number>;
	// the next of the seed's numbers in [0, 1) (xorshift32): the same story, the same scene
	random(): number;
}

// The stories of the story files (Story.story), registered (add), mounted
// headless (mount: a Ui of a size, the story's view rendered into its
// root, the clock's transitions finished until Controls.settled), and as
// tests (test: each story's tree snapshotted, helder test's runner calls it
// for a .story.hx file with its stories: of, helder.cli.TestCommand)
export declare class Stories {
	// story({...}) in a TypeScript program (helder/story; the definition
	// checked its fields where they are written)
	static define(def: StoryDef): Story;
	// the tree as text: each node's tag (or kind), box and text, indented
	// (in a phone's size, WIDTH x HEIGHT, unless given)
	static tree(s: Story, width?: number, height?: number): string;
}

export declare const story: typeof Stories.define;
export declare const tree: typeof Stories.tree;

// A project's stories as the studio's screens (apps/studio): the program
// the studio builds of a project (a dev build, headless: -D hxmc.dev -D
// helder.headless) shows one story in a window of the story's size
// (width, height; a phone's without), the one HELDER_STUDIO_SCREEN names
// (the first without). The studio starts one such process for each screen,
// so a screen's state (a TypeScript module's signals) is its own. Over the
// devtools protocol, `Studio.screens` answers which one this is and the
// others: {screen, screens: [{name, width, height}]}. Built for the web
// (wasm32-wasi) it is the studio's preview host there instead: every story
// in one program (helder.story.Host) in a worker (helder.story.web.Preview).
//
//   // the studio's generated main (bin/studio/<name>/ScreensMain.hx, screens.tsx)
//   helder.story.Screens.run(helder.story.Stories.of("Todo_story"));
//   import { screens } from "helder/story"; screens([empty, items]);
export declare class Screens {
	static run(stories: Story[]): void;
}

export declare const screens: typeof Screens.run;

// a neutral element's attributes: any, its handlers given ui's events (helder.ui.view.NodeEvents)
export interface NeutralAttributes {
	[attribute: string]: unknown;
	onPress?: ((event: Event) => void) | null;
	onClick?: ((event: Event) => void) | null;
	onPointerDown?: ((event: Event) => void) | null;
	onPointerUp?: ((event: Event) => void) | null;
	onPointerMove?: ((event: Event) => void) | null;
	onPointerEnter?: ((event: Event) => void) | null;
	onPointerLeave?: ((event: Event) => void) | null;
	onPointerCancel?: ((event: Event) => void) | null;
	onLostPointerCapture?: ((event: Event) => void) | null;
	onWheel?: ((event: Event) => void) | null;
	onKeyDown?: ((event: Event) => void) | null;
	onKeyUp?: ((event: Event) => void) | null;
	onTextInput?: ((event: Event) => void) | null;
	onComposition?: ((event: Event) => void) | null;
	onInput?: ((event: Event) => void) | null;
	onFocus?: ((event: Event) => void) | null;
	onBlur?: ((event: Event) => void) | null;
	onFocusIn?: ((event: Event) => void) | null;
	onFocusOut?: ((event: Event) => void) | null;
	onDragStart?: ((event: Event) => void) | null;
	onDragOver?: ((event: Event) => void) | null;
	onDragLeave?: ((event: Event) => void) | null;
	onDrop?: ((event: Event) => void) | null;
	onDragEnd?: ((event: Event) => void) | null;
	onResize?: ((event: Event) => void) | null;
	onTap?: ((event: unknown) => void) | null;
	onPan?: ((event: unknown) => void) | null;
	onPinch?: ((event: unknown) => void) | null;
	onScale?: ((event: unknown) => void) | null;
}

declare global {
	namespace JSX {
		// the neutral elements: ui's, realised by each renderer
		interface IntrinsicElements {
			view: NeutralAttributes;
			text: NeutralAttributes;
			scroll: NeutralAttributes;
			image: NeutralAttributes;
			icon: NeutralAttributes;
			field: NeutralAttributes;
			[tag: `view:${string}`]: NeutralAttributes;
			[tag: `text:${string}`]: NeutralAttributes;
			[tag: `field:${string}`]: NeutralAttributes;
		}
	}
}
