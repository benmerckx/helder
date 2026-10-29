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
