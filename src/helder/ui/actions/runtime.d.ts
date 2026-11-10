// What helder/ui/actions (src/helder/ui/actions/index.ts) calls of
// helder.ui's actions, for TypeScript programs (helder.typescript):
// helder.ui.actions.Script. A program imports helder/ui/actions, not this module.
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.
import type {Menu, Node, PlatformMenuItem} from "helder/ui";
import type {View} from "helder/view";

declare const __haxe: {Script: "helder.ui.actions.Script", __module: "helder.ui.actions.TypeScript"};

// helder.ui.actions for TypeScript programs (helder/ui/actions:
// src/helder/ui/actions/index.ts, which a program imports; this is its
// runtime, helder/ui/actions/runtime). A program's actions are objects,
// {type: "zoomTo", percent: 100}, made and recognised by index.ts's
// functions (each space's form: which action a value is, its arguments, a
// value of them), and its spaces Haxe's (ActionSpace): a definition's
// (define, its handler's output), and StandardAction's, whose values the
// program's handlers are given as its objects (mirror). The rest are
// helder.ui's: handlers, keymaps, dispatch, menus.
export declare class Script {
	// a program's actions(namespace, {...}): its definition's output
	// (ActionsDefinition.toJson), its values the program's (form: which
	// action one is, its arguments, one made of them, two the same)
	static define(json: string, index: (arg0: any) => number, args: (arg0: any) => any[], make: (arg0: number, arg1: any[]) => any, same: (arg0: number, arg1: any, arg2: any) => boolean): unknown;
	// StandardAction's actions (standard::Quit...)
	static standard(): unknown;
	// a space's actions as the definition's output describes them (JSON)
	static info(space: unknown): string;
	// a Haxe space's values as the program's objects (the form index.ts made for it)
	static mirror(space: unknown, index: (arg0: any) => number, args: (arg0: any) => any[], make: (arg0: number, arg1: any[]) => any): void;
	// a handler of space's actions (for <view actions={...}>): run takes one
	// (true) or lets it bubble (false), state what a menu shows it as
	static handle(space: unknown, run: (arg0: any) => boolean, state?: (arg0: any) => number): unknown;
	// a node's handler (Node.on: a ref's node), removed by the function returned
	static on(node: Node, space: unknown, run: (arg0: any) => boolean, state?: (arg0: any) => number): (() => void);
	// a window's handler (Ui.on), after its tree's
	static onWindow(ui: unknown, space: unknown, run: (arg0: any) => boolean, state?: (arg0: any) => number): (() => void);
	// the app's handler (Actions.on), after every window's
	static onApp(space: unknown, run: (arg0: any) => boolean, state?: (arg0: any) => number): (() => void);
	// "viewer::ZoomTo"
	static name(action: any): string;
	// an action of a keymap's JSON: "viewer::Next", ["viewer::ZoomTo", 100]
	static parse(json: string): any;
	static equals(a: any, b: any): boolean;
	// the app's keymap, every window's unless given its own
	static global(): unknown;
	static keymap(): unknown;
	// a default binding (keys "secondary-o", "ctrl-k ctrl-s"; null unbinds them there)
	static bind(keymap: unknown, keys: string, action: any, context?: string): void;
	// a user's JSON keymap, after the defaults
	static setUser(keymap: unknown, json: string): void;
	// a user's keymap file, read again when it changes (UiWindow polls it)
	static loadUser(keymap: unknown, path: string): void;
	// the keys of action's best binding as a menu shows them ("Ctrl+O"), null: none
	static label(keymap: unknown, action: any, context?: string): string | null;
	// the keymap's bindings as text ("ctrl-k ctrl-s -> viewer::Next in Editor")
	static bindings(keymap: unknown): string[];
	// on macOS secondary is Command (Keymap.mac, known at start)
	static setMac(mac: boolean): void;
	// the Ui a node is in (a ref's, once mounted: its window's), null: none
	static uiOf(node: Node): unknown | null;
	// a Ui of no window (tests), its text helder's own (helder.story's, the same on every system)
	static headless(width: number, height: number): unknown;
	static root(ui: unknown): Node;
	// content rendered into its root and laid out (dispose removes it)
	static mount(ui: unknown, content: View): (() => void);
	static setKeymap(ui: unknown, keymap: unknown): void;
	static layout(ui: unknown): void;
	// the focus given to node
	static focus(node: Node): void;
	// the node of a tag under node (the first, depth first), null: none
	static find(node: Node, tag: string): Node | null;
	// each keystroke of keys typed ("ctrl-k ctrl-s"), through the keymap
	static type(ui: unknown, keys: string): void;
	// action dispatched from the focus (or from), true: a handler took it
	static dispatch(ui: unknown, action: any, from?: Node): boolean;
	// what a menu shows action as from the focus (or from): ActionState
	static state(ui: unknown, action: any, from?: Node): number;
	static item(label: string, action: any): unknown;
	static separator(): unknown;
	static submenu(label: string, items: unknown[]): unknown;
	// a standard item ("about", "quit", "copy"...: MenuRole's), its label the platform's unless given
	static role(role: string, label?: string): unknown;
	// a menu of the bar (role "window": the window menu)
	static menu(label: string, items: unknown[], role?: string): Menu;
	// the items as the platform's menus take them: labels, shortcuts, states
	static resolve(ui: unknown, items: unknown[], from?: Node): PlatformMenuItem[];
	// a context menu at x, y for from (default: the focus)
	static popup(ui: unknown, items: unknown[], x: number, y: number, from?: Node): void;
	// the window's menu bar (the platform's, else drawn at the top of its root)
	static menuBar(ui: unknown, menus: Menu[]): unknown;
	static setMenus(bar: unknown, menus: Menu[]): void;
}
