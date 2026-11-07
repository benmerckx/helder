// helder.ui for TypeScript programs (helder.typescript): windows and their
// markup (see helder/view), the events handlers are given, the keys. Each
// class is the Haxe class `__haxe` names. The neutral elements (view, text,
// view:button...) take any attribute, their handlers given ui's events.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Read, RootView, Signal, View} from "helder/view";

declare const __haxe: {UiWindow: "helder.ui.draw.UiWindow", Event: "helder.ui.Event", Key: "helder.ui.Key", VirtualScroll: "helder.ui.VirtualScroll", UiFlow: "helder.ui.view.UiFlow", __module: "helder.ui.TypeScript"};

// a menu of the menu bar; role Window: the window menu (macOS's: its own
// items after Minimize, Zoom and Close)
export type Menu = { label: string; items: unknown[]; role?: "about" | "quit" | "hide" | "undo" | "redo" | "cut" | "copy" | "paste" | "select-all" | "minimize" | "zoom" | "fullscreen" | "close" | "window" };

// An item of a native menu (PlatformViews.menu): its label, its shortcut
// as shown ("Ctrl+C", "⌘C") and as keys (a menu that takes its keys
// itself: macOS's key equivalents), whether it is disabled or checked; a
// separator; a submenu's items. id: what the menu reports when it is chosen.
// role: a standard item's (helder.ui.menu.MenuRole: "about", "quit",
// "copy", "window" for a menu bar's window menu...), which a platform puts
// in its own place or gives its own behaviour (macOS).
export type PlatformMenuItem = { id: number; label: string; shortcut?: string; keys?: unknown; disabled?: boolean; checked?: boolean; separator?: boolean; items?: PlatformMenuItem[]; role?: string };

// <Surface>'s props (UiWindow.Surface)
export type SurfaceProps = { title?: Read<string>; width?: Read<number>; height?: Read<number>; theme?: Read<any>; background?: Read<any>; dark?: Read<boolean>; onClose?: () => void; onDrop?: (files: string[], x: number, y: number) => void; ref?: (arg0: UiWindow) => void; antialias?: boolean; fontSmoothing?: Read<string>; children?: UiView };

// helder.ui's markup (helder.view.ViewOf): a component returning one is
// pinned to ui, a children prop typed so makes its content ui's (a
// boundary's: <Surface>, <Ui> in a scene)
export type UiView = unknown;

// A window showing a UI tree drawn with the GPU: an helder.os Window, its
// gfx Device, a Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); a frame lays the tree out and draws it, when there is
// something new to draw (needsFrame: the Ui asked for one, the window was
// resized or lost its pixels). run() is the app loop for every UiWindow
// open, which sleeps while none has a frame to draw. In the browser each
// frame's accessibility tree goes to the mirror in the canvas (WebAccess:
// load src/helder/ui/imports.mjs), on macOS to NSAccessibility (MacAccess), on
// iOS to UIAccessibility (IosAccess), on Android to its AccessibilityNodeProvider (AndroidAccess),
// on Windows to UI Automation (WinAccess), on Linux to AT-SPI (LinuxAccess),
// and the actions asked for come back.
//
// In markup (helder.view) <Surface> is the root ui draws into: a UiWindow,
// its children ui's markup rendered into its root; several make several
// windows; run(content) opens them (Render.open) and runs the loop:
//
//   UiWindow.run(<Surface title="Todo" width={480} height={560} theme={sheet}>
//     <Todo/>
//   </Surface>);
//
// In a page's markup (helder.web's DOM or static renderer) a <Surface> is
// helder.web's: a canvas running a wasm program whose root is this one.
export declare class UiWindow {
	// the app loop: every UiWindow's frames and events until the last closes
	// (on the web it returns, the frames going on); content, when given, opened first
	static run(content?: RootView): void;
	// <Surface>: a window (a canvas on the web), its children rendered into its ui's root; closed with its owner
	static Surface(props: SurfaceProps): View;
}

export declare const Surface: typeof UiWindow.Surface;

// An event as Ui dispatches it: to the target, then (unless stopped) to
// each ancestor (current), except PointerEnter, PointerLeave, Focus and
// Blur, which each node gets for itself.
export declare class Event {
	// an event of type at target, the pointer at x, y in the window's coordinates
	static of(type: number, target: unknown, x: number, y: number): Event;
	readonly type: number;
	readonly target: unknown;
	// the node whose handler runs
	readonly current: unknown;
	// the pointer in window pixels (pointer events; else where it was last)
	readonly x: number;
	readonly y: number;
	// pointer buttons: 1 left, 2 middle, 3 right (a finger, a pen: 1)
	button: number;
	// pointer events: which pointer (0 the mouse, else helder.os's slot of a
	// finger or a pen: Pointer.id), its type, its pressure (0 to 1), and
	// whether it is the primary one (the mouse, the first finger down)
	pointerId: number;
	pointerType: number;
	pressure: number;
	isPrimary: boolean;
	// KeyDown, KeyUp: the key (Key) and the modifiers (Key.MOD_*)
	key: number;
	mods: number;
	// TextInput: the characters typed (an IME's composed text, too); Input: the field's text;
	// Composition: an input method's text not committed yet (empty: none)
	text: string;
	// Composition: the caret in text (UTF-16)
	caret: number;
	// Wheel: the scroll in pixels (down and right positive)
	// drag and drop: what is dragged (the source's dragData); DragEnd: whether it was dropped
	data: any;
	dropped: boolean;
	deltaX: number;
	deltaY: number;
	readonly stopped: boolean;
	// the default action (Tab moving the focus, the wheel scrolling) is not taken
	readonly defaultPrevented: boolean;
	// the pointer relative to current's border box (Node.localX: through
	// scrolling and transforms; fields, so that a handler's untyped event
	// reads them too)
	readonly localX: number;
	readonly localY: number;
	stop(): void;
	preventDefault(): void;
}

// Key codes: X11 KeySyms, as helder.os.Event.key gives them on every
// platform (Latin-1 keys are their unshifted character code: 'a' is 0x61)
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
	// the context menu key
	static readonly MENU: number;
	static readonly F1: number;
	static readonly F10: number;
	static readonly F12: number;
	static readonly DELETE: number;
	static readonly SHIFT: number;
	static readonly CONTROL: number;
	static readonly ALT: number;
	static readonly META: number;
	static readonly SPACE: number;
	// Event.mods bits
	static readonly MOD_SHIFT: number;
	static readonly MOD_CONTROL: number;
	static readonly MOD_ALT: number;
	static readonly MOD_META: number;
}

// A scroller over a long list's rows, only those in view made
// (UiFlow.VirtualList's; usable alone): count rows, their heights in a
// HeightIndex (estimated until measured), the rows of the window (the view
// and overscan more on each side) made by onMakeRow into a row node each and
// shown in the flow between two spacers as tall as the rows before and
// after them; rows that leave the window are hidden and kept (keep of them,
// the farthest from the window let go first, onDropRow), shown again as they
// were when they come back. After each layout (Ui.update: settle) the rows
// shown are measured and the window moved, laid out again while that
// changes it, so a frame never shows a gap or the estimates.
//
// The scroll is anchored to a row: the first in view and how far into it,
// kept through measures, a new estimate and rows put in or taken out
// before it (splice), so the content does not move. scrollToIndex (start,
// center, end or the nearest edge: auto) goes to a row made or not, held
// there while its rows are measured; focusIndex makes the row, scrolls to
// it and focuses it. The rows are a listbox's options to assistive
// technology (rowRole), each its place among all (posInSet, setSize). The
// keyboard on a row (its focus within the list): Up and Down, Page Up and
// Down, Home and End move the focus onto that row (made if need be, onRowActive
// told: a selection follows it); Enter and Space are onRowActivate's; the row
// focused or last moved to is the one Tab stops on (the others -1).
// Rows should not have margins: their measure is their border box.
export declare class VirtualScroll {
	// the first and last rows in view (-1: none)
	firstVisible(): number;
	lastVisible(): number;
	// scrolls to row index ("start", "center", "end"; "auto": as little as
	// shows it), made or not, held there while the rows are measured
	scrollToIndex(index: number, align?: string): void;
	// focuses row index (made, scrolled into view first), the focus ring shown
	focusIndex(index: number): void;
}

// helder.ui's own control flow components for markup (import
// helder.ui.view.UiFlow.*), beside helder.view.Flow's:
//
//   <Popover open={open} placement="below">{...}</Popover>
//   <VirtualList each={rows} by={r -> r.id} estimate={44} selected={sel}>{(row, i) -> ...}</VirtualList>
export declare class UiFlow {
	// a long list in a scroller (helder.ui.VirtualScroll): only the rows in
	// view are made, and overscan more on each side (3); rows that leave are
	// hidden and kept (keep of them, 64, the farthest let go first), by key
	// as For keeps them: by the item itself, by what by gives for it (a
	// row's Read then its key's latest item: a change to one item changes
	// its row alone), or keyed={false} by index. Its rows' heights are their
	// own, estimated (estimate, 44 pixels) until each is measured, the scroll
	// anchored to the row in view (an estimate made real, rows put in or
	// taken out above it: nothing moves); itemHeight: every row that high.
	// height pixels high, else it grows in its parent from 0 (flex: 1). A
	// listbox of options to assistive technology (label: its name), each
	// with its place among all of them; Up, Down, Page Up and Down, Home
	// and End move the focus to a row (made if need be), selected (the key
	// of the row selected: written as the focus moves, a row pressed) and
	// onActivate (Enter, Space) given its item. Its child function gets a
	// row's item (a Read) and its index when made; ref the VirtualScroll
	// (scrollToIndex, focusIndex, the window).
	static VirtualList<T>(props: { each: Read<T[]>; children: (arg0: Read<T>, arg1: number) => unknown; by?: (arg0: T) => any; keyed?: boolean; estimate?: number; itemHeight?: number; height?: number; overscan?: number; keep?: number; selected?: Signal<any>; onActivate?: (arg0: T) => void; label?: string; ref?: (arg0: VirtualScroll) => void; tag?: string }): unknown;
}

export declare const VirtualList: typeof UiFlow.VirtualList;

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
