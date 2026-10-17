package hxmc.ui;

// The platform's own views inside a drawn tree (Ui.platform; a window
// gives it where its platform has them): native controls placed where
// their nodes are laid out, over the drawn surface. A text editor first.
interface PlatformViews {
	// a native text editor (multiline: a text area's), or null where there is none
	function editor(multiline:Bool):Null<PlatformEditor>;
	// the editors' events since the last call, handed to their listeners
	function poll():Void;
}
