package hxmc.os;

// A top-level window. Its Surface carries the native handles for hxmc.gfx.
// Linux/X11 for now (hxmc.os.x11.X11Window); Win32, Cocoa, Wayland and the
// browser's canvas come in behind the same class.
class Window {
	public final surface:Surface;
	public var title(default, null):String;
	public var closed(default, null) = false;

	final native:hxmc.os.x11.X11Window;

	public function new(title:String, width:Int, height:Int) {
		this.title = title;
		native = new hxmc.os.x11.X11Window(this, title, width, height);
		surface = native.surface;
		App.windows.push(this);
	}

	public var width(get, never):Int;
	public var height(get, never):Int;

	inline function get_width()
		return surface.width;

	inline function get_height()
		return surface.height;

	public function close() {
		if (closed) return;
		closed = true;
		native.destroy();
		App.windows.remove(this);
	}
}
