package hxmc.ui;

// An item of a native menu (PlatformViews.menu): its label, its shortcut
// as shown ("Ctrl+C", "⌘C"), whether it is disabled or checked; a
// separator; a submenu's items. id: what the menu reports when it is chosen.
typedef PlatformMenuItem = {id:Int, label:String, ?shortcut:String, ?disabled:Bool, ?checked:Bool, ?separator:Bool, ?items:Array<PlatformMenuItem>};
