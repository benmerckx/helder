package helder.ui;

// What hears a PlatformEditor (EditableText)
interface PlatformEditorListener {
	// the text edited by the user, its selection after
	function editorEdited(text:String, start:Int, end:Int):Void;
	// the editor took (true) or lost (false) the keyboard's focus by the user's doing
	function editorFocused(on:Bool):Void;
	// a key the editor leaves to the program (Tab, Escape, Enter on one line, Up and Down): as Ui.keyDown takes it
	function editorKey(key:Int, mods:Int):Void;
}
