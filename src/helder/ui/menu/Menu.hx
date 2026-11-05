package helder.ui.menu;

import helder.ui.actions.Actions;

// One menu model for the menu bar and context menus (Menus): items bound
// to actions (helder.ui.actions), each shown with the keys the keymap binds
// to it and enabled or checked as the handler that would take it says
// (Ui.actionState, from the focus, or the node a context menu is for);
// separators, submenus, and roles: the standard items each platform has
// (StandardAction's, in the platform's place where it has one: macOS's
// application menu for About and Quit, its Window menu; its text editors'
// copy: and paste:).
enum MenuItem {
	Item(label:String, action:EnumValue);
	Separator;
	Submenu(label:String, items:Array<MenuItem>);
	Role(role:MenuRole, ?label:String);
}

// a menu of the menu bar; role Window: the window menu (macOS's: its own
// items after Minimize, Zoom and Close)
typedef Menu = {label:String, items:Array<MenuItem>, ?role:MenuRole};

enum abstract MenuRole(String) to String {
	var About = "about";
	var Quit = "quit";
	var Hide = "hide";
	var Undo = "undo";
	var Redo = "redo";
	var Cut = "cut";
	var Copy = "copy";
	var Paste = "paste";
	var SelectAll = "select-all";
	var Minimize = "minimize";
	var Zoom = "zoom";
	var Fullscreen = "fullscreen";
	var CloseWindow = "close";
	var Window = "window";

	// the action it dispatches
	public function action():Null<StandardAction>
		return switch (cast this : MenuRole) {
			case About: StandardAction.About;
			case Quit: StandardAction.Quit;
			case Hide: StandardAction.Hide;
			case Undo: StandardAction.Undo;
			case Redo: StandardAction.Redo;
			case Cut: StandardAction.Cut;
			case Copy: StandardAction.Copy;
			case Paste: StandardAction.Paste;
			case SelectAll: StandardAction.SelectAll;
			case Minimize: StandardAction.Minimize;
			case Zoom: StandardAction.Zoom;
			case Fullscreen: StandardAction.ToggleFullscreen;
			case CloseWindow: StandardAction.CloseWindow;
			case Window: null;
		}

	// its label where the model gives none (app: the app's name)
	public function label(app:String):String
		return switch (cast this : MenuRole) {
			case About: "About " + app;
			case Quit: "Quit " + app;
			case Hide: "Hide " + app;
			case Undo: "Undo";
			case Redo: "Redo";
			case Cut: "Cut";
			case Copy: "Copy";
			case Paste: "Paste";
			case SelectAll: "Select All";
			case Minimize: "Minimize";
			case Zoom: "Zoom";
			case Fullscreen: "Full Screen";
			case CloseWindow: "Close Window";
			case Window: "Window";
		}
}
