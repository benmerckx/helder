package hxmc.os.web;

import hxmc.os.Event;
import hxmc.unsafe.*;

// hxmc.os.Window in the browser (WebAssembly): a canvas of the page, through
// the imports of Dom (packages/os/imports.mjs). The browser owns the loop:
// App.run returns at once (and main after it), then requestAnimationFrame
// calls frame, a callback through the module's function table, which runs
// one turn of App's loop: the pending events (queued by the JavaScript side
// since the last frame), then onFrame. The canvas's drawing buffer follows
// its displayed size in device pixels (a Resize event when it changes);
// keys and the mouse come from the canvas (keys once it has the focus).
@:allow(hxmc.os)
class CanvasWindow {
	static final event = new Event();
	static final open:Array<CanvasWindow> = [];
	static var ev:Ptr<Int32> = Ptr.nil();
	// App.run's callbacks, for frame
	static var onFrame:Null<Void->Void>;
	static var onEvent:Null<Event->Void>;

	// Clipboard.read's callbacks, in order
	static final clipboardReads:Array<Null<String>->Void> = [];

	final owner:Window;
	final canvas:Int;
	final surface:Surface;

	function new(owner:Window, title:String, width:Int, height:Int) {
		this.owner = owner;
		canvas = Arena.scopedValue(a -> Dom.window_open(a.cstring(title), width, height));
		if (canvas == 0) throw "hxmc.os: no canvas for the window (not in a browser?)";
		surface = new Surface(Canvas, Ptr.nil(), Ptr.ofI64(canvas), Dom.width(canvas), Dom.height(canvas));
		open.push(this);
	}

	var scale(get, never):Float;

	inline function get_scale():Float
		return Dom.scale();

	static function writeClipboard(text:String)
		Arena.scoped(a -> Dom.clipboard_write(a.cstring(text)));

	static function readClipboard(callback:Null<String>->Void) {
		clipboardReads.push(callback);
		Dom.clipboard_read();
	}

	function setCursor(c:Cursor)
		Dom.set_cursor(canvas, c);

	function textInput(on:Bool, x:Int, y:Int, width:Int, height:Int)
		Dom.text_input(canvas, on ? 1 : 0, x, y, width, height);

	function destroy() {
		open.remove(this);
		Dom.window_close(canvas);
	}

	static function start(frame:Void->Void, events:Event->Void) {
		onFrame = frame;
		onEvent = events;
		Dom.start(Callback.addr(tick));
	}

	// a frame of the browser's: 0 ends the loop
	@:hxmc.callback static function tick():Int {
		var go = App.turn(onFrame, onEvent);
		// (what the frame printed, now: the module's stdout is buffered)
		Sys.stdout().flush();
		return go ? 1 : 0;
	}

	// dispatches the pending events
	static function poll(onEvent:Event->Void) {
		if (ev.isNull()) ev = LibC.malloc(28);
		while (Dom.next_event(ev) != 0) {
			if (ev[1] == 100) {
				var h = ev[2], text:Null<String> = h == 0 ? null : take(h);
				var cb = clipboardReads.shift();
				if (cb != null) cb(text);
				continue;
			}
			var w = find(ev[0]);
			if (w == null) continue;
			var e = event;
			e.window = w.owner;
			e.kind = cast ev[1];
			e.key = ev[2];
			e.x = ev[3];
			e.y = ev[4];
			e.button = ev[5];
			e.mods = ev[6];
			// (TextInput: the code point in key)
			if (e.kind == TextInput) {
				e.text = String.fromCharCode(ev[2]);
				e.key = 0;
			}
			// (Scroll: the deltas in 1/256 pixels, in key and button)
			if (e.kind == Scroll) {
				e.deltaX = ev[2] / 256;
				e.deltaY = ev[5] / 256;
				e.key = 0;
				e.button = 0;
			}
			// (TextEditing: the composition's string handle in key)
			if (e.kind == TextEditing) {
				e.text = ev[2] == 0 ? "" : take(ev[2]);
				e.key = 0;
			}
			if (e.kind == Resize) w.surface.resized(e.x, e.y);
			onEvent(e);
		}
	}

	// a string handle's text (the handle freed)
	static function take(h:Int):String {
		var n = Dom.text_length(h);
		var b = haxe.io.Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			Dom.text_take(h, p);
			LibC.memcpy(Mem.addr(b).add(8), p, (n : Int64));
		});
		return b.toString();
	}

	static function find(canvas:Int):Null<CanvasWindow> {
		for (w in open)
			if (w.canvas == canvas) return w;
		return null;
	}
}
