// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view). Each class is the Haxe class of its name in
// helder.ui, or the one __haxe names.
import type {Child, View} from "helder/view";

declare const __haxe: {UiWindow: "helder.ui.draw.UiWindow"};

// <Surface>'s props: values or reactive ones (a Signal, a Memo, a function), followed
export interface SurfaceProps {
	title?: unknown;
	width?: unknown;
	height?: unknown;
	theme?: unknown;
	background?: unknown;
	dark?: unknown;
	// the window closed by its user (default: closed)
	onClose?: () => void;
	children?: Child;
}

// a window drawing a ui tree with the GPU
export declare class UiWindow {
	// the app loop: every window's frames and events until the last closes; content opened first
	static run(content?: View): void;
	// <Surface>: a window, its children rendered into its ui's root; closed with its owner
	static Surface(props: SurfaceProps): View;
}

export declare const Surface: typeof UiWindow.Surface;

// an event as the ui dispatches it to a handler (onPress, onInput, onKeyDown, ...)
export declare class Event {
	// the pointer in window pixels
	readonly x: number;
	readonly y: number;
	// pointer buttons: 1 left, 2 middle, 3 right
	readonly button: number;
	// KeyDown, KeyUp: the key (Key) and the modifiers (Key.MOD_*)
	readonly key: number;
	readonly mods: number;
	// TextInput: the characters typed; Input: the field's text
	readonly text: string;
	readonly caret: number;
	readonly deltaX: number;
	readonly deltaY: number;
	readonly defaultPrevented: boolean;
	readonly localX: number;
	readonly localY: number;
	stop(): void;
	preventDefault(): void;
}

// keys as Event.key has them
export declare class Key {
	static readonly BACKSPACE: number;
	static readonly TAB: number;
	static readonly ENTER: number;
	static readonly ESCAPE: number;
	static readonly HOME: number;
	static readonly LEFT: number;
	static readonly UP: number;
	static readonly RIGHT: number;
	static readonly DOWN: number;
	static readonly PAGE_UP: number;
	static readonly PAGE_DOWN: number;
	static readonly END: number;
	static readonly INSERT: number;
	static readonly DELETE: number;
	static readonly SPACE: number;
	static readonly MOD_SHIFT: number;
	static readonly MOD_CONTROL: number;
	static readonly MOD_ALT: number;
	static readonly MOD_META: number;
}
