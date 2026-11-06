package viewer;

import helder.ui.actions.Actions;
import helder.ui.actions.Keymap;
import helder.ui.menu.Menu;

// The viewer's actions (helder.ui.actions: viewer::Next... in a keymap),
// its default keymap, its menus and its context menu. The keys and the
// menus' shortcuts are one: the keymap's (a user's file over it:
// ~/.config/helder-viewer/keymap.json, Store's folder elsewhere).
enum ViewerAction {
	Open;
	OpenRecent(path:String);
	Next;
	Previous;
	First;
	Last;
	ZoomIn;
	ZoomOut;
	Fit;
	ActualSize;
	ToggleFullscreen;
	LeaveFullscreen;
	ToggleStatus;
	ClosePicker;
	NextPage;
	PreviousPage;
	FirstPage;
	LastPage;
	GoToPage;
	CloseGoTo;
	CopyPath;
	ShowInFolder;
	OpenWithDefault;
}

class ViewerActions {
	static var declared = false;

	// the viewer's default bindings, in keymap (once): the root's context is
	// "Viewer", with picker while the picker is open, fullscreen while it is,
	// pdf while a document of several pages is shown, goto while its go to
	// page card is open
	public static function defaults(keymap:Keymap) {
		if (declared) return;
		declared = true;
		Actions.declare("viewer", ViewerAction);
		var here = "Viewer && !picker && !goto";
		keymap.bind("secondary-o", Open, "Viewer");
		for (k in ["space", "pagedown", "down", "right"])
			keymap.bind(k, Next, here);
		for (k in ["backspace", "pageup", "up", "left"])
			keymap.bind(k, Previous, here);
		keymap.bind("home", First, here);
		keymap.bind("end", Last, here);
		// (+ and -: whichever key the layout has them on, Mod with them too; the last is what menus show)
		for (k in ["secondary-=", "secondary-shift-=", "secondary-+", "=", "shift-=", "shift-+", "+"])
			keymap.bind(k, ZoomIn, here);
		for (k in ["secondary--", "shift--", "-"])
			keymap.bind(k, ZoomOut, here);
		keymap.bind("secondary-0", Fit, here);
		keymap.bind("0", Fit, here);
		keymap.bind("1", ActualSize, here);
		keymap.bind("enter", ToggleFullscreen, here);
		keymap.bind("ctrl-cmd-f", ToggleFullscreen, here);
		keymap.bind("f11", ToggleFullscreen, here);
		keymap.bind("escape", LeaveFullscreen, "Viewer && fullscreen && !picker");
		keymap.bind("i", ToggleStatus, here);
		keymap.bind("escape", ClosePicker, "Viewer && picker");
		// (a PDF's pages: Page Down and Up, Space and Backspace page through it, the arrows still the folder's files)
		var pdf = "Viewer && pdf && !picker && !goto";
		for (k in ["pagedown", "space", "]"])
			keymap.bind(k, NextPage, pdf);
		for (k in ["pageup", "backspace", "shift-space", "["])
			keymap.bind(k, PreviousPage, pdf);
		keymap.bind("secondary-home", FirstPage, pdf);
		keymap.bind("secondary-end", LastPage, pdf);
		keymap.bind("secondary-g", GoToPage, pdf);
		keymap.bind("g", GoToPage, pdf);
		keymap.bind("escape", CloseGoTo, "Viewer && goto");
		keymap.bind("secondary-shift-c", CopyPath, here);
		// (macOS: Command-Q is the application menu's)
		if (!Keymap.mac) keymap.bind("secondary-q", StandardAction.Quit);
	}

	// the menu bar: File (Open, Open Recent, Quit), View
	public static function menus(recent:Array<String>):Array<Menu> {
		var open:Array<MenuItem> = [Item("Open…", Open)];
		if (recent.length > 0) open.push(Submenu("Open Recent", [for (r in recent) Item(haxe.io.Path.withoutDirectory(r), OpenRecent(r))]));
		return [
			{label: "File", items: open.concat([Separator, Role(Quit)])},
			{
				label: "View",
				items: [
					Item("Fit", Fit), Item("Actual Size", ActualSize), Item("Zoom In", ZoomIn), Item("Zoom Out", ZoomOut), Separator,
					Item("Previous", Previous), Item("Next", Next), Separator, Item("Previous Page", PreviousPage), Item("Next Page", NextPage),
					Item("Go to Page…", GoToPage), Separator, Item("Full Screen", ToggleFullscreen), Item("Status Line", ToggleStatus)
				]
			}
		];
	}

	// the image's context menu
	public static final context:Array<MenuItem> = [
		Item("Copy Path", CopyPath),
		Item(Sys.systemName() == "Mac" ? "Show in Finder" : Sys.systemName() == "Windows" ? "Show in Explorer" : "Show in Folder", ShowInFolder),
		Item("Open with Default App", OpenWithDefault), Separator, Item("Fit", Fit), Item("Actual Size", ActualSize)
	];
}
