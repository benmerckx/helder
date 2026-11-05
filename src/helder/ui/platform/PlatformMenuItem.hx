package helder.ui.platform;

// An item of a native menu (PlatformViews.menu): its label, its shortcut
// as shown ("Ctrl+C", "⌘C") and as keys (a menu that takes its keys
// itself: macOS's key equivalents), whether it is disabled or checked; a
// separator; a submenu's items. id: what the menu reports when it is chosen.
// role: a standard item's (helder.ui.menu.MenuRole: "about", "quit",
// "copy", "window" for a menu bar's window menu...), which a platform puts
// in its own place or gives its own behaviour (macOS).
typedef PlatformMenuItem = {id:Int, label:String, ?shortcut:String, ?keys:helder.ui.actions.Keystroke, ?disabled:Bool, ?checked:Bool, ?separator:Bool,
	?items:Array<PlatformMenuItem>, ?role:String};
