// helder.story for TypeScript programs (helder.typescript): story({name,
// render, seed, store, caption, background, color}), a definition (its
// fields checked where they are written, as Haxe's helder.story.Story.story;
// nothing in a release build), each story's view made from its Controls;
// tree(story), its tree mounted headless as helder test snapshots it
// (its markup helder.ui's: the neutral elements, its renderer); screens
// (stories), the studio's program of a project's screens (Screens); shots
// (stories), helder publish's program of its screenshots (StoreShots).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Event, WebViewEvent} from "helder/ui";
import type {Signal, View} from "helder/view";

declare const __haxe: {Story: "helder.story.Story", Controls: "helder.story.Story.Controls", Stories: "helder.story.Stories", Screens: "helder.story.Screens", StoreShots: "helder.story.StoreShots", __module: "helder.story.TypeScript"};

export declare class Story {
	private readonly story: never;
}

// story({...})'s fields, as a TypeScript program gives them (helder/story:
// Stories.define, the definition checked them where they are written)
export type StoryDef = { name: string; render: (arg0: Controls) => View; seed?: number; width?: number; height?: number; store?: boolean; caption?: string; background?: number; color?: number; feature?: boolean };

// A story's controls: each a signal its view reads, recorded with its name
// and kind for an editor (the values a store screenshot uses are their
// defaults); random, a generator of the story's seed; settled, false while
// the scene is not ready (a store screenshot waits for it); play, a story
// that runs to a moment (a game mid-play): unsettled until its clock has
// run that long, the renderers running its frames on a virtual clock;
// onDispose, what to let go with the story
export declare class Controls {
	constructor(seed?: number);
	readonly seed: number;
	readonly list: Array<{ name: string; kind: string; value: any; options?: string[] }>;
	// each control's signal by its name (an editor's change: the studio's Story.set)
	readonly signals: unknown;
	readonly settled: Signal<boolean>;
	number(name: string, value: number): Signal<number>;
	bool(name: string, value: boolean): Signal<boolean>;
	text(name: string, value: string): Signal<string>;
	choice(name: string, options: string[], value?: string): Signal<string>;
	// 0xAARRGGBB
	color(name: string, value: number): Signal<number>;
	// the story plays for seconds of its clock, then is settled: what runs
	// on the clock (helder.ui's Clock: a game's frame, its physics, the
	// transitions) gets there frame by frame, Stories.FPS a second, whatever
	// the machine's speed (Stories.settle; a store screenshot, helder.run's,
	// a test's tree: that moment). In the studio it runs live, as it would.
	// Called while the story renders (its render function): its clock's
	play(seconds: number): void;
	// f called when the story is let go (a renderer done with it: a store
	// screenshot taken, a test's tree read): what it made that outlives its
	// view, a game's scene world, its GPU resources
	onDispose(f: () => void): void;
	// (the renderer's: the story let go, onDispose's in their order)
	dispose(): void;
	// the next of the seed's numbers in [0, 1) (xorshift32): the same story, the same scene
	random(): number;
}

// The stories of the story files (Story.story), registered (add), mounted
// headless (mount: a Ui of a size in a ScreenContext of its own, the
// story's view rendered into its root and brought to its moment: settle),
// and as tests (test: each story's tree snapshotted, helder test's runner
// calls it for a .story.hx file with its stories: of, helder.cli.TestCommand)
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
// the studio builds of a project (a dev build, -D hxmc.dev) runs every
// story in one program, the studio's preview host (helder.story.Host: each
// story a root of its own with a context of its own): natively one process
// (helder.story.NativeHost: its frames GPU textures the studio's process
// opens, or shared memory where the GPU shares none), built for the web
// (wasm32-wasi) a worker (helder.story.web.Preview). Over the devtools
// protocol `Studio.screens` answers the screens: {screens: [{name, width,
// height}]}.
//
//   // the studio's generated main (bin/studio/<name>/gen/StudioScreens.hx, screens.tsx)
//   helder.story.Screens.run(helder.story.Stories.of("Todo_story"));
//   import { screens } from "helder/story"; screens([empty, items]);
export declare class Screens {
	static run(stories: Story[]): void;
}

export declare const screens: typeof Screens.run;

// The screenshots of the stories with store: true, the one place an app's
// screenshots come from: the stores' and helder.run's. Each rendered
// offscreen on the GPU (helder.gfx's headless surface: Mesa's llvmpipe on
// Linux) at a size as a real layout (the size in points, the screen's
// scale), text in the system's fonts (DrawText), in a ScreenContext of its
// own whose clock is the shot's alone (Ui.now reads it): brought to its
// moment frame by frame (Stories.settle: a story that plays, Controls.play,
// laid out and painted each frame, its last one drawn), so a 3D scene
// mid-play comes out as it would on a screen, whatever the machine's speed.
// Written as opaque RGB PNGs (no alpha channel: Apple's rule).
//
// - The stores' (store): at each store's size (SIZES), the story's caption
//   (StoreOptions) in a band over it: <dir>/<size>/<story>.png.
// - helder.run's (web): at one size (a window's, 1280x800, or a phone's,
//   390x844 at 2x, for a portrait app), no band (helder.run's page shows
//   plain frames), in the stories' order, at most a number of them:
//   <dir>/shot-<n>.png.
//
// Either way <dir>/shots.json lists them (each file's size, story, caption,
// SHA-256 and MD5, which helder publish compares with the stores'). helder
// publish --screenshots and --run build a program of the project's story
// files around main (helder.cli.Shots); a TypeScript project's calls shots
// (helder/story) with its stories.
export declare class StoreShots {
	// (TypeScript's shots(stories): main over them; helder/story)
	static run(stories: Story[]): void;
}

export declare const shots: typeof StoreShots.run;

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
	onMessage?: ((event: WebViewEvent) => void) | null;
	onNavigate?: ((event: WebViewEvent) => void) | null;
	onUrlChange?: ((event: WebViewEvent) => void) | null;
	onLoad?: ((event: WebViewEvent) => void) | null;
	onTitle?: ((event: WebViewEvent) => void) | null;
	onProgress?: ((event: WebViewEvent) => void) | null;
	onLoadError?: ((event: WebViewEvent) => void) | null;
	onConsole?: ((event: WebViewEvent) => void) | null;
	onCrash?: ((event: WebViewEvent) => void) | null;
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
