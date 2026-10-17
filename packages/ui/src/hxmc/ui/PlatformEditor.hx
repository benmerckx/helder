package hxmc.ui;

// A native text editor: the theme draws its box, the editor its text (in
// the box's font, colour and alignment, with no border or background of
// its own) inside the box's padding. Its events go to the listener.
interface PlatformEditor {
	function listen(l:PlatformEditorListener):Void;
	// its text and selection, from the program
	function setText(text:String, start:Int, end:Int):Void;
	// its place in the window's coordinates (logical pixels); hidden: not shown (covered, or out of view)
	function place(x:Float, y:Float, width:Float, height:Float, shown:Bool):Void;
	function setStyle(font:Font, color:Color, placeholder:String, placeholderColor:Color, align:TextAlign, secret:Bool):Void;
	// the keyboard's focus given (true) or taken back for the drawn tree (false)
	function focus(on:Bool):Void;
	function dispose():Void;
}
