import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.draw.UiWindow;
import helder.ui.draw.UiWindow.Surface;
import helder.ui.menu.Menu;
import helder.ui.view.UiFlow.MenuBarView;
import helder.ui.widgets.Theme;
import helder.view.*;
import tables.Shell;
import tables.Tables;

// Tables (apps/tables/README.md): drizzle-kit studio's server in a window.
// `tables [url]`, the server at http://127.0.0.1:4983 unless given
class Main implements Markup {
	static function main() {
		var args = Sys.args();
		var url = args.length > 0 && !StringTools.startsWith(args[0], "--") ? args[0] : "http://127.0.0.1:4983/";
		if (!StringTools.startsWith(url, "http")) url = "http://" + url;
		fonts();
		actions("tables", TablesAction);
		Keymap.global.bind("secondary-s", Save)
			.bind("secondary-r", Refresh)
			.bind("secondary-k", Search)
			.bind("secondary-f", Filter)
			.bind("secondary-[", Back)
			.bind("secondary-enter", Run)
			.bind("secondary-1", Data)
			.bind("secondary-2", Structure)
			.bind("secondary-3", Query)
			.bind("secondary-z", Undo)
			.bind("secondary-i", Panel);
		var app = new Tables(url);
		// (the colours given inline follow the appearance chosen, as the sheet's do)
		Theme.appearance = () -> app.dark();
		app.start();
		// (an error nothing caught: its stack printed, said in the status bar, the app going on)
		helder.os.App.onError = (e, source) -> {
			Sys.stderr().writeString('tables: $source: ${e.details()}\n');
			app.say("Something went wrong: " + e.message, true);
			true;
		};
		UiWindow.run(<Surface title="Tables" width={1180} height={740} titlebar="inset" theme={Theme.sheet} background={Theme.c("canvas")}
			dark={app.dark()}>
			<view grow={1} actions={[Actions.handle(TablesAction, a -> {
				switch a {
					case Save: app.save();
					case Discard: app.discard();
					case Refresh: app.mode.peek() == "sql" ? app.run() : app.refresh();
					case Search: Shell.focusSearch();
					case Filter: if (app.mode.peek() == "data") Shell.focusFilter();
					case Back: app.back();
					case Run: if (app.mode.peek() == "sql") app.run();
					case Data: app.mode("data");
					case Structure: app.mode("structure");
					case Query: app.mode("sql");
					case Undo: if (app.mode.peek() == "data") app.undo();
					case Panel:
						app.mode("data");
						app.panel(!app.panel.peek());
					case Appearance(kind): app.appear(kind);
				}
				true;
			}, a -> switch a {
				case Data: app.mode.peek() == "data" ? Checked : Unchecked;
				case Structure: app.mode.peek() == "structure" ? Checked : Unchecked;
				case Query: app.mode.peek() == "sql" ? Checked : Unchecked;
				case Panel: app.panel.peek() ? Checked : Unchecked;
				case Appearance(kind): app.appearance.peek() == kind ? Checked : Unchecked;
				case Save | Discard | Undo: app.changes.peek() > 0 ? Enabled : Disabled;
				case Back: app.canBack.peek() ? Enabled : Disabled;
				case Run: app.mode.peek() == "sql" ? Enabled : Disabled;
				case _: Enabled;
			})]}>
				<MenuBarView menus={menus()}/>
				{Shell.view(app)}
			</view>
		</Surface>);
	}

	// the menu bar: File, Edit, View (its views, the row panel, the appearance)
	static function menus():Array<Menu>
		return [
			{label: "File", items: [Item("Save Changes", Save), Item("Discard Changes", Discard), Separator, Item("Refresh", Refresh), Separator, Role(Quit)]},
			{label: "Edit", items: [Item("Undo", Undo), Separator, Role(Cut), Role(Copy), Role(Paste), Role(SelectAll)]},
			{
				label: "View",
				items: [
					Item("Data", Data), Item("Structure", Structure), Item("SQL", Query), Separator, Item("Row Panel", Panel), Item("Back", Back), Separator,
					Item("Search Tables", Search), Item("Filter Rows", Filter), Separator,
					Submenu("Appearance", [Item("System", Appearance("system")), Item("Light", Appearance("light")), Item("Dark", Appearance("dark"))])
				]
			},
			{label: "Window", role: Window, items: []}
		];

	// Hanken Grotesk for the interface, Geist Mono for values (apps/tables/fonts)
	static function fonts() {
		var f = helder.text.SystemFonts.get();
		for (b in [
			helder.asset.Asset.embed("fonts/HankenGrotesk-Regular.ttf"),
			helder.asset.Asset.embed("fonts/HankenGrotesk-Medium.ttf"),
			helder.asset.Asset.embed("fonts/GeistMono-Regular.ttf")
		])
			try f.add(b) catch (_:Dynamic) {}
	}
}

enum TablesAction {
	Save;
	Discard;
	Refresh;
	Search;
	Filter;
	Back;
	Run;
	Data;
	Structure;
	Query;
	Undo;
	Panel;
	// "system", "light" or "dark"
	Appearance(kind:String);
}
