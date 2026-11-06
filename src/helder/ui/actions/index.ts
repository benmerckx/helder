// helder.ui's actions for TypeScript programs: `actions(namespace, {...})`,
// a definition (helder's compiler checks and compiles it with the program:
// helder.ui.actions.ActionsDefinition, the handler Haxe's
// `actions("viewer", ViewerAction)` runs), its methods the actions and
// their parameters the arguments. A method with arguments returns them as
// an object, `{percent}`: that is what TypeScript types the action as (a
// type has no parameter names). The bodies are never run.
//
//   import { actions, type ActionOf, handle, Keymap } from "helder/ui/actions";
//
//   export const Viewer = actions("viewer", {
//     next() {},
//     zoomTo(percent: number) { return { percent }; },
//   });
//   export type ViewerAction = ActionOf<typeof Viewer>;   // {type: "next"} | {type: "zoomTo", percent: number}
//
//   Keymap.global.bind("1", Viewer.zoomTo(100), "Viewer");
//   <view key-context="Viewer" actions={handle(Viewer, a => {
//     switch (a.type) {
//       case "next": next(); return true;
//       case "zoomTo": zoom(a.percent); return true;
//     }
//   })}>...</view>
//
// The namespace is an identifier, declared once in the program, and each
// argument one a JSON keymap can give (numbers, strings, booleans, arrays
// and objects of these): ["viewer::ZoomTo", 100]. Actions are dispatched
// through helder.ui's focus tree as Haxe's are (src/helder/ui/README.md:
// a node's handlers, its ancestors', the window's, the app's), shown by its
// menus with their keys and their handlers' states. `Standard` is
// StandardAction's (standard::Quit, standard::Copy...).
import { Script } from "helder/ui/actions/runtime";

// an action's arguments (a method's), as an object (its result)
type Method = (...args: any[]) => object | void;
export type ActionsDef = { readonly [name: string]: Method };

type Flat<T> = { [P in keyof T]: T[P] };
type Value<K, F> = F extends (...args: any[]) => infer R ? Flat<{ type: K } & (R extends object ? R : {})> : never;

// what actions(...) gives: a function per action making its value
export type Actions<D> = { readonly [K in keyof D & string]: D[K] extends (...args: infer P) => any ? (...args: P) => Value<K, D[K]> : never };

// the actions' values: {type: "next"} | {type: "zoomTo", percent: number}
export type ActionOf<A> = { [K in keyof A]: A[K] extends (...args: any[]) => infer V ? V : never }[keyof A];

// any action
export type Action = { readonly type: string };

// what a menu shows an action as (the handler that would take it says)
export type ActionState = 0 | 1 | 2 | 3 | 4;
export const Unhandled: ActionState = 0;
export const Disabled: ActionState = 1;
export const Enabled: ActionState = 2;
export const Checked: ActionState = 3;
export const Unchecked: ActionState = 4;

// a handler of one kind's actions (a node's: <view actions={...}>)
export type ActionHandler = { readonly __actionHandler: true };

type Info = { namespace: string; actions: { name: string; type: string; params: { name: string }[] }[] };
type Space = { readonly __space: true };

// (each actions(...)'s Haxe space, by the object of its functions)
const spaces = new Map<object, Space>();

// the objects of a space's values: the prototype they share, and the
// functions helder.ui recognises and makes them with
// (two arguments the same: JSON's values, compared as JSON compares them)
function same(a: unknown, b: unknown): boolean {
	if (a === b) return true;
	if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
	if (Array.isArray(a) || Array.isArray(b)) {
		if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
		return a.every((x, i) => same(x, b[i]));
	}
	const x = a as Record<string, unknown>, y = b as Record<string, unknown>;
	const keys = Object.keys(x).filter(k => x[k] !== undefined && x[k] !== null);
	return keys.length === Object.keys(y).filter(k => y[k] !== undefined && y[k] !== null).length && keys.every(k => same(x[k], y[k]));
}

type Form = {
	index: (v: any) => number;
	args: (v: any) => unknown[];
	make: (i: number, args: unknown[]) => unknown;
	same: (i: number, a: any, b: any) => boolean;
};

function form(info: Info): Form {
	const proto = {};
	const types = info.actions.map(a => a.type);
	return {
		index: v => (typeof v === "object" && v !== null && Object.getPrototypeOf(v) === proto ? types.indexOf(v.type) : -1),
		args: v => info.actions[types.indexOf(v.type)].params.map(p => v[p.name]),
		make: (i, args) => {
			const o = Object.create(proto);
			o.type = types[i];
			info.actions[i].params.forEach((p, k) => (o[p.name] = args[k]));
			return o;
		},
		same: (i, a, b) => info.actions[i].params.every(p => same(a[p.name], b[p.name])),
	};
}

function constructors(info: Info, make: (i: number, args: unknown[]) => unknown, space: Space): any {
	const out: any = {};
	info.actions.forEach((a, i) => (out[a.type] = (...args: unknown[]) => make(i, args)));
	spaces.set(out, space);
	return out;
}

// a program's actions: a definition (its argument an object literal of methods)
export function actions<const D extends ActionsDef>(namespace: string, def: D, generated?: string): Actions<D> {
	if (generated === undefined) throw new Error("actions: a definition, compiled by helder's compiler (its argument an object literal)");
	const info: Info = JSON.parse(generated);
	const f = form(info);
	return constructors(info, f.make, Script.define(generated, f.index, f.args, f.make, f.same) as Space);
}

// StandardAction's actions: the menus' roles, the window's and the text fields' (standard::Quit...)
export const Standard: Actions<{
	about(): void;
	quit(): void;
	hide(): void;
	hideOthers(): void;
	showAll(): void;
	closeWindow(): void;
	minimize(): void;
	zoom(): void;
	toggleFullscreen(): void;
	undo(): void;
	redo(): void;
	cut(): void;
	copy(): void;
	paste(): void;
	selectAll(): void;
}> = (() => {
	const space = Script.standard() as Space;
	const info: Info = JSON.parse(Script.info(space as any));
	const f = form(info);
	Script.mirror(space as any, f.index, f.args, f.make);
	return constructors(info, f.make, space);
})();
export type StandardAction = ActionOf<typeof Standard>;

function spaceOf(type: object): any {
	const s = spaces.get(type);
	if (s === undefined) throw new Error("helder/ui/actions: not an actions(...) object");
	return s;
}

// a handler of type's actions, for a node (<view actions={handle(Viewer, a => ...)}>):
// run takes one (true) or lets it bubble on (false); state what a menu shows it as
export function handle<A extends object>(type: A, run: (a: ActionOf<A>) => boolean, state?: (a: ActionOf<A>) => ActionState): ActionHandler {
	return Script.handle(spaceOf(type), run as (a: any) => boolean, state as ((a: any) => number) | undefined) as any;
}

// a node's handler (a ref's node), removed by the function returned
export function on<A extends object>(node: unknown, type: A, run: (a: ActionOf<A>) => boolean, state?: (a: ActionOf<A>) => ActionState): () => void {
	return Script.on(node as any, spaceOf(type), run as (a: any) => boolean, state as ((a: any) => number) | undefined);
}

// a window's handler (its Ui: uiOf a node in it, a ref's), after its tree's
export function onWindow<A extends object>(ui: Ui, type: A, run: (a: ActionOf<A>) => boolean, state?: (a: ActionOf<A>) => ActionState): () => void {
	return Script.onWindow(ui as any, spaceOf(type), run as (a: any) => boolean, state as ((a: any) => number) | undefined);
}

// the app's handler, after every window's
export function onApp<A extends object>(type: A, run: (a: ActionOf<A>) => boolean, state?: (a: ActionOf<A>) => ActionState): () => void {
	return Script.onApp(spaceOf(type), run as (a: any) => boolean, state as ((a: any) => number) | undefined);
}

// an action's name in a keymap: "viewer::ZoomTo"
export function actionName(a: Action): string {
	return Script.name(a);
}

// an action of a keymap's JSON: '"viewer::Next"', '["viewer::ZoomTo", 100]'
export function parseAction(json: string): Action {
	return Script.parse(json);
}

// the same action, its arguments equal
export function sameAction(a: Action, b: Action): boolean {
	return Script.equals(a, b);
}

// Key bindings (helder.ui.actions.Keymap): keystroke sequences to actions
// where a context predicate holds; a user's JSON keymap after the defaults
//   [{"context": "Viewer && !picker", "bindings": {"secondary-o": "viewer::Open", "1": ["viewer::ZoomTo", 100]}}]
export class Keymap {
	// (helder.ui's)
	readonly keymap: unknown;
	// the app's keymap, every window's unless given its own
	static readonly global: Keymap = new Keymap(Script.global());

	constructor(keymap?: unknown) {
		this.keymap = keymap ?? Script.keymap();
	}

	// a default binding (keys: "secondary-o", "ctrl-k ctrl-s"; context: a predicate, none: anywhere; null unbinds them there)
	bind(keys: string, action: Action | null, context?: string): Keymap {
		Script.bind(this.keymap as any, keys, action, context);
		return this;
	}

	// a user's JSON keymap, after the defaults (theirs win)
	setUser(json: string): void {
		Script.setUser(this.keymap as any, json);
	}

	// a user's keymap file, read again when it changes
	loadUser(path: string): void {
		Script.loadUser(this.keymap as any, path);
	}

	// the keys a menu shows for an action ("Ctrl+O", "⌘K ⌘S"), where the key contexts are ("Viewer > Editor"); null: none
	label(action: Action, context?: string): string | null {
		return Script.label(this.keymap as any, action, context);
	}

	// its bindings, lowest precedence first: "ctrl-k ctrl-s -> viewer::Next in Editor"
	bindings(): string[] {
		return Script.bindings(this.keymap as any);
	}
}

// whether secondary is Command (macOS: a window sets it) rather than Control
export function setMac(mac: boolean): void {
	Script.setMac(mac);
}

// A window's Ui (helder.ui.Ui), where actions are dispatched
export type Ui = { readonly __ui: true };

// the Ui a node is in (a ref's, once mounted: its window's), null: none
export function uiOf(node: unknown): Ui | null {
	return Script.uiOf(node as any) as any;
}

// a Ui of no window (tests), its root to render into, its keymap
export function headless(width: number, height: number): Ui {
	return Script.headless(width, height) as any;
}
export function rootOf(ui: Ui): unknown {
	return Script.root(ui as any);
}
// content (TSX) rendered into its root and laid out, removed by the function returned
export function mount(ui: Ui, content: unknown): () => void {
	return Script.mount(ui as any, content as any);
}
export function setKeymap(ui: Ui, keymap: Keymap): void {
	Script.setKeymap(ui as any, keymap.keymap as any);
}
// its layout updated (a headless one's)
export function update(ui: Ui): void {
	Script.layout(ui as any);
}
// the focus given to a node (a ref's)
export function focus(node: unknown): void {
	Script.focus(node as any);
}
// the first node under node with a tag (depth first), null: none
export function find(node: unknown, tag: string): unknown {
	return Script.find(node as any, tag);
}
// each keystroke of keys typed into the Ui ("ctrl-k ctrl-s"), through its keymap
export function press(ui: Ui, keys: string): void {
	Script.type(ui as any, keys);
}
// an action dispatched from the focus (or from), true: a handler took it
export function dispatch(ui: Ui, action: Action, from?: unknown): boolean {
	return Script.dispatch(ui as any, action, from as any);
}
// what a menu shows an action as, from the focus (or from)
export function stateOf(ui: Ui, action: Action, from?: unknown): ActionState {
	return Script.state(ui as any, action, from as any) as ActionState;
}

// Menus (helder.ui.menu): items bound to actions, each shown with its keys
// and its handler's state; separators, submenus, and the standard items
// each platform has (roles: "about", "quit", "copy", "paste"...)
export type MenuItem = { readonly __menuItem: true };
export type Menu = { label: string; items: MenuItem[]; role?: "window" };
// what a platform's menu is given (helder.ui.platform.PlatformMenuItem)
export type PlatformMenuItem = {
	id: number;
	label: string;
	shortcut?: string;
	disabled?: boolean;
	checked?: boolean;
	separator?: boolean;
	items?: PlatformMenuItem[];
	role?: string;
};

export function item(label: string, action: Action): MenuItem {
	return Script.item(label, action) as any;
}
export const separator: MenuItem = Script.separator() as any;
export function submenu(label: string, items: MenuItem[]): MenuItem {
	return Script.submenu(label, items as any) as any;
}
export function role(name: string, label?: string): MenuItem {
	return Script.role(name, label) as any;
}
// the items as a platform's menu takes them (labels, the keymap's shortcuts, the handlers' states)
export function resolve(ui: Ui, items: MenuItem[], from?: unknown): PlatformMenuItem[] {
	return Script.resolve(ui as any, items as any, from as any) as any;
}
// a context menu at x, y for from (default: the focus)
export function popup(ui: Ui, items: MenuItem[], x: number, y: number, from?: unknown): void {
	Script.popup(ui as any, items as any, x, y, from as any);
}

// a window's menu bar: the platform's (macOS's, Windows'), else drawn at the top of its root
export class MenuBar {
	readonly bar: unknown;
	constructor(ui: Ui, menus: Menu[]) {
		this.bar = Script.menuBar(ui as any, menus.map(m => Script.menu(m.label, m.items as any, m.role)) as any);
	}
	setMenus(menus: Menu[]): void {
		Script.setMenus(this.bar as any, menus.map(m => Script.menu(m.label, m.items as any, m.role)) as any);
	}
}
