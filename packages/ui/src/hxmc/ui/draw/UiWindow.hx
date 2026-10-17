package hxmc.ui.draw;

import hxmc.gfx.*;
import hxmc.os.App;
import hxmc.os.Event as OsEvent;
import hxmc.ui.*;
import hxmc.unsafe.*;

// A window showing a UI tree drawn with the GPU: an hxmc.os Window, its
// gfx Device, a Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); a frame lays the tree out and draws it, when there is
// something new to draw (needsFrame: the Ui asked for one, the window was
// resized or lost its pixels). run() is the app loop for every UiWindow
// open, which sleeps while none has a frame to draw. In the browser each
// frame's accessibility tree goes to the mirror in the canvas (WebAccess:
// load packages/ui/imports.mjs), on macOS to NSAccessibility (MacAccess),
// on Windows to UI Automation (WinAccess), on Linux to AT-SPI (LinuxAccess),
// and the actions asked for come back.
class UiWindow {
	public final window:hxmc.os.Window;
	public final device:Device;
	public final renderer:Renderer;
	public final ui:Ui;
	public var background:Color = Color.rgb(0xF4F4F5);
	public var onClose:Null<Void->Void>;
	// after each frame is drawn
	public var onFrame:Null<Void->Void>;
	// when set, the next frame's pixels are read into it before they are
	// presented (RGBA8, rows top to bottom: tests and screenshots)
	public var capture:Null<haxe.io.Bytes>;

	// how long the loop sleeps at most with nothing to draw (seconds): what
	// changes the UI from outside its events shows within it
	public static var idleWait = 0.1;
	// whether the system's appearance is dark (App.prefersDark), asked again
	// every second while the loop runs; each window's Ui.dark follows it
	public static final dark:hxmc.view.Signal<Bool> = hxmc.view.Reactive.signal(App.prefersDark());
	static var darkAsked = 0.0;

	static final open:Array<UiWindow> = [];
	// the last frame drawn: its size and scale (a change needs a frame)
	var redraw = true;
	var drawnW = 0;
	var drawnH = 0;
	var drawnScale = 0.0;
	// the tree sent to the browser's mirror last
	var access:Null<hxmc.ui.access.AccessTree>;
	// macOS's adapter (a MacAccess; Any: the other targets never reach its type)
	var macAccess:Any = null;
	// Windows' (a WinAccess)
	var winAccess:Any = null;
	// Linux's (a LinuxAccess)
	var linuxAccess:Any = null;
	// the text input area last given to the window ("": off)
	var typing = "";
	final pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
	var buttons = 0;

	public function new(title:String, width:Int, height:Int, ?text:TextEngine) {
		window = new hxmc.os.Window(title, width, height);
		// (shortcuts labelled as macOS's menus do)
		Shortcut.mac = Mem.os() == 1;
		// (Android: text fields get the soft keyboard and the input method)
		if (Mem.target() >= 9) hxmc.os.android.TextInput.enable();
		device = Device.create(window.surface);
		renderer = new Renderer(device);
		ui = new Ui(text == null ? new DrawText() : text, width, height);
		ui.clipboard = new SystemClipboard(window);
		ui.dark = dark.peek();
		// (the browser's own views: native text editors over the canvas)
		if (Mem.os() == 3) ui.platform = WebMirror.views(window.surface.handle.toI64().toInt());
		// (Windows': EDIT controls over the window)
		else if (Mem.os() == 2) ui.platform = new WinViews(window.surface.handle, ui, () -> renderer.scale);
		open.push(this);
	}

	public var root(get, never):Node;

	inline function get_root()
		return ui.root;

	// there is something new to draw
	public function needsFrame():Bool
		return redraw || ui.needsFrame || Clock.active || capture != null || device.width != drawnW || device.height != drawnH || window.scale != drawnScale;

	// draws a frame (the loop calls it when needsFrame): the clock ticked first
	public function frame() {
		Clock.tick(haxe.Timer.stamp());
		var s = window.scale;
		renderer.scale = device.width / Math.max(1, Math.round(device.width / s));
		ui.resize(device.width / renderer.scale, device.height / renderer.scale);
		ui.scale = renderer.scale;
		ui.update();
		var enc = device.beginFrame();
		if (enc == null) return;
		redraw = false;
		drawnW = device.width;
		drawnH = device.height;
		drawnScale = s;
		var c = pass.colors[0].clear;
		@:privateAccess {
			c.r = background.r / 255;
			c.g = background.g / 255;
			c.b = background.b / 255;
		}
		enc.beginPass(pass);
		renderer.begin(device.width, device.height);
		ui.paint(renderer);
		renderer.end(enc);
		enc.endPass();
		if (capture != null) {
			device.readPixels(capture);
			capture = null;
		}
		device.endFrame();
		updateTextInput();
		sendAccess();
		if (onFrame != null) onFrame();
	}

	// the window's text input: on at the focus's caret while it takes text
	// (the input method's place), else off; told when it changes
	function updateTextInput() {
		var a = ui.textInputArea(), k = renderer.scale;
		var x = 0, y = 0, w = 0, h = 0;
		if (a != null) {
			x = Math.round(a.x * k);
			y = Math.round(a.y * k);
			w = Math.round(Math.max(1, a.width * k));
			h = Math.round(a.height * k);
		}
		var now = a == null ? "" : '$x,$y,$w,$h';
		if (now == typing) return;
		if (a == null) {
			window.stopTextInput();
			// (which takes the keyboard's focus back from a native editor that just took it)
			if (ui.focus != null) @:privateAccess ui.focus.refocusNative();
		} else window.startTextInput(x, y, w, h);
		typing = now;
	}

	// the tree's changes to the browser's mirror or to macOS (the guards inside: an
	// instance method is compiled whether called or not, and the browser's
	// imports must stay out of the other targets)
	function sendAccess() {
		if (Mem.os() == 3) {
			var t = ui.accessTree();
			var json = t.changesJson(access);
			access = t;
			if (json != null) WebMirror.send(window.surface.handle.toI64().toInt(), json);
		} else if (Mem.os() == 1) {
			if (macAccess == null) macAccess = new MacAccess(window, ui);
			(cast macAccess : MacAccess).update();
		} else if (Mem.os() == 2) {
			if (winAccess == null) winAccess = new WinAccess(window, ui);
			(cast winAccess : WinAccess).update();
		} else if (Mem.os() == 0) {
			if (linuxAccess == null) linuxAccess = new LinuxAccess(window, ui);
			(cast linuxAccess : LinuxAccess).update();
		}
	}

	// the actions assistive technology asked for (the browser's), done
	function pollAccess() {
		if (Mem.os() == 3) {
			if (access != null) WebMirror.poll(ui);
		} else if (Mem.os() == 0) {
			if (linuxAccess != null) LinuxAccess.dispatch();
		}
	}

	// the window's cursor: the Ui's (hxmc.os.Cursor has Default for Auto first)
	function updateCursor()
		window.cursor = cast Std.int(Math.max(0, (ui.cursor() : Int) - 1));

	// one of the window's events
	public function handle(e:OsEvent) {
		var k = renderer.scale;
		switch e.kind {
			case Close:
				if (onClose != null) onClose() else close();
			case MouseMove:
				ui.pointerMove(e.x / k, e.y / k);
			case Scroll:
				// (Shift turns a vertical wheel sideways, as browsers do)
				var dx = e.deltaX, dy = e.deltaY;
				if (e.mods & hxmc.os.Event.Mods.SHIFT != 0 && dx == 0) {
					dx = dy;
					dy = 0;
				}
				ui.wheel(e.x / k, e.y / k, dx / k, dy / k);
			case MouseDown:
				ui.pointerDown(e.x / k, e.y / k, e.button);
			case MouseUp:
				ui.pointerUp(e.x / k, e.y / k, e.button);
			case KeyDown:
				ui.keyDown(e.key, e.mods);
			case KeyUp:
				ui.keyUp(e.key, e.mods);
			case TextInput:
				ui.textInput(e.text);
			case TextEditing:
				ui.composition(e.text, e.x);
			case Resize | Redraw:
				redraw = true;
			case _:
		}
		updateCursor();
	}

	public function close() {
		// (nested: only a constant condition drops the branch)
		if (Mem.os() == 1) {
			if (macAccess != null) (cast macAccess : MacAccess).dispose();
		}
		if (Mem.os() == 2) {
			if (winAccess != null) (cast winAccess : WinAccess).dispose();
		}
		if (Mem.os() == 0) {
			if (linuxAccess != null) (cast linuxAccess : LinuxAccess).dispose();
		}
		window.close();
		open.remove(this);
		device.dispose();
	}

	// the app loop: every UiWindow's frames and events until the last closes
	public static function run() {
		App.run(() -> {
			var now = haxe.Timer.stamp();
			if (now - darkAsked > 1) {
				darkAsked = now;
				var d = App.prefersDark();
				if (d != dark.peek()) {
					dark.value = d;
					for (w in open)
						w.ui.dark = d;
				}
			}
			var drew = false;
			for (w in open.copy())
				w.pollAccess();
			for (w in open.copy())
				if (w.needsFrame()) {
					w.frame();
					drew = true;
				}
			if (!drew) App.wait(idleWait);
		}, e -> for (w in open.copy()) if (w.window == e.window) w.handle(e));
	}
}

// the system's clipboard (hxmc.os.Clipboard) for a window's Ui
class SystemClipboard implements ClipboardHost {
	final window:hxmc.os.Window;

	public function new(window:hxmc.os.Window)
		this.window = window;

	public function write(text:String)
		hxmc.os.Clipboard.write(window, text);

	public function read(callback:Null<String>->Void)
		hxmc.os.Clipboard.read(window, callback);
}

// the browser's accessibility mirror (WebAccess), apart: its imports are
// reached only from the browser's branches
class WebMirror {
	public static function views(canvas:Int):PlatformViews
		return new WebViews(canvas);

	public static function send(canvas:Int, json:String)
		Arena.scoped(a -> WebAccess.access_update(canvas, a.cstring(json)));

	public static function poll(ui:Ui)
		Arena.scoped(a -> {
			var p:Ptr<Int32> = a.alloc(8);
			while (WebAccess.access_action(p) != 0)
				ui.accessAction(p[0], p[1]);
		});
}
