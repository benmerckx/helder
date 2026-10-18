package hxmc.ui;

// The platform's own views inside a drawn tree (Ui.platform; a window
// gives it where its platform has them): native controls placed where
// their nodes are laid out, over the drawn surface: text editors; and its
// menus.
interface PlatformViews {
	// a native text editor (multiline: a text area's), or null where there is none
	function editor(multiline:Bool):Null<PlatformEditor>;
	// the editors' events since the last call, handed to their listeners;
	// a menu asked for since, shown (it may wait there until dismissed)
	function poll():Void;
	// a native menu at x, y (the window's layout pixels; shown at the next
	// poll), chosen then called with the chosen item's id, or -1 when it is
	// dismissed; false where there is none
	function menu(items:Array<PlatformMenuItem>, x:Float, y:Float, chosen:Int->Void):Bool;
}
