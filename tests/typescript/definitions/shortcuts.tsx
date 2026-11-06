// actions(namespace, {...}) in TypeScript (Shortcuts.hx prints the same):
// a program's actions bound in a keymap (its defaults, then a user's JSON
// with arguments), typed into a headless window and dispatched from the
// focus up to a TSX handler; StandardAction's beside them; names, labels,
// the JSON's actions and a menu's items with their keys and states.
import {
	actions, type ActionOf, handle, Keymap, Standard, headless, mount, rootOf, setKeymap, find, focus, press, dispatch, stateOf,
	actionName, parseAction, sameAction, item, separator, role, resolve, MenuBar, Enabled, Disabled, Checked, Unchecked
} from "helder/ui/actions";

export const Viewer = actions("viewer", {
	next() {},
	zoomTo(percent: number) {
		return {percent};
	},
	move(to: {x: number; y: number}) {
		return {to};
	},
	open(path: string, tags: string[]) {
		return {path, tags};
	},
});
export type ViewerAction = ActionOf<typeof Viewer>;

function show(a: ViewerAction): string {
	switch (a.type) {
		case "next":
			return "next";
		case "zoomTo":
			return `zoomTo ${a.percent}`;
		case "move":
			return `move ${a.to.x},${a.to.y}`;
		case "open":
			return `open ${a.path} [${a.tags.join(",")}]`;
	}
}

const log: string[] = [];
let zoomed = false;
const ui = headless(200, 200);
const keymap = new Keymap().bind("n", Viewer.next(), "Viewer").bind("ctrl-k ctrl-z", Viewer.zoomTo(50), "Viewer").bind("1", Viewer.zoomTo(100))
	.bind("q", Standard.quit());
keymap.setUser(`[{"context": "Viewer", "bindings": {"2": ["viewer::ZoomTo", 200], "m": ["viewer::Move", {"x": 3, "y": 4}],
	"o": ["viewer::Open", ["a.png", ["x", "y"]]], "1": null}}]`);
setKeymap(ui, keymap);
mount(ui, <view key-context="Viewer" actions={[handle(Viewer, a => {
	log.push(show(a));
	if (a.type === "zoomTo") zoomed = !zoomed;
	return a.type !== "open";
}, a => a.type === "next" ? Disabled : a.type === "zoomTo" ? (zoomed ? Checked : Unchecked) : Enabled), handle(Standard, a => {
	log.push(actionName(a));
	return true;
})]}>
	<view tag="image" focusable width={20} height={20}/>
</view>);
focus(find(rootOf(ui), "image"));
for (const keys of ["n", "1", "2", "ctrl-k ctrl-z", "m", "o", "q"]) press(ui, keys);
console.log(log.join("\n"));
console.log(dispatch(ui, Viewer.move({x: 1, y: 2})), dispatch(ui, Viewer.open("b", [])), stateOf(ui, Viewer.next()), stateOf(ui, Viewer.zoomTo(1)));
console.log(keymap.bindings().join("\n"));
console.log(keymap.label(Viewer.zoomTo(200), "Viewer"), keymap.label(Viewer.zoomTo(50), "Viewer"), keymap.label(Viewer.zoomTo(100)), keymap.label(Standard.quit()));
const parsed = parseAction(`["viewer::ZoomTo", 7]`);
console.log(actionName(parsed), sameAction(parsed, Viewer.zoomTo(7)), sameAction(parsed, Viewer.zoomTo(8)), actionName(parseAction(`"standard::Copy"`)));
for (const it of resolve(ui, [item("Next", Viewer.next()), separator, item("Zoom", Viewer.zoomTo(200)), item("Open", Viewer.open("a.png", ["x", "y"])), role("quit")]))
	console.log(it.separator ? "-" : `${it.label}: ${it.shortcut ?? "-"}, ${it.disabled ? "disabled" : "enabled"}${it.checked === undefined ? "" : it.checked ? ", checked" : ", unchecked"}`);
// (a menu bar: F10 bound to its own action, menu::OpenMenuBar)
new MenuBar(ui, [{label: "View", items: [item("Zoom", Viewer.zoomTo(200))]}]);
console.log(keymap.label(parseAction(`"menu::OpenMenuBar"`)));
