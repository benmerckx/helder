package hxmc.ui;

// Where a Ui's widgets copy text to and paste it from (Ui.clipboard): the
// system's in a window (hxmc.ui.draw.UiWindow), a MemoryClipboard otherwise.
// read may answer later (X11, the browser): the callback gets the text, or
// null when there is none.
interface ClipboardHost {
	function write(text:String):Void;
	function read(callback:Null<String>->Void):Void;
}

// a clipboard of the process's own (tests, a Ui without a window)
class MemoryClipboard implements ClipboardHost {
	public var text:Null<String> = null;

	public function new() {}

	public function write(text:String)
		this.text = text;

	public function read(callback:Null<String>->Void)
		callback(text);
}
