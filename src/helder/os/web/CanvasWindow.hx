package helder.os.web;

import helder.os.Event;
import hxmc.unsafe.*;

// helder.os.Window in the browser (WebAssembly): a canvas of the page, through
// the imports of Dom (src/helder/os/imports.mjs). The browser owns the loop:
// App.run returns at once (and main after it), then requestAnimationFrame
// calls frame, a callback through the module's function table, which runs
// one turn of App's loop: the pending events (queued by the JavaScript side
// since the last frame), then onFrame. The canvas's drawing buffer follows
// its displayed size in device pixels (a Resize event when it changes);
// keys, their characters, the mouse and the wheel come from the canvas
// (keys once it has the focus), touches and pens as pointers (Pointers).
@:allow(helder.os)
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
		if (canvas == 0) throw "helder.os: no canvas for the window (not in a browser?)";
		surface = new Surface(Canvas, Ptr.nil(), Ptr.ofI64(canvas), Dom.width(canvas), Dom.height(canvas));
		if (open.length == 0) Dom.scrolls_at(Callback.addr(scrollsAt));
		open.push(this);
	}

	// a touch drag's question: Window.scrollsAt (-1: none set)
	@:hxmc.callback static function scrollsAt(canvas:Int, x:Int, y:Int, dx:Int, dy:Int):Int {
		var w = find(canvas);
		var f = w == null ? null : w.owner.scrollsAt;
		return f == null ? -1 : f(x, y, dx, dy) ? 1 : 0;
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

	function setTitle(t:String)
		Arena.scoped(a -> Dom.set_title(a.cstring(t)));

	function resize(w:Int, h:Int)
		Dom.set_size(canvas, w, h, 0);

	function setMinSize(w:Int, h:Int)
		Dom.set_size(canvas, w, h, 1);

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
		if (ev.isNull()) ev = LibC.malloc(48);
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
			if (ev[1] >= 15 && ev[1] <= 18 || ev[1] == 101) {
				pointer(w, onEvent);
				continue;
			}
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

	// a touch's or a pen's record (ev): its slot updated, its event sent (a
	// sample: kept for its next event)
	static function pointer(w:CanvasWindow, onEvent:Event->Void) {
		var key = ev[2], x = ev[3] / 256, y = ev[4] / 256, bits = ev[7];
		var type:PointerType = cast bits & 15, pressure = ev[8] / 65536, time = ev[9] / 16;
		var p = Pointers.find(key, type);
		if (ev[1] == 101) {
			if (p != null) @:privateAccess p.sample(x, y, time);
			return;
		}
		var kind:EventKind = cast ev[1];
		if (kind == PointerDown) p = Pointers.press(w.owner, key, type, x, y, pressure, time);
		if (p == null) return;
		if (kind == PointerMove) @:privateAccess p.moveTo(x, y, pressure, time);
		else if (kind == PointerUp || kind == PointerCancel) {
			if (x != p.x || y != p.y) @:privateAccess p.moveTo(x, y, p.pressure, time);
			Pointers.lift(p, kind == PointerCancel, time);
		}
		@:privateAccess p.tilt(ev[10], ev[11]);
		if (p.down) @:privateAccess p.setButtons(bits >> 4 & 255, pressure);
		var e = event;
		Pointers.fill(e, kind, p, ev[5], ev[6]);
		onEvent(e);
	}

	// a string handle's text (the handle freed)
	static function take(h:Int):String {
		var n = Dom.text_length(h);
		var b = haxe.io.Bytes.alloc(n);
		Arena.scoped(a -> {
			var p = a.alloc(n + 1, 1);
			Dom.text_take(h, p);
			BytesPtr.copyIn(b, 0, p, n);
		});
		return b.toString();
	}

	static function find(canvas:Int):Null<CanvasWindow> {
		for (w in open)
			if (w.canvas == canvas) return w;
		return null;
	}
}
