// Tables: drizzle-kit studio's server in a window, written in TypeScript.
// `tables [url]`, the server at http://127.0.0.1:4983 unless given
import { UiWindow, Surface, MenuBarView, Theme } from "helder/ui";
import { actions, handle, item, role, separator, submenu, Keymap, Checked, Unchecked, Enabled, Disabled } from "helder/ui/actions";
import { font } from "helder/asset";
import { App } from "helder/scene/runtime";
import { platform } from "helder/platform";
import { args } from "helder/os";
import { Tables, setMac } from "./tables";
import { view, focusSearch, focusFilter } from "./shell";

// Hanken Grotesk for the interface, Geist Mono for values
font("fonts/HankenGrotesk-Regular.ttf");
font("fonts/HankenGrotesk-Medium.ttf");
font("fonts/GeistMono-Regular.ttf");

setMac(platform.os === "macos");

const Do = actions("tables", {
	save() { return {}; },
	discard() { return {}; },
	refresh() { return {}; },
	search() { return {}; },
	filter() { return {}; },
	back() { return {}; },
	run() { return {}; },
	data() { return {}; },
	structure() { return {}; },
	query() { return {}; },
	undo() { return {}; },
	panel() { return {}; },
	appearance(kind: string) { return { kind }; }
});
Keymap.global.bind("secondary-s", Do.save())
	.bind("secondary-r", Do.refresh())
	.bind("secondary-k", Do.search())
	.bind("secondary-f", Do.filter())
	.bind("secondary-[", Do.back())
	.bind("secondary-enter", Do.run())
	.bind("secondary-1", Do.data())
	.bind("secondary-2", Do.structure())
	.bind("secondary-3", Do.query())
	.bind("secondary-z", Do.undo())
	.bind("secondary-i", Do.panel());

const given = args().length > 0 && !args()[0].startsWith("--") ? args()[0] : null;
const app = new Tables(given === null ? "http://127.0.0.1:4983/" : given.startsWith("http") ? given : "http://" + given);
app.focusFilter = focusFilter;
// (the colours given inline follow the appearance chosen, as the sheet's do)
Theme.appearance = () => app.dark();
// (an error nothing caught: said in the status bar, the app going on)
App.onError = (e, source) => {
	console.log(`tables: ${source}: ${e instanceof Error ? e.stack : e}`);
	app.say("Something went wrong: " + String(e), true);
	return true;
};
app.start();

// the menu bar: File, Edit, View (its views, the row panel, the appearance)
const menus = [
	{ label: "File", items: [item("Save Changes", Do.save()), item("Discard Changes", Do.discard()), separator, item("Refresh", Do.refresh()), separator, role("quit")] },
	{ label: "Edit", items: [item("Undo", Do.undo()), separator, role("cut"), role("copy"), role("paste"), role("select-all")] },
	{
		label: "View",
		items: [
			item("Data", Do.data()), item("Structure", Do.structure()), item("SQL", Do.query()), separator, item("Row Panel", Do.panel()), item("Back", Do.back()), separator,
			item("Search Tables", Do.search()), item("Filter Rows", Do.filter()), separator,
			submenu("Appearance", [item("System", Do.appearance("system")), item("Light", Do.appearance("light")), item("Dark", Do.appearance("dark"))])
		]
	},
	{ label: "Window", role: "window" as const, items: [] }
];

UiWindow.run(
	<Surface title="Tables" width={1180} height={740} titlebar="inset" theme={Theme.sheet} background={Theme.c("canvas")} dark={app.dark()}>
		<view grow={1} actions={handle(Do, a => {
			switch (a.type) {
				case "save": app.save(); break;
				case "discard": app.discard(); break;
				case "refresh": app.mode.peek() === "sql" ? app.run() : app.refresh(); break;
				case "search": focusSearch(); break;
				case "filter": if (app.mode.peek() === "data") focusFilter(); break;
				case "back": app.back(); break;
				case "run": if (app.mode.peek() === "sql") app.run(); break;
				case "data": app.mode("data"); break;
				case "structure": app.mode("structure"); break;
				case "query": app.mode("sql"); break;
				case "undo": if (app.mode.peek() === "data") app.undo(); break;
				case "panel":
					app.mode("data");
					app.panel(!app.panel.peek());
					break;
				case "appearance": app.appear(a.kind); break;
			}
			return true;
		}, a => {
			switch (a.type) {
				case "data": return app.mode.peek() === "data" ? Checked : Unchecked;
				case "structure": return app.mode.peek() === "structure" ? Checked : Unchecked;
				case "query": return app.mode.peek() === "sql" ? Checked : Unchecked;
				case "panel": return app.panel.peek() ? Checked : Unchecked;
				case "appearance": return app.appearance.peek() === a.kind ? Checked : Unchecked;
				case "save": case "discard": case "undo": return app.changes.peek() > 0 ? Enabled : Disabled;
				case "back": return app.canBack.peek() ? Enabled : Disabled;
				case "run": return app.mode.peek() === "sql" ? Enabled : Disabled;
				default: return Enabled;
			}
		})}>
			<MenuBarView menus={menus}/>
			{view(app)}
		</view>
	</Surface>
);
