package hxmc.ui.draw;

import hxmc.gfx.*;
import hxmc.os.App;
import hxmc.os.Event as OsEvent;
import hxmc.ui.*;

// A window showing a UI tree drawn with the GPU: an hxmc.os Window, its
// gfx Device, a Renderer and the Ui (root: the tree's root node, in the
// window's points). The window's events become the Ui's (pointer, wheel,
// keys, text); a frame lays the tree out and draws it, when there is
// something new to draw (needsFrame: the Ui asked for one, the window was
// resized or lost its pixels). run() is the app loop for every UiWindow
// open, which sleeps while none has a frame to draw.
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

	static final open:Array<UiWindow> = [];
	// the last frame drawn: its size and scale (a change needs a frame)
	var redraw = true;
	var drawnW = 0;
	var drawnH = 0;
	var drawnScale = 0.0;
	final pass:PassDesc = {colors: [{load: Clear, clear: new hxmc.gfx.Color(1, 1, 1)}]};
	var buttons = 0;

	public function new(title:String, width:Int, height:Int, ?text:TextEngine) {
		window = new hxmc.os.Window(title, width, height);
		device = Device.create(window.surface);
		renderer = new Renderer(device);
		ui = new Ui(text == null ? new DrawText() : text, width, height);
		open.push(this);
	}

	public var root(get, never):Node;

	inline function get_root()
		return ui.root;

	// there is something new to draw
	public function needsFrame():Bool
		return redraw || ui.needsFrame || capture != null || device.width != drawnW || device.height != drawnH || window.scale != drawnScale;

	// draws a frame (the loop calls it when needsFrame)
	public function frame() {
		var s = window.scale;
		renderer.scale = device.width / Math.max(1, Math.round(device.width / s));
		ui.resize(device.width / renderer.scale, device.height / renderer.scale);
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
		if (onFrame != null) onFrame();
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
			case MouseDown if (e.button == 4 || e.button == 5):
				ui.wheel(e.x / k, e.y / k, 0, e.button == 4 ? -40 : 40);
			case MouseDown:
				ui.pointerDown(e.x / k, e.y / k, e.button);
			case MouseUp if (e.button == 4 || e.button == 5):
			case MouseUp:
				ui.pointerUp(e.x / k, e.y / k, e.button);
			case KeyDown:
				ui.keyDown(e.key, e.mods);
			case KeyUp:
				ui.keyUp(e.key, e.mods);
			case TextInput:
				ui.textInput(e.text);
			case Resize | Redraw:
				redraw = true;
			case _:
		}
		updateCursor();
	}

	public function close() {
		window.close();
		open.remove(this);
		device.dispose();
	}

	// the app loop: every UiWindow's frames and events until the last closes
	public static function run() {
		App.run(() -> {
			var drew = false;
			for (w in open.copy())
				if (w.needsFrame()) {
					w.frame();
					drew = true;
				}
			if (!drew) App.wait(idleWait);
		}, e -> for (w in open.copy()) if (w.window == e.window) w.handle(e));
	}
}
